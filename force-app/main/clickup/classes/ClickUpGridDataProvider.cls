global with sharing class ClickUpGridDataProvider
    implements appcg.GridDataProviderV1, appcg.GridDataMutationProviderV1 {

    public class ProviderException extends Exception {}

    global ClickUpGridDataProvider() {}

    // "?"?"? Instance Cache "?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?
    private List<Map<String, Object>> cachedRecords;

    // "?"?"? Config "?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?

    @TestVisible
    private class ClickUpConfig {
        public String listId;
        public Boolean includeSubtasks;
        public Boolean includeClosed;
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
    private static ClickUpConfig parseConfig(appcg.GridDataProviderTypesV1.ProviderContext context) {
        appcg__Grid_Definition__c gridDef = getGridDefinition(context);
        String configJson = gridDef != null ? gridDef.appcg__Data_Provider_Config__c : null;
        if (String.isBlank(configJson)) {
            throw new ProviderException(
                'ClickUp provider requires configuration. ' +
                'Set Data Provider Configuration with {"listId":"..."}'
            );
        }

        ClickUpConfig cfg;
        try {
            cfg = (ClickUpConfig) JSON.deserialize(configJson, ClickUpConfig.class);
        } catch (Exception e) {
            throw new ProviderException('Invalid ClickUp provider configuration: ' + e.getMessage());
        }

        if (String.isBlank(cfg.listId)) {
            throw new ProviderException('listId is required in the provider configuration.');
        }

        if (cfg.includeClosed == null) {
            cfg.includeClosed = true;
        }
        if (cfg.includeSubtasks == null) {
            cfg.includeSubtasks = false;
        }

        return cfg;
    }

    // "?"?"? GridDataProviderV1 "?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?

    global appcg.GridDataProviderTypesV1.Capabilities getCapabilities(
        appcg.GridDataProviderTypesV1.ProviderContext context
    ) {
        ClickUpConfig cfg = parseConfig(context);
        ClickUpClient client = new ClickUpClient();

        // 1. Fetch list metadata for status workflow
        Map<String, Object> listMeta = client.getList(cfg.listId);
        List<appcg.GridDataProviderTypesV1.Option> statusOptions = extractStatusOptions(listMeta);

        // 2. Fetch initial task records
        Map<String, Object> tasksRes = client.getTasks(cfg.listId, 0, cfg.includeSubtasks, cfg.includeClosed);
        List<Object> rawTasks = (List<Object>) tasksRes.get('tasks');
        cachedRecords = parseClickUpTasks(rawTasks);

        appcg.GridDataProviderTypesV1.Capabilities capabilities = new appcg.GridDataProviderTypesV1.Capabilities();
        capabilities.supportedFeatures = new Set<String>{
            'SEARCH', 'REFRESH', 'ADD', 'EDIT', 'DELETE', 'DOWNLOAD_CSV'
        };
        capabilities.supportedRowActions = new Set<String>{ 'DELETE' };
        capabilities.supportsServerPagination = false;
        capabilities.columns = buildColumnDefinitions(statusOptions);

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
            : (gridDef?.appcg__Page_Size__c != null ? Integer.valueOf(gridDef.appcg__Page_Size__c) : 25);
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
            ClickUpConfig cfg = parseConfig(request.context);
            ClickUpClient client = new ClickUpClient();
            Map<String, Object> tasksRes = client.getTasks(cfg.listId, 0, cfg.includeSubtasks, cfg.includeClosed);
            List<Object> rawTasks = (List<Object>) tasksRes.get('tasks');
            records = parseClickUpTasks(rawTasks);
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
        result.totalCount = records != null ? records.size() : 0;
        return result;
    }

    // "?"?"? GridDataMutationProviderV1 "?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?

    global appcg.GridDataProviderTypesV1.SaveResult saveRecords(
        appcg.GridDataProviderTypesV1.SaveRequest request
    ) {
        ClickUpConfig cfg = parseConfig(request.context);
        ClickUpClient client = new ClickUpClient();

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
            String taskId = String.valueOf(record.get('Id'));
            Map<String, Object> payload = buildTaskPayload(record);
            client.updateTask(taskId, payload);
        }

        // Create new records
        for (Map<String, Object> record : newRecords) {
            Map<String, Object> payload = buildTaskPayload(record);
            Map<String, Object> created = client.createTask(cfg.listId, payload);
            if (created != null && created.containsKey('id')) {
                record.put('Id', String.valueOf(created.get('id')));
            }
            if (created != null && created.containsKey('url')) {
                record.put('url', String.valueOf(created.get('url')));
            }
        }

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

        ClickUpClient client = new ClickUpClient();
        for (String recordId : request.recordIds) {
            client.deleteTask(recordId);
        }
    }

    // "?"?"? Payload & Parsing Helpers "?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?

    @TestVisible
    private static Map<String, Object> buildTaskPayload(Map<String, Object> record) {
        Map<String, Object> payload = new Map<String, Object>();

        if (record.containsKey('name') && record.get('name') != null) {
            payload.put('name', String.valueOf(record.get('name')));
        }
        if (record.containsKey('description') && record.get('description') != null) {
            payload.put('description', String.valueOf(record.get('description')));
        }
        if (record.containsKey('status') && record.get('status') != null) {
            payload.put('status', String.valueOf(record.get('status')).toLowerCase().trim());
        }
        if (record.containsKey('priority') && record.get('priority') != null) {
            Integer pNum = mapPriorityToClickUp(record.get('priority'));
            if (pNum != null) {
                payload.put('priority', pNum);
            }
        }
        if (record.containsKey('dueDate') && record.get('dueDate') != null) {
            Long dueEpoch = parseDateToEpochMs(record.get('dueDate'));
            if (dueEpoch != null) {
                payload.put('due_date', dueEpoch);
            }
        }
        if (record.containsKey('startDate') && record.get('startDate') != null) {
            Long startEpoch = parseDateToEpochMs(record.get('startDate'));
            if (startEpoch != null) {
                payload.put('start_date', startEpoch);
            }
        }

        return payload;
    }

    @TestVisible
    private static List<Map<String, Object>> parseClickUpTasks(List<Object> rawTasks) {
        List<Map<String, Object>> records = new List<Map<String, Object>>();
        if (rawTasks == null) {
            return records;
        }

        for (Object itemObj : rawTasks) {
            if (!(itemObj instanceof Map<String, Object>)) continue;
            Map<String, Object> task = (Map<String, Object>) itemObj;
            Map<String, Object> row = new Map<String, Object>();

            row.put('Id', task.get('id'));
            row.put('name', task.get('name'));

            // Status
            String statusName = '';
            if (task.containsKey('status') && task.get('status') instanceof Map<String, Object>) {
                Map<String, Object> st = (Map<String, Object>) task.get('status');
                statusName = String.valueOf(st.get('status'));
            } else if (task.containsKey('status') && task.get('status') != null) {
                statusName = String.valueOf(task.get('status'));
            }
            row.put('status', statusName);

            // Priority
            String priorityName = 'None';
            if (task.containsKey('priority') && task.get('priority') instanceof Map<String, Object>) {
                Map<String, Object> pr = (Map<String, Object>) task.get('priority');
                if (pr.containsKey('priority') && pr.get('priority') != null) {
                    String pRaw = String.valueOf(pr.get('priority'));
                    priorityName = pRaw.substring(0, 1).toUpperCase() + pRaw.substring(1).toLowerCase();
                }
            }
            row.put('priority', priorityName);

            // Assignees
            List<String> assigneeNames = new List<String>();
            if (task.containsKey('assignees') && task.get('assignees') instanceof List<Object>) {
                for (Object aObj : (List<Object>) task.get('assignees')) {
                    if (aObj instanceof Map<String, Object>) {
                        Map<String, Object> aMap = (Map<String, Object>) aObj;
                        if (aMap.containsKey('username') && aMap.get('username') != null) {
                            assigneeNames.add(String.valueOf(aMap.get('username')));
                        }
                    }
                }
            }
            row.put('assignee', String.join(assigneeNames, ', '));

            // Dates
            row.put('dueDate', formatEpochMsToDate(task.get('due_date')));
            row.put('startDate', formatEpochMsToDate(task.get('start_date')));
            row.put('createdAt', formatEpochMsToDatetime(task.get('date_created')));

            // Description
            String taskDesc = '';
            if (task.containsKey('description') && task.get('description') != null) {
                taskDesc = String.valueOf(task.get('description'));
            } else if (task.containsKey('text_content') && task.get('text_content') != null) {
                taskDesc = String.valueOf(task.get('text_content'));
            }
            row.put('description', taskDesc);

            // URL
            row.put('url', task.get('url'));

            records.add(row);
        }
        return records;
    }

    @TestVisible
    private static Integer mapPriorityToClickUp(Object val) {
        if (val == null) return null;
        String p = String.valueOf(val).trim().toLowerCase();
        if (p == 'urgent' || p == '1') return 1;
        if (p == 'high' || p == '2') return 2;
        if (p == 'normal' || p == '3') return 3;
        if (p == 'low' || p == '4') return 4;
        return null;
    }

    @TestVisible
    private static String formatEpochMsToDate(Object val) {
        if (val == null) return null;
        String str = String.valueOf(val).trim();
        if (String.isBlank(str) || str == 'null') return null;
        try {
            Long ms = Long.valueOf(str);
            Datetime dt = Datetime.newInstance(ms);
            return dt.formatGMT('yyyy-MM-dd');
        } catch (Exception e) {
            return null;
        }
    }

    @TestVisible
    private static String formatEpochMsToDatetime(Object val) {
        if (val == null) return null;
        String str = String.valueOf(val).trim();
        if (String.isBlank(str) || str == 'null') return null;
        try {
            Long ms = Long.valueOf(str);
            Datetime dt = Datetime.newInstance(ms);
            return dt.formatGMT('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        } catch (Exception e) {
            return null;
        }
    }

    @TestVisible
    private static Long parseDateToEpochMs(Object val) {
        if (val == null) return null;
        String str = String.valueOf(val).trim();
        if (String.isBlank(str) || str == 'null') return null;
        if (str.isNumeric()) {
            return Long.valueOf(str);
        }
        if (str.length() == 10 && str.contains('-')) {
            Date d = Date.valueOf(str);
            Datetime dt = Datetime.newInstanceGmt(d.year(), d.month(), d.day(), 0, 0, 0);
            return dt.getTime();
        }
        try {
            Datetime dt = (Datetime) JSON.deserialize('"' + str + '"', Datetime.class);
            return dt.getTime();
        } catch (Exception e) {
            return null;
        }
    }

    @TestVisible
    private static List<appcg.GridDataProviderTypesV1.ColumnDefinition> buildColumnDefinitions(
        List<appcg.GridDataProviderTypesV1.Option> statusOptions
    ) {
        List<appcg.GridDataProviderTypesV1.ColumnDefinition> cols = new List<appcg.GridDataProviderTypesV1.ColumnDefinition>();

        cols.add(column('Id',          'Task ID',      'TEXT',     true,  false, '110px'));
        cols.add(column('name',        'Task Name',    'TEXT',     false, true,  '280px'));

        appcg.GridDataProviderTypesV1.ColumnDefinition statusCol = column('status', 'Status', 'PICKLIST', false, true, '140px');
        statusCol.picklistOptions = statusOptions;
        cols.add(statusCol);

        appcg.GridDataProviderTypesV1.ColumnDefinition priorityCol = column('priority', 'Priority', 'PICKLIST', false, true, '130px');
        priorityCol.picklistOptions = getPriorityOptions();
        cols.add(priorityCol);

        cols.add(column('assignee',    'Assignee',     'TEXT',     true,  true,  '160px'));
        cols.add(column('dueDate',     'Due Date',     'DATE',     false, true,  '130px'));
        cols.add(column('startDate',   'Start Date',   'DATE',     false, true,  '130px'));
        cols.add(column('description', 'Description',  'TEXT',     false, false, '280px'));
        cols.add(column('createdAt',   'Created Date', 'DATETIME', true,  true,  '170px'));
        cols.add(column('url',         'ClickUp Link', 'URL',      true,  false, '130px'));

        return cols;
    }

    private static appcg.GridDataProviderTypesV1.ColumnDefinition column(
        String id,
        String label,
        String fieldType,
        Boolean isReadOnly,
        Boolean visible,
        String columnWidth
    ) {
        appcg.GridDataProviderTypesV1.ColumnDefinition col = new appcg.GridDataProviderTypesV1.ColumnDefinition();
        col.id = id;
        col.label = label;
        col.fieldType = fieldType;
        col.isReadOnly = isReadOnly;
        col.visible = visible;
        col.columnWidth = columnWidth;
        return col;
    }

    @TestVisible
    private static List<appcg.GridDataProviderTypesV1.Option> extractStatusOptions(Map<String, Object> listMeta) {
        List<appcg.GridDataProviderTypesV1.Option> options = new List<appcg.GridDataProviderTypesV1.Option>();
        if (listMeta != null && listMeta.containsKey('statuses') && listMeta.get('statuses') instanceof List<Object>) {
            for (Object sObj : (List<Object>) listMeta.get('statuses')) {
                if (sObj instanceof Map<String, Object>) {
                    Map<String, Object> sMap = (Map<String, Object>) sObj;
                    String stName = String.valueOf(sMap.get('status'));
                    if (String.isNotBlank(stName)) {
                        appcg.GridDataProviderTypesV1.Option opt = new appcg.GridDataProviderTypesV1.Option();
                        opt.value = stName;
                        opt.label = stName.toUpperCase();
                        options.add(opt);
                    }
                }
            }
        }
        if (options.isEmpty()) {
            List<String> defaults = new List<String>{ 'to do', 'in progress', 'complete' };
            for (String def : defaults) {
                appcg.GridDataProviderTypesV1.Option opt = new appcg.GridDataProviderTypesV1.Option();
                opt.value = def;
                opt.label = def.toUpperCase();
                options.add(opt);
            }
        }
        return options;
    }

    @TestVisible
    private static List<appcg.GridDataProviderTypesV1.Option> getPriorityOptions() {
        List<appcg.GridDataProviderTypesV1.Option> options = new List<appcg.GridDataProviderTypesV1.Option>();
        List<String> pList = new List<String>{ 'Urgent', 'High', 'Normal', 'Low', 'None' };
        for (String p : pList) {
            appcg.GridDataProviderTypesV1.Option opt = new appcg.GridDataProviderTypesV1.Option();
            opt.value = p;
            opt.label = p;
            options.add(opt);
        }
        return options;
    }

    @TestVisible
    private static List<Map<String, Object>> filterBySearch(List<Map<String, Object>> records, String term) {
        if (records == null || String.isBlank(term)) {
            return records;
        }
        String lower = term.toLowerCase().trim();
        List<Map<String, Object>> filtered = new List<Map<String, Object>>();
        for (Map<String, Object> r : records) {
            Boolean match = false;
            for (String field : new List<String>{ 'name', 'status', 'priority', 'assignee', 'description' }) {
                Object val = r.get(field);
                if (val != null && String.valueOf(val).toLowerCase().contains(lower)) {
                    match = true;
                    break;
                }
            }
            if (match) {
                filtered.add(r);
            }
        }
        return filtered;
    }
}