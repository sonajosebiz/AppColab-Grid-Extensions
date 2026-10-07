global with sharing class ExcelGridDataProvider
    implements appcg.GridDataProviderV1, appcg.GridDataMutationProviderV1 {

    public class ProviderException extends Exception {}

    private List<Map<String, Object>> cachedRecords;
    private String cachedKey;

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
        if (testGridDef != null) return testGridDef;
        if (context == null || context.gridDefinitionId == null) return null;
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
        String configJson = getGridDefinition(context)?.appcg__Data_Provider_Config__c;
        if (String.isBlank(configJson)) {
            throw new ProviderException('Excel provider requires configuration: {"workbookId":"...","sheetName":"Sheet1"}.');
        }
        ExcelConfig cfg;
        try {
            cfg = (ExcelConfig) JSON.deserialize(configJson, ExcelConfig.class);
        } catch (Exception e) {
            throw new ProviderException('Invalid Excel provider configuration: ' + e.getMessage());
        }
        if (cfg == null) throw new ProviderException('Excel provider configuration must be a JSON object.');
        if (String.isBlank(cfg.workbookId)) cfg.workbookId = cfg.filePath;
        if (String.isBlank(cfg.workbookId)) {
            throw new ProviderException('workbookId (or filePath) is required in the Excel provider configuration.');
        }
        cfg.workbookId = cfg.workbookId.trim();
        cfg.sheetName = String.isBlank(cfg.sheetName) ? 'Sheet1' : cfg.sheetName.trim();
        if (cfg.headerRow == null) cfg.headerRow = 1;
        if (cfg.headerRow < 1 || cfg.headerRow > 1048576) {
            throw new ProviderException('headerRow must be a worksheet row number between 1 and 1048576.');
        }
        if (String.isNotBlank(cfg.parentMatchColumn)) cfg.parentMatchColumn = cfg.parentMatchColumn.trim();
        cfg.parentMatchField = String.isBlank(cfg.parentMatchField) ? 'Id' : cfg.parentMatchField.trim();
        if (cfg.autoPopulateParent == true && String.isBlank(cfg.parentMatchColumn)) {
            throw new ProviderException('parentMatchColumn is required when autoPopulateParent is enabled.');
        }
        return cfg;
    }

    // Graph uses zero-based row/column offsets; headerRow and grid IDs use worksheet row numbers.
    private class SheetData {
        List<Object> rows;
        List<String> headers;
        List<Map<String, Object>> records;
        Integer firstRow;
        Integer firstColumn;
        Integer lastRow;
    }

    private static SheetData readSheet(ExcelClient client, ExcelConfig cfg) {
        Map<String, Object> response = client.getUsedRange(cfg.workbookId, cfg.sheetName);
        SheetData sheet = new SheetData();
        sheet.rows = (List<Object>) response.get('values');
        sheet.firstRow = response.get('rowIndex') == null ? 1 : Integer.valueOf(response.get('rowIndex')) + 1;
        sheet.firstColumn = response.get('columnIndex') == null ? 1 : Integer.valueOf(response.get('columnIndex')) + 1;
        sheet.lastRow = sheet.firstRow + (sheet.rows == null ? 0 : sheet.rows.size()) - 1;
        Integer relativeHeader = cfg.headerRow - sheet.firstRow + 1;
        sheet.headers = extractHeaders(sheet.rows, relativeHeader);
        sheet.records = parseDataRows(sheet.rows, sheet.headers, relativeHeader, sheet.firstRow);
        return sheet;
    }

    private static String cacheKey(ExcelConfig cfg, appcg.GridDataProviderTypesV1.ProviderContext context) {
        return JSON.serialize(cfg) + ':' + context?.gridDefinitionId + ':' + context?.parentId;
    }

    global appcg.GridDataProviderTypesV1.Capabilities getCapabilities(appcg.GridDataProviderTypesV1.ProviderContext context) {
        ExcelConfig cfg = parseConfig(context);
        SheetData sheet = readSheet(new ExcelClient(), cfg);
        validateParentMatchColumn(cfg, sheet.headers, context);
        cachedRecords = filterByParent(sheet.records, cfg, context);
        cachedKey = cacheKey(cfg, context);
        appcg.GridDataProviderTypesV1.Capabilities capabilities = new appcg.GridDataProviderTypesV1.Capabilities();
        capabilities.supportedFeatures = new Set<String>{ 'SEARCH', 'REFRESH', 'ADD', 'EDIT', 'DELETE', 'DOWNLOAD_CSV' };
        capabilities.supportedRowActions = new Set<String>{ 'DELETE' };
        capabilities.supportsServerPagination = false;
        capabilities.columns = buildColumnDefinitions(sheet.headers, cachedRecords, cfg, context);
        return capabilities;
    }

    global appcg.GridDataProviderTypesV1.PageResult getData(appcg.GridDataProviderTypesV1.QueryRequest request) {
        if (request == null) throw new ProviderException('A query request is required.');
        ExcelConfig cfg = parseConfig(request.context);
        appcg__Grid_Definition__c gridDef = getGridDefinition(request.context);
        Integer recordLimit = gridDef?.appcg__Record_Limit__c > 0 ? (Integer) gridDef.appcg__Record_Limit__c : 1000;
        recordLimit = Math.min(recordLimit, 50000);
        Integer pageSize = request.pageSize > 0 ? request.pageSize :
            (String.isNotBlank(gridDef?.appcg__Page_Size__c) ? Integer.valueOf(gridDef.appcg__Page_Size__c) : 20);
        if (pageSize < 1) pageSize = 20;
        pageSize = gridDef?.appcg__Pagination_Type__c == 'Client-Side' ? recordLimit : Math.min(pageSize, recordLimit);
        List<Map<String, Object>> records;
        if (cachedRecords != null && cachedKey.equals(cacheKey(cfg, request.context))) {
            records = cachedRecords;
        } else {
            SheetData sheet = readSheet(new ExcelClient(), cfg);
            validateParentMatchColumn(cfg, sheet.headers, request.context);
            records = filterByParent(sheet.records, cfg, request.context);
        }
        clearCache();
        if (String.isNotBlank(request.searchTerm)) records = filterBySearch(records, request.searchTerm);
        while (records.size() > pageSize) records.remove(records.size() - 1);
        appcg.GridDataProviderTypesV1.PageResult result = new appcg.GridDataProviderTypesV1.PageResult();
        result.records = records;
        result.totalCount = records.size();
        return result;
    }

    global appcg.GridDataProviderTypesV1.SaveResult saveRecords(appcg.GridDataProviderTypesV1.SaveRequest request) {
        if (request == null) throw new ProviderException('A save request is required.');
        ExcelConfig cfg = parseConfig(request.context);
        appcg.GridDataProviderTypesV1.SaveResult result = new appcg.GridDataProviderTypesV1.SaveResult();
        result.records = request.records == null ? new List<Map<String, Object>>() : request.records;
        if (result.records.isEmpty()) return result;
        try {
            ExcelClient client = new ExcelClient();
            SheetData sheet = readSheet(client, cfg);
            requireHeaders(sheet);
            validateParentMatchColumn(cfg, sheet.headers, request.context);
            Set<String> allowedIds = editableIds(sheet, cfg, request.context);
            List<Map<String, Object>> inserts = new List<Map<String, Object>>();
            List<Map<String, Object>> updates = new List<Map<String, Object>>();
            String parentValue;
            Boolean lockParent = cfg.autoPopulateParent == true && String.isNotBlank(request.context?.parentId);
            if (lockParent) {
                parentValue = resolveParentMatchValue(cfg, request.context);
                if (String.isBlank(parentValue)) {
                    throw new ProviderException('The current parent record has no value for ' + cfg.parentMatchField + '.');
                }
            }
            // Validate the entire request before issuing any writes.
            for (Map<String, Object> record : result.records) {
                if (record == null) throw new ProviderException('Records cannot be null.');
                String rowId = record.get('Id') == null ? null : String.valueOf(record.get('Id'));
                if (String.isBlank(rowId) || rowId.startsWith('TEMP_')) {
                    inserts.add(record);
                } else {
                    validateRowId(rowId, allowedIds);
                    if (lockParent && record.containsKey(cfg.parentMatchColumn) &&
                        !parentValuesMatch(String.valueOf(record.get(cfg.parentMatchColumn)), parentValue, cfg.parentMatchField)) {
                        throw new ProviderException('The parent match column is read-only.');
                    }
                    updates.add(record);
                }
            }
            Integer nextRow = Math.max(sheet.lastRow, cfg.headerRow) + 1;
            if (nextRow + inserts.size() - 1 > 1048576) throw new ProviderException('The worksheet row limit would be exceeded.');
            for (Map<String, Object> record : updates) {
                Integer rowNumber = Integer.valueOf(String.valueOf(record.get('Id')));
                client.updateRange(cfg.workbookId, cfg.sheetName, rowRange(sheet, rowNumber, rowNumber),
                    new List<List<Object>>{ recordToRow(record, sheet.headers, true, lockParent ? cfg.parentMatchColumn : null, parentValue) });
            }
            if (!inserts.isEmpty()) {
                List<List<Object>> values = new List<List<Object>>();
                for (Map<String, Object> record : inserts) {
                    values.add(recordToRow(record, sheet.headers, false, lockParent ? cfg.parentMatchColumn : null, parentValue));
                }
                client.updateRange(cfg.workbookId, cfg.sheetName, rowRange(sheet, nextRow, nextRow + inserts.size() - 1), values);
                for (Map<String, Object> record : inserts) {
                    record.put('Id', String.valueOf(nextRow++));
                    if (lockParent) record.put(cfg.parentMatchColumn, parentValue);
                }
            }
            return result;
        } finally {
            clearCache();
        }
    }

    global void deleteRecords(appcg.GridDataProviderTypesV1.DeleteRequest request) {
        if (request == null || request.recordIds == null || request.recordIds.isEmpty()) return;
        ExcelConfig cfg = parseConfig(request.context);
        try {
            ExcelClient client = new ExcelClient();
            SheetData sheet = readSheet(client, cfg);
            requireHeaders(sheet);
            validateParentMatchColumn(cfg, sheet.headers, request.context);
            Set<String> allowedIds = editableIds(sheet, cfg, request.context);
            Set<Integer> uniqueRows = new Set<Integer>();
            for (String rowId : request.recordIds) {
                validateRowId(rowId, allowedIds);
                uniqueRows.add(Integer.valueOf(rowId));
            }
            List<Integer> rows = new List<Integer>(uniqueRows);
            rows.sort();
            // Delete bottom-up so earlier row positions remain valid.
            for (Integer i = rows.size() - 1; i >= 0; i--) {
                client.deleteRowRange(cfg.workbookId, cfg.sheetName, rowRange(sheet, rows[i], rows[i]));
            }
        } finally {
            clearCache();
        }
    }

    private void clearCache() {
        cachedRecords = null;
        cachedKey = null;
    }

    private static void requireHeaders(SheetData sheet) {
        if (sheet.headers.isEmpty()) throw new ProviderException('The configured header row must contain column names before saving or deleting rows.');
    }

    private static Set<String> editableIds(SheetData sheet, ExcelConfig cfg, appcg.GridDataProviderTypesV1.ProviderContext context) {
        Set<String> ids = new Set<String>();
        for (Map<String, Object> record : filterByParent(sheet.records, cfg, context)) ids.add((String) record.get('Id'));
        return ids;
    }

    private static void validateRowId(String rowId, Set<String> allowedIds) {
        if (String.isBlank(rowId) || !rowId.isNumeric() || !allowedIds.contains(rowId)) {
            throw new ProviderException('Row ID "' + rowId + '" is not an editable data row. Refresh the grid before editing.');
        }
    }

    private static String rowRange(SheetData sheet, Integer startRow, Integer endRow) {
        return getColumnLetter(sheet.firstColumn) + startRow + ':' +
            getColumnLetter(sheet.firstColumn + sheet.headers.size() - 1) + endRow;
    }

    @TestVisible
    private static List<String> extractHeaders(List<Object> allRows, Integer headerRow) {
        List<String> headers = new List<String>();
        if (allRows == null || headerRow == null || headerRow < 1 || headerRow > allRows.size()) return headers;
        List<Object> raw = (List<Object>) allRows[headerRow - 1];
        if (raw == null) return headers;
        Boolean hasHeader = false;
        for (Object value : raw) {
            if (value != null && String.isNotBlank(String.valueOf(value))) hasHeader = true;
        }
        if (!hasHeader) return headers;
        Set<String> usedNames = new Set<String>{ 'id' };
        for (Integer i = 0; i < raw.size(); i++) {
            String base = raw[i] == null ? '' : String.valueOf(raw[i]).trim();
            if (String.isBlank(base)) base = 'Column' + (i + 1);
            String name = base;
            Integer suffix = 2;
            while (usedNames.contains(name.toLowerCase())) name = base + '_' + suffix++;
            headers.add(name);
            usedNames.add(name.toLowerCase());
        }
        return headers;
    }

    @TestVisible
    private static List<Map<String, Object>> parseDataRows(List<Object> allRows, List<String> headers, Integer headerRow) {
        return parseDataRows(allRows, headers, headerRow, 1);
    }

    private static List<Map<String, Object>> parseDataRows(List<Object> allRows, List<String> headers, Integer headerRow, Integer firstRow) {
        List<Map<String, Object>> records = new List<Map<String, Object>>();
        if (allRows == null || headers.isEmpty() || headerRow < 1) return records;
        for (Integer i = headerRow; i < allRows.size(); i++) {
            List<Object> row = (List<Object>) allRows[i];
            Map<String, Object> record = new Map<String, Object>{ 'Id' => String.valueOf(firstRow + i) };
            Boolean hasValue = false;
            for (Integer j = 0; j < headers.size(); j++) {
                Object value = row != null && j < row.size() ? row[j] : null;
                record.put(headers[j], value == null ? '' : value);
                if (value != null && String.isNotBlank(String.valueOf(value))) hasValue = true;
            }
            if (hasValue) records.add(record);
        }
        return records;
    }

    private static List<Object> recordToRow(Map<String, Object> record, List<String> headers, Boolean partial, String parentColumn, String parentValue) {
        List<Object> row = new List<Object>();
        for (String header : headers) {
            if (parentColumn != null && header == parentColumn) {
                row.add(parentValue);
            } else if (partial && !record.containsKey(header)) {
                // Graph null values preserve existing cells, including formulas.
                row.add(null);
            } else {
                row.add(record.get(header) == null ? (Object) '' : record.get(header));
            }
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
