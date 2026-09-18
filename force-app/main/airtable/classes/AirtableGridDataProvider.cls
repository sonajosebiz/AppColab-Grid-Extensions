global with sharing class AirtableGridDataProvider
    implements appcg.GridDataProviderV1, appcg.GridDataMutationProviderV1 {

    public class ProviderException extends Exception {}


    private static final Set<String> READ_ONLY_TYPES = new Set<String>{
        'singleCollaborator', 'multipleCollaborators', 'multipleAttachments',
        'aiText', 'formula', 'rollup', 'lookup', 'count', 'createdTime',
        'lastModifiedTime', 'autoNumber', 'createdBy', 'lastModifiedBy',
        'button', 'externalSyncSource'
    };

    // ─── Instance Cache ───────────────────────────────────────────────
    private List<Map<String, Object>> cachedRecords;

    // ─── Config ───────────────────────────────────────────────────────

    @TestVisible
    private class AirtableConfig {
        public String baseId;
        public String tableIdOrName;
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
    private static AirtableConfig parseConfig(appcg.GridDataProviderTypesV1.ProviderContext context) {
        appcg__Grid_Definition__c gridDef = getGridDefinition(context);
        String configJson = gridDef != null ? gridDef.appcg__Data_Provider_Config__c : null;
        if (String.isBlank(configJson)) {
            throw new ProviderException(
                'Airtable provider requires configuration. ' +
                'Set Data Provider Configuration with {"baseId":"app...","tableIdOrName":"..."}'
            );
        }
        AirtableConfig cfg;
        try {
            cfg = (AirtableConfig) JSON.deserialize(configJson, AirtableConfig.class);
        } catch (Exception e) {
            throw new ProviderException('Invalid Airtable provider configuration: ' + e.getMessage());
        }
        if (String.isBlank(cfg.baseId)) {
            throw new ProviderException('baseId is required in the provider configuration.');
        }
        if (String.isBlank(cfg.tableIdOrName)) {
            throw new ProviderException('tableIdOrName is required in the provider configuration.');
        }
        return cfg;
    }

    // ─── GridDataProviderV1 ───────────────────────────────────────────

    global appcg.GridDataProviderTypesV1.Capabilities getCapabilities(
        appcg.GridDataProviderTypesV1.ProviderContext context
    ) {
        AirtableConfig cfg = parseConfig(context);
        try {
            AirtableClient client = new AirtableClient();

            // 1. Resolve table schema for read-only / computed fields
            Set<String> readOnlyFields = resolveReadOnlyFields(client, cfg.baseId, cfg.tableIdOrName);

            // 2. Fetch records
            Map<String, Object> response = client.listRecords(cfg.baseId, cfg.tableIdOrName, 100, null);
            List<Object> rawRecords = (List<Object>) response.get('records');

            // Parse records and discover dynamic columns from fields
            List<String> fieldNames = extractFieldNames(rawRecords);
            cachedRecords = parseAirtableRecords(rawRecords, fieldNames);

            appcg.GridDataProviderTypesV1.Capabilities capabilities = new appcg.GridDataProviderTypesV1.Capabilities();
            capabilities.supportedFeatures = new Set<String>{
                'SEARCH', 'REFRESH', 'ADD', 'EDIT', 'DELETE', 'DOWNLOAD_CSV'
            };
            capabilities.supportedRowActions = new Set<String>{ 'DELETE' };
            capabilities.supportsServerPagination = false;
            capabilities.columns = buildColumnDefinitions(fieldNames, readOnlyFields);
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
                pageSize = Math.min(recordLimit, 1000);
            } else {
                pageSize = (gridDef?.appcg__Record_Limit__c != null && gridDef.appcg__Record_Limit__c > 0)
                    ? Math.min(requestedPageSize, (Integer) gridDef.appcg__Record_Limit__c)
                    : Math.min(requestedPageSize, 1000);
            }

            if (cachedRecords != null) {
                // Use cache from getCapabilities() — avoids duplicate callout
                records = cachedRecords;
                cachedRecords = null;
            } else {
                // Standalone fetch
                AirtableConfig cfg = parseConfig(request.context);
                AirtableClient client = new AirtableClient();
                Map<String, Object> response = client.listRecords(cfg.baseId, cfg.tableIdOrName, 100, null);
                List<Object> rawRecords = (List<Object>) response.get('records');
                List<String> fieldNames = extractFieldNames(rawRecords);
                records = parseAirtableRecords(rawRecords, fieldNames);
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
        } finally {
        }
    }

    // ─── GridDataMutationProviderV1 ───────────────────────────────────

    global appcg.GridDataProviderTypesV1.SaveResult saveRecords(
        appcg.GridDataProviderTypesV1.SaveRequest request
    ) {
        AirtableConfig cfg = parseConfig(request.context);
        try {
            AirtableClient client = new AirtableClient();
            Set<String> readOnlyFields = resolveReadOnlyFields(client, cfg.baseId, cfg.tableIdOrName);

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
            if (!existingRecords.isEmpty()) {
                List<Map<String, Object>> patchPayload = new List<Map<String, Object>>();
                for (Map<String, Object> record : existingRecords) {
                    patchPayload.add(new Map<String, Object>{
                        'id' => String.valueOf(record.get('Id')),
                        'fields' => cleanRecordFields(record, readOnlyFields)
                    });
                }
                client.updateRecords(cfg.baseId, cfg.tableIdOrName, patchPayload);
            }

            // Create new records
            if (!newRecords.isEmpty()) {
                List<Map<String, Object>> postPayload = new List<Map<String, Object>>();
                for (Map<String, Object> record : newRecords) {
                    postPayload.add(new Map<String, Object>{
                        'fields' => cleanRecordFields(record, readOnlyFields)
                    });
                }
                Map<String, Object> createResponse = client.createRecords(cfg.baseId, cfg.tableIdOrName, postPayload);
                List<Object> createdRecords = (List<Object>) createResponse.get('records');

                if (createdRecords != null && createdRecords.size() == newRecords.size()) {
                    for (Integer i = 0; i < newRecords.size(); i++) {
                        Map<String, Object> createdRec = (Map<String, Object>) createdRecords[i];
                        newRecords[i].put('Id', String.valueOf(createdRec.get('id')));
                    }
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
        } finally {
        }
    }

    global void deleteRecords(appcg.GridDataProviderTypesV1.DeleteRequest request) {
        if (request.recordIds == null || request.recordIds.isEmpty()) {
            return;
        }
        AirtableConfig cfg = parseConfig(request.context);
        try {
            AirtableClient client = new AirtableClient();
            client.deleteRecords(cfg.baseId, cfg.tableIdOrName, request.recordIds);
        } finally {
        }
    }

    // ─── Helpers ──────────────────────────────────────────────────────

    @TestVisible
    private static Set<String> resolveReadOnlyFields(
        AirtableClient client,
        String baseId,
        String tableIdOrName
    ) {
        Set<String> readOnlyFields = new Set<String>();
        try {
            Map<String, Object> schema = client.getBaseSchema(baseId);
            List<Object> tables = (List<Object>) schema.get('tables');
            if (tables != null) {
                for (Object tblObj : tables) {
                    Map<String, Object> tbl = (Map<String, Object>) tblObj;
                    String tblName = (String) tbl.get('name');
                    String tblId = (String) tbl.get('id');
                    if (tableIdOrName.equalsIgnoreCase(tblName) || tableIdOrName.equalsIgnoreCase(tblId)) {
                        List<Object> fields = (List<Object>) tbl.get('fields');
                        if (fields != null) {
                            for (Object fldObj : fields) {
                                Map<String, Object> fld = (Map<String, Object>) fldObj;
                                String fieldType = (String) fld.get('type');
                                String fieldName = (String) fld.get('name');
                                if (READ_ONLY_TYPES.contains(fieldType)) {
                                    readOnlyFields.add(fieldName);
                                }
                            }
                        }
                        break;
                    }
                }
            }
        } catch (Exception e) {
            // Gracefully ignore schema errors if token lacks schema.bases:read
        }
        return readOnlyFields;
    }

    @TestVisible
    private static List<String> extractFieldNames(List<Object> rawRecords) {
        Set<String> fieldSet = new Set<String>();
        if (rawRecords != null) {
            for (Object recObj : rawRecords) {
                Map<String, Object> rec = (Map<String, Object>) recObj;
                Map<String, Object> fields = (Map<String, Object>) rec.get('fields');
                if (fields != null) {
                    fieldSet.addAll(fields.keySet());
                }
            }
        }
        return new List<String>(fieldSet);
    }

    @TestVisible
    private static List<Map<String, Object>> parseAirtableRecords(
        List<Object> rawRecords,
        List<String> fieldNames
    ) {
        List<Map<String, Object>> parsed = new List<Map<String, Object>>();
        if (rawRecords == null) {
            return parsed;
        }
        for (Object recObj : rawRecords) {
            Map<String, Object> rec = (Map<String, Object>) recObj;
            Map<String, Object> fields = (Map<String, Object>) rec.get('fields');
            Map<String, Object> row = new Map<String, Object>();
            row.put('Id', String.valueOf(rec.get('id')));

            if (fields != null) {
                for (String fieldName : fieldNames) {
                    Object val = fields.get(fieldName);
                    row.put(fieldName, formatFieldValue(val));
                }
            }
            parsed.add(row);
        }
        return parsed;
    }

    private static Object formatFieldValue(Object raw) {
        if (raw == null) return '';
        if (raw instanceof Map<String, Object>) {
            Map<String, Object> m = (Map<String, Object>) raw;
            if (m.containsKey('name') && m.get('name') != null) {
                return String.valueOf(m.get('name'));
            }
            if (m.containsKey('value') && m.get('value') != null) {
                return String.valueOf(m.get('value'));
            }
            if (m.containsKey('state') && 'error'.equals(m.get('state'))) {
                return '';
            }
            return JSON.serialize(raw);
        }
        if (raw instanceof List<Object>) {
            List<String> strList = new List<String>();
            for (Object item : (List<Object>) raw) {
                if (item != null) {
                    if (item instanceof Map<String, Object>) {
                        Map<String, Object> im = (Map<String, Object>) item;
                        strList.add(im.containsKey('name') ? String.valueOf(im.get('name')) : JSON.serialize(im));
                    } else {
                        strList.add(String.valueOf(item));
                    }
                }
            }
            return String.join(strList, ', ');
        }
        return String.valueOf(raw);
    }

    private static Map<String, Object> cleanRecordFields(Map<String, Object> record, Set<String> readOnlyFields) {
        Map<String, Object> clean = new Map<String, Object>();
        for (String key : record.keySet()) {
            if (key == 'Id' || key == 'attributes') continue;
            if (readOnlyFields != null && readOnlyFields.contains(key)) continue;
            clean.put(key, record.get(key));
        }
        return clean;
    }

    private static List<appcg.GridDataProviderTypesV1.ColumnDefinition> buildColumnDefinitions(
        List<String> fieldNames,
        Set<String> readOnlyFields
    ) {
        List<appcg.GridDataProviderTypesV1.ColumnDefinition> columns =
            new List<appcg.GridDataProviderTypesV1.ColumnDefinition>();

        // Hidden Id column (Airtable Record ID e.g. recXXXXXXXX)
        columns.add(column('Id', 'ID', 'TEXT', true, false, '120px'));

        for (String name : fieldNames) {
            Boolean isReadOnly = (readOnlyFields != null && readOnlyFields.contains(name));
            columns.add(column(name, name, 'TEXT', isReadOnly, true, null));
        }
        return columns;
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
