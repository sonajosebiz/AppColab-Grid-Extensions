global class HubSpotGridDataProvider implements appcg.GridDataProviderV1, appcg.GridDataMutationProviderV1 {

    public class ProviderException extends Exception {}

    @TestVisible
    private static appcg__Grid_Definition__c testGridDef;
    @TestVisible
    private static Map<String, String> testParentFieldValues = new Map<String, String>();

    @TestVisible
    private List<Map<String, Object>> cachedRecords;
    @TestVisible
    private Integer cachedTotalCount;

    public class HubSpotConfig {
        public String objectType; // e.g. 'emails', 'contacts', 'deals', 'companies'
        public List<String> properties;
        public List<appcg.GridDataProviderTypesV1.ColumnDefinition> columns;
        public String parentMatchField; // Salesforce field to read from parent record (e.g. 'Email', 'HubSpot_Contact_Id__c')
        public String hubspotMatchProperty; // HubSpot property to match against (e.g. 'email', 'hs_object_id', 'hs_email_to_email')
    }

    private static appcg__Grid_Definition__c getGridDefinition(appcg.GridDataProviderTypesV1.ProviderContext context) {
        if (testGridDef != null) {
            return testGridDef;
        }
        if (context == null || context.gridDefinitionId == null) {
            return null;
        }
        List<appcg__Grid_Definition__c> defs = [
            SELECT Id, appcg__Data_Provider_Config__c, appcg__Pagination_Type__c, appcg__Page_Size__c, appcg__Record_Limit__c
            FROM appcg__Grid_Definition__c
            WHERE Id = :context.gridDefinitionId
            LIMIT 1
        ];
        return defs.isEmpty() ? null : defs[0];
    }

    @TestVisible
    private static HubSpotConfig parseConfig(appcg.GridDataProviderTypesV1.ProviderContext context) {
        appcg__Grid_Definition__c gridDef = getGridDefinition(context);
        String configJson = gridDef != null ? gridDef.appcg__Data_Provider_Config__c : null;
        if (String.isBlank(configJson)) {
            throw new ProviderException(
                'HubSpotGridDataProvider requires configuration on the Grid Definition record (appcg__Data_Provider_Config__c).'
            );
        }
        HubSpotConfig cfg = new HubSpotConfig();
        try {
            Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(configJson);
            cfg.objectType = stringValue(raw.get('objectType'));
            cfg.parentMatchField = stringValue(raw.get('parentMatchField'));
            cfg.hubspotMatchProperty = stringValue(raw.get('hubspotMatchProperty'));
            cfg.properties = stringList(raw.get('properties'));
            cfg.columns = columnList(raw.get('columns'));
        } catch (Exception e) {
            throw new ProviderException('Invalid HubSpot provider configuration: ' + e.getMessage());
        }
        if (String.isBlank(cfg.objectType)) {
            cfg.objectType = 'contacts'; // Default to contacts if not specified
        }
        return cfg;
    }

    private static String stringValue(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static List<String> stringList(Object value) {
        if (!(value instanceof List<Object>)) {
            return null;
        }
        List<String> values = new List<String>();
        for (Object item : (List<Object>) value) {
            if (item != null) values.add(String.valueOf(item));
        }
        return values;
    }

    private static List<appcg.GridDataProviderTypesV1.ColumnDefinition> columnList(Object value) {
        if (!(value instanceof List<Object>)) {
            return null;
        }
        List<appcg.GridDataProviderTypesV1.ColumnDefinition> columns =
            new List<appcg.GridDataProviderTypesV1.ColumnDefinition>();
        for (Object item : (List<Object>) value) {
            if (!(item instanceof Map<String, Object>)) continue;
            Map<String, Object> raw = (Map<String, Object>) item;
            appcg.GridDataProviderTypesV1.ColumnDefinition column =
                new appcg.GridDataProviderTypesV1.ColumnDefinition();
            column.id = stringValue(raw.get('id'));
            column.label = stringValue(raw.get('label'));
            column.fieldType = stringValue(raw.get('fieldType'));
            column.isReadOnly = raw.containsKey('isReadOnly') ? (Boolean) raw.get('isReadOnly') : false;
            column.visible = raw.containsKey('visible') ? (Boolean) raw.get('visible') : true;
            column.columnWidth = stringValue(raw.get('columnWidth'));
            columns.add(column);
        }
        return columns;
    }

    // ─── GridDataProviderV1 ───────────────────────────────────────────

    global appcg.GridDataProviderTypesV1.Capabilities getCapabilities(
        appcg.GridDataProviderTypesV1.ProviderContext context
    ) {
        HubSpotConfig cfg = parseConfig(context);
        try {
            HubSpotClient client = new HubSpotClient();

            String parentMatchVal = null;
            if (context != null && String.isNotBlank(context.parentId)) {
                parentMatchVal = resolveParentValue(context.parentId, cfg.parentMatchField);
            }

            // 1. Fetch sample records
            Map<String, Object> listRes;
            try {
                listRes = fetchHubSpotRecords(client, cfg, parentMatchVal, 100, null, cfg.properties);
            } catch (Exception e) {
                listRes = new Map<String, Object>{ 'results' => new List<Object>(), 'total' => 0 };
            }
            List<Object> rawResults = (List<Object>) listRes.get('results');
            cachedRecords = parseHubSpotRecords(rawResults);
            cachedTotalCount = listRes.containsKey('total') ? Integer.valueOf(listRes.get('total')) : cachedRecords.size();

            // 2. Build column definitions (from config override, specific properties, or schema describe)
            List<appcg.GridDataProviderTypesV1.ColumnDefinition> cols;
            if (cfg.columns != null && !cfg.columns.isEmpty()) {
                cols = cfg.columns;
            } else {
                cols = resolveColumns(client, cfg.objectType, cfg.properties, cachedRecords);
            }

            appcg.GridDataProviderTypesV1.Capabilities capabilities = new appcg.GridDataProviderTypesV1.Capabilities();
            capabilities.supportedFeatures = new Set<String>{
                'SEARCH', 'REFRESH', 'ADD', 'EDIT', 'DELETE', 'EXPORT'
            };
            capabilities.supportedRowActions = new Set<String>{ 'DELETE' };
            capabilities.supportsServerPagination = true;
            capabilities.maxPageSize = 100;
            capabilities.columns = cols;
            return capabilities;
        } finally {
        }
    }

    global appcg.GridDataProviderTypesV1.PageResult getData(
        appcg.GridDataProviderTypesV1.QueryRequest request
    ) {
        try {
            List<Map<String, Object>> records;
            Integer totalCount;

            appcg__Grid_Definition__c gridDef = getGridDefinition(request?.context);
            String paginationType = gridDef?.appcg__Pagination_Type__c;
            Integer recordLimit = (gridDef?.appcg__Record_Limit__c != null && gridDef.appcg__Record_Limit__c > 0)
                ? (Integer) gridDef.appcg__Record_Limit__c
                : 100;

            Integer startIndex = request.startIndex != null ? Math.max(0, request.startIndex) : 0;
            Integer pageSize;
            Integer requestedPageSize = (request.pageSize != null && request.pageSize > 0)
                ? request.pageSize
                : (gridDef?.appcg__Page_Size__c != null ? Integer.valueOf(gridDef.appcg__Page_Size__c) : 20);
            if (paginationType == 'Client-Side') {
                pageSize = Math.min(recordLimit, 1000);
            } else {
                pageSize = (gridDef?.appcg__Record_Limit__c != null && gridDef.appcg__Record_Limit__c > 0)
                    ? Math.min(requestedPageSize, (Integer) gridDef.appcg__Record_Limit__c)
                    : Math.min(requestedPageSize, 100);
            }

            if (cachedRecords != null && startIndex == 0 && String.isBlank(request.searchTerm)) {
                records = cachedRecords;
                cachedRecords = null;
                totalCount = cachedTotalCount;
            } else {
                HubSpotConfig cfg = parseConfig(request.context);
                HubSpotClient client = new HubSpotClient();

                String parentMatchVal = null;
                if (request.context != null && String.isNotBlank(request.context.parentId)) {
                    parentMatchVal = resolveParentValue(request.context.parentId, cfg.parentMatchField);
                }

                Map<String, Object> response = fetchHubSpotRecords(client, cfg, parentMatchVal, pageSize, request.searchTerm, cfg.properties);
                List<Object> rawResults = (List<Object>) response.get('results');
                records = parseHubSpotRecords(rawResults);

                if (response.containsKey('total')) {
                    totalCount = Integer.valueOf(response.get('total'));
                } else {
                    totalCount = records.size();
                }
            }

            while (records != null && records.size() > pageSize) {
                records.remove(records.size() - 1);
            }

            // Client-side search fallback
            if (String.isNotBlank(request.searchTerm)) {
                records = filterBySearch(records, request.searchTerm);
                totalCount = records.size();
            }

            if (gridDef?.appcg__Record_Limit__c != null && gridDef.appcg__Record_Limit__c > 0 && totalCount != null) {
                totalCount = Math.min(totalCount, (Integer) gridDef.appcg__Record_Limit__c);
            }

            appcg.GridDataProviderTypesV1.PageResult result = new appcg.GridDataProviderTypesV1.PageResult();
            result.records = records;
            result.totalCount = (paginationType == 'Client-Side') ? records.size() : totalCount;
            return result;
        } finally {
        }
    }

    // ─── Query Dispatcher ─────────────────────────────────────────────

    private static Map<String, Object> fetchHubSpotRecords(
        HubSpotClient client,
        HubSpotConfig cfg,
        String parentMatchVal,
        Integer pageSize,
        String searchTerm,
        List<String> properties
    ) {
        String objectType = cfg.objectType;

        // If pulling emails for a contact
        if (String.isNotBlank(parentMatchVal) && 'emails'.equalsIgnoreCase(objectType)) {
            String contactId = parentMatchVal;

            // If parentMatchVal is an email address, resolve its HubSpot Contact ID
            if (parentMatchVal.contains('@')) {
                try {
                    Map<String, Object> contactSearch = client.searchObjectsByProperty('contacts', 'email', parentMatchVal, 1, null, new List<String>{'id', 'email'});
                    List<Object> contactRes = (List<Object>) contactSearch.get('results');
                    if (contactRes != null && !contactRes.isEmpty()) {
                        Map<String, Object> cMap = (Map<String, Object>) contactRes[0];
                        contactId = (String) cMap.get('id');
                    }
                } catch (Exception e) {
                    // Fall back to search
                }
            }

            // If contactId is resolved, fetch associated emails
            if (String.isNotBlank(contactId) && !contactId.contains('@')) {
                try {
                    Map<String, Object> assocRes = client.getAssociations('contacts', contactId, 'emails');
                    List<Object> assocList = (List<Object>) assocRes.get('results');
                    if (assocList != null && !assocList.isEmpty()) {
                        List<String> emailIds = new List<String>();
                        for (Object o : assocList) {
                            Map<String, Object> a = (Map<String, Object>) o;
                            if (a.containsKey('id')) {
                                emailIds.add(String.valueOf(a.get('id')));
                            }
                        }
                        if (!emailIds.isEmpty()) {
                            return client.batchReadObjects('emails', emailIds, properties);
                        }
                    } else {
                        return new Map<String, Object>{ 'results' => new List<Object>(), 'total' => 0 };
                    }
                } catch (Exception e) {
                    // Fallback to search query
                }
            }

            // Fallback: Search emails by email address
            List<Map<String, Object>> filterGroups = new List<Map<String, Object>>{
                new Map<String, Object>{
                    'filters' => new List<Map<String, Object>>{
                        new Map<String, Object>{
                            'propertyName' => 'hs_email_to_email',
                            'operator' => 'CONTAINS_TOKEN',
                            'value' => parentMatchVal
                        }
                    }
                },
                new Map<String, Object>{
                    'filters' => new List<Map<String, Object>>{
                        new Map<String, Object>{
                            'propertyName' => 'hs_email_from_email',
                            'operator' => 'CONTAINS_TOKEN',
                            'value' => parentMatchVal
                        }
                    }
                }
            };
            return client.searchObjectsWithFilterGroups('emails', filterGroups, pageSize, null, properties);
        }

        // Generic parent matching for other objects
        if (String.isNotBlank(parentMatchVal)) {
            String matchProp = String.isNotBlank(cfg.hubspotMatchProperty)
                ? cfg.hubspotMatchProperty
                : ('contacts'.equalsIgnoreCase(objectType) ? 'email' : 'hs_object_id');
            return client.searchObjectsByProperty(objectType, matchProp, parentMatchVal, pageSize, null, properties);
        }

        // Search term
        if (String.isNotBlank(searchTerm)) {
            return client.searchObjects(objectType, searchTerm, pageSize, null, properties);
        }

        // Standard list
        return client.listObjects(objectType, pageSize, null, properties);
    }

    // ─── GridDataMutationProviderV1 ───────────────────────────────────

    global appcg.GridDataProviderTypesV1.SaveResult saveRecords(
        appcg.GridDataProviderTypesV1.SaveRequest request
    ) {
        HubSpotConfig cfg = parseConfig(request.context);
        try {
            HubSpotClient client = new HubSpotClient();
            List<Map<String, Object>> savedRecords = new List<Map<String, Object>>();

            for (Map<String, Object> row : request.records) {
                String recordId = (String) row.get('Id');
                Map<String, Object> props = new Map<String, Object>();
                for (String key : row.keySet()) {
                    if (key != 'Id' && key != 'createdAt' && key != 'updatedAt' && key != 'archived') {
                        props.put(key, row.get(key));
                    }
                }

                Map<String, Object> res;
                if (String.isNotBlank(recordId) && recordId.startsWith('TEMP_')) {
                    // Create
                    res = client.createObject(cfg.objectType, props);
                } else if (String.isNotBlank(recordId)) {
                    // Update
                    res = client.updateObject(cfg.objectType, recordId, props);
                }

                if (res != null) {
                    Map<String, Object> parsed = flattenHubSpotRecord(res);
                    savedRecords.add(parsed);
                }
            }

            appcg.GridDataProviderTypesV1.SaveResult result = new appcg.GridDataProviderTypesV1.SaveResult();
            result.records = savedRecords;
            return result;
        } finally {
        }
    }

    global void deleteRecords(appcg.GridDataProviderTypesV1.DeleteRequest request) {
        HubSpotConfig cfg = parseConfig(request.context);
        try {
            HubSpotClient client = new HubSpotClient();
            for (String recordId : request.recordIds) {
                if (String.isNotBlank(recordId) && !recordId.startsWith('TEMP_')) {
                    client.deleteObject(cfg.objectType, recordId);
                }
            }
        } finally {
        }
    }

    // ─── Parent Record Value Resolution ───────────────────────────────

    @TestVisible
    private static String resolveParentValue(String parentId, String parentFieldName) {
        if (String.isBlank(parentId)) {
            return null;
        }
        if (testParentFieldValues != null && testParentFieldValues.containsKey(parentId)) {
            return testParentFieldValues.get(parentId);
        }
        try {
            Id pid = (Id) parentId;
            String sObjName = pid.getSObjectType().getDescribe().getName();
            String fieldToQuery = String.isNotBlank(parentFieldName) ? String.escapeSingleQuotes(parentFieldName) : 'Email';

            Map<String, SObjectField> fieldMap = pid.getSObjectType().getDescribe().fields.getMap();
            if (!fieldMap.containsKey(fieldToQuery) && !fieldMap.containsKey(fieldToQuery.toLowerCase())) {
                if (fieldMap.containsKey('Email')) {
                    fieldToQuery = 'Email';
                } else {
                    return null;
                }
            }

            String soql = 'SELECT Id, ' + fieldToQuery + ' FROM ' + String.escapeSingleQuotes(sObjName) + ' WHERE Id = :pid LIMIT 1';
            List<SObject> results = Database.query(soql);
            if (!results.isEmpty()) {
                Object val = results[0].get(fieldToQuery);
                return val != null ? String.valueOf(val) : null;
            }
        } catch (Exception e) {
            // Non-SObject ID or field not present
        }
        return null;
    }

    // ─── Record Parsing & Normalization ───────────────────────────────

    private static List<Map<String, Object>> parseHubSpotRecords(List<Object> rawResults) {
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        if (rawResults == null) {
            return rows;
        }
        for (Object item : rawResults) {
            Map<String, Object> rawMap = (Map<String, Object>) item;
            rows.add(flattenHubSpotRecord(rawMap));
        }
        return rows;
    }

    private static Map<String, Object> flattenHubSpotRecord(Map<String, Object> rawMap) {
        Map<String, Object> row = new Map<String, Object>();
        if (rawMap == null) {
            return row;
        }

        String recordId = (String) rawMap.get('id');
        row.put('Id', recordId);

        if (rawMap.containsKey('createdAt')) {
            row.put('createdAt', rawMap.get('createdAt'));
        }
        if (rawMap.containsKey('updatedAt')) {
            row.put('updatedAt', rawMap.get('updatedAt'));
        }

        Map<String, Object> props = (Map<String, Object>) rawMap.get('properties');
        if (props != null) {
            for (String key : props.keySet()) {
                row.put(key, props.get(key));
            }
        }
        return row;
    }

    // ─── Column Inference & Schema Discovery ──────────────────────────

    private static List<appcg.GridDataProviderTypesV1.ColumnDefinition> resolveColumns(
        HubSpotClient client,
        String objectType,
        List<String> requestedProperties,
        List<Map<String, Object>> sampleRecords
    ) {
        List<appcg.GridDataProviderTypesV1.ColumnDefinition> cols = new List<appcg.GridDataProviderTypesV1.ColumnDefinition>();

        // Hidden Id column
        cols.add(column('Id', 'ID', 'TEXT', true, false, '100px'));

        // If specific properties were requested in configuration
        if (requestedProperties != null && !requestedProperties.isEmpty()) {
            Map<String, Map<String, Object>> propMetaByName = new Map<String, Map<String, Object>>();
            try {
                Map<String, Object> descRes = client.describeProperties(objectType);
                List<Object> propList = (List<Object>) descRes.get('results');
                if (propList != null) {
                    for (Object p : propList) {
                        Map<String, Object> prop = (Map<String, Object>) p;
                        propMetaByName.put((String) prop.get('name'), prop);
                    }
                }
            } catch (Exception e) {
                // Ignore describe errors and fallback to label/type heuristics
            }

            for (String propName : requestedProperties) {
                Map<String, Object> meta = propMetaByName.get(propName);
                String label = (meta != null && meta.containsKey('label')) ? (String) meta.get('label') : formatLabel(propName);
                String typeStr = (meta != null && meta.containsKey('type')) ? (String) meta.get('type') : null;
                Boolean readOnly = (meta != null && meta.containsKey('readOnlyValue')) ? Boolean.valueOf(meta.get('readOnlyValue')) : false;

                String fieldType = String.isNotBlank(typeStr) ? mapHubSpotType(typeStr, propName) : 'TEXT';
                cols.add(column(propName, label, fieldType, readOnly, true, '180px'));
            }
            return cols;
        }

        // Default: Discover all properties via Property Describe API
        try {
            Map<String, Object> descRes = client.describeProperties(objectType);
            List<Object> propList = (List<Object>) descRes.get('results');
            if (propList != null && !propList.isEmpty()) {
                for (Object propObj : propList) {
                    Map<String, Object> prop = (Map<String, Object>) propObj;
                    String name = (String) prop.get('name');
                    String label = (String) prop.get('label');
                    String typeStr = (String) prop.get('type');
                    Boolean readOnly = prop.containsKey('readOnlyValue') ? Boolean.valueOf(prop.get('readOnlyValue')) : false;

                    // Skip internal system properties from cluttering default column list
                    if (name.startsWith('hs_') && !name.startsWith('hs_email_')) {
                        continue;
                    }

                    String fieldType = mapHubSpotType(typeStr, name);
                    String colLabel = String.isNotBlank(label) ? label : formatLabel(name);
                    cols.add(column(name, colLabel, fieldType, readOnly, true, '180px'));
                }
                if (cols.size() > 1) {
                    return cols;
                }
            }
        } catch (Exception e) {
            // Fall back to sample records inference
        }

        // Fallback: Infer from sample records
        if (sampleRecords != null && !sampleRecords.isEmpty()) {
            Set<String> seen = new Set<String>{ 'Id' };
            for (Map<String, Object> r : sampleRecords) {
                for (String key : r.keySet()) {
                    if (!seen.contains(key)) {
                        seen.add(key);
                        String fieldType = inferTypeFromValue(r.get(key), key);
                        Boolean readOnly = (key == 'createdAt' || key == 'updatedAt' || key == 'id');
                        cols.add(column(key, formatLabel(key), fieldType, readOnly, true, '180px'));
                    }
                }
            }
        }

        return cols;
    }

    private static appcg.GridDataProviderTypesV1.ColumnDefinition column(
        String id,
        String label,
        String fieldType,
        Boolean isReadOnly,
        Boolean visible,
        String width
    ) {
        appcg.GridDataProviderTypesV1.ColumnDefinition c = new appcg.GridDataProviderTypesV1.ColumnDefinition();
        c.id = id;
        c.label = label;
        c.fieldType = fieldType;
        c.isReadOnly = isReadOnly;
        c.visible = visible;
        c.columnWidth = width;
        return c;
    }

    private static String mapHubSpotType(String typeStr, String propName) {
        if (String.isBlank(typeStr)) {
            return 'TEXT';
        }
        String t = typeStr.toLowerCase();
        if (t == 'number') {
            if (propName.toLowerCase().contains('amount') || propName.toLowerCase().contains('price') || propName.toLowerCase().contains('revenue')) {
                return 'CURRENCY';
            }
            return 'NUMBER';
        }
        if (t == 'date') {
            return 'DATE';
        }
        if (t == 'datetime') {
            return 'DATETIME';
        }
        if (t == 'bool' || t == 'boolean') {
            return 'BOOLEAN';
        }
        if (t == 'enumeration') {
            return 'TEXT';
        }
        return 'TEXT';
    }

    private static String inferTypeFromValue(Object val, String propName) {
        if (val == null) {
            return 'TEXT';
        }
        if (val instanceof Boolean) {
            return 'BOOLEAN';
        }
        if (val instanceof Decimal || val instanceof Integer || val instanceof Double || val instanceof Long) {
            if (propName.toLowerCase().contains('amount') || propName.toLowerCase().contains('price')) {
                return 'CURRENCY';
            }
            return 'NUMBER';
        }
        if (val instanceof String) {
            String strVal = (String) val;
            if (Pattern.matches('^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}.*Z?$', strVal)) {
                return 'DATETIME';
            }
            if (Pattern.matches('^\\d{4}-\\d{2}-\\d{2}$', strVal)) {
                return 'DATE';
            }
        }
        return 'TEXT';
    }

    private static String formatLabel(String apiName) {
        if (String.isBlank(apiName)) {
            return '';
        }
        String cleanName = apiName;
        if (cleanName.startsWith('hs_email_')) {
            cleanName = cleanName.substring('hs_email_'.length());
        } else if (cleanName.startsWith('hs_')) {
            cleanName = cleanName.substring('hs_'.length());
        }
        String label = cleanName.replace('_', ' ');
        List<String> words = label.split(' ');
        List<String> capitalized = new List<String>();
        for (String w : words) {
            if (String.isNotBlank(w)) {
                capitalized.add(w.substring(0, 1).toUpperCase() + (w.length() > 1 ? w.substring(1) : ''));
            }
        }
        return String.join(capitalized, ' ');
    }

    private static List<Map<String, Object>> filterBySearch(
        List<Map<String, Object>> records,
        String searchTerm
    ) {
        List<Map<String, Object>> filtered = new List<Map<String, Object>>();
        String termLower = searchTerm.toLowerCase();
        for (Map<String, Object> r : records) {
            for (String key : r.keySet()) {
                Object val = r.get(key);
                if (val != null && String.valueOf(val).toLowerCase().contains(termLower)) {
                    filtered.add(r);
                    break;
                }
            }
        }
        return filtered;
    }
}
