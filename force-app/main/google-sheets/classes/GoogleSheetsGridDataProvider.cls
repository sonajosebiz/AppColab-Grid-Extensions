global with sharing class GoogleSheetsGridDataProvider implements appcg.GridDataProviderV1, appcg.GridDataMutationProviderV1 {
    public class ProviderException extends Exception {
    }

    // ─── Instance Cache ───────────────────────────────────────────────
    // getCapabilities() and getData() are called on the same instance during
    // the initial grid load. Read the sheet once and reuse it in getData().

    private List<String> cachedHeaders;
    private List<Map<String, Object>> cachedRecords;

    // ─── Config ───────────────────────────────────────────────────────

    @TestVisible
    private class SheetConfig {
        public String spreadsheetId;
        public String sheetName;
        public Integer headerRow;
        public Integer sheetGid;
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
            SELECT
                Id,
                appcg__Data_Provider_Config__c,
                appcg__Pagination_Type__c,
                appcg__Record_Limit__c,
                appcg__Page_Size__c
            FROM appcg__Grid_Definition__c
            WHERE Id = :context.gridDefinitionId
            LIMIT 1
        ];
        return defs.isEmpty() ? null : defs[0];
    }

    @TestVisible
    private static SheetConfig parseConfig(appcg.GridDataProviderTypesV1.ProviderContext context) {
        appcg__Grid_Definition__c gridDef = getGridDefinition(context);
        String configJson = gridDef != null ? gridDef.appcg__Data_Provider_Config__c : null;
        if (String.isBlank(configJson)) {
            throw new ProviderException(
                'Google Sheets provider requires configuration. ' +
                'Set Data Provider Configuration with {"spreadsheetId":"...","sheetName":"..."}'
            );
        }
        SheetConfig cfg;
        try {
            cfg = (SheetConfig) JSON.deserialize(configJson, SheetConfig.class);
        } catch (Exception e) {
            throw new ProviderException('Invalid Google Sheets provider configuration: ' + e.getMessage());
        }
        if (String.isBlank(cfg.spreadsheetId)) {
            throw new ProviderException('spreadsheetId is required in the provider configuration.');
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

    global appcg.GridDataProviderTypesV1.Capabilities getCapabilities(
        appcg.GridDataProviderTypesV1.ProviderContext context
    ) {
        SheetConfig cfg = parseConfig(context);

        GoogleSheetsClient client = new GoogleSheetsClient();
        Map<String, Object> response = client.getValues(cfg.spreadsheetId, cfg.sheetName);
        List<Object> allRows = (List<Object>) response.get('values');

        // Parse headers and cache everything for getData()
        cachedHeaders = extractHeaders(allRows, cfg.headerRow);
        cachedRecords = parseDataRows(allRows, cachedHeaders, cfg.headerRow);
        validateParentMatchColumn(cfg, cachedHeaders, context);
        cachedRecords = filterByParent(cachedRecords, cfg, context);

        appcg.GridDataProviderTypesV1.Capabilities capabilities = new appcg.GridDataProviderTypesV1.Capabilities();
        capabilities.supportedFeatures = new Set<String>{
            'SEARCH',
            'REFRESH',
            'ADD',
            'EDIT',
            'DELETE',
            'DOWNLOAD_CSV'
        };
        capabilities.supportedRowActions = new Set<String>{ 'DELETE' };
        capabilities.supportsServerPagination = false;
        capabilities.columns = buildColumnDefinitions(cachedHeaders, cfg, context);
        return capabilities;
    }

    global appcg.GridDataProviderTypesV1.PageResult getData(appcg.GridDataProviderTypesV1.QueryRequest request) {
        List<Map<String, Object>> records;
        SheetConfig cfg = parseConfig(request.context);

        appcg__Grid_Definition__c gridDef = getGridDefinition(request?.context);
        String paginationType = gridDef?.appcg__Pagination_Type__c;
        Integer recordLimit = (gridDef?.appcg__Record_Limit__c != null &&
            gridDef.appcg__Record_Limit__c > 0)
            ? (Integer) gridDef.appcg__Record_Limit__c
            : 1000;

        Integer pageSize;
        Integer requestedPageSize = (request.pageSize != null &&
            request.pageSize > 0)
            ? request.pageSize
            : (gridDef?.appcg__Page_Size__c != null ? Integer.valueOf(gridDef.appcg__Page_Size__c) : 20);
        if (paginationType == 'Client-Side') {
            pageSize = Math.min(recordLimit, 50000);
        } else {
            pageSize = (gridDef?.appcg__Record_Limit__c != null &&
                gridDef.appcg__Record_Limit__c > 0)
                ? Math.min(requestedPageSize, (Integer) gridDef.appcg__Record_Limit__c)
                : Math.min(requestedPageSize, 50000);
        }

        if (cachedRecords != null) {
            // Use cache from getCapabilities() — no callout needed
            records = cachedRecords;
            cachedRecords = null; // Free memory
        } else {
            // Standalone call (e.g. getCustomProviderPage) — fetch fresh
            GoogleSheetsClient client = new GoogleSheetsClient();
            Map<String, Object> response = client.getValues(cfg.spreadsheetId, cfg.sheetName);
            List<Object> allRows = (List<Object>) response.get('values');
            List<String> headers = extractHeaders(allRows, cfg.headerRow);
            records = parseDataRows(allRows, headers, cfg.headerRow);
            validateParentMatchColumn(cfg, headers, request.context);
            records = filterByParent(records, cfg, request.context);
        }

        // Apply search filter
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
    }

    // ─── GridDataMutationProviderV1 ───────────────────────────────────

    global appcg.GridDataProviderTypesV1.SaveResult saveRecords(appcg.GridDataProviderTypesV1.SaveRequest request) {
        SheetConfig cfg = parseConfig(request.context);

        GoogleSheetsClient client = new GoogleSheetsClient();

        // Read header row to know column order
        Map<String, Object> headerResponse = client.getValues(
            cfg.spreadsheetId,
            cfg.sheetName + '!' + cfg.headerRow + ':' + cfg.headerRow
        );
        List<String> headers = extractHeaders((List<Object>) headerResponse.get('values'), 1);

        // Separate new records (null, blank, or TEMP_ IDs) from existing records (row numbers)
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

        if (
            !newRecords.isEmpty() &&
            cfg.autoPopulateParent == true &&
            request.context != null &&
            String.isNotBlank(request.context.parentId)
        ) {
            validateParentMatchColumn(cfg, headers, request.context);
            String parentMatchValue = resolveParentMatchValue(cfg, request.context);
            if (String.isBlank(parentMatchValue)) {
                throw new ProviderException(
                    'The current parent record has no value for ' + cfg.parentMatchField + '.'
                );
            }
            for (Map<String, Object> record : newRecords) {
                record.put(cfg.parentMatchColumn, parentMatchValue);
            }
        }

        // Update existing rows via batchUpdate
        if (!existingRecords.isEmpty()) {
            List<Map<String, Object>> updateData = new List<Map<String, Object>>();
            for (Map<String, Object> record : existingRecords) {
                String rowNum = String.valueOf(record.get('Id'));
                List<Object> rowValues = recordToRow(record, headers);
                updateData.add(
                    new Map<String, Object>{
                        'range' => cfg.sheetName +
                        '!A' +
                        rowNum,
                        'values' => new List<List<Object>>{ rowValues }
                    }
                );
            }
            client.batchUpdateValues(cfg.spreadsheetId, updateData);
        }

        if (!newRecords.isEmpty()) {
            // Get current row count to determine new row IDs
            Map<String, Object> fullData = client.getValues(cfg.spreadsheetId, cfg.sheetName);
            List<Object> allRows = (List<Object>) fullData.get('values');
            Integer nextRowNumber = (allRows != null ? allRows.size() : cfg.headerRow) + 1;

            List<List<Object>> appendRows = new List<List<Object>>();
            for (Map<String, Object> record : newRecords) {
                appendRows.add(recordToRow(record, headers));
            }
            client.appendValues(cfg.spreadsheetId, cfg.sheetName, appendRows);

            // Assign final IDs to appended records in-place
            for (Map<String, Object> record : newRecords) {
                record.put('Id', String.valueOf(nextRowNumber));
                nextRowNumber++;
            }
        }

        // Return saved records preserving original order from request.records
        List<Map<String, Object>> savedRecords = new List<Map<String, Object>>();
        for (Map<String, Object> record : request.records) {
            savedRecords.add(record);
        }

        appcg.GridDataProviderTypesV1.SaveResult result = new appcg.GridDataProviderTypesV1.SaveResult();
        result.records = savedRecords;
        return result;
    }

    global void deleteRecords(appcg.GridDataProviderTypesV1.DeleteRequest request) {
        SheetConfig cfg = parseConfig(request.context);

        // Resolve the numeric sheet GID
        Integer sheetGid = cfg.sheetGid;
        GoogleSheetsClient client = new GoogleSheetsClient();

        if (sheetGid == null) {
            sheetGid = resolveSheetGid(client, cfg.spreadsheetId, cfg.sheetName);
        }

        // Convert row IDs to 0-based indices and sort descending
        // to avoid index shifting during deletion
        List<Integer> rowIndices = new List<Integer>();
        for (String recordId : request.recordIds) {
            rowIndices.add(Integer.valueOf(recordId) - 1); // 1-based to 0-based
        }
        rowIndices.sort();

        // Build deleteDimension requests in reverse order (bottom-up)
        List<Map<String, Object>> deleteRequests = new List<Map<String, Object>>();
        for (Integer i = rowIndices.size() - 1; i >= 0; i--) {
            deleteRequests.add(
                new Map<String, Object>{
                    'deleteDimension' => new Map<String, Object>{
                        'range' => new Map<String, Object>{
                            'sheetId' => sheetGid,
                            'dimension' => 'ROWS',
                            'startIndex' => rowIndices[i],
                            'endIndex' => rowIndices[i] + 1
                        }
                    }
                }
            );
        }

        client.batchUpdate(cfg.spreadsheetId, deleteRequests);
    }

    // ─── Helpers ──────────────────────────────────────────────────────

    @TestVisible
    private static List<String> extractHeaders(List<Object> allRows, Integer headerRow) {
        List<String> headers = new List<String>();
        if (allRows == null || allRows.size() < headerRow) {
            return headers;
        }
        List<Object> row = (List<Object>) allRows[headerRow - 1];
        for (Object cell : row) {
            headers.add(cell != null ? String.valueOf(cell) : '');
        }
        return headers;
    }

    @TestVisible
    private static List<Map<String, Object>> parseDataRows(
        List<Object> allRows,
        List<String> headers,
        Integer headerRow
    ) {
        List<Map<String, Object>> records = new List<Map<String, Object>>();
        if (allRows == null || headers.isEmpty()) {
            return records;
        }
        for (Integer i = headerRow; i < allRows.size(); i++) {
            List<Object> row = (List<Object>) allRows[i];
            Map<String, Object> record = new Map<String, Object>();
            // Row number is 1-based; data rows start at headerRow+1
            record.put('Id', String.valueOf(i + 1));
            for (Integer j = 0; j < headers.size(); j++) {
                Object cellValue = (j < row.size()) ? row[j] : '';
                record.put(headers[j], cellValue != null ? String.valueOf(cellValue) : '');
            }
            records.add(record);
        }
        return records;
    }

    private static List<appcg.GridDataProviderTypesV1.ColumnDefinition> buildColumnDefinitions(
        List<String> headers,
        SheetConfig cfg,
        appcg.GridDataProviderTypesV1.ProviderContext context
    ) {
        List<appcg.GridDataProviderTypesV1.ColumnDefinition> columns = new List<appcg.GridDataProviderTypesV1.ColumnDefinition>();

        // Hidden Id column
        columns.add(column('Id', 'ID', 'TEXT', true, false, '60px'));

        Boolean lockParentColumn =
            cfg.autoPopulateParent == true &&
            context != null &&
            String.isNotBlank(context.parentId);
        for (String header : headers) {
            Boolean isParentColumn = String.isNotBlank(cfg.parentMatchColumn) && header == cfg.parentMatchColumn;
            columns.add(column(header, header, 'TEXT', lockParentColumn && isParentColumn, true, null));
        }
        return columns;
    }

    private static void validateParentMatchColumn(
        SheetConfig cfg,
        List<String> headers,
        appcg.GridDataProviderTypesV1.ProviderContext context
    ) {
        if (context == null || String.isBlank(context.parentId) || String.isBlank(cfg.parentMatchColumn)) {
            return;
        }
        if (headers == null || !headers.contains(cfg.parentMatchColumn)) {
            throw new ProviderException(
                'Parent match column "' + cfg.parentMatchColumn + '" was not found in the Google Sheet header row.'
            );
        }
    }

    private static List<Map<String, Object>> filterByParent(
        List<Map<String, Object>> records,
        SheetConfig cfg,
        appcg.GridDataProviderTypesV1.ProviderContext context
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
            if (
                rawValue != null && parentValuesMatch(String.valueOf(rawValue), parentMatchValue, cfg.parentMatchField)
            ) {
                filtered.add(record);
            }
        }
        return filtered;
    }

    private static Boolean parentValuesMatch(String sheetValue, String parentValue, String parentMatchField) {
        String normalizedSheetValue = sheetValue == null ? null : sheetValue.trim();
        String normalizedParentValue = parentValue == null ? null : parentValue.trim();
        if (String.isBlank(normalizedSheetValue) || String.isBlank(normalizedParentValue)) {
            return false;
        }
        if (normalizedSheetValue.equals(normalizedParentValue)) {
            return true;
        }
        return 'Id'.equalsIgnoreCase(parentMatchField) &&
            normalizedSheetValue.length() >= 15 &&
            normalizedParentValue.length() >= 15 &&
            normalizedSheetValue.substring(0, 15).equals(normalizedParentValue.substring(0, 15));
    }

    @TestVisible
    private static String resolveParentMatchValue(
        SheetConfig cfg,
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
            Map<String, Schema.SObjectField> fields = parentDescribe.fields.getMap();
            String fieldApiName;
            for (String candidate : fields.keySet()) {
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

            String query =
                'SELECT ' +
                fieldApiName +
                ' FROM ' +
                parentDescribe.getName() +
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

    private static appcg.GridDataProviderTypesV1.ColumnDefinition column(
        String id,
        String label,
        String fieldType,
        Boolean isReadOnly,
        Boolean visible,
        String width
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

    private static List<Map<String, Object>> filterBySearch(List<Map<String, Object>> records, String searchTerm) {
        String lowerSearch = searchTerm.toLowerCase();
        List<Map<String, Object>> filtered = new List<Map<String, Object>>();
        for (Map<String, Object> record : records) {
            for (String key : record.keySet()) {
                if (key == 'Id')
                    continue;
                Object val = record.get(key);
                if (val != null && String.valueOf(val).toLowerCase().contains(lowerSearch)) {
                    filtered.add(record);
                    break;
                }
            }
        }
        return filtered;
    }

    private static List<Object> recordToRow(Map<String, Object> record, List<String> headers) {
        List<Object> row = new List<Object>();
        for (String header : headers) {
            Object val = record.get(header);
            row.add(val != null ? String.valueOf(val) : '');
        }
        return row;
    }

    @TestVisible
    private static Integer resolveSheetGid(GoogleSheetsClient client, String spreadsheetId, String sheetName) {
        Map<String, Object> meta = client.getMetadata(spreadsheetId);
        List<Object> sheets = (List<Object>) meta.get('sheets');
        if (sheets != null) {
            for (Object sheetObj : sheets) {
                Map<String, Object> sheet = (Map<String, Object>) sheetObj;
                Map<String, Object> props = (Map<String, Object>) sheet.get('properties');
                if (props != null && sheetName.equals((String) props.get('title'))) {
                    return Integer.valueOf(props.get('sheetId'));
                }
            }
        }
        throw new ProviderException('Sheet "' + sheetName + '" not found in spreadsheet ' + spreadsheetId);
    }
}
