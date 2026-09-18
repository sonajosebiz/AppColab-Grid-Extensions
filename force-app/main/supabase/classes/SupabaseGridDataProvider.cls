global with sharing class SupabaseGridDataProvider
    implements appcg.GridDataProviderV1, appcg.GridDataMutationProviderV1 {

    public class ProviderException extends Exception {}


    // ─── Instance Cache ───────────────────────────────────────────────
    private List<Map<String, Object>> cachedRecords;
    private Integer cachedTotalCount;

    // ─── Config ───────────────────────────────────────────────────────

    @TestVisible
    private class SupabaseConfig {
        public String tableName;
        public String idColumn;
        public String selectFields;
        public String orderClause;
        public Integer recordLimit;
        public String parentMatchColumn;
        public String surveyId;
        public String parentId;
        public String filterQuery;
        public List<appcg.GridDataProviderTypesV1.ColumnDefinition> customColumns;
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
    private static SupabaseConfig parseConfig(appcg.GridDataProviderTypesV1.ProviderContext context) {
        appcg__Grid_Definition__c gridDef = getGridDefinition(context);
        String configJson = gridDef != null ? gridDef.appcg__Data_Provider_Config__c : null;
        if (String.isBlank(configJson)) {
            throw new ProviderException(
                'Supabase provider requires configuration. ' +
                'Set Data Provider Configuration with {"tableName":"contacts"}'
            );
        }

        SupabaseConfig cfg = new SupabaseConfig();
        cfg.idColumn = 'id';
        cfg.selectFields = '*';
        cfg.recordLimit = (gridDef?.appcg__Record_Limit__c != null && gridDef.appcg__Record_Limit__c > 0)
            ? (Integer) gridDef.appcg__Record_Limit__c
            : 100;

        try {
            Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(configJson);
            if (raw.containsKey('tableName')) {
                cfg.tableName = String.valueOf(raw.get('tableName')).trim();
            } else if (raw.containsKey('table')) {
                cfg.tableName = String.valueOf(raw.get('table')).trim();
            }

            if (raw.containsKey('idColumn')) {
                cfg.idColumn = String.valueOf(raw.get('idColumn')).trim();
            }
            if (raw.containsKey('select')) {
                cfg.selectFields = String.valueOf(raw.get('select')).trim();
            } else if (raw.containsKey('selectFields')) {
                cfg.selectFields = String.valueOf(raw.get('selectFields')).trim();
            }

            if (raw.containsKey('order')) {
                cfg.orderClause = String.valueOf(raw.get('order')).trim();
            } else if (raw.containsKey('orderBy')) {
                cfg.orderClause = String.valueOf(raw.get('orderBy')).trim();
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

            if (raw.containsKey('parentMatchColumn')) {
                cfg.parentMatchColumn = String.valueOf(raw.get('parentMatchColumn')).trim();
            }
            if (raw.containsKey('surveyId')) {
                cfg.surveyId = String.valueOf(raw.get('surveyId')).trim();
            } else if (raw.containsKey('survey_id')) {
                cfg.surveyId = String.valueOf(raw.get('survey_id')).trim();
            }
            if (raw.containsKey('parentId')) {
                cfg.parentId = String.valueOf(raw.get('parentId')).trim();
            }
            if (raw.containsKey('filterQuery')) {
                cfg.filterQuery = String.valueOf(raw.get('filterQuery')).trim();
            } else if (raw.containsKey('filter')) {
                cfg.filterQuery = String.valueOf(raw.get('filter')).trim();
            }

            // Resilience: If user put "SRV-0002" into parentMatchColumn in wizard
            if (String.isNotBlank(cfg.parentMatchColumn) && cfg.parentMatchColumn.startsWithIgnoreCase('SRV-')) {
                cfg.surveyId = cfg.parentMatchColumn;
                cfg.parentMatchColumn = 'survey_id';
            }

            // Custom columns override (optional)
            if (raw.containsKey('columns')) {
                cfg.customColumns = parseCustomColumns(raw.get('columns'));
            }
        } catch (Exception e) {
            throw new ProviderException('Invalid Supabase provider configuration: ' + e.getMessage());
        }

        if (String.isBlank(cfg.tableName)) {
            throw new ProviderException('tableName is required in configuration (e.g. "contacts" or "orders").');
        }

        return cfg;
    }

    @TestVisible
    private static String buildEffectiveFilter(SupabaseConfig cfg, appcg.GridDataProviderTypesV1.ProviderContext context) {
        List<String> filters = new List<String>();

        String targetParentId = null;
        if (context != null && String.isNotBlank(context.parentId)) {
            targetParentId = context.parentId;
        } else if (String.isNotBlank(cfg.parentId)) {
            targetParentId = cfg.parentId;
        } else if (String.isNotBlank(cfg.surveyId)) {
            targetParentId = cfg.surveyId;
        }

        String matchCol = String.isNotBlank(cfg.parentMatchColumn) ? cfg.parentMatchColumn : null;
        if (String.isNotBlank(targetParentId) && String.isNotBlank(matchCol)) {
            filters.add(EncodingUtil.urlEncode(matchCol, 'UTF-8') + '=eq.' + EncodingUtil.urlEncode(targetParentId, 'UTF-8'));
        }

        if (String.isNotBlank(cfg.filterQuery)) {
            filters.add(cfg.filterQuery);
        }

        return filters.isEmpty() ? null : String.join(filters, '&');
    }

    private static List<appcg.GridDataProviderTypesV1.ColumnDefinition> parseCustomColumns(Object rawColsObj) {
        List<appcg.GridDataProviderTypesV1.ColumnDefinition> cols = new List<appcg.GridDataProviderTypesV1.ColumnDefinition>();
        if (rawColsObj instanceof List<Object>) {
            List<Object> rawList = (List<Object>) rawColsObj;
            for (Object item : rawList) {
                if (item instanceof Map<String, Object>) {
                    Map<String, Object> colMap = (Map<String, Object>) item;
                    appcg.GridDataProviderTypesV1.ColumnDefinition col = new appcg.GridDataProviderTypesV1.ColumnDefinition();
                    col.id = String.valueOf(colMap.get('id'));
                    col.label = colMap.containsKey('label') ? String.valueOf(colMap.get('label')) : col.id;
                    col.fieldType = colMap.containsKey('type') ? String.valueOf(colMap.get('type')) : 'TEXT';
                    col.isReadOnly = colMap.containsKey('isReadOnly') ? (Boolean) colMap.get('isReadOnly') : false;
                    col.visible = colMap.containsKey('visible') ? (Boolean) colMap.get('visible') : true;
                    if (colMap.containsKey('width')) {
                        col.columnWidth = String.valueOf(colMap.get('width'));
                    } else if (colMap.containsKey('columnWidth')) {
                        col.columnWidth = String.valueOf(colMap.get('columnWidth'));
                    }
                    cols.add(col);
                }
            }
        }
        return cols;
    }

    // ─── GridDataProviderV1 ───────────────────────────────────────────

    global appcg.GridDataProviderTypesV1.Capabilities getCapabilities(
        appcg.GridDataProviderTypesV1.ProviderContext context
    ) {
        SupabaseConfig cfg = parseConfig(context);
        try {
            String effectiveFilter = buildEffectiveFilter(cfg, context);
            SupabaseClient client = new SupabaseClient();
            SupabaseClient.QueryResult qr = client.queryTableWithCount(
                cfg.tableName,
                cfg.selectFields,
                cfg.orderClause,
                20,
                0,
                effectiveFilter
            );

            cachedRecords = normalizeRecords(qr.records, cfg.idColumn);
            cachedTotalCount = qr.totalCount;

            appcg.GridDataProviderTypesV1.Capabilities capabilities = new appcg.GridDataProviderTypesV1.Capabilities();
            capabilities.supportedFeatures = new Set<String>{
                'SEARCH', 'REFRESH', 'ADD', 'EDIT', 'DELETE', 'DOWNLOAD_CSV'
            };
            capabilities.supportedRowActions = new Set<String>{ 'DELETE' };
            capabilities.supportsServerPagination = true;
            capabilities.maxPageSize = 100;

            if (cfg.customColumns != null && !cfg.customColumns.isEmpty()) {
                capabilities.columns = cfg.customColumns;
            } else {
                capabilities.columns = inferColumnDefinitions(cachedRecords, cfg.idColumn);
            }

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
                : 1000;

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
                    : Math.min(requestedPageSize, 1000);
            }

            if (cachedRecords != null && startIndex == 0) {
                records = cachedRecords;
                totalCount = cachedTotalCount;
                cachedRecords = null;
            } else {
                SupabaseConfig cfg = parseConfig(request.context);
                String effectiveFilter = buildEffectiveFilter(cfg, request?.context);
                SupabaseClient client = new SupabaseClient();
                SupabaseClient.QueryResult qr = client.queryTableWithCount(
                    cfg.tableName,
                    cfg.selectFields,
                    cfg.orderClause,
                    pageSize,
                    startIndex,
                    effectiveFilter
                );
                records = normalizeRecords(qr.records, cfg.idColumn);
                totalCount = qr.totalCount;
            }

            while (records != null && records.size() > pageSize) {
                records.remove(records.size() - 1);
            }

            // Apply search filter
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

    // ─── GridDataMutationProviderV1 ───────────────────────────────────

    global appcg.GridDataProviderTypesV1.SaveResult saveRecords(
        appcg.GridDataProviderTypesV1.SaveRequest request
    ) {
        SupabaseConfig cfg = parseConfig(request.context);
        try {
            SupabaseClient client = new SupabaseClient();
            List<Map<String, Object>> savedRecords = new List<Map<String, Object>>();

            for (Map<String, Object> record : request.records) {
                Object rawId = record.get('Id');
                String recordId = rawId == null ? null : String.valueOf(rawId);

                Map<String, Object> payload = cleanPayloadFields(record, cfg.idColumn);

                if (String.isBlank(recordId) || recordId.startsWith('TEMP_')) {
                    // Create new record
                    List<Object> createdList = client.insertRecord(cfg.tableName, payload);
                    if (!createdList.isEmpty() && createdList[0] instanceof Map<String, Object>) {
                        Map<String, Object> createdMap = (Map<String, Object>) createdList[0];
                        if (createdMap.containsKey(cfg.idColumn)) {
                            record.put('Id', String.valueOf(createdMap.get(cfg.idColumn)));
                            record.put(cfg.idColumn, createdMap.get(cfg.idColumn));
                        }
                    }
                } else {
                    // Update existing record
                    client.updateRecord(cfg.tableName, cfg.idColumn, recordId, payload);
                }
                savedRecords.add(record);
            }

            appcg.GridDataProviderTypesV1.SaveResult result = new appcg.GridDataProviderTypesV1.SaveResult();
            result.records = savedRecords;
            return result;
        } finally {
        }
    }

    global void deleteRecords(appcg.GridDataProviderTypesV1.DeleteRequest request) {
        if (request.recordIds == null || request.recordIds.isEmpty()) {
            return;
        }
        SupabaseConfig cfg = parseConfig(request.context);
        try {
            SupabaseClient client = new SupabaseClient();
            for (String recId : request.recordIds) {
                client.deleteRecord(cfg.tableName, cfg.idColumn, recId);
            }
        } finally {
        }
    }

    // ─── Record Normalization & Field Helpers ─────────────────────────

    @TestVisible
    private static List<Map<String, Object>> normalizeRecords(
        List<Object> rawList,
        String idColumn
    ) {
        List<Map<String, Object>> records = new List<Map<String, Object>>();
        if (rawList == null) return records;

        Integer index = 1;
        for (Object item : rawList) {
            if (item instanceof Map<String, Object>) {
                Map<String, Object> orig = (Map<String, Object>) item;
                Map<String, Object> row = new Map<String, Object>(orig);

                if (String.isNotBlank(idColumn) && orig.containsKey(idColumn) && orig.get(idColumn) != null) {
                    row.put('Id', String.valueOf(orig.get(idColumn)));
                } else if (!row.containsKey('Id')) {
                    row.put('Id', 'sb_' + index);
                }
                records.add(row);
                index++;
            }
        }
        return records;
    }

    private static Map<String, Object> cleanPayloadFields(
        Map<String, Object> record,
        String idColumn
    ) {
        Map<String, Object> payload = new Map<String, Object>();
        for (String key : record.keySet()) {
            // Exclude grid internal 'Id' and auto-generated audit fields
            if ('Id'.equalsIgnoreCase(key)) {
                continue;
            }
            if (String.isNotBlank(idColumn) && idColumn.equalsIgnoreCase(key)) {
                continue;
            }
            if ('created_at'.equalsIgnoreCase(key) || 'updated_at'.equalsIgnoreCase(key)) {
                continue;
            }
            payload.put(key, record.get(key));
        }
        return payload;
    }

    // ─── Dynamic Column Inference ─────────────────────────────────────

    @TestVisible
    private static List<appcg.GridDataProviderTypesV1.ColumnDefinition> inferColumnDefinitions(
        List<Map<String, Object>> records,
        String idColumn
    ) {
        List<appcg.GridDataProviderTypesV1.ColumnDefinition> columns =
            new List<appcg.GridDataProviderTypesV1.ColumnDefinition>();

        // Hidden Id column
        columns.add(column('Id', 'Row ID', 'TEXT', true, false, '100px'));

        if (records == null || records.isEmpty()) {
            // Default placeholder column if table is empty
            columns.add(column(String.isNotBlank(idColumn) ? idColumn : 'id', 'ID', 'TEXT', true, true, '140px'));
            return columns;
        }

        Map<String, Object> sampleRow = records[0];
        for (String key : sampleRow.keySet()) {
            if ('Id'.equalsIgnoreCase(key)) {
                continue;
            }

            Object val = sampleRow.get(key);
            String fieldType = detectFieldType(val);
            Boolean isReadOnly = isReadOnlyField(key, idColumn);
            String label = formatColumnLabel(key);
            String width = detectColumnWidth(key, fieldType);

            columns.add(column(key, label, fieldType, isReadOnly, true, width));
        }

        return columns;
    }

    private static String detectFieldType(Object val) {
        if (val == null) {
            return 'TEXT';
        }
        if (val instanceof Boolean) {
            return 'BOOLEAN';
        }
        if (val instanceof Decimal || val instanceof Integer || val instanceof Double || val instanceof Long) {
            return 'NUMBER';
        }
        if (val instanceof String) {
            String str = (String) val;
            if (str.contains('@') && str.contains('.')) {
                return 'EMAIL';
            }
            if (str.length() >= 19 && str.contains('T') && (str.endsWith('Z') || str.contains('+'))) {
                return 'DATETIME';
            }
        }
        return 'TEXT';
    }

    private static Boolean isReadOnlyField(String key, String idColumn) {
        if (String.isNotBlank(idColumn) && idColumn.equalsIgnoreCase(key)) {
            return true;
        }
        if ('id'.equalsIgnoreCase(key) || 'created_at'.equalsIgnoreCase(key) || 'updated_at'.equalsIgnoreCase(key)) {
            return true;
        }
        return false;
    }

    private static String formatColumnLabel(String key) {
        if (String.isBlank(key)) return '';
        List<String> parts = key.replace('_', ' ').replace('-', ' ').split(' ');
        List<String> formatted = new List<String>();
        for (String p : parts) {
            if (String.isNotBlank(p)) {
                formatted.add(p.substring(0, 1).toUpperCase() + (p.length() > 1 ? p.substring(1).toLowerCase() : ''));
            }
        }
        return String.join(formatted, ' ');
    }

    private static String detectColumnWidth(String key, String fieldType) {
        if ('id'.equalsIgnoreCase(key) || 'BOOLEAN'.equals(fieldType)) {
            return '120px';
        }
        if ('DATETIME'.equals(fieldType)) {
            return '170px';
        }
        if ('NUMBER'.equals(fieldType)) {
            return '130px';
        }
        if ('EMAIL'.equals(fieldType)) {
            return '200px';
        }
        return null;
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
        String lowerTerm = searchTerm.toLowerCase();
        List<Map<String, Object>> filtered = new List<Map<String, Object>>();
        for (Map<String, Object> rec : records) {
            Boolean matched = false;
            for (String key : rec.keySet()) {
                if ('Id'.equalsIgnoreCase(key)) continue;
                Object val = rec.get(key);
                if (val != null && String.valueOf(val).toLowerCase().contains(lowerTerm)) {
                    matched = true;
                    break;
                }
            }
            if (matched) {
                filtered.add(rec);
            }
        }
        return filtered;
    }
}
