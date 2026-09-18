global with sharing class GoogleAnalyticsGridDataProvider
    implements appcg.GridDataProviderV1 {

    public class ProviderException extends Exception {}


    // ─── Instance Cache ───────────────────────────────────────────────
    private List<Map<String, Object>> cachedRecords;

    // ─── Config ───────────────────────────────────────────────────────

    @TestVisible
    private class AnalyticsConfig {
        public String propertyId;
        public String reportType;
        public String dateRange;
        public String userId;
        public Integer recordLimit;
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
    private static AnalyticsConfig parseConfig(appcg.GridDataProviderTypesV1.ProviderContext context) {
        appcg__Grid_Definition__c gridDef = getGridDefinition(context);
        String configJson = gridDef != null ? gridDef.appcg__Data_Provider_Config__c : null;
        if (String.isBlank(configJson)) {
            throw new ProviderException(
                'Google Analytics provider requires configuration. ' +
                'Set Data Provider Configuration with {"propertyId":"446193663","reportType":"top_pages"}'
            );
        }
        AnalyticsConfig cfg = new AnalyticsConfig();
        cfg.recordLimit = (gridDef?.appcg__Record_Limit__c != null && gridDef.appcg__Record_Limit__c > 0)
            ? (Integer) gridDef.appcg__Record_Limit__c
            : 100;
        try {
            Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(configJson);
            if (raw.containsKey('propertyId')) {
                cfg.propertyId = String.valueOf(raw.get('propertyId')).trim();
            }
            if (raw.containsKey('reportType')) {
                cfg.reportType = String.valueOf(raw.get('reportType')).trim().toLowerCase();
            }
            if (raw.containsKey('dateRange')) {
                cfg.dateRange = String.valueOf(raw.get('dateRange')).trim().toLowerCase();
            }
            if (raw.containsKey('userId')) {
                cfg.userId = String.valueOf(raw.get('userId')).trim();
            }
            if (raw.containsKey('limit')) {
                Object lim = raw.get('limit');
                if (lim instanceof Integer) {
                    cfg.recordLimit = (Integer) lim;
                } else if (lim instanceof Decimal) {
                    cfg.recordLimit = ((Decimal) lim).intValue();
                } else if (lim instanceof String) {
                    cfg.recordLimit = Integer.valueOf(lim);
                }
            } else if (raw.containsKey('recordLimit')) {
                cfg.recordLimit = Integer.valueOf(raw.get('recordLimit'));
            }
        } catch (Exception e) {
            throw new ProviderException('Invalid Google Analytics provider configuration: ' + e.getMessage());
        }

        if (String.isBlank(cfg.propertyId)) {
            throw new ProviderException('propertyId is required in configuration (e.g. "446193663").');
        }
        if (String.isBlank(cfg.reportType)) {
            cfg.reportType = 'top_pages'; // default report
        }
        if (String.isBlank(cfg.dateRange)) {
            cfg.dateRange = 'last_30_days'; // default date range
        }
        if (cfg.recordLimit == null || cfg.recordLimit <= 0) {
            cfg.recordLimit = 100;
        } else if (cfg.recordLimit > 1000) {
            cfg.recordLimit = 1000;
        }

        // If parentId is passed in context (e.g. on a Contact page), use it as target userId
        if (context != null && String.isNotBlank(context.parentId) && String.isBlank(cfg.userId)) {
            cfg.userId = context.parentId;
        }

        return cfg;
    }

    // ─── GridDataProviderV1 ───────────────────────────────────────────

    global appcg.GridDataProviderTypesV1.Capabilities getCapabilities(
        appcg.GridDataProviderTypesV1.ProviderContext context
    ) {
        AnalyticsConfig cfg = parseConfig(context);
        try {
            GoogleAnalyticsClient client = new GoogleAnalyticsClient();
            Map<String, Object> requestBody = buildReportRequest(cfg);
            Map<String, Object> response = client.runReport(cfg.propertyId, requestBody);

            cachedRecords = parseReportRows(cfg.reportType, response);

            appcg.GridDataProviderTypesV1.Capabilities capabilities = new appcg.GridDataProviderTypesV1.Capabilities();
            capabilities.supportedFeatures = new Set<String>{
                'SEARCH', 'REFRESH', 'DOWNLOAD_CSV'
            };
            capabilities.supportedRowActions = new Set<String>();
            capabilities.supportsServerPagination = false;
            capabilities.columns = buildColumnDefinitions(cfg.reportType);
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
                records = cachedRecords;
                cachedRecords = null;
            } else {
                AnalyticsConfig cfg = parseConfig(request.context);
                GoogleAnalyticsClient client = new GoogleAnalyticsClient();
                Map<String, Object> requestBody = buildReportRequest(cfg);
                Map<String, Object> response = client.runReport(cfg.propertyId, requestBody);
                records = parseReportRows(cfg.reportType, response);
            }

            while (records != null && records.size() > pageSize) {
                records.remove(records.size() - 1);
            }

            // Apply search filter
            if (String.isNotBlank(request.searchTerm)) {
                records = filterBySearch(records, request.searchTerm);
            }

            if (gridDef?.appcg__Record_Limit__c != null && gridDef.appcg__Record_Limit__c > 0 && records != null) {
                records = records;
            }

            appcg.GridDataProviderTypesV1.PageResult result = new appcg.GridDataProviderTypesV1.PageResult();
            result.records = records;
            result.totalCount = (gridDef?.appcg__Record_Limit__c != null && gridDef.appcg__Record_Limit__c > 0)
                ? Math.min(records.size(), (Integer) gridDef.appcg__Record_Limit__c)
                : records.size();
            return result;
        } finally {
        }
    }

    // ─── Report Request Builder ───────────────────────────────────────

    @TestVisible
    private static Map<String, Object> buildReportRequest(AnalyticsConfig cfg) {
        Map<String, Object> req = new Map<String, Object>();

        List<Map<String, String>> dimensions = new List<Map<String, String>>();
        List<Map<String, String>> metrics = new List<Map<String, String>>();

        if ('geo'.equals(cfg.reportType)) {
            dimensions.add(new Map<String, String>{ 'name' => 'country' });
            dimensions.add(new Map<String, String>{ 'name' => 'city' });
            metrics.add(new Map<String, String>{ 'name' => 'activeUsers' });
            metrics.add(new Map<String, String>{ 'name' => 'newUsers' });
            metrics.add(new Map<String, String>{ 'name' => 'sessions' });
        } else if ('traffic_sources'.equals(cfg.reportType)) {
            dimensions.add(new Map<String, String>{ 'name' => 'sessionDefaultChannelGroup' });
            dimensions.add(new Map<String, String>{ 'name' => 'sessionSourceMedium' });
            metrics.add(new Map<String, String>{ 'name' => 'sessions' });
            metrics.add(new Map<String, String>{ 'name' => 'activeUsers' });
            metrics.add(new Map<String, String>{ 'name' => 'engagedSessions' });
        } else if ('user_activity'.equals(cfg.reportType) || 'events'.equals(cfg.reportType) || 'timeline'.equals(cfg.reportType)) {
            dimensions.add(new Map<String, String>{ 'name' => 'dateHourMinute' });
            dimensions.add(new Map<String, String>{ 'name' => 'pageTitle' });
            dimensions.add(new Map<String, String>{ 'name' => 'eventName' });
            dimensions.add(new Map<String, String>{ 'name' => 'country' });
            metrics.add(new Map<String, String>{ 'name' => 'eventCount' });
        } else {
            // Default: 'top_pages'
            dimensions.add(new Map<String, String>{ 'name' => 'pageTitle' });
            dimensions.add(new Map<String, String>{ 'name' => 'pagePath' });
            metrics.add(new Map<String, String>{ 'name' => 'screenPageViews' });
            metrics.add(new Map<String, String>{ 'name' => 'activeUsers' });
            metrics.add(new Map<String, String>{ 'name' => 'userEngagementDuration' });
        }

        req.put('dimensions', dimensions);
        req.put('metrics', metrics);

        // Date range
        Map<String, String> dr = resolveDateRange(cfg.dateRange);
        req.put('dateRanges', new List<Object>{ dr });
        req.put('limit', cfg.recordLimit);

        return req;
    }

    @TestVisible
    private static Map<String, String> resolveDateRange(String rangeKey) {
        String startVal = '30daysAgo';
        String endVal = 'today';

        if ('last_7_days'.equals(rangeKey) || '7days'.equals(rangeKey)) {
            startVal = '7daysAgo';
        } else if ('last_28_days'.equals(rangeKey) || '28days'.equals(rangeKey)) {
            startVal = '28daysAgo';
        } else if ('last_90_days'.equals(rangeKey) || '90days'.equals(rangeKey)) {
            startVal = '90daysAgo';
        } else if ('today'.equals(rangeKey)) {
            startVal = 'today';
        } else if ('yesterday'.equals(rangeKey)) {
            startVal = 'yesterday';
            endVal = 'yesterday';
        }

        return new Map<String, String>{
            'startDate' => startVal,
            'endDate' => endVal
        };
    }

    // ─── Response Parser ──────────────────────────────────────────────

    @TestVisible
    private static List<Map<String, Object>> parseReportRows(
        String reportType,
        Map<String, Object> response
    ) {
        List<Map<String, Object>> records = new List<Map<String, Object>>();
        if (response == null || !response.containsKey('rows')) {
            return records;
        }

        List<Object> rows = (List<Object>) response.get('rows');
        if (rows == null) return records;

        Integer rowIndex = 1;
        for (Object rObj : rows) {
            Map<String, Object> rMap = (Map<String, Object>) rObj;
            Map<String, Object> row = new Map<String, Object>();
            row.put('Id', 'ga_' + rowIndex++);

            List<Object> dVals = (List<Object>) rMap.get('dimensionValues');
            List<Object> mVals = (List<Object>) rMap.get('metricValues');

            if ('geo'.equals(reportType)) {
                row.put('country', extractVal(dVals, 0, '(not set)'));
                row.put('city', extractVal(dVals, 1, '(not set)'));
                row.put('activeUsers', extractNum(mVals, 0));
                row.put('newUsers', extractNum(mVals, 1));
                row.put('sessions', extractNum(mVals, 2));
            } else if ('traffic_sources'.equals(reportType)) {
                row.put('sessionDefaultChannelGroup', extractVal(dVals, 0, '(Direct)'));
                row.put('sessionSourceMedium', extractVal(dVals, 1, '(direct) / (none)'));
                row.put('sessions', extractNum(mVals, 0));
                row.put('activeUsers', extractNum(mVals, 1));
                row.put('engagedSessions', extractNum(mVals, 2));
            } else if ('user_activity'.equals(reportType) || 'events'.equals(reportType) || 'timeline'.equals(reportType)) {
                row.put('dateHourMinute', formatGaDateTime(extractVal(dVals, 0, '')));
                row.put('pageTitle', extractVal(dVals, 1, ''));
                row.put('eventName', extractVal(dVals, 2, 'page_view'));
                row.put('country', extractVal(dVals, 3, '(not set)'));
                row.put('eventCount', extractNum(mVals, 0));
            } else {
                // Default: top_pages
                row.put('pageTitle', extractVal(dVals, 0, ''));
                row.put('pagePath', extractVal(dVals, 1, '/'));
                row.put('screenPageViews', extractNum(mVals, 0));
                row.put('activeUsers', extractNum(mVals, 1));
                row.put('userEngagementDuration', extractNum(mVals, 2));
            }
            records.add(row);
        }
        return records;
    }

    private static String extractVal(List<Object> vals, Integer index, String defVal) {
        if (vals != null && vals.size() > index) {
            Map<String, Object> item = (Map<String, Object>) vals[index];
            if (item != null && item.containsKey('value')) {
                String v = String.valueOf(item.get('value'));
                return String.isNotBlank(v) ? v : defVal;
            }
        }
        return defVal;
    }

    private static Decimal extractNum(List<Object> vals, Integer index) {
        if (vals != null && vals.size() > index) {
            Map<String, Object> item = (Map<String, Object>) vals[index];
            if (item != null && item.containsKey('value')) {
                try {
                    return Decimal.valueOf(String.valueOf(item.get('value')));
                } catch (Exception e) {
                    return 0;
                }
            }
        }
        return 0;
    }

    @TestVisible
    private static String formatGaDateTime(String raw) {
        // YYYYMMDDHHmm e.g. "202608241730" -> "2026-08-24 17:30"
        if (String.isNotBlank(raw) && raw.length() >= 12) {
            return raw.substring(0, 4) + '-' + raw.substring(4, 6) + '-' + raw.substring(6, 8) + ' ' +
                   raw.substring(8, 10) + ':' + raw.substring(10, 12);
        }
        return raw;
    }

    // ─── Column Definitions ───────────────────────────────────────────

    private static List<appcg.GridDataProviderTypesV1.ColumnDefinition> buildColumnDefinitions(String reportType) {
        List<appcg.GridDataProviderTypesV1.ColumnDefinition> columns =
            new List<appcg.GridDataProviderTypesV1.ColumnDefinition>();

        // Hidden Id column
        columns.add(column('Id', 'ID', 'TEXT', true, false, '100px'));

        if ('geo'.equals(reportType)) {
            columns.add(column('country', 'Country', 'TEXT', true, true, '160px'));
            columns.add(column('city', 'City', 'TEXT', true, true, '160px'));
            columns.add(column('activeUsers', 'Active Users', 'NUMBER', true, true, '120px'));
            columns.add(column('newUsers', 'New Users', 'NUMBER', true, true, '120px'));
            columns.add(column('sessions', 'Sessions', 'NUMBER', true, true, '120px'));
        } else if ('traffic_sources'.equals(reportType)) {
            columns.add(column('sessionDefaultChannelGroup', 'Channel Group', 'TEXT', true, true, '180px'));
            columns.add(column('sessionSourceMedium', 'Source / Medium', 'TEXT', true, true, '220px'));
            columns.add(column('sessions', 'Sessions', 'NUMBER', true, true, '120px'));
            columns.add(column('activeUsers', 'Active Users', 'NUMBER', true, true, '120px'));
            columns.add(column('engagedSessions', 'Engaged Sessions', 'NUMBER', true, true, '140px'));
        } else if ('user_activity'.equals(reportType) || 'events'.equals(reportType) || 'timeline'.equals(reportType)) {
            columns.add(column('dateHourMinute', 'Date & Time', 'DATETIME', true, true, '170px'));
            columns.add(column('pageTitle', 'Page Visited', 'TEXT', true, true, null));
            columns.add(column('eventName', 'Event / Action', 'TEXT', true, true, '140px'));
            columns.add(column('country', 'Location', 'TEXT', true, true, '150px'));
            columns.add(column('eventCount', 'Events', 'NUMBER', true, true, '100px'));
        } else {
            // Default: 'top_pages'
            columns.add(column('pageTitle', 'Title', 'TEXT', true, true, null));
            columns.add(column('pagePath', 'Page Path', 'TEXT', true, true, '200px'));
            columns.add(column('screenPageViews', 'Views', 'NUMBER', true, true, '110px'));
            columns.add(column('activeUsers', 'Active Users', 'NUMBER', true, true, '120px'));
            columns.add(column('userEngagementDuration', 'Engagement Time (s)', 'NUMBER', true, true, '160px'));
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
                if ('Id'.equalsIgnoreCase(key)) continue;
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
