global with sharing class OutlookGridDataProvider implements appcg.GridDataProviderV1 {

    public class ProviderException extends Exception {}

    private static final Integer DEFAULT_PAGE_SIZE = 20;
    private static final Integer MAX_PAGE_SIZE = 50;

    @TestVisible
    private class OutlookConfig {
        public String resource;          // 'messages' (default) or 'events'
        public String filter;            // OData filter expression
        public String parentMatchField;  // Field on parent record to filter by (default 'Email')
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
    private static OutlookConfig parseConfig(appcg.GridDataProviderTypesV1.ProviderContext context) {
        OutlookConfig cfg = new OutlookConfig();
        cfg.resource = 'messages';
        cfg.parentMatchField = 'Email';

        appcg__Grid_Definition__c gridDef = getGridDefinition(context);
        String configJson = gridDef != null ? gridDef.appcg__Data_Provider_Config__c : null;
        if (String.isBlank(configJson)) {
            return cfg;
        }

        try {
            Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(configJson);
            if (raw.containsKey('resource')) {
                cfg.resource = String.valueOf(raw.get('resource')).trim().toLowerCase();
            }
            if (raw.containsKey('filter')) {
                cfg.filter = String.valueOf(raw.get('filter')).trim();
            }
            if (raw.containsKey('parentMatchField')) {
                cfg.parentMatchField = String.valueOf(raw.get('parentMatchField')).trim();
            }
        } catch (Exception e) {
            return cfg;
        }
        return cfg;
    }

    // ─── GridDataProviderV1 Capabilities ─────────────────────────────

    global appcg.GridDataProviderTypesV1.Capabilities getCapabilities(appcg.GridDataProviderTypesV1.ProviderContext context) {
        OutlookConfig cfg = parseConfig(context);
        appcg.GridDataProviderTypesV1.Capabilities capabilities = new appcg.GridDataProviderTypesV1.Capabilities();
        capabilities.supportedFeatures = new Set<String>{ 'SEARCH', 'REFRESH' };
        capabilities.supportedRowActions = new Set<String>();
        capabilities.supportsServerPagination = true;
        capabilities.maxPageSize = MAX_PAGE_SIZE;
        capabilities.columns = buildColumnDefinitions(cfg.resource);
        return capabilities;
    }

    // ─── GridDataProviderV1 Data Retrieval ───────────────────────────

    global appcg.GridDataProviderTypesV1.PageResult getData(appcg.GridDataProviderTypesV1.QueryRequest request) {
        appcg.GridDataProviderTypesV1.PageResult result = new appcg.GridDataProviderTypesV1.PageResult();
        result.records = new List<Map<String, Object>>();
        result.totalCount = 0;

        appcg__Grid_Definition__c gridDef = getGridDefinition(request?.context);
        OutlookConfig cfg = parseConfig(request?.context);

        String paginationType = gridDef?.appcg__Pagination_Type__c;
        Integer recordLimit = (gridDef?.appcg__Record_Limit__c != null && gridDef.appcg__Record_Limit__c > 0)
            ? (Integer) gridDef.appcg__Record_Limit__c
            : 500;

        Integer pageSize;
        Integer requestedPageSize = (request.pageSize != null && request.pageSize > 0)
            ? request.pageSize
            : (gridDef?.appcg__Page_Size__c != null ? Integer.valueOf(gridDef.appcg__Page_Size__c) : DEFAULT_PAGE_SIZE);

        if (paginationType == 'Client-Side') {
            pageSize = Math.min(recordLimit, MAX_PAGE_SIZE);
        } else {
            pageSize = Math.min(requestedPageSize, MAX_PAGE_SIZE);
        }

        Integer skip = (request.startIndex != null && request.startIndex >= 0) ? request.startIndex : 0;
        String filterExpression = buildFilterExpression(request, cfg);

        IntegrationLogger.deferInserts = true;
        try {
            OutlookClient client = new OutlookClient();
            if ('events'.equals(cfg.resource)) {
                Map<String, Object> response = client.listEvents(pageSize, skip, filterExpression);
                List<Object> items = (List<Object>) response.get('value');
                if (items != null) {
                    for (Object item : items) {
                        result.records.add(parseEventRow((Map<String, Object>) item));
                    }
                }
                result.totalCount = computeTotalCount(response, result.records.size(), skip, paginationType, recordLimit);
            } else {
                Map<String, Object> response = client.listMessages(pageSize, skip, filterExpression, request.searchTerm);
                List<Object> items = (List<Object>) response.get('value');
                if (items != null) {
                    for (Object item : items) {
                        result.records.add(parseMessageRow((Map<String, Object>) item));
                    }
                }
                result.totalCount = computeTotalCount(response, result.records.size(), skip, paginationType, recordLimit);
            }
        } finally {
            IntegrationLogger.deferInserts = false;
            IntegrationLogger.commitLogs();
        }

        return result;
    }

    // ─── Filter & Search Builder ──────────────────────────────────────

    @TestVisible
    private static String buildFilterExpression(appcg.GridDataProviderTypesV1.QueryRequest request, OutlookConfig cfg) {
        List<String> filterClauses = new List<String>();

        // 1. Parent record filter (e.g. on Contact / Lead / Account)
        if (request?.context?.parentId != null) {
            String parentValue = resolveParentFieldValue(request.context, cfg.parentMatchField);
            if (String.isNotBlank(parentValue)) {
                String escaped = parentValue.replace('\'', '\'\'');
                filterClauses.add('(from/emailAddress/address eq \'' + escaped + '\' or toRecipients/any(r: r/emailAddress/address eq \'' + escaped + '\'))');
            }
        }

        // 2. Base filter from config
        if (String.isNotBlank(cfg.filter)) {
            filterClauses.add('(' + cfg.filter.trim() + ')');
        }

        // 3. Admin filter rules
        if (request?.adminFilter?.rules != null) {
            for (appcg.GridDataProviderTypesV1.FilterRule rule : request.adminFilter.rules) {
                if (String.isNotBlank(rule.field) && String.isNotBlank(rule.value)) {
                    filterClauses.add('(' + rule.field + ' eq \'' + rule.value.replace('\'', '\'\'') + '\')');
                }
            }
        }

        // 4. User filter rules
        if (request?.userFilter?.rules != null) {
            for (appcg.GridDataProviderTypesV1.FilterRule rule : request.userFilter.rules) {
                if (String.isNotBlank(rule.field) && String.isNotBlank(rule.value)) {
                    filterClauses.add('(' + rule.field + ' eq \'' + rule.value.replace('\'', '\'\'') + '\')');
                }
            }
        }

        return filterClauses.isEmpty() ? null : String.join(filterClauses, ' and ');
    }

    @TestVisible
    private static String resolveParentFieldValue(appcg.GridDataProviderTypesV1.ProviderContext context, String fieldName) {
        if (context == null || context.parentId == null) {
            return null;
        }
        String requestedField = String.isBlank(fieldName) ? 'Email' : fieldName.trim();
        try {
            Id parentId = (Id) context.parentId;
            Schema.DescribeSObjectResult describe = parentId.getSObjectType().getDescribe();
            Map<String, Schema.SObjectField> fields = describe.fields.getMap();
            String fieldApiName;
            for (String candidate : fields.keySet()) {
                if (candidate.equalsIgnoreCase(requestedField)) {
                    fieldApiName = candidate;
                    break;
                }
            }
            if (fieldApiName == null) {
                return null;
            }
            String soql = 'SELECT ' + fieldApiName + ' FROM ' + describe.getName() + ' WHERE Id = :parentId WITH USER_MODE LIMIT 1';
            List<SObject> parents = Database.query(soql);
            if (parents.isEmpty()) {
                return null;
            }
            Object val = parents[0].get(fieldApiName);
            return val == null ? null : String.valueOf(val);
        } catch (Exception e) {
            return null;
        }
    }

    private static Integer computeTotalCount(
        Map<String, Object> response, Integer returnedCount, Integer skip, String paginationType, Integer recordLimit
    ) {
        if (paginationType == 'Client-Side') {
            return returnedCount;
        }
        if (response.containsKey('@odata.count') && response.get('@odata.count') != null) {
            Integer c = Integer.valueOf(response.get('@odata.count'));
            return (recordLimit > 0) ? Math.min(c, recordLimit) : c;
        }
        // If nextLink exists, there is at least one more page of results
        Integer total = skip + returnedCount;
        if (response.containsKey('@odata.nextLink') && response.get('@odata.nextLink') != null) {
            total += 1;
        }
        return (recordLimit > 0) ? Math.min(total, recordLimit) : total;
    }

    // ─── Column Definitions ───────────────────────────────────────────

    @TestVisible
    private static List<appcg.GridDataProviderTypesV1.ColumnDefinition> buildColumnDefinitions(String resource) {
        List<appcg.GridDataProviderTypesV1.ColumnDefinition> columns = new List<appcg.GridDataProviderTypesV1.ColumnDefinition>();
        columns.add(column('Id', 'ID', 'TEXT', true, false, '100px'));

        if ('events'.equals(resource)) {
            columns.add(column('Subject', 'Subject', 'TEXT', true, true, '280px'));
            columns.add(column('Start', 'Start', 'TEXT', true, true, '180px'));
            columns.add(column('End', 'End', 'TEXT', true, true, '180px'));
            columns.add(column('Organizer', 'Organizer', 'TEXT', true, true, '200px'));
            columns.add(column('Location', 'Location', 'TEXT', true, true, '180px'));
            columns.add(column('IsAllDay', 'All Day', 'BOOLEAN', true, true, '80px'));
            columns.add(column('WebLink', 'Outlook Link', 'URL', true, true, '120px'));
        } else {
            columns.add(column('From', 'From', 'TEXT', true, true, '220px'));
            columns.add(column('To', 'To', 'TEXT', true, true, '220px'));
            columns.add(column('Subject', 'Subject', 'TEXT', true, true, '280px'));
            columns.add(column('Date', 'Date', 'TEXT', true, true, '180px'));
            columns.add(column('Snippet', 'Preview', 'TEXT', true, true, '320px'));
            columns.add(column('IsRead', 'Read', 'BOOLEAN', true, true, '80px'));
            columns.add(column('HasAttachments', 'Attachments', 'BOOLEAN', true, true, '100px'));
            columns.add(column('WebLink', 'Outlook Link', 'URL', true, true, '120px'));
        }
        return columns;
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

    // ─── Row Parsers ──────────────────────────────────────────────────

    @TestVisible
    private static Map<String, Object> parseMessageRow(Map<String, Object> raw) {
        Map<String, Object> row = new Map<String, Object>();
        row.put('Id', raw.get('id'));
        row.put('Subject', raw.get('subject') != null ? raw.get('subject') : '(No Subject)');
        row.put('Snippet', raw.get('bodyPreview'));
        row.put('IsRead', raw.get('isRead') == true);
        row.put('HasAttachments', raw.get('hasAttachments') == true);
        row.put('WebLink', raw.get('webLink'));
        row.put('Date', formatIsoDateTime((String) raw.get('receivedDateTime')));

        // Extract From
        Map<String, Object> fromObj = (Map<String, Object>) raw.get('from');
        if (fromObj != null) {
            Map<String, Object> emailObj = (Map<String, Object>) fromObj.get('emailAddress');
            if (emailObj != null) {
                String name = (String) emailObj.get('name');
                String addr = (String) emailObj.get('address');
                if (String.isNotBlank(name) && String.isNotBlank(addr) && !name.equalsIgnoreCase(addr)) {
                    row.put('From', name + ' <' + addr + '>');
                } else {
                    row.put('From', String.isNotBlank(addr) ? addr : (String.isNotBlank(name) ? name : ''));
                }
            }
        }
        if (!row.containsKey('From')) {
            row.put('From', '');
        }

        // Extract To recipients
        List<Object> toList = (List<Object>) raw.get('toRecipients');
        List<String> toAddrs = new List<String>();
        if (toList != null) {
            for (Object o : toList) {
                Map<String, Object> r = (Map<String, Object>) o;
                Map<String, Object> ea = (Map<String, Object>) r.get('emailAddress');
                if (ea != null && ea.containsKey('address')) {
                    toAddrs.add((String) ea.get('address'));
                }
            }
        }
        row.put('To', String.join(toAddrs, ', '));

        return row;
    }

    @TestVisible
    private static Map<String, Object> parseEventRow(Map<String, Object> raw) {
        Map<String, Object> row = new Map<String, Object>();
        row.put('Id', raw.get('id'));
        row.put('Subject', raw.get('subject') != null ? raw.get('subject') : '(No Subject)');
        row.put('IsAllDay', raw.get('isAllDay') == true);
        row.put('WebLink', raw.get('webLink'));

        // Start and End
        Map<String, Object> startObj = (Map<String, Object>) raw.get('start');
        if (startObj != null && startObj.get('dateTime') != null) {
            row.put('Start', formatIsoDateTime((String) startObj.get('dateTime')));
        } else {
            row.put('Start', '');
        }

        Map<String, Object> endObj = (Map<String, Object>) raw.get('end');
        if (endObj != null && endObj.get('dateTime') != null) {
            row.put('End', formatIsoDateTime((String) endObj.get('dateTime')));
        } else {
            row.put('End', '');
        }

        // Organizer
        Map<String, Object> orgObj = (Map<String, Object>) raw.get('organizer');
        if (orgObj != null) {
            Map<String, Object> emailObj = (Map<String, Object>) orgObj.get('emailAddress');
            if (emailObj != null) {
                String name = (String) emailObj.get('name');
                String addr = (String) emailObj.get('address');
                row.put('Organizer', String.isNotBlank(name) ? name : (String.isNotBlank(addr) ? addr : ''));
            }
        }
        if (!row.containsKey('Organizer')) {
            row.put('Organizer', '');
        }

        // Location
        Map<String, Object> locObj = (Map<String, Object>) raw.get('location');
        row.put('Location', locObj != null && locObj.get('displayName') != null ? (String) locObj.get('displayName') : '');

        return row;
    }

    @TestVisible
    private static String formatIsoDateTime(String isoStr) {
        if (String.isBlank(isoStr)) {
            return '';
        }
        try {
            // Trim sub-second precision to standard ISO milliseconds if present
            String clean = isoStr;
            Integer dotIdx = clean.indexOf('.');
            if (dotIdx > 0) {
                Integer zIdx = clean.indexOf('Z', dotIdx);
                if (zIdx > 0) {
                    clean = clean.substring(0, Math.min(dotIdx + 4, zIdx)) + 'Z';
                } else {
                    clean = clean.substring(0, Math.min(dotIdx + 4, clean.length()));
                }
            }
            DateTime dt = (DateTime) JSON.deserialize('"' + clean + '"', DateTime.class);
            return dt.format('MMM d, yyyy h:mm a');
        } catch (Exception e) {
            return isoStr;
        }
    }
}
