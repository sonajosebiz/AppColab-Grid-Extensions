global with sharing class ExcelGridDataProvider implements appcg.GridDataProviderV1, appcg.GridDataMutationProviderV1 {

    public class ProviderException extends Exception {}

    // ─── Instance Cache ───────────────────────────────────────────────
    private List<String> cachedHeaders;
    private List<Map<String, Object>> cachedRecords;

    // ─── Config ───────────────────────────────────────────────────────

    @TestVisible
    private class ExcelConfig {
        public String workbookId;
        public String filePath;
        public String sheetName;
        public Integer headerRow;
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
    private static ExcelConfig parseConfig(appcg.GridDataProviderTypesV1.ProviderContext context) {
        appcg__Grid_Definition__c gridDef = getGridDefinition(context);
        String configJson = gridDef != null ? gridDef.appcg__Data_Provider_Config__c : null;
        if (String.isBlank(configJson)) {
            throw new ProviderException(
                'Excel provider requires configuration. ' +
                'Set Data Provider Configuration with {"workbookId":"...","sheetName":"Sheet1"}'
            );
        }

        ExcelConfig cfg;
        try {
            cfg = (ExcelConfig) JSON.deserialize(configJson, ExcelConfig.class);
        } catch (Exception e) {
            throw new ProviderException('Invalid Excel provider configuration: ' + e.getMessage());
        }

        if (String.isBlank(cfg.workbookId) && String.isNotBlank(cfg.filePath)) {
            cfg.workbookId = cfg.filePath;
        }
        if (String.isBlank(cfg.workbookId)) {
            throw new ProviderException('workbookId (or filePath) is required in the Excel provider configuration.');
        }
        if (String.isBlank(cfg.sheetName)) {
            cfg.sheetName = 'Sheet1';
        }
        if (cfg.headerRow == null || cfg.headerRow < 1) {
            cfg.headerRow = 1;
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

    global appcg.GridDataProviderTypesV1.Capabilities getCapabilities(appcg.GridDataProviderTypesV1.ProviderContext context) {
        ExcelConfig cfg = parseConfig(context);

        IntegrationLogger.deferInserts = true;
        ExcelClient client = new ExcelClient();
        Map<String, Object> response = client.getUsedRange(cfg.workbookId, cfg.sheetName);
        List<Object> allRows = (List<Object>) response.get('values');

        cachedHeaders = extractHeaders(allRows, cfg.headerRow);
        cachedRecords = parseDataRows(allRows, cachedHeaders, cfg.headerRow);
        validateParentMatchColumn(cfg, cachedHeaders, context);
        cachedRecords = filterByParent(cachedRecords, cfg, context);

        appcg.GridDataProviderTypesV1.Capabilities capabilities = new appcg.GridDataProviderTypesV1.Capabilities();
        capabilities.supportedFeatures = new Set<String>{
            'SEARCH', 'REFRESH', 'ADD', 'EDIT', 'DELETE', 'DOWNLOAD_CSV'
        };
        capabilities.supportedRowActions = new Set<String>{ 'DELETE' };
        capabilities.supportsServerPagination = false;
        capabilities.columns = buildColumnDefinitions(cachedHeaders, cachedRecords, cfg, context);
        return capabilities;
    }

    global appcg.GridDataProviderTypesV1.PageResult getData(appcg.GridDataProviderTypesV1.QueryRequest request) {
        IntegrationLogger.deferInserts = true;
        try {
            List<Map<String, Object>> records;
            ExcelConfig cfg = parseConfig(request.context);

            appcg__Grid_Definition__c gridDef = getGridDefinition(request?.context);
            String paginationType = gridDef?.appcg__Pagination_Type__c;
            Integer recordLimit = (gridDef?.appcg__Record_Limit__c != null && gridDef.appcg__Record_Limit__c > 0)
                ? (Integer) gridDef.appcg__Record_Limit__c
                : 1000;

            Integer pageSize;
            Integer requestedPageSize = (request.pageSize != null && request.pageSize > 0)
                ? request.pageSize
                : (gridDef?.appcg__Page_Size__c != null ? Integer.valueOf(gridDef.appcg__Page_Size__c) : 20);

            if (paginationType == 'Client-Side') {
                pageSize = Math.min(recordLimit, 50000);
            } else {
                pageSize = (gridDef?.appcg__Record_Limit__c != null && gridDef.appcg__Record_Limit__c > 0)
                    ? Math.min(requestedPageSize, (Integer) gridDef.appcg__Record_Limit__c)
                    : Math.min(requestedPageSize, 50000);
            }

            if (cachedRecords != null) {
                records = cachedRecords;
                cachedRecords = null;
            } else {
                ExcelClient client = new ExcelClient();
                Map<String, Object> response = client.getUsedRange(cfg.workbookId, cfg.sheetName);
                List<Object> allRows = (List<Object>) response.get('values');
                List<String> headers = extractHeaders(allRows, cfg.headerRow);
                records = parseDataRows(allRows, headers, cfg.headerRow);
                validateParentMatchColumn(cfg, headers, request.context);
                records = filterByParent(records, cfg, request.context);
            }

            if (String.isNotBlank(request.searchTerm)) {
                records = filterBySearch(records, request.searchTerm);
            }

            while (records != null && records.size() > pageSize) {
                records.remove(records.size() - 1);
            }

            appcg.GridDataProviderTypesV1.PageResult result = new appcg.GridDataProviderTypesV1.PageResult();
            result.records = records;
            result.totalCount = records.size();
            return result;
        } finally {
            IntegrationLogger.deferInserts = false;
            IntegrationLogger.commitLogs();
        }
    }

    // ─── GridDataMutationProviderV1 ───────────────────────────────────

    global appcg.GridDataProviderTypesV1.SaveResult saveRecords(appcg.GridDataProviderTypesV1.SaveRequest request) {
        ExcelConfig cfg = parseConfig(request.context);

        IntegrationLogger.deferInserts = true;
        try {
            ExcelClient client = new ExcelClient();

            // Read usedRange to know headers and current row boundaries
            Map<String, Object> usedRange = client.getUsedRange(cfg.workbookId, cfg.sheetName);
            List<Object> allRows = (List<Object>) usedRange.get('values');
            List<String> headers = extractHeaders(allRows, cfg.headerRow);

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

            if (!newRecords.isEmpty() && cfg.autoPopulateParent == true && request.context != null && String.isNotBlank(request.context.parentId)) {
                validateParentMatchColumn(cfg, headers, request.context);
                String parentMatchValue = resolveParentMatchValue(cfg, request.context);
                if (String.isBlank(parentMatchValue)) {
                    throw new ProviderException('The current parent record has no value for ' + cfg.parentMatchField + '.');
                }
                for (Map<String, Object> record : newRecords) {
                    record.put(cfg.parentMatchColumn, parentMatchValue);
                }
            }

            String lastColLetter = getColumnLetter(headers.size());

            // 1. Update existing rows
            for (Map<String, Object> record : existingRecords) {
                String rowNum = String.valueOf(record.get('Id'));
                List<Object> rowValues = recordToRow(record, headers);
                String rangeAddress = 'A' + rowNum + ':' + lastColLetter + rowNum;
                client.updateRange(cfg.workbookId, cfg.sheetName, rangeAddress, new List<List<Object>>{ rowValues });
            }

            // 2. Append new rows
            if (!newRecords.isEmpty()) {
                Integer nextRowNumber = (allRows != null ? allRows.size() : cfg.headerRow) + 1;
                for (Map<String, Object> record : newRecords) {
                    List<Object> rowValues = recordToRow(record, headers);
                    String rangeAddress = 'A' + nextRowNumber + ':' + lastColLetter + nextRowNumber;
                    client.updateRange(cfg.workbookId, cfg.sheetName, rangeAddress, new List<List<Object>>{ rowValues });
                    record.put('Id', String.valueOf(nextRowNumber));
                    nextRowNumber++;
                }
            }

            appcg.GridDataProviderTypesV1.SaveResult result = new appcg.GridDataProviderTypesV1.SaveResult();
            result.records = request.records;
            return result;
        } finally {
            IntegrationLogger.deferInserts = false;
            IntegrationLogger.commitLogs();
        }
    }

    global void deleteRecords(appcg.GridDataProviderTypesV1.DeleteRequest request) {
        if (request == null || request.recordIds == null || request.recordIds.isEmpty()) return;
        ExcelConfig cfg = parseConfig(request.context);
        IntegrationLogger.deferInserts = true;
        try {
            ExcelClient client = new ExcelClient();
            Map<String, Object> usedRange = client.getUsedRange(cfg.workbookId, cfg.sheetName);
            List<Object> allRows = (List<Object>) usedRange.get('values');
            List<String> headers = extractHeaders(allRows, cfg.headerRow);
            String lastColLetter = getColumnLetter(headers.size());

            // Convert row numbers and sort descending to avoid index shifting during deletion
            List<Integer> rowNums = new List<Integer>();
            for (String recId : request.recordIds) {
                if (String.isNotBlank(recId) && recId.isNumeric()) {
                    rowNums.add(Integer.valueOf(recId));
                }
            }
            rowNums.sort();
            for (Integer i = rowNums.size() - 1; i >= 0; i--) {
                Integer row = rowNums[i];
                String rangeAddress = 'A' + row + ':' + lastColLetter + row;
                client.deleteRowRange(cfg.workbookId, cfg.sheetName, rangeAddress);
            }
        } finally {
            IntegrationLogger.deferInserts = false;
            IntegrationLogger.commitLogs();
        }
    }

    // ─── Helpers ──────────────────────────────────────────────────────

    @TestVisible
    private static List<String> extractHeaders(List<Object> allRows, Integer headerRow) {
        List<String> headers = new List<String>();
        if (allRows == null || allRows.isEmpty() || headerRow > allRows.size()) {
            return headers;
        }
        List<Object> rawHeaders = (List<Object>) allRows[headerRow - 1];
        if (rawHeaders == null) {
            return headers;
        }
        for (Integer i = 0; i < rawHeaders.size(); i++) {
            Object val = rawHeaders[i];
            String name = val != null ? String.valueOf(val).trim() : '';
            if (String.isBlank(name)) {
                name = 'Column' + (i + 1);
            }
            headers.add(name);
        }
        return headers;
    }

    @TestVisible
    private static List<Map<String, Object>> parseDataRows(List<Object> allRows, List<String> headers, Integer headerRow) {
        List<Map<String, Object>> records = new List<Map<String, Object>>();
        if (allRows == null || allRows.size() <= headerRow) {
            return records;
        }
        for (Integer i = headerRow; i < allRows.size(); i++) {
            List<Object> row = (List<Object>) allRows[i];
            Map<String, Object> record = new Map<String, Object>();
            record.put('Id', String.valueOf(i + 1));
            for (Integer j = 0; j < headers.size(); j++) {
                Object cellValue = (row != null && j < row.size()) ? row[j] : '';
                record.put(headers[j], cellValue != null ? cellValue : '');
            }
            records.add(record);
        }
        return records;
    }

    private static List<Object> recordToRow(Map<String, Object> record, List<String> headers) {
        List<Object> row = new List<Object>();
        for (String h : headers) {
            Object v = record.get(h);
            row.add(v == null ? '' : v);
        }
        return row;
    }

    @TestVisible
    private static String getColumnLetter(Integer colIndex) {
        String letter = '';
        Integer temp = (colIndex == null || colIndex < 1) ? 1 : colIndex;
        while (temp > 0) {
            Integer mod = Math.mod(temp - 1, 26);
            letter = String.fromCharArray(new List<Integer>{ 65 + mod }) + letter;
            temp = (temp - mod) / 26;
        }
        return letter;
    }

    private static List<appcg.GridDataProviderTypesV1.ColumnDefinition> buildColumnDefinitions(
        List<String> headers,
        List<Map<String, Object>> records,
        ExcelConfig cfg,
        appcg.GridDataProviderTypesV1.ProviderContext context
    ) {
        List<appcg.GridDataProviderTypesV1.ColumnDefinition> columns = new List<appcg.GridDataProviderTypesV1.ColumnDefinition>();
        columns.add(column('Id', 'ID', 'TEXT', true, false, '60px'));

        Boolean lockParentColumn = (cfg.autoPopulateParent == true && context != null && String.isNotBlank(context.parentId));

        for (String header : headers) {
            Boolean isParentColumn = String.isNotBlank(cfg.parentMatchColumn) && header == cfg.parentMatchColumn;
            String fieldType = inferFieldType(header, records);
            columns.add(column(header, header, fieldType, lockParentColumn && isParentColumn, true, null));
        }
        return columns;
    }

    @TestVisible
    private static String inferFieldType(String header, List<Map<String, Object>> records) {
        if (records == null || records.isEmpty()) return 'TEXT';
        for (Integer i = 0; i < Math.min(records.size(), 10); i++) {
            Object v = records[i].get(header);
            if (v instanceof Boolean) return 'BOOLEAN';
            if (v instanceof Decimal || v instanceof Integer || v instanceof Double) return 'NUMBER';
            if (v instanceof String) {
                String str = (String) v;
                if (str.contains('@') && str.contains('.')) return 'EMAIL';
            }
        }
        return 'TEXT';
    }

    private static appcg.GridDataProviderTypesV1.ColumnDefinition column(
        String id, String label, String fieldType, Boolean isReadOnly, Boolean visible, String width
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

    private static void validateParentMatchColumn(
        ExcelConfig cfg, List<String> headers, appcg.GridDataProviderTypesV1.ProviderContext context
    ) {
        if (context == null || String.isBlank(context.parentId) || String.isBlank(cfg.parentMatchColumn)) {
            return;
        }
        if (headers == null || !headers.contains(cfg.parentMatchColumn)) {
            throw new ProviderException('Parent match column "' + cfg.parentMatchColumn + '" was not found in the Excel header row.');
        }
    }

    private static List<Map<String, Object>> filterByParent(
        List<Map<String, Object>> records, ExcelConfig cfg, appcg.GridDataProviderTypesV1.ProviderContext context
    ) {
        if (context == null || String.isBlank(context.parentId) || String.isBlank(cfg.parentMatchColumn)) {
            return records;
        }
        String parentMatchValue = resolveParentMatchValue(cfg, context);
        List<Map<String, Object>> filtered = new List<Map<String, Object>>();
        if (String.isBlank(parentMatchValue)) {
            return filtered;
        }
        for (Map<String, Object> record : records) {
            Object rawValue = record.get(cfg.parentMatchColumn);
            if (rawValue != null && parentValuesMatch(String.valueOf(rawValue), parentMatchValue, cfg.parentMatchField)) {
                filtered.add(record);
            }
        }
        return filtered;
    }

    private static Boolean parentValuesMatch(String sheetValue, String parentValue, String parentMatchField) {
        String s = sheetValue == null ? null : sheetValue.trim();
        String p = parentValue == null ? null : parentValue.trim();
        if (String.isBlank(s) || String.isBlank(p)) return false;
        if (s.equals(p)) return true;
        return 'Id'.equalsIgnoreCase(parentMatchField) && s.length() >= 15 && p.length() >= 15 && s.substring(0, 15).equals(p.substring(0, 15));
    }

    @TestVisible
    private static String resolveParentMatchValue(ExcelConfig cfg, appcg.GridDataProviderTypesV1.ProviderContext context) {
        if (context == null || String.isBlank(context.parentId)) return null;
        String requestedField = String.isBlank(cfg.parentMatchField) ? 'Id' : cfg.parentMatchField.trim();
        if ('Id'.equalsIgnoreCase(requestedField)) {
            return context.parentId;
        }
        try {
            Id parentRecordId = (Id) context.parentId;
            Schema.DescribeSObjectResult parentDescribe = parentRecordId.getSObjectType().getDescribe();
            Map<String, Schema.SObjectField> fields = parentDescribe.fields.getMap();
            String fieldApiName;
            for (String candidate : fields.keySet()) {
                if (candidate.equalsIgnoreCase(requestedField)) {
                    fieldApiName = candidate;
                    break;
                }
            }
            if (fieldApiName == null) {
                throw new ProviderException('Parent match field "' + requestedField + '" does not exist on ' + parentDescribe.getName() + '.');
            }
            String query = 'SELECT ' + fieldApiName + ' FROM ' + parentDescribe.getName() + ' WHERE Id = :parentRecordId WITH USER_MODE LIMIT 1';
            List<SObject> parents = Database.query(query);
            if (parents.isEmpty()) return null;
            Object value = parents[0].get(fieldApiName);
            return value == null ? null : String.valueOf(value);
        } catch (ProviderException e) {
            throw e;
        } catch (Exception e) {
            throw new ProviderException('Unable to resolve parent match value: ' + e.getMessage());
        }
    }

    private static List<Map<String, Object>> filterBySearch(List<Map<String, Object>> records, String searchTerm) {
        String lowerSearch = searchTerm.toLowerCase();
        List<Map<String, Object>> filtered = new List<Map<String, Object>>();
        for (Map<String, Object> record : records) {
            for (String key : record.keySet()) {
                if ('Id'.equals(key)) continue;
                Object val = record.get(key);
                if (val != null && String.valueOf(val).toLowerCase().contains(lowerSearch)) {
                    filtered.add(record);
                    break;
                }
            }
        }
        return filtered;
    }
}
