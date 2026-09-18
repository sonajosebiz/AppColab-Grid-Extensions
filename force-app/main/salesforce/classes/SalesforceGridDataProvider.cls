global with sharing class SalesforceGridDataProvider
    implements appcg.GridDataProviderV1, appcg.GridDataMutationProviderV1 {

    public class ProviderException extends Exception {}


    private static final Set<String> SYSTEM_READ_ONLY_FIELDS = new Set<String>{
        'id', 'createddate', 'createdbyid', 'lastmodifieddate', 'lastmodifiedbyid',
        'systemmodstamp', 'isdeleted'
    };

    // ─── Instance Cache ───────────────────────────────────────────────
    private List<Map<String, Object>> cachedRecords;

    // ─── Config ───────────────────────────────────────────────────────

    @TestVisible
    private class SalesforceConfig {
        public String sObjectName;
        public String fields;
        public String whereClause;
        public String orderBy;
        public Integer recordLimit;
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
    private static SalesforceConfig parseConfig(appcg.GridDataProviderTypesV1.ProviderContext context) {
        appcg__Grid_Definition__c gridDef = getGridDefinition(context);
        String configJson = gridDef != null ? gridDef.appcg__Data_Provider_Config__c : null;
        if (String.isBlank(configJson)) {
            throw new ProviderException(
                'Salesforce provider requires configuration. ' +
                'Set Data Provider Configuration with {"sObject":"Contact","fields":"FirstName, LastName, Email, Phone"}'
            );
        }
        SalesforceConfig cfg = new SalesforceConfig();
        cfg.recordLimit = (gridDef?.appcg__Record_Limit__c != null && gridDef.appcg__Record_Limit__c > 0)
            ? (Integer) gridDef.appcg__Record_Limit__c
            : 100;
        try {
            Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(configJson);
            if (raw.containsKey('sObject')) {
                cfg.sObjectName = String.valueOf(raw.get('sObject')).trim();
            } else if (raw.containsKey('sObjectName')) {
                cfg.sObjectName = String.valueOf(raw.get('sObjectName')).trim();
            }
            if (raw.containsKey('fields')) {
                cfg.fields = String.valueOf(raw.get('fields')).trim();
            }
            if (raw.containsKey('whereClause')) {
                cfg.whereClause = String.valueOf(raw.get('whereClause')).trim();
            }
            if (raw.containsKey('orderBy')) {
                cfg.orderBy = String.valueOf(raw.get('orderBy')).trim();
            }
            if (raw.containsKey('limit')) {
                Object lim = raw.get('limit');
                if (lim instanceof Integer) {
                    cfg.recordLimit = (Integer) lim;
                } else if (lim instanceof Decimal) {
                    cfg.recordLimit = ((Decimal) lim).intValue();
                } else if (lim instanceof String) {
                    cfg.recordLimit = Integer.valueOf(lim);
                }
            } else if (raw.containsKey('recordLimit')) {
                cfg.recordLimit = Integer.valueOf(raw.get('recordLimit'));
            }
        } catch (Exception e) {
            throw new ProviderException('Invalid Salesforce provider configuration: ' + e.getMessage());
        }

        if (String.isBlank(cfg.sObjectName)) {
            throw new ProviderException('sObject is required in the provider configuration (e.g. "Contact" or "Account").');
        }
        if (cfg.recordLimit == null || cfg.recordLimit <= 0) {
            cfg.recordLimit = 100;
        } else if (cfg.recordLimit > 2000) {
            cfg.recordLimit = 2000;
        }

        return cfg;
    }

    // ─── GridDataProviderV1 ───────────────────────────────────────────

    global appcg.GridDataProviderTypesV1.Capabilities getCapabilities(
        appcg.GridDataProviderTypesV1.ProviderContext context
    ) {
        SalesforceConfig cfg = parseConfig(context);
        try {
            SalesforceClient client = new SalesforceClient();

            // 1. Fetch Remote SObject describe metadata
            Map<String, Object> describeRes = client.describeSObject(cfg.sObjectName);
            Map<String, RemoteFieldMeta> fieldMetaMap = parseDescribeFields(describeRes);

            // 2. Resolve requested fields list
            List<String> fieldList = resolveFieldList(cfg.fields, fieldMetaMap);

            // 3. Query remote records
            String soql = buildSoqlQuery(cfg.sObjectName, fieldList, cfg.whereClause, cfg.orderBy, cfg.recordLimit);
            Map<String, Object> queryRes = client.query(soql);
            List<Object> rawRecords = (List<Object>) queryRes.get('records');

            cachedRecords = parseRecords(rawRecords, fieldList);

            appcg.GridDataProviderTypesV1.Capabilities capabilities = new appcg.GridDataProviderTypesV1.Capabilities();
            capabilities.supportedFeatures = new Set<String>{
                'SEARCH', 'REFRESH', 'ADD', 'EDIT', 'DELETE', 'DOWNLOAD_CSV'
            };
            capabilities.supportedRowActions = new Set<String>{ 'DELETE' };
            capabilities.supportsServerPagination = false;
            capabilities.columns = buildColumnDefinitions(fieldList, fieldMetaMap);
            return capabilities;
        } finally {
        }
    }

    global appcg.GridDataProviderTypesV1.PageResult getData(
        appcg.GridDataProviderTypesV1.QueryRequest request
    ) {
        try {
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
                pageSize = Math.min(recordLimit, 2000);
            } else {
                pageSize = (gridDef?.appcg__Record_Limit__c != null && gridDef.appcg__Record_Limit__c > 0)
                    ? Math.min(requestedPageSize, (Integer) gridDef.appcg__Record_Limit__c)
                    : Math.min(requestedPageSize, 2000);
            }

            if (cachedRecords != null) {
                records = cachedRecords;
                cachedRecords = null;
            } else {
                SalesforceConfig cfg = parseConfig(request.context);
                SalesforceClient client = new SalesforceClient();
                Map<String, Object> describeRes = client.describeSObject(cfg.sObjectName);
                Map<String, RemoteFieldMeta> fieldMetaMap = parseDescribeFields(describeRes);
                List<String> fieldList = resolveFieldList(cfg.fields, fieldMetaMap);

                String soql = buildSoqlQuery(cfg.sObjectName, fieldList, cfg.whereClause, cfg.orderBy, pageSize);
                Map<String, Object> queryRes = client.query(soql);
                List<Object> rawRecords = (List<Object>) queryRes.get('records');
                records = parseRecords(rawRecords, fieldList);
            }

            while (records != null && records.size() > pageSize) {
                records.remove(records.size() - 1);
            }

            // Apply client-side search filter
            if (String.isNotBlank(request.searchTerm)) {
                records = filterBySearch(records, request.searchTerm);
            }

            appcg.GridDataProviderTypesV1.PageResult result = new appcg.GridDataProviderTypesV1.PageResult();
            result.records = records;
            result.totalCount = records.size();
            return result;
        } finally {
        }
    }

    // ─── GridDataMutationProviderV1 ───────────────────────────────────

    global appcg.GridDataProviderTypesV1.SaveResult saveRecords(
        appcg.GridDataProviderTypesV1.SaveRequest request
    ) {
        SalesforceConfig cfg = parseConfig(request.context);
        try {
            SalesforceClient client = new SalesforceClient();
            Map<String, Object> describeRes = client.describeSObject(cfg.sObjectName);
            Map<String, RemoteFieldMeta> fieldMetaMap = parseDescribeFields(describeRes);

            List<Map<String, Object>> saved = new List<Map<String, Object>>();

            for (Map<String, Object> record : request.records) {
                String recId = (String) record.get('Id');
                Map<String, Object> cleanFields = filterWritableFields(record, fieldMetaMap);

                if (String.isBlank(recId)) {
                    // Create
                    Map<String, Object> createRes = client.createRecord(cfg.sObjectName, cleanFields);
                    String newId = (String) createRes.get('id');
                    Map<String, Object> createdRow = new Map<String, Object>(record);
                    createdRow.put('Id', newId);
                    saved.add(createdRow);
                } else {
                    // Update
                    client.updateRecord(cfg.sObjectName, recId, cleanFields);
                    saved.add(record);
                }
            }

            appcg.GridDataProviderTypesV1.SaveResult result = new appcg.GridDataProviderTypesV1.SaveResult();
            result.records = saved;
            return result;
        } finally {
        }
    }

    global void deleteRecords(appcg.GridDataProviderTypesV1.DeleteRequest request) {
        if (request.recordIds == null || request.recordIds.isEmpty()) {
            return;
        }
        SalesforceConfig cfg = parseConfig(request.context);
        try {
            SalesforceClient client = new SalesforceClient();
            for (String recId : request.recordIds) {
                if (String.isNotBlank(recId)) {
                    client.deleteRecord(cfg.sObjectName, recId);
                }
            }
        } finally {
        }
    }

    // ─── Schema & Field Helpers ───────────────────────────────────────

    @TestVisible
    private class RemoteFieldMeta {
        public String name;
        public String label;
        public String type;
        public Boolean updateable;
        public Boolean createable;
        public Boolean calculated;
        public List<appcg.GridDataProviderTypesV1.Option> picklistOptions;
    }

    @TestVisible
    private static Map<String, RemoteFieldMeta> parseDescribeFields(Map<String, Object> describeRes) {
        Map<String, RemoteFieldMeta> mapByName = new Map<String, RemoteFieldMeta>();
        if (describeRes == null || !describeRes.containsKey('fields')) {
            return mapByName;
        }

        List<Object> rawFields = (List<Object>) describeRes.get('fields');
        for (Object fObj : rawFields) {
            Map<String, Object> fMap = (Map<String, Object>) fObj;
            RemoteFieldMeta meta = new RemoteFieldMeta();
            meta.name = (String) fMap.get('name');
            meta.label = (String) fMap.get('label');
            meta.type = (String) fMap.get('type');
            meta.updateable = fMap.get('updateable') == true;
            meta.createable = fMap.get('createable') == true;
            meta.calculated = fMap.get('calculated') == true;
            meta.picklistOptions = new List<appcg.GridDataProviderTypesV1.Option>();

            if (fMap.containsKey('picklistValues')) {
                List<Object> pVals = (List<Object>) fMap.get('picklistValues');
                if (pVals != null) {
                    for (Object pObj : pVals) {
                        Map<String, Object> pMap = (Map<String, Object>) pObj;
                        if (pMap.get('active') == true) {
                            appcg.GridDataProviderTypesV1.Option opt = new appcg.GridDataProviderTypesV1.Option();
                            opt.label = (String) pMap.get('label');
                            opt.value = (String) pMap.get('value');
                            meta.picklistOptions.add(opt);
                        }
                    }
                }
            }
            mapByName.put(meta.name.toLowerCase(), meta);
        }
        return mapByName;
    }

    @TestVisible
    private static List<String> resolveFieldList(String userFields, Map<String, RemoteFieldMeta> fieldMetaMap) {
        List<String> listFields = new List<String>();
        Set<String> seen = new Set<String>();

        // Always ensure Id is in the field list
        listFields.add('Id');
        seen.add('id');

        if (String.isNotBlank(userFields)) {
            for (String part : userFields.split(',')) {
                String trimmed = part.trim();
                if (String.isNotBlank(trimmed) && !seen.contains(trimmed.toLowerCase())) {
                    RemoteFieldMeta meta = fieldMetaMap.get(trimmed.toLowerCase());
                    String canonical = (meta != null) ? meta.name : trimmed;
                    listFields.add(canonical);
                    seen.add(trimmed.toLowerCase());
                }
            }
        } else {
            // Default to first few common fields if no fields specified
            for (String key : new List<String>{ 'name', 'title', 'email', 'phone', 'createddate' }) {
                if (fieldMetaMap.containsKey(key) && !seen.contains(key)) {
                    listFields.add(fieldMetaMap.get(key).name);
                    seen.add(key);
                }
            }
        }
        return listFields;
    }

    @TestVisible
    private static String buildSoqlQuery(
        String sObjectApiName,
        List<String> fieldList,
        String whereClause,
        String orderBy,
        Integer recordLimit
    ) {
        String soql = 'SELECT ' + String.join(fieldList, ', ') + ' FROM ' + sObjectApiName;
        if (String.isNotBlank(whereClause)) {
            soql += ' WHERE ' + whereClause;
        }
        if (String.isNotBlank(orderBy)) {
            soql += ' ORDER BY ' + orderBy;
        }
        if (recordLimit != null && recordLimit > 0) {
            soql += ' LIMIT ' + recordLimit;
        }
        return soql;
    }

    @TestVisible
    private static List<Map<String, Object>> parseRecords(
        List<Object> rawRecords,
        List<String> fieldList
    ) {
        List<Map<String, Object>> parsed = new List<Map<String, Object>>();
        if (rawRecords == null) return parsed;

        for (Object rObj : rawRecords) {
            Map<String, Object> rMap = (Map<String, Object>) rObj;
            Map<String, Object> row = new Map<String, Object>();

            for (String fName : fieldList) {
                Object val = rMap.get(fName);
                if (val instanceof Map<String, Object>) {
                    // Relationship object or nested map -> ignore attributes or stringify
                    if ('attributes'.equalsIgnoreCase(fName)) continue;
                    row.put(fName, JSON.serialize(val));
                } else {
                    row.put(fName, val == null ? '' : val);
                }
            }
            if (!row.containsKey('Id') && rMap.containsKey('Id')) {
                row.put('Id', String.valueOf(rMap.get('Id')));
            }
            parsed.add(row);
        }
        return parsed;
    }

    @TestVisible
    private static Map<String, Object> filterWritableFields(
        Map<String, Object> record,
        Map<String, RemoteFieldMeta> fieldMetaMap
    ) {
        Map<String, Object> clean = new Map<String, Object>();
        for (String k : record.keySet()) {
            String lower = k.toLowerCase();
            if (SYSTEM_READ_ONLY_FIELDS.contains(lower) || 'attributes'.equals(lower)) {
                continue;
            }
            RemoteFieldMeta meta = fieldMetaMap.get(lower);
            if (meta != null && meta.updateable == false && meta.createable == false) {
                continue;
            }
            if (meta != null && meta.calculated == true) {
                continue;
            }
            clean.put(k, record.get(k));
        }
        return clean;
    }

    @TestVisible
    private static List<appcg.GridDataProviderTypesV1.ColumnDefinition> buildColumnDefinitions(
        List<String> fieldList,
        Map<String, RemoteFieldMeta> fieldMetaMap
    ) {
        List<appcg.GridDataProviderTypesV1.ColumnDefinition> cols = new List<appcg.GridDataProviderTypesV1.ColumnDefinition>();

        for (String fName : fieldList) {
            String lower = fName.toLowerCase();
            RemoteFieldMeta meta = fieldMetaMap.get(lower);

            appcg.GridDataProviderTypesV1.ColumnDefinition col = new appcg.GridDataProviderTypesV1.ColumnDefinition();
            col.id = (meta != null) ? meta.name : fName;
            col.label = (meta != null && String.isNotBlank(meta.label)) ? meta.label : fName;

            if ('id'.equals(lower)) {
                col.label = 'ID';
                col.fieldType = 'TEXT';
                col.visible = false;
                col.isReadOnly = true;
                col.columnWidth = '140px';
            } else {
                col.visible = true;
                col.fieldType = mapFieldType(meta != null ? meta.type : 'string');
                col.isReadOnly = (meta != null && meta.updateable == false) ||
                                 (meta != null && meta.calculated == true) ||
                                 SYSTEM_READ_ONLY_FIELDS.contains(lower);

                if (meta != null && !meta.picklistOptions.isEmpty()) {
                    col.picklistOptions = meta.picklistOptions;
                }
            }
            cols.add(col);
        }
        return cols;
    }

    @TestVisible
    private static String mapFieldType(String sfType) {
        if (String.isBlank(sfType)) return 'TEXT';
        String t = sfType.toLowerCase();

        if (t == 'boolean') return 'BOOLEAN';
        if (t == 'int' || t == 'integer' || t == 'double' || t == 'currency' || t == 'percent') return 'NUMBER';
        if (t == 'date' || t == 'datetime' || t == 'time') return 'DATETIME';
        if (t == 'picklist') return 'PICKLIST';
        if (t == 'phone') return 'PHONE';
        if (t == 'email') return 'EMAIL';
        if (t == 'url') return 'URL';
        return 'TEXT';
    }

    private static List<Map<String, Object>> filterBySearch(
        List<Map<String, Object>> records,
        String searchTerm
    ) {
        String lower = searchTerm.toLowerCase();
        List<Map<String, Object>> filtered = new List<Map<String, Object>>();
        for (Map<String, Object> record : records) {
            for (String key : record.keySet()) {
                if ('Id'.equalsIgnoreCase(key)) continue;
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
