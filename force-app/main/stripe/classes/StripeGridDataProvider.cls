global with sharing class StripeGridDataProvider
    implements appcg.GridDataProviderV1, appcg.GridDataMutationProviderV1 {

    public class ProviderException extends Exception {}


    // ─── Instance Cache ───────────────────────────────────────────────
    private List<Map<String, Object>> cachedRecords;

    // ─── Config ───────────────────────────────────────────────────────

    @TestVisible
    private class StripeConfig {
        public String resource;
        public String parentMatchColumn;
        public String parentMatchField;
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
    private static StripeConfig parseConfig(appcg.GridDataProviderTypesV1.ProviderContext context) {
        StripeConfig cfg = new StripeConfig();
        cfg.resource = 'customers'; // default

        appcg__Grid_Definition__c gridDef = getGridDefinition(context);
        String configJson = gridDef != null ? gridDef.appcg__Data_Provider_Config__c : null;

        if (String.isNotBlank(configJson)) {
            try {
                StripeConfig parsed = (StripeConfig) JSON.deserialize(
                    configJson,
                    StripeConfig.class
                );
                if (parsed != null && String.isNotBlank(parsed.resource)) {
                    cfg.resource = parsed.resource.trim().toLowerCase();
                }
                if (parsed != null) {
                    cfg.parentMatchColumn = parsed.parentMatchColumn?.trim();
                    cfg.parentMatchField = parsed.parentMatchField?.trim();
                }
            } catch (Exception e) {
                throw new ProviderException('Invalid Stripe provider configuration: ' + e.getMessage());
            }
        }
        if (String.isNotBlank(cfg.parentMatchColumn) && String.isBlank(cfg.parentMatchField)) {
            cfg.parentMatchField = 'Id';
        }
        return cfg;
    }

    // ─── GridDataProviderV1 ───────────────────────────────────────────

    global appcg.GridDataProviderTypesV1.Capabilities getCapabilities(
        appcg.GridDataProviderTypesV1.ProviderContext context
    ) {
        StripeConfig cfg = parseConfig(context);
        try {
            cachedRecords = null;
            if (String.isBlank(cfg.parentMatchColumn) || context == null || String.isBlank(context.parentId)) {
                StripeClient client = new StripeClient();
                Map<String, Object> response = client.listResources(cfg.resource, 100, null);
                cachedRecords = parseStripeRecords(cfg.resource, (List<Object>) response.get('data'));
            } else {
                validateParentMatchColumn(cfg);
            }

            appcg.GridDataProviderTypesV1.Capabilities capabilities = new appcg.GridDataProviderTypesV1.Capabilities();
            if ('customers'.equals(cfg.resource)) {
                capabilities.supportedFeatures = new Set<String>{
                    'SEARCH', 'REFRESH', 'ADD', 'EDIT', 'DELETE', 'DOWNLOAD_CSV'
                };
                capabilities.supportedRowActions = new Set<String>{ 'DELETE' };
            } else if ('subscriptions'.equals(cfg.resource)) {
                capabilities.supportedFeatures = new Set<String>{
                    'SEARCH', 'REFRESH', 'DELETE', 'DOWNLOAD_CSV'
                };
                capabilities.supportedRowActions = new Set<String>{ 'DELETE' };
            } else {
                capabilities.supportedFeatures = new Set<String>{
                    'SEARCH', 'REFRESH', 'DOWNLOAD_CSV'
                };
                capabilities.supportedRowActions = new Set<String>();
            }

            capabilities.supportsServerPagination = true;
            capabilities.maxPageSize = 100;
            capabilities.columns = buildColumnDefinitions(cfg.resource);
            return capabilities;
        } finally {
        }
    }

    global appcg.GridDataProviderTypesV1.PageResult getData(
        appcg.GridDataProviderTypesV1.QueryRequest request
    ) {
        try {
            StripeConfig cfg = parseConfig(request?.context);
            if (String.isNotBlank(cfg.parentMatchColumn) && request?.context != null &&
                String.isNotBlank(request.context.parentId)) {
                cachedRecords = null;
                return getParentFilteredData(request, cfg);
            }
            List<Map<String, Object>> records;
            Integer totalCount;

            appcg__Grid_Definition__c gridDef = getGridDefinition(request?.context);
            String paginationType = gridDef?.appcg__Pagination_Type__c;
            Integer recordLimit = (gridDef?.appcg__Record_Limit__c != null && gridDef.appcg__Record_Limit__c > 0)
                ? (Integer) gridDef.appcg__Record_Limit__c
                : 100;

            Integer startIndex = request.startIndex != null ? Math.max(0, request.startIndex) : 0;
            Integer pageSize;
            Integer requestedPageSize = (request.pageSize != null && request.pageSize > 0)
                ? request.pageSize
                : (gridDef?.appcg__Page_Size__c != null ? Integer.valueOf(gridDef.appcg__Page_Size__c) : 20);
            if (paginationType == 'Client-Side') {
                pageSize = Math.min(recordLimit, 100);
            } else {
                pageSize = (gridDef?.appcg__Record_Limit__c != null && gridDef.appcg__Record_Limit__c > 0)
                    ? Math.min(requestedPageSize, (Integer) gridDef.appcg__Record_Limit__c)
                    : Math.min(requestedPageSize, 100);
            }

            if (cachedRecords != null && startIndex == 0) {
                records = cachedRecords;
                cachedRecords = null;
                totalCount = records.size();
            } else {
                StripeClient client = new StripeClient();

                // Fetch requested page chunk
                Integer fetchLimit = Math.min(startIndex + pageSize, 100);
                Map<String, Object> response = client.listResources(cfg.resource, fetchLimit, null);
                List<Object> rawList = (List<Object>) response.get('data');
                Boolean hasMore = Boolean.valueOf(response.get('has_more'));
                List<Map<String, Object>> allParsed = parseStripeRecords(cfg.resource, rawList);

                if (startIndex < allParsed.size()) {
                    records = new List<Map<String, Object>>();
                    Integer endIndex = Math.min(allParsed.size(), startIndex + pageSize);
                    for (Integer i = startIndex; i < endIndex; i++) {
                        records.add(allParsed[i]);
                    }
                } else {
                    records = new List<Map<String, Object>>();
                }

                if (hasMore == true) {
                    totalCount = startIndex + records.size() + 1;
                } else {
                    totalCount = allParsed.size();
                }
            }

            while (records != null && records.size() > pageSize) {
                records.remove(records.size() - 1);
            }

            if (gridDef?.appcg__Record_Limit__c != null && gridDef.appcg__Record_Limit__c > 0 && totalCount != null) {
                totalCount = Math.min(totalCount, (Integer) gridDef.appcg__Record_Limit__c);
            }

            // Apply search filter
            if (String.isNotBlank(request.searchTerm)) {
                records = filterBySearch(records, request.searchTerm);
                totalCount = records.size();
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
        StripeConfig cfg = parseConfig(request.context);
        if (!'customers'.equals(cfg.resource)) {
            throw new ProviderException('Inline editing is only supported for the customers resource.');
        }
        try {
            StripeClient client = new StripeClient();
            List<Map<String, Object>> savedRecords = new List<Map<String, Object>>();

            for (Map<String, Object> record : request.records) {
                Object rawId = record.get('Id');
                String recordId = rawId == null ? null : String.valueOf(rawId);
                Map<String, Object> payload = cleanCustomerFields(record);

                if (String.isBlank(recordId) || recordId.startsWith('TEMP_')) {
                    // Create new customer
                    Map<String, Object> created = client.createResource('customers', payload);
                    record.put('Id', String.valueOf(created.get('id')));
                    if (created.containsKey('created')) {
                        record.put('created', formatTimestamp(created.get('created')));
                    }
                } else {
                    // Update existing customer
                    client.updateResource('customers', recordId, payload);
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
        StripeConfig cfg = parseConfig(request.context);
        try {
            StripeClient client = new StripeClient();
            for (String recId : request.recordIds) {
                client.deleteResource(cfg.resource, recId);
            }
        } finally {
        }
    }

    // ─── Helpers ──────────────────────────────────────────────────────

    private static appcg.GridDataProviderTypesV1.PageResult getParentFilteredData(
        appcg.GridDataProviderTypesV1.QueryRequest request,
        StripeConfig cfg
    ) {
        String matchColumn = validateParentMatchColumn(cfg);
        String parentValue = resolveParentMatchValue(cfg, request.context);
        appcg.GridDataProviderTypesV1.PageResult result = new appcg.GridDataProviderTypesV1.PageResult();
        result.records = new List<Map<String, Object>>();
        result.totalCount = 0;
        if (String.isBlank(parentValue)) {
            return result;
        }

        appcg__Grid_Definition__c gridDef = getGridDefinition(request.context);
        Integer recordLimit = (gridDef?.appcg__Record_Limit__c != null && gridDef.appcg__Record_Limit__c > 0)
            ? (Integer) gridDef.appcg__Record_Limit__c : 100;
        Boolean clientSide = gridDef?.appcg__Pagination_Type__c == 'Client-Side';
        Integer requestedPageSize = (request.pageSize != null && request.pageSize > 0)
            ? request.pageSize
            : (gridDef?.appcg__Page_Size__c != null ? Integer.valueOf(gridDef.appcg__Page_Size__c) : 20);
        Integer pageSize = clientSide ? Math.min(recordLimit, 100) : Math.min(requestedPageSize, 100);
        Integer startIndex = clientSide ? 0 : (request.startIndex == null ? 0 : Math.max(0, request.startIndex));
        String searchTerm = String.isBlank(request.searchTerm) ? null : request.searchTerm.toLowerCase();
        String customerId = matchColumn == 'customer' &&
            new Set<String>{ 'charges', 'invoices', 'subscriptions', 'payment_intents' }.contains(cfg.resource)
            ? parentValue.trim() : null;

        StripeClient client = new StripeClient();
        String startingAfter;
        Boolean hasMore = true;
        Integer matchedCount = 0;
        while (hasMore && matchedCount < recordLimit) {
            if (Limits.getCallouts() >= Limits.getLimitCallouts()) {
                throw new ProviderException('Stripe parent filter exceeded the available callouts. Narrow the Stripe data or use a customer ID match.');
            }
            Map<String, Object> response = client.listResources(cfg.resource, 100, startingAfter, customerId);
            List<Object> rawList = (List<Object>) response.get('data');
            if (rawList == null || rawList.isEmpty()) {
                break;
            }
            for (Map<String, Object> record : parseStripeRecords(cfg.resource, rawList)) {
                Object value = record.get(matchColumn);
                if (value == null || !parentValuesMatch(String.valueOf(value), parentValue, matchColumn)) {
                    continue;
                }
                if (searchTerm != null && filterBySearch(new List<Map<String, Object>>{ record }, searchTerm).isEmpty()) {
                    continue;
                }
                if (matchedCount >= startIndex && matchedCount < startIndex + pageSize) {
                    result.records.add(record);
                }
                matchedCount++;
                if (matchedCount >= recordLimit) {
                    break;
                }
            }
            hasMore = response.get('has_more') == true;
            Map<String, Object> lastRawRecord = (Map<String, Object>) rawList[rawList.size() - 1];
            startingAfter = lastRawRecord.get('id') == null ? null : String.valueOf(lastRawRecord.get('id'));
            if (hasMore && String.isBlank(startingAfter)) {
                throw new ProviderException('Stripe returned a page without a cursor for the parent filter.');
            }
        }
        result.totalCount = clientSide ? result.records.size() : matchedCount;
        return result;
    }

    private static String validateParentMatchColumn(StripeConfig cfg) {
        for (appcg.GridDataProviderTypesV1.ColumnDefinition column : buildColumnDefinitions(cfg.resource)) {
            if (column.id.equalsIgnoreCase(cfg.parentMatchColumn)) {
                return column.id;
            }
        }
        throw new ProviderException(
            'Parent match column "' + cfg.parentMatchColumn + '" is not available for Stripe ' + cfg.resource + '.'
        );
    }

    private static Boolean parentValuesMatch(String stripeValue, String parentValue, String column) {
        String left = stripeValue == null ? null : stripeValue.trim();
        String right = parentValue == null ? null : parentValue.trim();
        if (String.isBlank(left) || String.isBlank(right)) {
            return false;
        }
        return column == 'email' || column == 'customer_email' || column == 'receipt_email'
            ? left.equalsIgnoreCase(right) : left.equals(right);
    }

    @TestVisible
    private static String resolveParentMatchValue(
        StripeConfig cfg,
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
            String fieldApiName;
            for (String candidate : parentDescribe.fields.getMap().keySet()) {
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
            String query = 'SELECT ' + fieldApiName + ' FROM ' + parentDescribe.getName() +
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

    @TestVisible
    private static List<Map<String, Object>> parseStripeRecords(
        String resource,
        List<Object> rawList
    ) {
        List<Map<String, Object>> parsed = new List<Map<String, Object>>();
        if (rawList == null) return parsed;

        for (Object itemObj : rawList) {
            Map<String, Object> item = (Map<String, Object>) itemObj;
            Map<String, Object> row = new Map<String, Object>();
            row.put('Id', String.valueOf(item.get('id')));

            if ('customers'.equals(resource)) {
                row.put('name', item.get('name') == null ? '' : String.valueOf(item.get('name')));
                row.put('email', item.get('email') == null ? '' : String.valueOf(item.get('email')));
                row.put('phone', item.get('phone') == null ? '' : String.valueOf(item.get('phone')));
                row.put('description', item.get('description') == null ? '' : String.valueOf(item.get('description')));
                row.put('currency', item.get('currency') == null ? '' : String.valueOf(item.get('currency')).toUpperCase());
                row.put('balance', formatAmount(item.get('balance')));
                row.put('delinquent', item.get('delinquent') == true ? 'true' : 'false');
                row.put('created', formatTimestamp(item.get('created')));
            } else if ('invoices'.equals(resource)) {
                row.put('number', item.get('number') == null ? '' : String.valueOf(item.get('number')));
                row.put('customer', item.get('customer') == null ? '' : String.valueOf(item.get('customer')));
                row.put('customer_name', item.get('customer_name') == null ? '' : String.valueOf(item.get('customer_name')));
                row.put('customer_email', item.get('customer_email') == null ? '' : String.valueOf(item.get('customer_email')));
                row.put('status', item.get('status') == null ? '' : String.valueOf(item.get('status')));
                row.put('amount_due', formatAmount(item.get('amount_due')));
                row.put('amount_paid', formatAmount(item.get('amount_paid')));
                row.put('currency', item.get('currency') == null ? '' : String.valueOf(item.get('currency')).toUpperCase());
                row.put('due_date', formatTimestamp(item.get('due_date')));
                row.put('created', formatTimestamp(item.get('created')));
            } else if ('subscriptions'.equals(resource)) {
                row.put('customer', item.get('customer') == null ? '' : String.valueOf(item.get('customer')));
                row.put('status', item.get('status') == null ? '' : String.valueOf(item.get('status')));
                row.put('current_period_start', formatTimestamp(item.get('current_period_start')));
                row.put('current_period_end', formatTimestamp(item.get('current_period_end')));
                row.put('cancel_at_period_end', item.get('cancel_at_period_end') == true ? 'true' : 'false');
                row.put('created', formatTimestamp(item.get('created')));
            } else if ('charges'.equals(resource)) {
                row.put('amount', formatAmount(item.get('amount')));
                row.put('currency', item.get('currency') == null ? '' : String.valueOf(item.get('currency')).toUpperCase());
                row.put('status', item.get('status') == null ? '' : String.valueOf(item.get('status')));
                row.put('customer', item.get('customer') == null ? '' : String.valueOf(item.get('customer')));
                Map<String, Object> billingDetails = item.get('billing_details') instanceof Map<String, Object>
                    ? (Map<String, Object>) item.get('billing_details') : null;
                Object customerEmail = billingDetails?.get('email');
                if (customerEmail == null || String.isBlank(String.valueOf(customerEmail))) {
                    customerEmail = item.get('receipt_email');
                }
                row.put('customer_email', customerEmail == null ? '' : String.valueOf(customerEmail));
                row.put('description', item.get('description') == null ? '' : String.valueOf(item.get('description')));
                row.put('paid', item.get('paid') == true ? 'true' : 'false');
                row.put('refunded', item.get('refunded') == true ? 'true' : 'false');
                row.put('created', formatTimestamp(item.get('created')));
            } else if ('payment_intents'.equals(resource)) {
                row.put('amount', formatAmount(item.get('amount')));
                row.put('amount_received', formatAmount(item.get('amount_received')));
                row.put('currency', item.get('currency') == null ? '' : String.valueOf(item.get('currency')).toUpperCase());
                row.put('status', item.get('status') == null ? '' : String.valueOf(item.get('status')));
                row.put('customer', item.get('customer') == null ? '' : String.valueOf(item.get('customer')));
                row.put('receipt_email', item.get('receipt_email') == null ? '' : String.valueOf(item.get('receipt_email')));
                row.put('description', item.get('description') == null ? '' : String.valueOf(item.get('description')));
                row.put('created', formatTimestamp(item.get('created')));
            } else {
                // Generic fallback
                for (String key : item.keySet()) {
                    Object v = item.get(key);
                    if (v instanceof Map<String, Object> || v instanceof List<Object>) {
                        row.put(key, JSON.serialize(v));
                    } else {
                        row.put(key, v == null ? '' : String.valueOf(v));
                    }
                }
            }
            parsed.add(row);
        }
        return parsed;
    }

    private static Map<String, Object> cleanCustomerFields(Map<String, Object> record) {
        Map<String, Object> clean = new Map<String, Object>();
        Set<String> writableFields = new Set<String>{ 'name', 'email', 'phone', 'description' };
        for (String key : record.keySet()) {
            if (writableFields.contains(key.toLowerCase()) && record.get(key) != null) {
                clean.put(key.toLowerCase(), String.valueOf(record.get(key)));
            }
        }
        return clean;
    }

    @TestVisible
    private static String formatTimestamp(Object rawEpoch) {
        if (rawEpoch == null) return '';
        try {
            Long epochSec = Long.valueOf(String.valueOf(rawEpoch));
            if (epochSec <= 0) return '';
            Datetime dt = Datetime.newInstance(epochSec * 1000L);
            return dt.formatGmt('yyyy-MM-dd HH:mm:ss');
        } catch (Exception e) {
            return String.valueOf(rawEpoch);
        }
    }

    @TestVisible
    private static String formatAmount(Object rawCents) {
        if (rawCents == null) return '0.00';
        try {
            Decimal cents = Decimal.valueOf(String.valueOf(rawCents));
            return String.valueOf((cents / 100.0).setScale(2));
        } catch (Exception e) {
            return String.valueOf(rawCents);
        }
    }

    private static List<appcg.GridDataProviderTypesV1.ColumnDefinition> buildColumnDefinitions(String resource) {
        List<appcg.GridDataProviderTypesV1.ColumnDefinition> columns =
            new List<appcg.GridDataProviderTypesV1.ColumnDefinition>();

        // Hidden Id column (e.g. cus_XXX, in_XXX, sub_XXX, ch_XXX)
        columns.add(column('Id', 'ID', 'TEXT', true, false, '140px'));

        if ('customers'.equals(resource)) {
            columns.add(column('name', 'Name', 'TEXT', false, true, null));
            columns.add(column('email', 'Email', 'TEXT', false, true, null));
            columns.add(column('phone', 'Phone', 'TEXT', false, true, null));
            columns.add(column('description', 'Description', 'TEXT', false, true, null));
            columns.add(column('currency', 'Currency', 'TEXT', true, true, '90px'));
            columns.add(column('balance', 'Balance', 'NUMBER', true, true, '100px'));
            columns.add(column('delinquent', 'Delinquent', 'BOOLEAN', true, true, '90px'));
            columns.add(column('created', 'Created Date', 'DATETIME', true, true, '160px'));
        } else if ('invoices'.equals(resource)) {
            columns.add(column('number', 'Invoice Number', 'TEXT', true, true, '130px'));
            columns.add(column('customer', 'Customer', 'TEXT', true, false, '140px'));
            columns.add(column('customer_name', 'Name', 'TEXT', true, true, null));
            columns.add(column('customer_email', 'Email', 'TEXT', true, true, null));
            columns.add(column('status', 'Status', 'TEXT', true, true, '100px'));
            columns.add(column('amount_due', 'Amount Due', 'NUMBER', true, true, '100px'));
            columns.add(column('amount_paid', 'Amount Paid', 'NUMBER', true, true, '100px'));
            columns.add(column('currency', 'Currency', 'TEXT', true, true, '80px'));
            columns.add(column('due_date', 'Due Date', 'DATETIME', true, true, '160px'));
            columns.add(column('created', 'Created Date', 'DATETIME', true, true, '160px'));
        } else if ('subscriptions'.equals(resource)) {
            columns.add(column('customer', 'Customer', 'TEXT', true, true, '140px'));
            columns.add(column('status', 'Status', 'TEXT', true, true, '110px'));
            columns.add(column('current_period_start', 'Period Start', 'DATETIME', true, true, '160px'));
            columns.add(column('current_period_end', 'Period End', 'DATETIME', true, true, '160px'));
            columns.add(column('cancel_at_period_end', 'Cancel At End', 'BOOLEAN', true, true, '110px'));
            columns.add(column('created', 'Created Date', 'DATETIME', true, true, '160px'));
        } else if ('charges'.equals(resource)) {
            columns.add(column('amount', 'Amount', 'NUMBER', true, true, '100px'));
            columns.add(column('currency', 'Currency', 'TEXT', true, true, '80px'));
            columns.add(column('status', 'Status', 'TEXT', true, true, '100px'));
            columns.add(column('customer', 'Customer', 'TEXT', true, true, '140px'));
            columns.add(column('customer_email', 'Customer Email', 'TEXT', true, true, null));
            columns.add(column('description', 'Description', 'TEXT', true, true, null));
            columns.add(column('paid', 'Paid', 'BOOLEAN', true, true, '80px'));
            columns.add(column('refunded', 'Refunded', 'BOOLEAN', true, true, '90px'));
            columns.add(column('created', 'Created Date', 'DATETIME', true, true, '160px'));
        } else if ('payment_intents'.equals(resource)) {
            columns.add(column('amount', 'Amount', 'NUMBER', true, true, '100px'));
            columns.add(column('amount_received', 'Amount Received', 'NUMBER', true, true, '120px'));
            columns.add(column('currency', 'Currency', 'TEXT', true, true, '80px'));
            columns.add(column('status', 'Status', 'TEXT', true, true, '120px'));
            columns.add(column('customer', 'Customer', 'TEXT', true, true, '140px'));
            columns.add(column('receipt_email', 'Receipt Email', 'TEXT', true, true, null));
            columns.add(column('description', 'Description', 'TEXT', true, true, null));
            columns.add(column('created', 'Created Date', 'DATETIME', true, true, '160px'));
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
