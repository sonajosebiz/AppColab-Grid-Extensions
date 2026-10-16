global with sharing class GitHubGridDataProvider
    implements appcg.GridDataProviderV1, appcg.GridDataMutationProviderV1 {

    public class ProviderException extends Exception {}

    global GitHubGridDataProvider() {}

    // "?"?"? Instance Cache "?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?
    private List<Map<String, Object>> cachedRecords;

    // "?"?"? Config "?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?

    @TestVisible
    private class GitHubConfig {
        public String owner;
        public String repo;
        public String state;                // 'all' (default), 'open', 'closed'
        public Boolean includePullRequests; // false (default)
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
    private static GitHubConfig parseConfig(appcg.GridDataProviderTypesV1.ProviderContext context) {
        appcg__Grid_Definition__c gridDef = getGridDefinition(context);
        String configJson = gridDef != null ? gridDef.appcg__Data_Provider_Config__c : null;
        if (String.isBlank(configJson)) {
            throw new ProviderException(
                'GitHub provider requires configuration. ' +
                'Set Data Provider Configuration with {"owner":"...","repo":"..."}'
            );
        }

        GitHubConfig cfg;
        try {
            cfg = (GitHubConfig) JSON.deserialize(configJson, GitHubConfig.class);
        } catch (Exception e) {
            throw new ProviderException('Invalid GitHub provider configuration: ' + e.getMessage());
        }

        if (String.isBlank(cfg.owner)) {
            throw new ProviderException('owner is required in GitHub provider configuration.');
        }
        if (String.isBlank(cfg.repo)) {
            throw new ProviderException('repo is required in GitHub provider configuration.');
        }

        if (String.isBlank(cfg.state)) {
            cfg.state = 'all';
        }
        if (cfg.includePullRequests == null) {
            cfg.includePullRequests = false;
        }

        return cfg;
    }

    // "?"?"? GridDataProviderV1 "?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?

    global appcg.GridDataProviderTypesV1.Capabilities getCapabilities(
        appcg.GridDataProviderTypesV1.ProviderContext context
    ) {
        GitHubConfig cfg = parseConfig(context);
        GitHubClient client = new GitHubClient();

        // Fetch initial issues (page 1, up to 100)
        List<Object> rawIssues = client.listIssues(cfg.owner, cfg.repo, cfg.state, 1, 100);
        cachedRecords = parseGitHubIssues(rawIssues, cfg.includePullRequests);

        appcg.GridDataProviderTypesV1.Capabilities capabilities = new appcg.GridDataProviderTypesV1.Capabilities();
        capabilities.supportedFeatures = new Set<String>{
            'SEARCH', 'REFRESH', 'ADD', 'EDIT', 'DOWNLOAD_CSV'
        };
        capabilities.supportedRowActions = new Set<String>();
        capabilities.supportsServerPagination = false;
        capabilities.columns = buildColumnDefinitions();

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
            GitHubConfig cfg = parseConfig(request.context);
            GitHubClient client = new GitHubClient();
            List<Object> rawIssues = client.listIssues(cfg.owner, cfg.repo, cfg.state, 1, 100);
            records = parseGitHubIssues(rawIssues, cfg.includePullRequests);
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
        GitHubConfig cfg = parseConfig(request.context);
        GitHubClient client = new GitHubClient();

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

        // Update existing issues
        for (Map<String, Object> record : existingRecords) {
            Integer issueNumber = Integer.valueOf(String.valueOf(record.get('Id')));
            Map<String, Object> payload = buildIssuePayload(record);
            client.updateIssue(cfg.owner, cfg.repo, issueNumber, payload);
        }

        // Create new issues
        for (Map<String, Object> record : newRecords) {
            Map<String, Object> payload = buildIssuePayload(record);
            Map<String, Object> created = client.createIssue(cfg.owner, cfg.repo, payload);
            if (created != null && created.containsKey('number')) {
                record.put('Id', String.valueOf(created.get('number')));
            }
            if (created != null && created.containsKey('html_url')) {
                record.put('url', String.valueOf(created.get('html_url')));
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
        GitHubConfig cfg = parseConfig(request.context);
        GitHubClient client = new GitHubClient();
        for (String recordId : request.recordIds) {
            Integer issueNumber = Integer.valueOf(recordId);
            client.updateIssue(cfg.owner, cfg.repo, issueNumber, new Map<String, Object>{ 'state' => 'closed' });
        }
    }

    // "?"?"? Helpers & Parsers "?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?

    @TestVisible
    private static Map<String, Object> buildIssuePayload(Map<String, Object> record) {
        Map<String, Object> payload = new Map<String, Object>();
        if (record.containsKey('title') && record.get('title') != null) {
            payload.put('title', String.valueOf(record.get('title')));
        }
        if (record.containsKey('state') && record.get('state') != null) {
            payload.put('state', String.valueOf(record.get('state')).toLowerCase().trim());
        }
        if (record.containsKey('body') && record.get('body') != null) {
            payload.put('body', String.valueOf(record.get('body')));
        }
        return payload;
    }

    @TestVisible
    private static List<Map<String, Object>> parseGitHubIssues(List<Object> rawIssues, Boolean includePullRequests) {
        List<Map<String, Object>> records = new List<Map<String, Object>>();
        if (rawIssues == null) {
            return records;
        }

        for (Object itemObj : rawIssues) {
            if (!(itemObj instanceof Map<String, Object>)) continue;
            Map<String, Object> issue = (Map<String, Object>) itemObj;

            // Filter out pull requests unless explicitly enabled
            if (includePullRequests != true && issue.containsKey('pull_request') && issue.get('pull_request') != null) {
                continue;
            }

            Map<String, Object> row = new Map<String, Object>();

            // Identity
            row.put('Id', String.valueOf(issue.get('number')));
            row.put('title', issue.get('title'));
            row.put('state', issue.get('state'));

            // Author
            String authorName = '';
            if (issue.containsKey('user') && issue.get('user') instanceof Map<String, Object>) {
                authorName = String.valueOf(((Map<String, Object>) issue.get('user')).get('login'));
            }
            row.put('author', authorName);

            // Assignees
            List<String> assigneeNames = new List<String>();
            if (issue.containsKey('assignees') && issue.get('assignees') instanceof List<Object>) {
                for (Object aObj : (List<Object>) issue.get('assignees')) {
                    if (aObj instanceof Map<String, Object>) {
                        assigneeNames.add(String.valueOf(((Map<String, Object>) aObj).get('login')));
                    }
                }
            } else if (issue.containsKey('assignee') && issue.get('assignee') instanceof Map<String, Object>) {
                assigneeNames.add(String.valueOf(((Map<String, Object>) issue.get('assignee')).get('login')));
            }
            row.put('assignees', String.join(assigneeNames, ', '));

            // Labels
            List<String> labelNames = new List<String>();
            if (issue.containsKey('labels') && issue.get('labels') instanceof List<Object>) {
                for (Object lObj : (List<Object>) issue.get('labels')) {
                    if (lObj instanceof Map<String, Object>) {
                        labelNames.add(String.valueOf(((Map<String, Object>) lObj).get('name')));
                    }
                }
            }
            row.put('labels', String.join(labelNames, ', '));

            // Comments
            row.put('comments', issue.get('comments'));

            // Timestamps
            row.put('createdAt', formatIsoDatetime(issue.get('created_at')));
            row.put('updatedAt', formatIsoDatetime(issue.get('updated_at')));

            // Body
            String bodyText = '';
            if (issue.containsKey('body') && issue.get('body') != null) {
                bodyText = String.valueOf(issue.get('body'));
            }
            row.put('body', bodyText);

            // Web URL
            row.put('url', issue.get('html_url'));

            records.add(row);
        }

        return records;
    }

    @TestVisible
    private static String formatIsoDatetime(Object val) {
        if (val == null) return null;
        String str = String.valueOf(val).trim();
        if (String.isBlank(str) || str == 'null') return null;
        try {
            Datetime dt = (Datetime) JSON.deserialize('"' + str + '"', Datetime.class);
            return dt.formatGMT('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        } catch (Exception e) {
            return str;
        }
    }

    @TestVisible
    private static List<appcg.GridDataProviderTypesV1.ColumnDefinition> buildColumnDefinitions() {
        List<appcg.GridDataProviderTypesV1.ColumnDefinition> cols = new List<appcg.GridDataProviderTypesV1.ColumnDefinition>();

        cols.add(column('Id',        'Issue #',      'TEXT',     true,  true, '100px'));
        cols.add(column('title',     'Title',        'TEXT',     false, true, '320px'));

        appcg.GridDataProviderTypesV1.ColumnDefinition stateCol = column('state', 'State', 'PICKLIST', false, true, '120px');
        stateCol.picklistOptions = getStateOptions();
        cols.add(stateCol);

        cols.add(column('author',    'Author',       'TEXT',     true,  true, '140px'));
        cols.add(column('assignees', 'Assignees',    'TEXT',     true,  true, '160px'));
        cols.add(column('labels',    'Labels',       'TEXT',     true,  true, '180px'));
        cols.add(column('comments',  'Comments',     'INTEGER',  true,  true, '100px'));
        cols.add(column('createdAt', 'Created Date', 'DATETIME', true,  true, '170px'));
        cols.add(column('updatedAt', 'Updated Date', 'DATETIME', true,  true, '170px'));
        cols.add(column('body',      'Description',  'TEXT',     false, true, '300px'));
        cols.add(column('url',       'GitHub Link',  'URL',      true,  true, '130px'));

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
    private static List<appcg.GridDataProviderTypesV1.Option> getStateOptions() {
        List<appcg.GridDataProviderTypesV1.Option> options = new List<appcg.GridDataProviderTypesV1.Option>();
        for (String st : new List<String>{ 'open', 'closed' }) {
            appcg.GridDataProviderTypesV1.Option opt = new appcg.GridDataProviderTypesV1.Option();
            opt.value = st;
            opt.label = st.toUpperCase();
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
            for (String field : new List<String>{ 'title', 'state', 'author', 'assignees', 'labels', 'body' }) {
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