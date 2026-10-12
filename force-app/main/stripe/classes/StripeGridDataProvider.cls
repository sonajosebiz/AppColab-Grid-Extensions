global with sharing class StripeGridDataProvider
    implements appcg.GridDataProviderV1, appcg.GridDataMutationProviderV1 {

    public class ProviderException extends Exception {}


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
        if (!new Set<String>{
            'customers', 'invoices', 'subscriptions', 'charges', 'payment_intents',
            'refunds', 'disputes', 'payouts', 'products', 'prices', 'balance_transactions'
        }.contains(cfg.resource)) {
            throw new ProviderException('Unsupported Stripe resource: ' + cfg.resource);
        }
        return cfg;
    }

    // ─── GridDataProviderV1 ───────────────────────────────────────────

    global appcg.GridDataProviderTypesV1.Capabilities getCapabilities(
        appcg.GridDataProviderTypesV1.ProviderContext context
    ) {
        StripeConfig cfg = parseConfig(context);
        if (String.isNotBlank(cfg.parentMatchColumn) && context != null && String.isNotBlank(context.parentId)) {
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
    }

    global appcg.GridDataProviderTypesV1.PageResult getData(
        appcg.GridDataProviderTypesV1.QueryRequest request
    ) {
        StripeConfig cfg = parseConfig(request?.context);
        if (String.isNotBlank(cfg.parentMatchColumn) && request?.context != null &&
            String.isNotBlank(request.context.parentId)) {
            return getParentFilteredData(request, cfg);
        }
        return getUnfilteredData(request, cfg);
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
        if (cfg.resource != 'customers' && cfg.resource != 'subscriptions') {
            throw new ProviderException('Delete is only supported for customers and subscriptions.');
        }
        try {
            StripeClient client = new StripeClient();
            for (String recId : request.recordIds) {
                client.deleteResource(cfg.resource, recId);
            }
        } finally {
        }
    }

    // ─── Helpers ──────────────────────────────────────────────────────

    private static appcg.GridDataProviderTypesV1.PageResult getUnfilteredData(
        appcg.GridDataProviderTypesV1.QueryRequest request,
        StripeConfig cfg
    ) {
        appcg__Grid_Definition__c gridDef = getGridDefinition(request?.context);
        Integer recordLimit = (gridDef?.appcg__Record_Limit__c != null && gridDef.appcg__Record_Limit__c > 0)
            ? (Integer) gridDef.appcg__Record_Limit__c : 100;
        Boolean clientSide = gridDef?.appcg__Pagination_Type__c == 'Client-Side';
        Integer requestedPageSize = request?.pageSize != null && request.pageSize > 0
            ? request.pageSize
            : (gridDef?.appcg__Page_Size__c != null ? Integer.valueOf(gridDef.appcg__Page_Size__c) : 20);
        Integer pageSize = clientSide ? recordLimit : Math.min(requestedPageSize, 100);
        Integer startIndex = clientSide ? 0 : Math.max(0, request?.startIndex ?? 0);
        String searchTerm = String.isBlank(request?.searchTerm) ? null : request.searchTerm.toLowerCase();
        appcg.GridDataProviderTypesV1.PageResult result = new appcg.GridDataProviderTypesV1.PageResult();
        result.records = new List<Map<String, Object>>();

        StripeClient client = new StripeClient();
        String startingAfter;
        Boolean hasMore = true;
        Integer examined = 0;
        Integer matched = 0;
        while (hasMore && examined < recordLimit) {
            if (Limits.getCallouts() >= Limits.getLimitCallouts()) {
                throw new ProviderException('Stripe list exceeded the available callouts. Lower the grid record limit.');
            }
            Map<String, Object> response = client.listResources(
                cfg.resource, Math.min(100, recordLimit - examined), startingAfter
            );
            List<Object> rawList = (List<Object>) response.get('data');
            if (rawList == null || rawList.isEmpty()) break;
            for (Map<String, Object> record : parseStripeRecords(cfg.resource, rawList)) {
                if (examined >= recordLimit) break;
                examined++;
                if (searchTerm != null && filterBySearch(
                    new List<Map<String, Object>>{ record }, searchTerm
                ).isEmpty()) continue;
                if (clientSide || (matched >= startIndex && matched < startIndex + pageSize)) {
                    result.records.add(record);
                }
                matched++;
            }
            hasMore = response.get('has_more') == true;
            Map<String, Object> lastRawRecord = (Map<String, Object>) rawList[rawList.size() - 1];
            startingAfter = lastRawRecord.get('id') == null ? null : String.valueOf(lastRawRecord.get('id'));
            if (hasMore && String.isBlank(startingAfter)) {
                throw new ProviderException('Stripe returned a page without a cursor.');
            }
        }
        result.totalCount = matched;
        return result;
    }

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
        Integer pageSize = clientSide ? recordLimit : Math.min(requestedPageSize, 100);
        Integer startIndex = clientSide ? 0 : (request.startIndex == null ? 0 : Math.max(0, request.startIndex));
        String searchTerm = String.isBlank(request.searchTerm) ? null : request.searchTerm.toLowerCase();
        String filterName = listFilterName(cfg.resource, matchColumn);

        StripeClient client = new StripeClient();
        String startingAfter;
        Boolean hasMore = true;
        Integer matchedCount = 0;
        while (hasMore && matchedCount < recordLimit) {
            if (Limits.getCallouts() >= Limits.getLimitCallouts()) {
                throw new ProviderException('Stripe parent filter exceeded the available callouts. Narrow the Stripe data or use a customer ID match.');
            }
            Map<String, Object> response = client.listResources(
                cfg.resource, 100, startingAfter, filterName, filterName == null ? null : parentValue.trim()
            );
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

    private static String listFilterName(String resource, String column) {
        if (column == 'customer' && new Set<String>{
            'charges', 'invoices', 'subscriptions', 'payment_intents'
        }.contains(resource)) return 'customer';
        if ((resource == 'refunds' || resource == 'disputes') &&
            (column == 'charge' || column == 'payment_intent')) return column;
        if (resource == 'prices' && column == 'product') return 'product';
        return null;
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
                for (String spec : extraFieldSpecs(resource)) {
                    List<String> parts = spec.split('\\|');
                    Object value = fieldValue(item, parts[3]);
                    if (parts[4] == 'AMOUNT') {
                        value = formatAmount(value);
                    } else if (parts[4] == 'TIME') {
                        value = formatTimestamp(value);
                    } else if (parts[4] == 'BOOLEAN') {
                        value = value == true ? 'true' : 'false';
                    } else if (parts[4] == 'UPPER') {
                        value = value == null ? '' : String.valueOf(value).toUpperCase();
                    } else {
                        value = value == null ? '' : String.valueOf(value);
                    }
                    row.put(parts[0], value);
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
        } else {
            for (String spec : extraFieldSpecs(resource)) {
                List<String> parts = spec.split('\\|');
                columns.add(column(parts[0], parts[1], parts[2], true, true, parts[5]));
            }
        }
        return columns;
    }

    // id | label | grid type | Stripe field path | format | width
    private static List<String> extraFieldSpecs(String resource) {
        if (resource == 'refunds') return new List<String>{
            'amount|Amount|NUMBER|amount|AMOUNT|100px', 'currency|Currency|TEXT|currency|UPPER|80px',
            'status|Status|TEXT|status|TEXT|110px', 'charge|Charge|TEXT|charge|TEXT|160px',
            'payment_intent|Payment Intent|TEXT|payment_intent|TEXT|170px',
            'reason|Reason|TEXT|reason|TEXT|160px', 'created|Created Date|DATETIME|created|TIME|160px'
        };
        if (resource == 'disputes') return new List<String>{
            'amount|Amount|NUMBER|amount|AMOUNT|100px', 'currency|Currency|TEXT|currency|UPPER|80px',
            'status|Status|TEXT|status|TEXT|140px', 'charge|Charge|TEXT|charge|TEXT|160px',
            'payment_intent|Payment Intent|TEXT|payment_intent|TEXT|170px',
            'reason|Reason|TEXT|reason|TEXT|160px', 'created|Created Date|DATETIME|created|TIME|160px'
        };
        if (resource == 'payouts') return new List<String>{
            'amount|Amount|NUMBER|amount|AMOUNT|100px', 'currency|Currency|TEXT|currency|UPPER|80px',
            'status|Status|TEXT|status|TEXT|110px', 'destination|Destination|TEXT|destination|TEXT|170px',
            'arrival_date|Arrival Date|DATETIME|arrival_date|TIME|160px',
            'description|Description|TEXT|description|TEXT|200px',
            'created|Created Date|DATETIME|created|TIME|160px'
        };
        if (resource == 'products') return new List<String>{
            'name|Name|TEXT|name|TEXT|200px', 'description|Description|TEXT|description|TEXT|240px',
            'active|Active|BOOLEAN|active|BOOLEAN|90px',
            'default_price|Default Price|TEXT|default_price|TEXT|170px',
            'created|Created Date|DATETIME|created|TIME|160px'
        };
        if (resource == 'prices') return new List<String>{
            'product|Product|TEXT|product|TEXT|170px', 'nickname|Nickname|TEXT|nickname|TEXT|160px',
            'unit_amount|Unit Amount|NUMBER|unit_amount|AMOUNT|110px',
            'currency|Currency|TEXT|currency|UPPER|80px', 'type|Type|TEXT|type|TEXT|110px',
            'interval|Interval|TEXT|recurring.interval|TEXT|100px',
            'active|Active|BOOLEAN|active|BOOLEAN|90px',
            'created|Created Date|DATETIME|created|TIME|160px'
        };
        if (resource == 'balance_transactions') return new List<String>{
            'amount|Amount|NUMBER|amount|AMOUNT|100px', 'fee|Fee|NUMBER|fee|AMOUNT|100px',
            'net|Net|NUMBER|net|AMOUNT|100px', 'currency|Currency|TEXT|currency|UPPER|80px',
            'type|Type|TEXT|type|TEXT|150px', 'source|Source|TEXT|source|TEXT|170px',
            'created|Created Date|DATETIME|created|TIME|160px'
        };
        return new List<String>();
    }

    private static Object fieldValue(Map<String, Object> record, String path) {
        Object value = record;
        for (String part : path.split('\\.')) {
            if (!(value instanceof Map<String, Object>)) return null;
            value = ((Map<String, Object>) value).get(part);
        }
        return value;
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
