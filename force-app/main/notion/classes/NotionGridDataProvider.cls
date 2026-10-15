global with sharing class NotionGridDataProvider
    implements appcg.GridDataProviderV1, appcg.GridDataMutationProviderV1 {

    public class ProviderException extends Exception {}

    private static final Set<String> READ_ONLY_TYPES = new Set<String>{
        'created_time', 'created_by', 'last_edited_time', 'last_edited_by',
        'formula', 'rollup', 'unique_id', 'verification', 'button'
    };

    // ─── Instance Cache ───────────────────────────────────────────────
    private List<Map<String, Object>> cachedRecords;

    // ─── Config ───────────────────────────────────────────────────────

    @TestVisible
    private class NotionConfig {
        public String databaseId;
        public Map<String, Object> filter;
        public List<Object> sorts;
    }

    @TestVisible
    private static appcg__Grid_Definition__c testGridDef;

    @TestVisible
    private static appcg__Grid_Definition__c getGridDefinition(appcg.GridDataProviderTypesV1.ProviderContext context) {
        if (testGridDef != null) {
            return testGridDef;
        }
        if (context == null || context.gridDefinitionId == null) {
            return null;
        }
        List<appcg__Grid_Definition__c> defs = [
            SELECT Id, appcg__Data_Provider_Config__c, appcg__Pagination_Type__c, appcg__Record_Limit__c, appcg__Page_Size__c
            FROM appcg__Grid_Definition__c
            WHERE Id = :context.gridDefinitionId
            LIMIT 1
        ];
        return defs.isEmpty() ? null : defs[0];
    }

    @TestVisible
    private static NotionConfig parseConfig(appcg.GridDataProviderTypesV1.ProviderContext context) {
        appcg__Grid_Definition__c gridDef = getGridDefinition(context);
        String configJson = gridDef != null ? gridDef.appcg__Data_Provider_Config__c : null;
        if (String.isBlank(configJson)) {
            throw new ProviderException(
                'Notion provider requires configuration. ' +
                'Set Data Provider Configuration with {"databaseId":"..."}'
            );
        }
        NotionConfig cfg;
        try {
            cfg = (NotionConfig) JSON.deserialize(configJson, NotionConfig.class);
        } catch (Exception e) {
            throw new ProviderException('Invalid Notion provider configuration: ' + e.getMessage());
        }
        if (String.isBlank(cfg.databaseId)) {
            throw new ProviderException('databaseId is required in the provider configuration.');
        }
        return cfg;
    }

    // ─── GridDataProviderV1 ───────────────────────────────────────────

    global appcg.GridDataProviderTypesV1.Capabilities getCapabilities(
        appcg.GridDataProviderTypesV1.ProviderContext context
    ) {
        NotionConfig cfg = parseConfig(context);
        NotionClient client = new NotionClient();

        // 1. Fetch database schema
        Map<String, Object> dbMeta = client.getDatabase(cfg.databaseId);
        Map<String, Object> propsMeta = (Map<String, Object>) dbMeta.get('properties');
        Map<String, String> propertyTypes = extractPropertyTypes(propsMeta);

        // 2. Fetch initial records
        Map<String, Object> queryRes = client.queryDatabase(cfg.databaseId, 100, null, cfg.filter, cfg.sorts);
        List<Object> rawResults = (List<Object>) queryRes.get('results');

        // If schema was empty from getDatabase, discover types from first record
        if (propertyTypes.isEmpty() && rawResults != null && !rawResults.isEmpty()) {
            Map<String, Object> firstPage = (Map<String, Object>) rawResults[0];
            Map<String, Object> pageProps = (Map<String, Object>) firstPage.get('properties');
            propertyTypes = extractPropertyTypes(pageProps);
        }

        cachedRecords = parseNotionPages(rawResults, propertyTypes);

        appcg.GridDataProviderTypesV1.Capabilities capabilities = new appcg.GridDataProviderTypesV1.Capabilities();
        capabilities.supportedFeatures = new Set<String>{
            'SEARCH', 'REFRESH', 'ADD', 'EDIT', 'DELETE', 'DOWNLOAD_CSV'
        };
        capabilities.supportedRowActions = new Set<String>{ 'DELETE' };
        capabilities.supportsServerPagination = false;
        capabilities.columns = buildColumnDefinitions(propsMeta, propertyTypes);
        return capabilities;
    }

    global appcg.GridDataProviderTypesV1.PageResult getData(
        appcg.GridDataProviderTypesV1.QueryRequest request
    ) {
        List<Map<String, Object>> records;

        appcg__Grid_Definition__c gridDef = getGridDefinition(request?.context);
        String paginationType = gridDef?.appcg__Pagination_Type__c;
        Integer recordLimit = (gridDef?.appcg__Record_Limit__c != null && gridDef.appcg__Record_Limit__c > 0)
            ? (Integer) gridDef.appcg__Record_Limit__c
            : 100;

        Integer pageSize;
        Integer requestedPageSize = (request.pageSize != null && request.pageSize > 0)
            ? request.pageSize
            : (gridDef?.appcg__Page_Size__c != null ? Integer.valueOf(gridDef.appcg__Page_Size__c) : 20);
        if (paginationType == 'Client-Side') {
            pageSize = Math.min(recordLimit, 1000);
        } else {
            pageSize = (gridDef?.appcg__Record_Limit__c != null && gridDef.appcg__Record_Limit__c > 0)
                ? Math.min(requestedPageSize, (Integer) gridDef.appcg__Record_Limit__c)
                : Math.min(requestedPageSize, 1000);
        }

        if (cachedRecords != null) {
            records = cachedRecords;
            cachedRecords = null;
        } else {
            NotionConfig cfg = parseConfig(request.context);
            NotionClient client = new NotionClient();
            Map<String, Object> dbMeta = client.getDatabase(cfg.databaseId);
            Map<String, Object> propsMeta = (Map<String, Object>) dbMeta.get('properties');
            Map<String, String> propertyTypes = extractPropertyTypes(propsMeta);

            Map<String, Object> queryRes = client.queryDatabase(cfg.databaseId, 100, null, cfg.filter, cfg.sorts);
            List<Object> rawResults = (List<Object>) queryRes.get('results');
            records = parseNotionPages(rawResults, propertyTypes);
        }

        while (records != null && records.size() > pageSize) {
            records.remove(records.size() - 1);
        }

        // Apply search filter
        if (String.isNotBlank(request.searchTerm)) {
            records = filterBySearch(records, request.searchTerm);
        }

        appcg.GridDataProviderTypesV1.PageResult result = new appcg.GridDataProviderTypesV1.PageResult();
        result.records = records;
        result.totalCount = records.size();
        return result;
    }

    // ─── GridDataMutationProviderV1 ───────────────────────────────────

    global appcg.GridDataProviderTypesV1.SaveResult saveRecords(
        appcg.GridDataProviderTypesV1.SaveRequest request
    ) {
        NotionConfig cfg = parseConfig(request.context);
        NotionClient client = new NotionClient();

        // Fetch property types from database schema
        Map<String, Object> dbMeta = client.getDatabase(cfg.databaseId);
        Map<String, Object> propsMeta = (Map<String, Object>) dbMeta.get('properties');
        Map<String, String> propertyTypes = extractPropertyTypes(propsMeta);

        Set<String> readOnlyFields = new Set<String>();
        for (String propName : propertyTypes.keySet()) {
            String pType = propertyTypes.get(propName);
            if (READ_ONLY_TYPES.contains(pType)) {
                readOnlyFields.add(propName);
            }
        }

        List<Map<String, Object>> newRecords = new List<Map<String, Object>>();
        List<Map<String, Object>> existingRecords = new List<Map<String, Object>>();

        for (Map<String, Object> record : request.records) {
            Object rawId = record.get('Id');
            String recordId = rawId == null ? null : String.valueOf(rawId);
            if (String.isBlank(recordId) || recordId.startsWith('TEMP_')) {
                newRecords.add(record);
            } else {
                existingRecords.add(record);
            }
        }

        // Update existing records
        for (Map<String, Object> record : existingRecords) {
            String pageId = String.valueOf(record.get('Id'));
            Map<String, Object> propsPayload = serializeNotionProperties(record, propertyTypes, readOnlyFields);
            client.updatePage(pageId, propsPayload);
        }

        // Create new records
        for (Map<String, Object> record : newRecords) {
            Map<String, Object> propsPayload = serializeNotionProperties(record, propertyTypes, readOnlyFields);
            Map<String, Object> createRes = client.createPage(cfg.databaseId, propsPayload);
            if (createRes != null && createRes.containsKey('id')) {
                record.put('Id', String.valueOf(createRes.get('id')));
            }
        }

        // Return saved records preserving exact request order
        List<Map<String, Object>> savedRecords = new List<Map<String, Object>>();
        for (Map<String, Object> record : request.records) {
            savedRecords.add(record);
        }

        appcg.GridDataProviderTypesV1.SaveResult result = new appcg.GridDataProviderTypesV1.SaveResult();
        result.records = savedRecords;
        return result;
    }

    global void deleteRecords(appcg.GridDataProviderTypesV1.DeleteRequest request) {
        if (request.recordIds == null || request.recordIds.isEmpty()) {
            return;
        }
        parseConfig(request.context);

        NotionClient client = new NotionClient();
        for (String recId : request.recordIds) {
            client.archivePage(recId);
        }
    }

    // ─── Helpers ──────────────────────────────────────────────────────

    @TestVisible
    private static Map<String, String> extractPropertyTypes(Map<String, Object> propsMeta) {
        Map<String, String> types = new Map<String, String>();
        if (propsMeta == null) return types;
        for (String name : propsMeta.keySet()) {
            Map<String, Object> prop = (Map<String, Object>) propsMeta.get(name);
            if (prop != null && prop.containsKey('type')) {
                types.put(name, String.valueOf(prop.get('type')));
            }
        }
        return types;
    }

    @TestVisible
    private static List<Map<String, Object>> parseNotionPages(
        List<Object> rawPages,
        Map<String, String> propertyTypes
    ) {
        List<Map<String, Object>> records = new List<Map<String, Object>>();
        if (rawPages == null) return records;

        for (Object pObj : rawPages) {
            Map<String, Object> page = (Map<String, Object>) pObj;
            records.add(parsePageRecord(page, propertyTypes));
        }
        return records;
    }

    private static Map<String, Object> parsePageRecord(
        Map<String, Object> page,
        Map<String, String> propertyTypes
    ) {
        Map<String, Object> row = new Map<String, Object>();
        row.put('Id', page.get('id'));

        Map<String, Object> props = (Map<String, Object>) page.get('properties');
        if (props == null) return row;

        for (String propName : props.keySet()) {
            Map<String, Object> propVal = (Map<String, Object>) props.get(propName);
            if (propVal == null) continue;

            String propType = (String) propVal.get('type');
            row.put(propName, extractPropertyValue(propVal, propType));
        }
        return row;
    }

    @TestVisible
    private static Object extractPropertyValue(Map<String, Object> propVal, String propType) {
        if (propVal == null || String.isBlank(propType)) return null;

        if (propType == 'title' || propType == 'rich_text') {
            List<Object> textArr = (List<Object>) propVal.get(propType);
            if (textArr == null || textArr.isEmpty()) return null;
            List<String> fragments = new List<String>();
            for (Object item : textArr) {
                Map<String, Object> textObj = (Map<String, Object>) item;
                if (textObj.containsKey('plain_text')) {
                    fragments.add((String) textObj.get('plain_text'));
                }
            }
            return String.join(fragments, '');
        }

        if (propType == 'number') {
            return propVal.get('number');
        }

        if (propType == 'select') {
            Map<String, Object> sel = (Map<String, Object>) propVal.get('select');
            return sel != null ? sel.get('name') : null;
        }

        if (propType == 'status') {
            Map<String, Object> st = (Map<String, Object>) propVal.get('status');
            return st != null ? st.get('name') : null;
        }

        if (propType == 'multi_select') {
            List<Object> mList = (List<Object>) propVal.get('multi_select');
            if (mList == null || mList.isEmpty()) return null;
            List<String> names = new List<String>();
            for (Object item : mList) {
                Map<String, Object> sel = (Map<String, Object>) item;
                if (sel != null && sel.containsKey('name')) {
                    names.add((String) sel.get('name'));
                }
            }
            return String.join(names, ', ');
        }

        if (propType == 'date') {
            Map<String, Object> dt = (Map<String, Object>) propVal.get('date');
            if (dt == null) return null;
            String startVal = (String) dt.get('start');
            String endVal = (String) dt.get('end');
            if (String.isNotBlank(endVal) && endVal != startVal) {
                return startVal + ' -> ' + endVal;
            }
            return startVal;
        }

        if (propType == 'checkbox') {
            return propVal.get('checkbox') == true;
        }

        if (propType == 'url') {
            return propVal.get('url');
        }

        if (propType == 'email') {
            return propVal.get('email');
        }

        if (propType == 'phone_number') {
            return propVal.get('phone_number');
        }

        if (propType == 'created_time' || propType == 'last_edited_time') {
            return propVal.get(propType);
        }

        if (propType == 'created_by' || propType == 'last_edited_by') {
            Map<String, Object> usr = (Map<String, Object>) propVal.get(propType);
            return usr != null ? usr.get('name') : null;
        }

        if (propType == 'people') {
            List<Object> pList = (List<Object>) propVal.get('people');
            if (pList == null || pList.isEmpty()) return null;
            List<String> names = new List<String>();
            for (Object pObj : pList) {
                Map<String, Object> pMap = (Map<String, Object>) pObj;
                if (pMap.containsKey('name')) {
                    names.add((String) pMap.get('name'));
                }
            }
            return String.join(names, ', ');
        }

        if (propType == 'formula') {
            Map<String, Object> fMap = (Map<String, Object>) propVal.get('formula');
            if (fMap == null) return null;
            String fType = (String) fMap.get('type');
            return fMap.get(fType);
        }

        if (propType == 'rollup') {
            Map<String, Object> rMap = (Map<String, Object>) propVal.get('rollup');
            if (rMap == null) return null;
            String rType = (String) rMap.get('type');
            if (rType == 'array') {
                return JSON.serialize(rMap.get('array'));
            }
            return rMap.get(rType);
        }

        Object raw = propVal.get(propType);
        return raw != null ? String.valueOf(raw) : null;
    }

    @TestVisible
    private static Map<String, Object> serializeNotionProperties(
        Map<String, Object> record,
        Map<String, String> propertyTypes,
        Set<String> readOnlyFields
    ) {
        Map<String, Object> props = new Map<String, Object>();
        for (String key : record.keySet()) {
            if (key == 'Id' || key == 'attributes') continue;
            if (readOnlyFields != null && readOnlyFields.contains(key)) continue;

            String propType = propertyTypes.containsKey(key) ? propertyTypes.get(key) : 'rich_text';
            Object val = record.get(key);
            Map<String, Object> serialized = serializePropertyValue(val, propType);
            if (serialized != null) {
                props.put(key, serialized);
            }
        }
        return props;
    }

    private static Map<String, Object> serializePropertyValue(Object val, String propType) {
        if (propType == 'title') {
            String str = val == null ? '' : String.valueOf(val);
            return new Map<String, Object>{
                'title' => new List<Object>{
                    new Map<String, Object>{
                        'text' => new Map<String, Object>{ 'content' => str }
                    }
                }
            };
        }

        if (propType == 'rich_text') {
            String str = val == null ? '' : String.valueOf(val);
            return new Map<String, Object>{
                'rich_text' => new List<Object>{
                    new Map<String, Object>{
                        'text' => new Map<String, Object>{ 'content' => str }
                    }
                }
            };
        }

        if (propType == 'number') {
            Decimal num = (val == null || String.isBlank(String.valueOf(val))) ? null : Decimal.valueOf(String.valueOf(val));
            return new Map<String, Object>{ 'number' => num };
        }

        if (propType == 'select') {
            String name = (val == null) ? null : String.valueOf(val).trim();
            return new Map<String, Object>{
                'select' => String.isBlank(name) ? null : new Map<String, Object>{ 'name' => name }
            };
        }

        if (propType == 'status') {
            String name = (val == null) ? null : String.valueOf(val).trim();
            return new Map<String, Object>{
                'status' => String.isBlank(name) ? null : new Map<String, Object>{ 'name' => name }
            };
        }

        if (propType == 'multi_select') {
            List<Map<String, Object>> tags = new List<Map<String, Object>>();
            if (val != null) {
                for (String tag : String.valueOf(val).split(',')) {
                    if (String.isNotBlank(tag.trim())) {
                        tags.add(new Map<String, Object>{ 'name' => tag.trim() });
                    }
                }
            }
            return new Map<String, Object>{ 'multi_select' => tags };
        }

        if (propType == 'date') {
            String dStr = (val == null) ? null : String.valueOf(val).trim();
            return new Map<String, Object>{
                'date' => String.isBlank(dStr) ? null : new Map<String, Object>{ 'start' => dStr }
            };
        }

        if (propType == 'checkbox') {
            Boolean b = (val instanceof Boolean) ? (Boolean) val : (val != null && Boolean.valueOf(String.valueOf(val)));
            return new Map<String, Object>{ 'checkbox' => b };
        }

        if (propType == 'url') {
            String u = (val == null || String.isBlank(String.valueOf(val))) ? null : String.valueOf(val).trim();
            return new Map<String, Object>{ 'url' => u };
        }

        if (propType == 'email') {
            String e = (val == null || String.isBlank(String.valueOf(val))) ? null : String.valueOf(val).trim();
            return new Map<String, Object>{ 'email' => e };
        }

        if (propType == 'phone_number') {
            String p = (val == null || String.isBlank(String.valueOf(val))) ? null : String.valueOf(val).trim();
            return new Map<String, Object>{ 'phone_number' => p };
        }

        return null;
    }

    private static List<appcg.GridDataProviderTypesV1.ColumnDefinition> buildColumnDefinitions(
        Map<String, Object> propsMeta,
        Map<String, String> propertyTypes
    ) {
        List<appcg.GridDataProviderTypesV1.ColumnDefinition> columns =
            new List<appcg.GridDataProviderTypesV1.ColumnDefinition>();

        // Hidden Id column (Notion Page UUID)
        columns.add(column('Id', 'Page ID', 'TEXT', true, false, '120px'));

        for (String name : propertyTypes.keySet()) {
            String propType = propertyTypes.get(name);
            Boolean isReadOnly = READ_ONLY_TYPES.contains(propType);
            String gridFieldType = mapToGridFieldType(propType);

            appcg.GridDataProviderTypesV1.ColumnDefinition col = column(name, name, gridFieldType, isReadOnly, true, null);

            // Populate picklist options if applicable
            if (propsMeta != null && propsMeta.containsKey(name) &&
                (propType == 'select' || propType == 'status' || propType == 'multi_select')) {
                Map<String, Object> propDef = (Map<String, Object>) propsMeta.get(name);
                Map<String, Object> typeConf = (Map<String, Object>) propDef.get(propType);
                if (typeConf != null && typeConf.containsKey('options')) {
                    List<Object> opts = (List<Object>) typeConf.get('options');
                    col.picklistOptions = new List<appcg.GridDataProviderTypesV1.Option>();
                    for (Object optObj : opts) {
                        Map<String, Object> optMap = (Map<String, Object>) optObj;
                        appcg.GridDataProviderTypesV1.Option opt = new appcg.GridDataProviderTypesV1.Option();
                        opt.label = (String) optMap.get('name');
                        opt.value = (String) optMap.get('name');
                        col.picklistOptions.add(opt);
                    }
                }
            }
            columns.add(col);
        }
        return columns;
    }

    private static String mapToGridFieldType(String propType) {
        if (propType == 'number') return 'NUMBER';
        if (propType == 'checkbox') return 'BOOLEAN';
        if (propType == 'date' || propType == 'created_time' || propType == 'last_edited_time') return 'DATETIME';
        if (propType == 'select' || propType == 'status') return 'PICKLIST';
        if (propType == 'url') return 'URL';
        if (propType == 'email') return 'EMAIL';
        if (propType == 'phone_number') return 'PHONE';
        return 'TEXT';
    }

    private static appcg.GridDataProviderTypesV1.ColumnDefinition column(
        String id, String label, String fieldType,
        Boolean isReadOnly, Boolean visible, String width
    ) {
        appcg.GridDataProviderTypesV1.ColumnDefinition col = new appcg.GridDataProviderTypesV1.ColumnDefinition();
        col.id = id;
        col.label = label;
        col.fieldType = fieldType;
        col.isReadOnly = isReadOnly;
        col.visible = visible;
        col.columnWidth = width;
        return col;
    }

    private static List<Map<String, Object>> filterBySearch(
        List<Map<String, Object>> records,
        String searchTerm
    ) {
        String lower = searchTerm.toLowerCase();
        List<Map<String, Object>> filtered = new List<Map<String, Object>>();
        for (Map<String, Object> record : records) {
            for (String key : record.keySet()) {
                if (key == 'Id') continue;
                Object val = record.get(key);
                if (val != null && String.valueOf(val).toLowerCase().contains(lower)) {
                    filtered.add(record);
                    break;
                }
            }
        }
        return filtered;
    }
}
