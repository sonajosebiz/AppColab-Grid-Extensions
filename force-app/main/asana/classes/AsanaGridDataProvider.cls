global with sharing class AsanaGridDataProvider
    implements appcg.GridDataProviderV1, appcg.GridDataMutationProviderV1 {

    public class ProviderException extends Exception {}


    private static final Integer DEFAULT_PAGE_SIZE = 20;
    private static final Integer MAX_PAGE_SIZE = 100;

    // ─── Instance Cache ───────────────────────────────────────────────
    private List<Map<String, Object>> cachedRecords;
    private Integer cachedTotalCount;

    // ─── Config ───────────────────────────────────────────────────────

    @TestVisible
    private class AsanaConfig {
        public String resource;       // 'tasks' (default), 'projects', 'sections'
        public String projectId;      // Asana Project GID
        public String sectionId;      // Asana Section GID
        public String workspaceId;    // Asana Workspace GID
        public String userTaskListId; // Asana My Tasks GID
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
    private static AsanaConfig parseConfig(appcg.GridDataProviderTypesV1.ProviderContext context) {
        appcg__Grid_Definition__c gridDef = getGridDefinition(context);
        String configJson = gridDef != null ? gridDef.appcg__Data_Provider_Config__c : null;
        if (String.isBlank(configJson)) {
            throw new ProviderException(
                'Asana provider requires configuration. ' +
                'Set Data Provider Configuration with {"projectId":"..."}'
            );
        }

        AsanaConfig cfg = new AsanaConfig();
        cfg.resource = 'tasks';

        try {
            Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(configJson);
            if (raw.containsKey('resource')) {
                cfg.resource = String.valueOf(raw.get('resource')).toLowerCase().trim();
            }
            if (raw.containsKey('projectId')) {
                cfg.projectId = String.valueOf(raw.get('projectId')).trim();
            }
            if (raw.containsKey('sectionId')) {
                cfg.sectionId = String.valueOf(raw.get('sectionId')).trim();
            }
            if (raw.containsKey('workspaceId')) {
                cfg.workspaceId = String.valueOf(raw.get('workspaceId')).trim();
            }
            if (raw.containsKey('userTaskListId')) {
                cfg.userTaskListId = String.valueOf(raw.get('userTaskListId')).trim();
            }
        } catch (Exception e) {
            throw new ProviderException('Invalid Asana provider configuration: ' + e.getMessage());
        }

        if ('tasks'.equals(cfg.resource) &&
            String.isBlank(cfg.projectId) &&
            String.isBlank(cfg.sectionId) &&
            String.isBlank(cfg.userTaskListId)) {
            throw new ProviderException('projectId, sectionId, or userTaskListId is required for tasks resource.');
        }

        if ('projects'.equals(cfg.resource) && String.isBlank(cfg.workspaceId)) {
            throw new ProviderException('workspaceId is required for projects resource.');
        }

        return cfg;
    }

    // ─── GridDataProviderV1 ───────────────────────────────────────────

    global appcg.GridDataProviderTypesV1.Capabilities getCapabilities(
        appcg.GridDataProviderTypesV1.ProviderContext context
    ) {
        AsanaConfig cfg = parseConfig(context);
        try {
            AsanaClient client = new AsanaClient();

            // Fetch initial page of records and cache
            Map<String, Object> response = fetchResourcePage(client, cfg, 0, DEFAULT_PAGE_SIZE);
            List<Object> rawList = (List<Object>) response.get('data');
            Boolean hasNext = response.containsKey('next_page') && response.get('next_page') != null;

            cachedRecords = parseAsanaRecords(rawList, cfg.resource);
            cachedTotalCount = hasNext ? cachedRecords.size() + 1 : cachedRecords.size();

            // Fetch section list if project is configured (to populate column options)
            List<appcg.GridDataProviderTypesV1.Option> sectionOptions = new List<appcg.GridDataProviderTypesV1.Option>();
            if (String.isNotBlank(cfg.projectId) && 'tasks'.equals(cfg.resource)) {
                try {
                    Map<String, Object> secRes = client.getProjectSections(cfg.projectId);
                    List<Object> secList = (List<Object>) secRes.get('data');
                    if (secList != null) {
                        for (Object s : secList) {
                            Map<String, Object> sm = (Map<String, Object>) s;
                            appcg.GridDataProviderTypesV1.Option opt = new appcg.GridDataProviderTypesV1.Option();
                            opt.label = String.valueOf(sm.get('name'));
                            opt.value = String.valueOf(sm.get('name'));
                            sectionOptions.add(opt);
                        }
                    }
                } catch (Exception ignored) {}
            }

            appcg.GridDataProviderTypesV1.Capabilities capabilities = new appcg.GridDataProviderTypesV1.Capabilities();
            capabilities.supportedFeatures = new Set<String>{
                'SEARCH', 'REFRESH', 'ADD', 'EDIT', 'DELETE', 'DOWNLOAD_CSV'
            };
            capabilities.supportedRowActions = new Set<String>{ 'DELETE' };
            capabilities.supportsServerPagination = true;
            capabilities.maxPageSize = MAX_PAGE_SIZE;
            capabilities.columns = buildColumnDefinitions(cfg.resource, sectionOptions);

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

            Integer pageSize;
            Integer requestedPageSize = (request.pageSize != null && request.pageSize > 0)
                ? request.pageSize
                : (gridDef?.appcg__Page_Size__c != null ? Integer.valueOf(gridDef.appcg__Page_Size__c) : DEFAULT_PAGE_SIZE);
            if (paginationType == 'Client-Side') {
                pageSize = Math.min(recordLimit, MAX_PAGE_SIZE);
            } else {
                pageSize = (gridDef?.appcg__Record_Limit__c != null && gridDef.appcg__Record_Limit__c > 0)
                    ? Math.min(requestedPageSize, (Integer) gridDef.appcg__Record_Limit__c)
                    : Math.min(requestedPageSize, MAX_PAGE_SIZE);
            }
            Integer startIndex = request.startIndex != null ? Math.max(0, request.startIndex) : 0;

            if (cachedRecords != null && startIndex == 0) {
                // Use cached first page from getCapabilities()
                records = cachedRecords;
                totalCount = cachedTotalCount;
                cachedRecords = null;
            } else {
                AsanaConfig cfg = parseConfig(request.context);
                AsanaClient client = new AsanaClient();
                Map<String, Object> response = fetchResourcePage(client, cfg, startIndex, pageSize);
                List<Object> rawList = (List<Object>) response.get('data');
                Boolean hasNext = response.containsKey('next_page') && response.get('next_page') != null;

                records = parseAsanaRecords(rawList, cfg.resource);
                totalCount = hasNext ? startIndex + records.size() + 1 : startIndex + records.size();
            }

            while (records != null && records.size() > pageSize) {
                records.remove(records.size() - 1);
            }

            // Apply search filtering if search term provided
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
        AsanaConfig cfg = parseConfig(request.context);
        try {
            AsanaClient client = new AsanaClient();

            if (request.records != null) {
                for (Map<String, Object> record : request.records) {
                    String recordId = record.get('Id') == null ? null : String.valueOf(record.get('Id'));

                    if (String.isBlank(recordId) || recordId.startsWith('TEMP_')) {
                        // Create Task
                        Map<String, Object> taskData = new Map<String, Object>();
                        if (record.containsKey('name')) {
                            taskData.put('name', record.get('name'));
                        }
                        if (record.containsKey('notes')) {
                            taskData.put('notes', record.get('notes'));
                        }
                        if (record.containsKey('dueOn') && String.isNotBlank(String.valueOf(record.get('dueOn')))) {
                            taskData.put('due_on', record.get('dueOn'));
                        }
                        if (record.containsKey('completed')) {
                            taskData.put('completed', record.get('completed'));
                        }
                        if (String.isNotBlank(cfg.projectId)) {
                            taskData.put('projects', new List<String>{ cfg.projectId });
                        }

                        Map<String, Object> createRes = client.createTask(taskData);
                        Map<String, Object> createdTask = (Map<String, Object>) createRes.get('data');
                        if (createdTask != null && createdTask.containsKey('gid')) {
                            record.put('Id', createdTask.get('gid'));
                        }
                    } else {
                        // Update Task
                        Map<String, Object> taskData = new Map<String, Object>();
                        if (record.containsKey('name')) {
                            taskData.put('name', record.get('name'));
                        }
                        if (record.containsKey('notes')) {
                            taskData.put('notes', record.get('notes'));
                        }
                        if (record.containsKey('dueOn')) {
                            Object due = record.get('dueOn');
                            taskData.put('due_on', (due == null || String.isBlank(String.valueOf(due))) ? null : due);
                        }
                        if (record.containsKey('completed')) {
                            taskData.put('completed', record.get('completed'));
                        }

                        client.updateTask(recordId, taskData);
                    }
                }
            }

            appcg.GridDataProviderTypesV1.SaveResult result = new appcg.GridDataProviderTypesV1.SaveResult();
            result.records = request.records;
            return result;
        } finally {
        }
    }

    global void deleteRecords(appcg.GridDataProviderTypesV1.DeleteRequest request) {
        if (request == null || request.recordIds == null || request.recordIds.isEmpty()) {
            return;
        }
        try {
            AsanaClient client = new AsanaClient();
            for (String recordId : request.recordIds) {
                if (String.isNotBlank(recordId) && !recordId.startsWith('TEMP_')) {
                    client.deleteTask(recordId);
                }
            }
        } finally {
        }
    }

    // ─── Internal Fetchers & Parsers ──────────────────────────────────

    private static Map<String, Object> fetchResourcePage(
        AsanaClient client,
        AsanaConfig cfg,
        Integer startIndex,
        Integer pageSize
    ) {
        // Page 1 query
        if (startIndex == 0) {
            if ('projects'.equals(cfg.resource)) {
                return client.getProjects(cfg.workspaceId);
            }
            if (String.isNotBlank(cfg.sectionId)) {
                return client.getSectionTasks(cfg.sectionId, pageSize, null);
            }
            if (String.isNotBlank(cfg.userTaskListId)) {
                return client.getUserTasks(cfg.userTaskListId, pageSize, null);
            }
            return client.getProjectTasks(cfg.projectId, pageSize, null);
        }

        // Subsequent page traversal
        String offsetToken = null;
        Integer currentOffset = 0;
        Map<String, Object> lastResponse = null;

        while (currentOffset <= startIndex) {
            Integer fetchSize = Math.min(pageSize, MAX_PAGE_SIZE);

            if (String.isNotBlank(cfg.sectionId)) {
                lastResponse = client.getSectionTasks(cfg.sectionId, fetchSize, offsetToken);
            } else if (String.isNotBlank(cfg.userTaskListId)) {
                lastResponse = client.getUserTasks(cfg.userTaskListId, fetchSize, offsetToken);
            } else {
                lastResponse = client.getProjectTasks(cfg.projectId, fetchSize, offsetToken);
            }

            if (currentOffset == startIndex) {
                return lastResponse;
            }

            Map<String, Object> nextPage = (Map<String, Object>) lastResponse.get('next_page');
            if (nextPage == null || !nextPage.containsKey('offset')) {
                break;
            }
            offsetToken = (String) nextPage.get('offset');
            currentOffset += fetchSize;
        }

        return lastResponse != null ? lastResponse : new Map<String, Object>{ 'data' => new List<Object>() };
    }

    @TestVisible
    private static List<Map<String, Object>> parseAsanaRecords(List<Object> rawList, String resource) {
        List<Map<String, Object>> records = new List<Map<String, Object>>();
        if (rawList == null) {
            return records;
        }

        for (Object itemObj : rawList) {
            Map<String, Object> item = (Map<String, Object>) itemObj;
            Map<String, Object> row = new Map<String, Object>();

            row.put('Id', item.get('gid'));
            row.put('name', item.get('name'));

            if ('projects'.equals(resource)) {
                row.put('color', item.get('color'));
                row.put('archived', item.get('archived') == true);
                row.put('createdAt', item.get('created_at'));
                row.put('permalinkUrl', item.get('permalink_url'));
            } else {
                // Task resource
                row.put('completed', item.get('completed') == true);
                row.put('dueOn', item.get('due_on'));
                row.put('dueAt', item.get('due_at'));
                row.put('notes', item.get('notes'));
                row.put('createdAt', item.get('created_at'));
                row.put('modifiedAt', item.get('modified_at'));
                row.put('permalinkUrl', item.get('permalink_url'));

                // Assignee
                if (item.containsKey('assignee') && item.get('assignee') instanceof Map<String, Object>) {
                    Map<String, Object> assignee = (Map<String, Object>) item.get('assignee');
                    row.put('assigneeName', assignee.get('name'));
                    row.put('assigneeEmail', assignee.get('email'));
                } else {
                    row.put('assigneeName', '');
                    row.put('assigneeEmail', '');
                }

                // Section name from memberships
                String sectionName = '';
                if (item.containsKey('memberships') && item.get('memberships') instanceof List<Object>) {
                    List<Object> memberships = (List<Object>) item.get('memberships');
                    for (Object mObj : memberships) {
                        Map<String, Object> m = (Map<String, Object>) mObj;
                        if (m.containsKey('section') && m.get('section') instanceof Map<String, Object>) {
                            Map<String, Object> sec = (Map<String, Object>) m.get('section');
                            sectionName = String.valueOf(sec.get('name'));
                            break;
                        }
                    }
                }
                row.put('sectionName', sectionName);
            }

            records.add(row);
        }

        return records;
    }

    // ─── Column Definitions ───────────────────────────────────────────

    @TestVisible
    private static List<appcg.GridDataProviderTypesV1.ColumnDefinition> buildColumnDefinitions(
        String resource,
        List<appcg.GridDataProviderTypesV1.Option> sectionOptions
    ) {
        List<appcg.GridDataProviderTypesV1.ColumnDefinition> cols = new List<appcg.GridDataProviderTypesV1.ColumnDefinition>();

        if ('projects'.equals(resource)) {
            cols.add(column('Id',           'ID',            'TEXT',     true,  false, '100px'));
            cols.add(column('name',         'Name',          'TEXT',     false, true,  '260px'));
            cols.add(column('color',        'Color',                        'TEXT',     true,  true,  '120px'));
            cols.add(column('archived',     'Archived',                     'BOOLEAN',  true,  true,  '90px'));
            cols.add(column('createdAt',    'Created Date',  'DATETIME', true,  true,  '180px'));
            cols.add(column('permalinkUrl', 'Asana Link',                   'URL',      true,  true,  '140px'));
        } else {
            // Task columns
            cols.add(column('Id',           'ID',            'TEXT',     true,  false, '100px'));
            cols.add(column('name',         'Name',          'TEXT',     false, true,  '280px'));
            cols.add(column('assigneeName', 'Assignee',      'TEXT',     true,  true,  '180px'));

            appcg.GridDataProviderTypesV1.ColumnDefinition secCol = column('sectionName', 'Section', 'TEXT', true, true, '160px');
            if (sectionOptions != null && !sectionOptions.isEmpty()) {
                secCol.fieldType = 'PICKLIST';
                secCol.picklistOptions = sectionOptions;
            }
            cols.add(secCol);

            cols.add(column('dueOn',        'Due Date',      'DATE',     false, true,  '120px'));
            cols.add(column('completed',    'Status',        'BOOLEAN',  false, true,  '90px'));
            cols.add(column('notes',        'Description',   'TEXT',     false, true,  '300px'));
            cols.add(column('createdAt',    'Created Date',  'DATETIME', true,  true,  '170px'));
            cols.add(column('permalinkUrl', 'Asana Link',                   'URL',      true,  true,  '140px'));
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

    private static List<Map<String, Object>> filterBySearch(
        List<Map<String, Object>> records,
        String searchTerm
    ) {
        String lower = searchTerm.toLowerCase();
        List<Map<String, Object>> filtered = new List<Map<String, Object>>();
        for (Map<String, Object> r : records) {
            Boolean matched = false;
            for (String key : r.keySet()) {
                if ('Id'.equalsIgnoreCase(key)) continue;
                Object v = r.get(key);
                if (v != null && String.valueOf(v).toLowerCase().contains(lower)) {
                    matched = true;
                    break;
                }
            }
            if (matched) {
                filtered.add(r);
            }
        }
        return filtered;
    }
}
