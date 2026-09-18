global with sharing class TrelloGridDataProvider
    implements appcg.GridDataProviderV1, appcg.GridDataMutationProviderV1 {

    public class ProviderException extends Exception {}


    // ─── Instance Cache ───────────────────────────────────────────────
    private List<Map<String, Object>> cachedRecords;

    // ─── Config ───────────────────────────────────────────────────────

    @TestVisible
    private class TrelloConfig {
        public String boardId;
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
    private static TrelloConfig parseConfig(appcg.GridDataProviderTypesV1.ProviderContext context) {
        appcg__Grid_Definition__c gridDef = getGridDefinition(context);
        String configJson = gridDef != null ? gridDef.appcg__Data_Provider_Config__c : null;
        if (String.isBlank(configJson)) {
            throw new ProviderException(
                'Trello provider requires configuration. ' +
                'Set Data Provider Configuration with {"boardId":"..."}'
            );
        }
        TrelloConfig cfg;
        try {
            cfg = (TrelloConfig) JSON.deserialize(configJson, TrelloConfig.class);
        } catch (Exception e) {
            throw new ProviderException('Invalid Trello provider configuration: ' + e.getMessage());
        }
        if (String.isBlank(cfg.boardId)) {
            throw new ProviderException('boardId is required in the provider configuration.');
        }
        return cfg;
    }

    // ─── GridDataProviderV1 ───────────────────────────────────────────

    global appcg.GridDataProviderTypesV1.Capabilities getCapabilities(
        appcg.GridDataProviderTypesV1.ProviderContext context
    ) {
        TrelloConfig cfg = parseConfig(context);
        try {
            TrelloClient client = new TrelloClient();

            // 1. Fetch board lists to resolve list names
            Map<String, String> listMap = resolveListNames(client, cfg.boardId);

            // 2. Fetch cards
            List<Object> rawCards = client.getBoardCards(cfg.boardId);
            cachedRecords = parseTrelloCards(rawCards, listMap);

            appcg.GridDataProviderTypesV1.Capabilities capabilities = new appcg.GridDataProviderTypesV1.Capabilities();
            capabilities.supportedFeatures = new Set<String>{
                'SEARCH', 'REFRESH', 'ADD', 'EDIT', 'DELETE', 'DOWNLOAD_CSV'
            };
            capabilities.supportedRowActions = new Set<String>{ 'DELETE' };
            capabilities.supportsServerPagination = false;
            capabilities.columns = buildColumnDefinitions(listMap);
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
                : 1000;

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
                TrelloConfig cfg = parseConfig(request.context);
                TrelloClient client = new TrelloClient();
                Map<String, String> listMap = resolveListNames(client, cfg.boardId);
                List<Object> rawCards = client.getBoardCards(cfg.boardId);
                records = parseTrelloCards(rawCards, listMap);
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
        TrelloConfig cfg = parseConfig(request.context);
        try {
            TrelloClient client = new TrelloClient();
            Map<String, String> nameToListId = resolveNameToIdList(client, cfg.boardId);
            String defaultListId = nameToListId.isEmpty() ? null : nameToListId.values()[0];

            List<Map<String, Object>> savedRecords = new List<Map<String, Object>>();

            for (Map<String, Object> record : request.records) {
                Object rawId = record.get('Id');
                String recordId = rawId == null ? null : String.valueOf(rawId);

                Map<String, Object> payload = new Map<String, Object>();
                if (record.containsKey('name') && record.get('name') != null) {
                    payload.put('name', String.valueOf(record.get('name')));
                }
                if (record.containsKey('desc') && record.get('desc') != null) {
                    payload.put('desc', String.valueOf(record.get('desc')));
                }
                if (record.containsKey('due')) {
                    String dueStr = record.get('due') == null ? null : String.valueOf(record.get('due')).trim();
                    payload.put('due', String.isBlank(dueStr) ? null : dueStr);
                }
                if (record.containsKey('dueComplete') && record.get('dueComplete') != null) {
                    Object dc = record.get('dueComplete');
                    payload.put('dueComplete', dc == true || 'true'.equalsIgnoreCase(String.valueOf(dc)));
                }

                // List resolution
                if (record.containsKey('listName') && record.get('listName') != null) {
                    String targetListName = String.valueOf(record.get('listName')).trim();
                    if (nameToListId.containsKey(targetListName.toLowerCase())) {
                        payload.put('idList', nameToListId.get(targetListName.toLowerCase()));
                    } else if (nameToListId.values().contains(targetListName)) {
                        payload.put('idList', targetListName);
                    }
                }

                if (String.isBlank(recordId) || recordId.startsWith('TEMP_')) {
                    // New Card
                    if (!payload.containsKey('idList') && String.isNotBlank(defaultListId)) {
                        payload.put('idList', defaultListId);
                    }
                    Map<String, Object> created = client.createCard(payload);
                    record.put('Id', String.valueOf(created.get('id')));
                    if (created.containsKey('shortUrl')) {
                        record.put('url', String.valueOf(created.get('shortUrl')));
                    }
                } else {
                    // Update Card
                    client.updateCard(recordId, payload);
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
        try {
            TrelloClient client = new TrelloClient();
            for (String cardId : request.recordIds) {
                client.deleteCard(cardId);
            }
        } finally {
        }
    }

    // ─── Helpers ──────────────────────────────────────────────────────

    @TestVisible
    private static Map<String, String> resolveListNames(TrelloClient client, String boardId) {
        Map<String, String> mapIdToName = new Map<String, String>();
        try {
            List<Object> lists = client.getBoardLists(boardId);
            if (lists != null) {
                for (Object lObj : lists) {
                    Map<String, Object> l = (Map<String, Object>) lObj;
                    mapIdToName.put(String.valueOf(l.get('id')), String.valueOf(l.get('name')));
                }
            }
        } catch (Exception e) {
            // Non-fatal list lookup
        }
        return mapIdToName;
    }

    @TestVisible
    private static Map<String, String> resolveNameToIdList(TrelloClient client, String boardId) {
        Map<String, String> mapNameToId = new Map<String, String>();
        try {
            List<Object> lists = client.getBoardLists(boardId);
            if (lists != null) {
                for (Object lObj : lists) {
                    Map<String, Object> l = (Map<String, Object>) lObj;
                    String name = String.valueOf(l.get('name')).toLowerCase().trim();
                    mapNameToId.put(name, String.valueOf(l.get('id')));
                }
            }
        } catch (Exception e) {
            // Non-fatal list lookup
        }
        return mapNameToId;
    }

    @TestVisible
    private static List<Map<String, Object>> parseTrelloCards(
        List<Object> rawCards,
        Map<String, String> listMap
    ) {
        List<Map<String, Object>> parsed = new List<Map<String, Object>>();
        if (rawCards == null) return parsed;

        for (Object cardObj : rawCards) {
            Map<String, Object> card = (Map<String, Object>) cardObj;
            Map<String, Object> row = new Map<String, Object>();
            row.put('Id', String.valueOf(card.get('id')));
            row.put('name', card.get('name') == null ? '' : String.valueOf(card.get('name')));
            row.put('desc', card.get('desc') == null ? '' : String.valueOf(card.get('desc')));

            // List Name
            String idList = String.valueOf(card.get('idList'));
            row.put('listName', (listMap != null && listMap.containsKey(idList)) ? listMap.get(idList) : idList);

            // Due Date & Completion
            row.put('due', card.get('due') == null ? '' : String.valueOf(card.get('due')));
            row.put('dueComplete', card.get('dueComplete') == true);

            // Labels
            List<String> labelNames = new List<String>();
            List<Object> labels = (List<Object>) card.get('labels');
            if (labels != null) {
                for (Object lblObj : labels) {
                    Map<String, Object> lbl = (Map<String, Object>) lblObj;
                    String lblName = String.valueOf(lbl.get('name'));
                    if (String.isNotBlank(lblName)) {
                        labelNames.add(lblName);
                    }
                }
            }
            row.put('labels', String.join(labelNames, ', '));

            // Members
            List<String> memberNames = new List<String>();
            List<Object> members = (List<Object>) card.get('members');
            if (members != null) {
                for (Object memObj : members) {
                    Map<String, Object> mem = (Map<String, Object>) memObj;
                    String fullName = String.valueOf(mem.get('fullName'));
                    if (String.isNotBlank(fullName)) {
                        memberNames.add(fullName);
                    }
                }
            }
            row.put('members', String.join(memberNames, ', '));
            row.put('url', card.get('shortUrl') == null ? '' : String.valueOf(card.get('shortUrl')));

            parsed.add(row);
        }
        return parsed;
    }

    private static List<appcg.GridDataProviderTypesV1.ColumnDefinition> buildColumnDefinitions(Map<String, String> listMap) {
        List<appcg.GridDataProviderTypesV1.ColumnDefinition> columns =
            new List<appcg.GridDataProviderTypesV1.ColumnDefinition>();

        columns.add(column('Id', 'ID', 'TEXT', true, false, '120px'));
        columns.add(column('name', 'Name', 'TEXT', false, true, '220px'));

        // List Name as Picklist
        appcg.GridDataProviderTypesV1.ColumnDefinition listCol = column('listName', 'Status', 'PICKLIST', false, true, '160px');
        if (listMap != null && !listMap.isEmpty()) {
            listCol.picklistOptions = new List<appcg.GridDataProviderTypesV1.Option>();
            for (String listName : listMap.values()) {
                appcg.GridDataProviderTypesV1.Option opt = new appcg.GridDataProviderTypesV1.Option();
                opt.label = listName;
                opt.value = listName;
                listCol.picklistOptions.add(opt);
            }
        }
        columns.add(listCol);

        columns.add(column('due', 'Due Date', 'DATETIME', false, true, '160px'));
        columns.add(column('dueComplete', 'Complete?', 'BOOLEAN', false, true, '100px'));
        columns.add(column('labels', 'Labels', 'TEXT', true, true, '140px'));
        columns.add(column('members', 'Assignee', 'TEXT', true, true, '140px'));
        columns.add(column('desc', 'Description', 'TEXT', false, true, null));
        columns.add(column('url', 'Link', 'URL', true, true, '120px'));

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
