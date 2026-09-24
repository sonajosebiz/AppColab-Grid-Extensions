global with sharing class SalesforceGridDataProvider
    implements appcg.GridDataProviderV1, appcg.GridDataMutationProviderV1 {

    public class ProviderException extends Exception {}


    private static final Set<String> SYSTEM_READ_ONLY_FIELDS = new Set<String>{
        'id', 'createddate', 'createdbyid', 'lastmodifieddate', 'lastmodifiedbyid',
        'systemmodstamp', 'isdeleted'
    };

    private static final Integer MAX_RECORDS = 50000;
    private static final Integer MAX_PAGE_SIZE = 2000;

    // ─── Config ───────────────────────────────────────────────────────

    @TestVisible
    private class SalesforceConfig {
        public String sObjectName;
        public String fields;
        public String whereClause;
        public String orderBy;
        public Integer recordLimit;
        public String parentMatchColumn;
        public String parentMatchField;
        public Boolean autoPopulateParent;
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
            if (raw.containsKey('parentMatchColumn') && raw.get('parentMatchColumn') != null) {
                cfg.parentMatchColumn = String.valueOf(raw.get('parentMatchColumn')).trim();
            }
            if (raw.containsKey('parentMatchField') && raw.get('parentMatchField') != null) {
                cfg.parentMatchField = String.valueOf(raw.get('parentMatchField')).trim();
            }
            cfg.autoPopulateParent = raw.get('autoPopulateParent') == true;
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
        } else if (cfg.recordLimit > MAX_RECORDS) {
            cfg.recordLimit = MAX_RECORDS;
        }
        if (String.isNotBlank(cfg.parentMatchColumn) && String.isBlank(cfg.parentMatchField)) {
            cfg.parentMatchField = 'Id';
        }
        if (cfg.autoPopulateParent == true && String.isBlank(cfg.parentMatchColumn)) {
            throw new ProviderException('parentMatchColumn is required when autoPopulateParent is enabled.');
        }

        return cfg;
    }

    // ─── GridDataProviderV1 ───────────────────────────────────────────

    global appcg.GridDataProviderTypesV1.Capabilities getCapabilities(
        appcg.GridDataProviderTypesV1.ProviderContext context
    ) {
        SalesforceConfig cfg = parseConfig(context);

        SalesforceClient client = new SalesforceClient();

        Map<String, Object> describeRes = client.describeSObject(cfg.sObjectName);
        Map<String, RemoteFieldMeta> fieldMetaMap = parseDescribeFields(describeRes);
        List<String> fieldList = resolveFieldList(cfg.fields, fieldMetaMap);
        String parentColumn = resolveParentMatchColumn(cfg, fieldMetaMap, context);

        appcg.GridDataProviderTypesV1.Capabilities capabilities = new appcg.GridDataProviderTypesV1.Capabilities();
        capabilities.supportedFeatures = new Set<String>{
            'SEARCH', 'REFRESH', 'ADD', 'EDIT', 'DELETE', 'DOWNLOAD_CSV'
        };
        capabilities.supportedRowActions = new Set<String>{ 'DELETE' };
        capabilities.supportsServerPagination = true;
        capabilities.maxPageSize = MAX_PAGE_SIZE;
        capabilities.columns = buildColumnDefinitions(fieldList, fieldMetaMap);
        if (cfg.autoPopulateParent == true && parentColumn != null) {
            for (appcg.GridDataProviderTypesV1.ColumnDefinition column : capabilities.columns) {
                if (column.id.equalsIgnoreCase(parentColumn)) {
                    column.isReadOnly = true;
                }
            }
        }
        return capabilities;
    }

    global appcg.GridDataProviderTypesV1.PageResult getData(
        appcg.GridDataProviderTypesV1.QueryRequest request
    ) {
        SalesforceConfig cfg = parseConfig(request?.context);
        appcg__Grid_Definition__c gridDef = getGridDefinition(request?.context);
        String paginationType = gridDef?.appcg__Pagination_Type__c;
        Boolean clientSide = paginationType == 'Client-Side';
        Integer requestedPageSize = (request?.pageSize != null && request.pageSize > 0)
            ? request.pageSize
            : (gridDef?.appcg__Page_Size__c != null ? Integer.valueOf(gridDef.appcg__Page_Size__c) : 20);
        Integer pageSize = clientSide ? cfg.recordLimit : Math.min(requestedPageSize, MAX_PAGE_SIZE);
        Integer startIndex = clientSide ? 0 : Math.max(0, request?.startIndex ?? 0);
        Boolean searching = String.isNotBlank(request?.searchTerm);

        SalesforceClient client = new SalesforceClient();
        Map<String, RemoteFieldMeta> fieldMetaMap = parseDescribeFields(client.describeSObject(cfg.sObjectName));
        List<String> fieldList = resolveFieldList(cfg.fields, fieldMetaMap);
        String parentColumn = resolveParentMatchColumn(cfg, fieldMetaMap, request?.context);
        String parentValue = parentColumn == null ? null : resolveParentMatchValue(cfg, request.context);

        appcg.GridDataProviderTypesV1.PageResult result = new appcg.GridDataProviderTypesV1.PageResult();
        result.records = new List<Map<String, Object>>();
        if (parentColumn != null && String.isBlank(parentValue)) {
            result.totalCount = 0;
            return result;
        }

        String whereClause = cfg.whereClause;
        if (parentColumn != null) {
            String predicate = parentColumn + ' = \'' + String.escapeSingleQuotes(parentValue) + '\'';
            whereClause = String.isBlank(whereClause)
                ? predicate : '(' + whereClause + ') AND ' + predicate;
        }

        String orderBy = String.isBlank(cfg.orderBy) ? 'Id ASC' : cfg.orderBy;
        if (!Pattern.compile('(?i)(^|,)\\s*Id\\s*(ASC|DESC)?\\s*(,|$)').matcher(orderBy).find()) {
            orderBy += ', Id ASC';
        }
        String soql = buildSoqlQuery(cfg.sObjectName, fieldList, whereClause, orderBy, cfg.recordLimit);
        Map<String, Object> response = client.query(soql);
        Integer totalCount = response.get('totalSize') == null
            ? 0 : Math.min(cfg.recordLimit, Integer.valueOf(String.valueOf(response.get('totalSize'))));
        if (!clientSide && !searching && startIndex >= totalCount) {
            result.totalCount = totalCount;
            return result;
        }
        Integer index = 0;
        Integer endIndex = startIndex >= cfg.recordLimit
            ? cfg.recordLimit : Math.min(cfg.recordLimit, startIndex + pageSize);
        Boolean fetchAll = clientSide || searching;
        Integer matchedCount = 0;
        String lowerSearch = searching ? request.searchTerm.toLowerCase() : null;
        while (response != null) {
            List<Object> batch = (List<Object>) response.get('records');
            if (batch != null) {
                for (Object rawRecord : batch) {
                    if (index >= cfg.recordLimit) break;
                    if (searching) {
                        Map<String, Object> row = parseRecords(new List<Object>{ rawRecord }, fieldList)[0];
                        if (recordMatchesSearch(row, lowerSearch)) {
                            if (clientSide || (matchedCount >= startIndex && matchedCount < endIndex)) {
                                result.records.add(row);
                            }
                            matchedCount++;
                        }
                    } else if (clientSide || (index >= startIndex && index < endIndex)) {
                        result.records.addAll(parseRecords(new List<Object>{ rawRecord }, fieldList));
                    }
                    index++;
                }
            }
            if (index >= cfg.recordLimit || (!fetchAll && index >= endIndex) || response.get('done') == true) {
                break;
            }
            String nextUrl = (String) response.get('nextRecordsUrl');
            if (String.isBlank(nextUrl)) {
                throw new ProviderException('Salesforce query ended without a query locator.');
            }
            response = client.queryMore(nextUrl);
        }

        if (searching) {
            totalCount = matchedCount;
        }

        result.totalCount = totalCount;
        return result;
    }

    // ─── GridDataMutationProviderV1 ───────────────────────────────────

    global appcg.GridDataProviderTypesV1.SaveResult saveRecords(
        appcg.GridDataProviderTypesV1.SaveRequest request
    ) {
        SalesforceConfig cfg = parseConfig(request.context);

        SalesforceClient client = new SalesforceClient();
        Map<String, Object> describeRes = client.describeSObject(cfg.sObjectName);
        Map<String, RemoteFieldMeta> fieldMetaMap = parseDescribeFields(describeRes);
        String parentColumn = resolveParentMatchColumn(cfg, fieldMetaMap, request.context);
        String parentValue = null;
        Boolean hasNewRecords = false;
        for (Map<String, Object> record : request.records) {
            String recordId = record.get('Id') == null ? null : String.valueOf(record.get('Id'));
            if (String.isBlank(recordId) || recordId.startsWith('TEMP_')) {
                hasNewRecords = true;
                break;
            }
        }
        if (hasNewRecords && cfg.autoPopulateParent == true && parentColumn != null) {
            parentValue = resolveParentMatchValue(cfg, request.context);
            if (String.isBlank(parentValue)) {
                throw new ProviderException(
                    'The current parent record has no value for ' + cfg.parentMatchField + '.'
                );
            }
            if (fieldMetaMap.get(parentColumn.toLowerCase()).createable != true) {
                throw new ProviderException('Parent match column "' + parentColumn + '" is not createable.');
            }
        }

        List<Map<String, Object>> saved = new List<Map<String, Object>>();

        for (Map<String, Object> record : request.records) {
            String recId = record.get('Id') == null ? null : String.valueOf(record.get('Id'));
            Map<String, Object> cleanFields = filterWritableFields(record, fieldMetaMap);

            if (String.isBlank(recId) || recId.startsWith('TEMP_')) {
                // Create
                if (parentValue != null) {
                    cleanFields.put(parentColumn, parentValue);
                }
                Map<String, Object> createRes = client.createRecord(cfg.sObjectName, cleanFields);
                String newId = (String) createRes.get('id');
                Map<String, Object> createdRow = new Map<String, Object>(record);
                createdRow.put('Id', newId);
                if (parentValue != null) {
                    createdRow.put(parentColumn, parentValue);
                }
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
    }

    global void deleteRecords(appcg.GridDataProviderTypesV1.DeleteRequest request) {
        if (request.recordIds == null || request.recordIds.isEmpty()) {
            return;
        }
        SalesforceConfig cfg = parseConfig(request.context);

        SalesforceClient client = new SalesforceClient();
        for (String recId : request.recordIds) {
            if (String.isNotBlank(recId)) {
                client.deleteRecord(cfg.sObjectName, recId);
            }
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
    private static String resolveParentMatchColumn(
        SalesforceConfig cfg,
        Map<String, RemoteFieldMeta> fieldMetaMap,
        appcg.GridDataProviderTypesV1.ProviderContext context
    ) {
        if (context == null || String.isBlank(context.parentId) || String.isBlank(cfg.parentMatchColumn)) {
            return null;
        }
        RemoteFieldMeta meta = fieldMetaMap.get(cfg.parentMatchColumn.toLowerCase());
        if (meta == null) {
            throw new ProviderException(
                'Parent match column "' + cfg.parentMatchColumn + '" was not found on remote ' + cfg.sObjectName + '.'
            );
        }
        return meta.name;
    }

    @TestVisible
    private static String resolveParentMatchValue(
        SalesforceConfig cfg,
        appcg.GridDataProviderTypesV1.ProviderContext context
    ) {
        if (context == null || String.isBlank(context.parentId)) {
            return null;
        }
        String requestedField = String.isBlank(cfg.parentMatchField) ? 'Id' : cfg.parentMatchField.trim();
        if ('Id'.equalsIgnoreCase(requestedField)) {
            return context.parentId;
        }
        try {
            Id parentRecordId = (Id) context.parentId;
            Schema.DescribeSObjectResult parentDescribe = parentRecordId.getSObjectType().getDescribe();
            String fieldApiName;
            for (String candidate : parentDescribe.fields.getMap().keySet()) {
                if (candidate.equalsIgnoreCase(requestedField)) {
                    fieldApiName = candidate;
                    break;
                }
            }
            if (fieldApiName == null) {
                throw new ProviderException(
                    'Parent match field "' + requestedField + '" does not exist on ' + parentDescribe.getName() + '.'
                );
            }
            String query = 'SELECT ' + fieldApiName + ' FROM ' + parentDescribe.getName() +
                ' WHERE Id = :parentRecordId WITH USER_MODE LIMIT 1';
            List<SObject> parents = Database.query(query);
            if (parents.isEmpty()) {
                return null;
            }
            Object value = parents[0].get(fieldApiName);
            return value == null ? null : String.valueOf(value);
        } catch (ProviderException e) {
            throw e;
        } catch (Exception e) {
            throw new ProviderException('Unable to resolve the parent match value: ' + e.getMessage());
        }
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

    private static Boolean recordMatchesSearch(Map<String, Object> record, String lowerSearch) {
        for (String key : record.keySet()) {
            if ('Id'.equalsIgnoreCase(key)) continue;
            Object val = record.get(key);
            if (val != null && String.valueOf(val).toLowerCase().contains(lowerSearch)) {
                return true;
            }
        }
        return false;
    }
}
