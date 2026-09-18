global with sharing class GmailGridDataProvider implements appcg.GridDataProviderV1 {

    public class ProviderException extends Exception {}

    private static final Integer DEFAULT_PAGE_SIZE = 20;
    private static final Integer MAX_CALLOUT_MESSAGES = 25;

    @TestVisible
    private class GmailConfig {
        public String query;
        public Integer maxResults;
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
    private static GmailConfig parseConfig(appcg.GridDataProviderTypesV1.ProviderContext context) {
        appcg__Grid_Definition__c gridDef = getGridDefinition(context);
        String configJson = gridDef != null ? gridDef.appcg__Data_Provider_Config__c : null;
        if (String.isBlank(configJson)) {
            return new GmailConfig();
        }
        try {
            return (GmailConfig) JSON.deserialize(configJson, GmailConfig.class);
        } catch (Exception e) {
            return new GmailConfig();
        }
    }

    global appcg.GridDataProviderTypesV1.Capabilities getCapabilities(appcg.GridDataProviderTypesV1.ProviderContext context) {
        appcg.GridDataProviderTypesV1.Capabilities capabilities = new appcg.GridDataProviderTypesV1.Capabilities();
        capabilities.supportedFeatures = new Set<String>{ 'SEARCH', 'REFRESH' };
        capabilities.supportedRowActions = new Set<String>();
        capabilities.supportsServerPagination = true;
        capabilities.maxPageSize = DEFAULT_PAGE_SIZE;
        capabilities.columns = buildColumnDefinitions();
        return capabilities;
    }

    global appcg.GridDataProviderTypesV1.PageResult getData(appcg.GridDataProviderTypesV1.QueryRequest request) {
        appcg.GridDataProviderTypesV1.PageResult result = new appcg.GridDataProviderTypesV1.PageResult();
        result.records = new List<Map<String, Object>>();
        result.totalCount = 0;

        appcg__Grid_Definition__c gridDef = getGridDefinition(request?.context);
        GmailConfig config = parseConfig(request?.context);

        String paginationType = gridDef?.appcg__Pagination_Type__c;
        Integer recordLimit = (gridDef?.appcg__Record_Limit__c != null && gridDef.appcg__Record_Limit__c > 0)
            ? (Integer) gridDef.appcg__Record_Limit__c
            : DEFAULT_PAGE_SIZE;

        Integer pageSize;
        Integer requestedPageSize = (request.pageSize != null && request.pageSize > 0)
            ? request.pageSize
            : (gridDef?.appcg__Page_Size__c != null ? Integer.valueOf(gridDef.appcg__Page_Size__c) : DEFAULT_PAGE_SIZE);

        if (paginationType == 'Client-Side') {
            pageSize = Math.min(recordLimit, MAX_CALLOUT_MESSAGES);
        } else {
            pageSize = (gridDef?.appcg__Record_Limit__c != null && gridDef.appcg__Record_Limit__c > 0)
                ? Math.min(requestedPageSize, (Integer) gridDef.appcg__Record_Limit__c)
                : Math.min(requestedPageSize, DEFAULT_PAGE_SIZE);
        }

        if (config.maxResults != null && config.maxResults > 0) {
            pageSize = Math.min(pageSize, config.maxResults);
        }
        // Enforce hard ceiling to never exceed Salesforce's 100 HTTP callout limit per transaction
        pageSize = Math.min(pageSize, MAX_CALLOUT_MESSAGES);

        String gmailQuery = buildGmailQuery(request, config.query);
        try {
            GmailClient client = new GmailClient();
            Map<String, Object> listRes = client.listMessages(gmailQuery, pageSize);

            Integer estimatedTotal = listRes.containsKey('resultSizeEstimate')
                ? Integer.valueOf(listRes.get('resultSizeEstimate'))
                : 0;
            if (gridDef?.appcg__Record_Limit__c != null && gridDef.appcg__Record_Limit__c > 0) {
                estimatedTotal = Math.min(estimatedTotal, (Integer) gridDef.appcg__Record_Limit__c);
            }
            result.totalCount = estimatedTotal;

            List<Object> messages = (List<Object>) listRes.get('messages');
            if (messages == null || messages.isEmpty()) {
                return result;
            }

            Integer fetchLimit = Math.min(messages.size(), pageSize);
            fetchLimit = Math.min(fetchLimit, MAX_CALLOUT_MESSAGES);

            for (Integer i = 0; i < fetchLimit; i++) {
                Map<String, Object> msgRef = (Map<String, Object>) messages[i];
                String msgId = (String) msgRef.get('id');
                if (String.isNotBlank(msgId)) {
                    Map<String, Object> fullMsg = client.getMessage(msgId);
                    result.records.add(parseToGridRow(fullMsg));
                }
            }

            while (result.records != null && result.records.size() > pageSize) {
                result.records.remove(result.records.size() - 1);
            }
        } finally {
        }

        if (paginationType == 'Client-Side') {
            result.totalCount = result.records.size();
        }

        return result;
    }

    // ─── Column Definitions ───────────────────────────────────────────

    private static List<appcg.GridDataProviderTypesV1.ColumnDefinition> buildColumnDefinitions() {
        return new List<appcg.GridDataProviderTypesV1.ColumnDefinition>{
            column('Id',          'ID',  'TEXT',     true, false, '100px'),
            column('From',        'From',        'TEXT',     true, true,  '220px'),
            column('To',          'To',          'TEXT',     true, true,  '220px'),
            column('Subject',     'Subject',     'TEXT',     true, true,  '300px'),
            column('Date',        'Date',        'TEXT',     true, true,  '180px'),
            column('Snippet',     'Snippet',     'TEXT',     true, true,  '350px'),
            column('IsUnread',    'Unread',      'BOOLEAN',  true, true,  '80px')
        };
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

    // ─── Query Builder ────────────────────────────────────────────────

    @TestVisible
    private static String buildGmailQuery(appcg.GridDataProviderTypesV1.QueryRequest request) {
        return buildGmailQuery(request, null);
    }

    @TestVisible
    private static String buildGmailQuery(appcg.GridDataProviderTypesV1.QueryRequest request, String baseQuery) {
        List<String> parts = new List<String>();

        if (String.isNotBlank(baseQuery)) {
            parts.add(baseQuery.trim());
        }

        // User search term from the grid search bar
        if (String.isNotBlank(request.searchTerm)) {
            parts.add(request.searchTerm.trim());
        }

        // Admin filter rules (e.g. label:INBOX, from:someone@example.com)
        if (request.adminFilter != null && request.adminFilter.rules != null) {
            for (appcg.GridDataProviderTypesV1.FilterRule rule : request.adminFilter.rules) {
                if (String.isNotBlank(rule.field) && String.isNotBlank(rule.value)) {
                    parts.add(rule.field + ':' + rule.value);
                }
            }
        }

        // User filter rules
        if (request.userFilter != null && request.userFilter.rules != null) {
            for (appcg.GridDataProviderTypesV1.FilterRule rule : request.userFilter.rules) {
                if (String.isNotBlank(rule.field) && String.isNotBlank(rule.value)) {
                    parts.add(rule.field + ':' + rule.value);
                }
            }
        }

        return parts.isEmpty() ? null : String.join(parts, ' ');
    }

    // ─── Row Parser ───────────────────────────────────────────────────

    @TestVisible
    private static Map<String, Object> parseToGridRow(Map<String, Object> raw) {
        Map<String, Object> row = new Map<String, Object>();
        row.put('Id', raw.get('id'));

        // Parse internalDate for formatted display
        if (raw.get('internalDate') != null) {
            Long internalDate = Long.valueOf((String) raw.get('internalDate'));
            row.put('Date', DateTime.newInstance(internalDate).format('MMM d, yyyy h:mm a'));
        }

        row.put('Snippet', raw.get('snippet'));

        // Labels and unread status
        Boolean isUnread = false;
        List<Object> labelObjs = (List<Object>) raw.get('labelIds');
        if (labelObjs != null) {
            for (Object lbl : labelObjs) {
                if (String.valueOf(lbl) == 'UNREAD') {
                    isUnread = true;
                    break;
                }
            }
        }
        row.put('IsUnread', isUnread);

        // Extract headers: From, To, Subject
        Map<String, Object> payload = (Map<String, Object>) raw.get('payload');
        if (payload != null) {
            List<Object> headers = (List<Object>) payload.get('headers');
            if (headers != null) {
                for (Object hObj : headers) {
                    Map<String, Object> header = (Map<String, Object>) hObj;
                    String name = (String) header.get('name');
                    String val = (String) header.get('value');
                    if (name == null) continue;
                    if (name.equalsIgnoreCase('From')) {
                        row.put('From', val);
                    } else if (name.equalsIgnoreCase('To')) {
                        row.put('To', val);
                    } else if (name.equalsIgnoreCase('Subject')) {
                        row.put('Subject', val);
                    } else if (name.equalsIgnoreCase('Date') && !row.containsKey('Date')) {
                        row.put('Date', val);
                    }
                }
            }
        }

        if (!row.containsKey('Subject') || row.get('Subject') == null) {
            row.put('Subject', '(No Subject)');
        }
        if (!row.containsKey('From')) {
            row.put('From', '');
        }
        if (!row.containsKey('To')) {
            row.put('To', '');
        }

        return row;
    }
}
