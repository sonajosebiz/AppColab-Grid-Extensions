global with sharing class ShopifyGridDataProvider
    implements appcg.GridDataProviderV1, appcg.GridDataMutationProviderV1 {

    public class ProviderException extends Exception {}


    // ─── Instance Cache ───────────────────────────────────────────────
    private List<Map<String, Object>> cachedRecords;

    // ─── Config ───────────────────────────────────────────────────────

    @TestVisible
    private class ShopifyConfig {
        public String resource;
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
    private static ShopifyConfig parseConfig(appcg.GridDataProviderTypesV1.ProviderContext context) {
        ShopifyConfig cfg = new ShopifyConfig();
        cfg.resource = 'products'; // default

        appcg__Grid_Definition__c gridDef = getGridDefinition(context);
        String configJson = gridDef != null ? gridDef.appcg__Data_Provider_Config__c : null;

        if (String.isNotBlank(configJson)) {
            try {
                ShopifyConfig parsed = (ShopifyConfig) JSON.deserialize(
                    configJson,
                    ShopifyConfig.class
                );
                if (parsed != null && String.isNotBlank(parsed.resource)) {
                    cfg.resource = parsed.resource.trim().toLowerCase();
                }
            } catch (Exception e) {
                throw new ProviderException('Invalid Shopify provider configuration: ' + e.getMessage());
            }
        }
        return cfg;
    }

    // ─── GridDataProviderV1 ───────────────────────────────────────────

    global appcg.GridDataProviderTypesV1.Capabilities getCapabilities(
        appcg.GridDataProviderTypesV1.ProviderContext context
    ) {
        ShopifyConfig cfg = parseConfig(context);
        try {
            ShopifyClient client = new ShopifyClient();
            Map<String, Object> response = client.listResources(cfg.resource, 100, null, null);
            List<Object> rawList = (List<Object>) response.get(cfg.resource);

            cachedRecords = parseShopifyRecords(cfg.resource, rawList);

            appcg.GridDataProviderTypesV1.Capabilities capabilities = new appcg.GridDataProviderTypesV1.Capabilities();
            if ('products'.equals(cfg.resource) || 'customers'.equals(cfg.resource)) {
                capabilities.supportedFeatures = new Set<String>{
                    'SEARCH', 'REFRESH', 'ADD', 'EDIT', 'DELETE', 'DOWNLOAD_CSV'
                };
                capabilities.supportedRowActions = new Set<String>{ 'DELETE' };
            } else {
                capabilities.supportedFeatures = new Set<String>{
                    'SEARCH', 'REFRESH', 'DOWNLOAD_CSV'
                };
                capabilities.supportedRowActions = new Set<String>();
            }

            capabilities.supportsServerPagination = false;
            capabilities.columns = buildColumnDefinitions(cfg.resource);
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
                pageSize = Math.min(recordLimit, 250);
            } else {
                pageSize = (gridDef?.appcg__Record_Limit__c != null && gridDef.appcg__Record_Limit__c > 0)
                    ? Math.min(requestedPageSize, (Integer) gridDef.appcg__Record_Limit__c)
                    : Math.min(requestedPageSize, 250);
            }

            if (cachedRecords != null) {
                records = cachedRecords;
                cachedRecords = null;
            } else {
                ShopifyConfig cfg = parseConfig(request.context);
                ShopifyClient client = new ShopifyClient();
                Map<String, Object> response = client.listResources(cfg.resource, 100, null, null);
                List<Object> rawList = (List<Object>) response.get(cfg.resource);
                records = parseShopifyRecords(cfg.resource, rawList);
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
        ShopifyConfig cfg = parseConfig(request.context);
        if (!'products'.equals(cfg.resource) && !'customers'.equals(cfg.resource)) {
            throw new ProviderException('Inline editing is only supported for products and customers.');
        }
        try {
            ShopifyClient client = new ShopifyClient();
            List<Map<String, Object>> saved = new List<Map<String, Object>>();

            for (Map<String, Object> record : request.records) {
                String recId = (String) record.get('Id');
                Map<String, Object> fields = cleanFields(cfg.resource, record);

                if (String.isBlank(recId)) {
                    // Create new
                    Map<String, Object> res = client.createResource(cfg.resource, fields);
                    String singular = ShopifyClient.toSingular(cfg.resource);
                    Map<String, Object> created = (Map<String, Object>) res.get(singular);
                    List<Map<String, Object>> parsed = parseShopifyRecords(
                        cfg.resource,
                        new List<Object>{ created }
                    );
                    if (!parsed.isEmpty()) {
                        saved.add(parsed[0]);
                    }
                } else {
                    // Update existing
                    Map<String, Object> res = client.updateResource(cfg.resource, recId, fields);
                    String singular = ShopifyClient.toSingular(cfg.resource);
                    Map<String, Object> updated = (Map<String, Object>) res.get(singular);
                    List<Map<String, Object>> parsed = parseShopifyRecords(
                        cfg.resource,
                        new List<Object>{ updated }
                    );
                    if (!parsed.isEmpty()) {
                        saved.add(parsed[0]);
                    }
                }
            }

            appcg.GridDataProviderTypesV1.SaveResult result = new appcg.GridDataProviderTypesV1.SaveResult();
            result.records = saved;
            return result;
        } finally {
        }
    }

    global void deleteRecords(appcg.GridDataProviderTypesV1.DeleteRequest request) {
        if (request.recordIds == null || request.recordIds.isEmpty()) {
            return;
        }
        ShopifyConfig cfg = parseConfig(request.context);
        if (!'products'.equals(cfg.resource) && !'customers'.equals(cfg.resource)) {
            throw new ProviderException('Deletion is only supported for products and customers.');
        }
        try {
            ShopifyClient client = new ShopifyClient();
            for (String recId : request.recordIds) {
                client.deleteResource(cfg.resource, recId);
            }
        } finally {
        }
    }

    // ─── Helpers ──────────────────────────────────────────────────────

    @TestVisible
    private static List<Map<String, Object>> parseShopifyRecords(
        String resource,
        List<Object> rawList
    ) {
        List<Map<String, Object>> parsed = new List<Map<String, Object>>();
        if (rawList == null) return parsed;

        for (Object itemObj : rawList) {
            Map<String, Object> item = (Map<String, Object>) itemObj;
            Map<String, Object> row = new Map<String, Object>();
            row.put('Id', String.valueOf(item.get('id')));

            if ('products'.equals(resource)) {
                row.put('title', item.get('title') == null ? '' : String.valueOf(item.get('title')));
                row.put('vendor', item.get('vendor') == null ? '' : String.valueOf(item.get('vendor')));
                row.put('product_type', item.get('product_type') == null ? '' : String.valueOf(item.get('product_type')));
                row.put('status', item.get('status') == null ? 'active' : String.valueOf(item.get('status')));
                row.put('tags', item.get('tags') == null ? '' : String.valueOf(item.get('tags')));
                row.put('created_at', formatIsoDate(item.get('created_at')));

                // Extract variant info (price and inventory)
                List<Object> variants = (List<Object>) item.get('variants');
                if (variants != null && !variants.isEmpty()) {
                    Map<String, Object> firstVar = (Map<String, Object>) variants[0];
                    row.put('price', firstVar.get('price') == null ? '0.00' : String.valueOf(firstVar.get('price')));
                    row.put('inventory_quantity', firstVar.get('inventory_quantity') == null ? 0 : firstVar.get('inventory_quantity'));
                } else {
                    row.put('price', '0.00');
                    row.put('inventory_quantity', 0);
                }
            } else if ('orders'.equals(resource)) {
                row.put('name', item.get('name') == null ? '' : String.valueOf(item.get('name')));
                row.put('email', item.get('email') == null ? '' : String.valueOf(item.get('email')));
                row.put('financial_status', item.get('financial_status') == null ? '' : String.valueOf(item.get('financial_status')));
                row.put('fulfillment_status', item.get('fulfillment_status') == null ? 'unfulfilled' : String.valueOf(item.get('fulfillment_status')));
                row.put('total_price', item.get('total_price') == null ? '0.00' : String.valueOf(item.get('total_price')));
                row.put('currency', item.get('currency') == null ? 'USD' : String.valueOf(item.get('currency')).toUpperCase());
                row.put('created_at', formatIsoDate(item.get('created_at')));

                // Customer info
                Map<String, Object> cust = (Map<String, Object>) item.get('customer');
                if (cust != null) {
                    String fn = cust.get('first_name') == null ? '' : String.valueOf(cust.get('first_name'));
                    String ln = cust.get('last_name') == null ? '' : String.valueOf(cust.get('last_name'));
                    row.put('customer_name', (fn + ' ' + ln).trim());
                    if (row.get('email') == '') {
                        row.put('email', cust.get('email') == null ? '' : String.valueOf(cust.get('email')));
                    }
                } else {
                    row.put('customer_name', '');
                }
            } else if ('customers'.equals(resource)) {
                row.put('first_name', item.get('first_name') == null ? '' : String.valueOf(item.get('first_name')));
                row.put('last_name', item.get('last_name') == null ? '' : String.valueOf(item.get('last_name')));
                row.put('email', item.get('email') == null ? '' : String.valueOf(item.get('email')));
                row.put('phone', item.get('phone') == null ? '' : String.valueOf(item.get('phone')));
                row.put('orders_count', item.get('orders_count') == null ? 0 : item.get('orders_count'));
                row.put('total_spent', item.get('total_spent') == null ? '0.00' : String.valueOf(item.get('total_spent')));
                row.put('state', item.get('state') == null ? 'enabled' : String.valueOf(item.get('state')));
                row.put('tags', item.get('tags') == null ? '' : String.valueOf(item.get('tags')));
                row.put('created_at', formatIsoDate(item.get('created_at')));
            }
            parsed.add(row);
        }
        return parsed;
    }

    private static Map<String, Object> cleanFields(String resource, Map<String, Object> record) {
        Map<String, Object> clean = new Map<String, Object>();
        if ('products'.equals(resource)) {
            Set<String> allowed = new Set<String>{ 'title', 'vendor', 'product_type', 'status', 'tags' };
            for (String k : record.keySet()) {
                if (allowed.contains(k.toLowerCase()) && record.get(k) != null) {
                    clean.put(k.toLowerCase(), record.get(k));
                }
            }
            if (record.containsKey('price')) {
                clean.put('variants', new List<Object>{
                    new Map<String, Object>{ 'price' => String.valueOf(record.get('price')) }
                });
            }
        } else if ('customers'.equals(resource)) {
            Set<String> allowed = new Set<String>{ 'first_name', 'last_name', 'email', 'phone', 'tags' };
            for (String k : record.keySet()) {
                if (allowed.contains(k.toLowerCase()) && record.get(k) != null) {
                    clean.put(k.toLowerCase(), record.get(k));
                }
            }
        }
        return clean;
    }

    @TestVisible
    private static String formatIsoDate(Object raw) {
        if (raw == null) return '';
        String s = String.valueOf(raw);
        if (s.length() >= 19) {
            return s.substring(0, 10) + ' ' + s.substring(11, 19);
        }
        return s;
    }

    private static List<appcg.GridDataProviderTypesV1.ColumnDefinition> buildColumnDefinitions(String resource) {
        List<appcg.GridDataProviderTypesV1.ColumnDefinition> columns =
            new List<appcg.GridDataProviderTypesV1.ColumnDefinition>();

        // Hidden Id column
        columns.add(column('Id', 'ID', 'TEXT', true, false, '140px', null));

        if ('products'.equals(resource)) {
            columns.add(column('title', 'Title', 'TEXT', false, true, null, null));
            columns.add(column('vendor', 'Vendor', 'TEXT', false, true, '140px', null));
            columns.add(column('product_type', 'Type', 'TEXT', false, true, '130px', null));

            List<appcg.GridDataProviderTypesV1.Option> statusOptions = new List<appcg.GridDataProviderTypesV1.Option>{
                option('active', 'Active'),
                option('draft', 'Draft'),
                option('archived', 'Archived')
            };
            columns.add(column('status', 'Status', 'PICKLIST', false, true, '110px', statusOptions));
            columns.add(column('price', 'Price', 'NUMBER', false, true, '100px', null));
            columns.add(column('inventory_quantity', 'Inventory', 'NUMBER', true, true, '100px', null));
            columns.add(column('tags', 'Tags', 'TEXT', false, true, '150px', null));
            columns.add(column('created_at', 'Created Date', 'DATETIME', true, true, '160px', null));
        } else if ('orders'.equals(resource)) {
            columns.add(column('name', 'Order #', 'TEXT', true, true, '120px', null));
            columns.add(column('customer_name', 'Customer', 'TEXT', true, true, null, null));
            columns.add(column('email', 'Email', 'TEXT', true, true, null, null));

            List<appcg.GridDataProviderTypesV1.Option> finOptions = new List<appcg.GridDataProviderTypesV1.Option>{
                option('paid', 'Paid'),
                option('pending', 'Pending'),
                option('authorized', 'Authorized'),
                option('refunded', 'Refunded'),
                option('voided', 'Voided')
            };
            columns.add(column('financial_status', 'Financial Status', 'PICKLIST', true, true, '130px', finOptions));

            List<appcg.GridDataProviderTypesV1.Option> fulOptions = new List<appcg.GridDataProviderTypesV1.Option>{
                option('fulfilled', 'Fulfilled'),
                option('partial', 'Partially Fulfilled'),
                option('unfulfilled', 'Unfulfilled')
            };
            columns.add(column('fulfillment_status', 'Fulfillment', 'PICKLIST', true, true, '130px', fulOptions));
            columns.add(column('total_price', 'Total', 'NUMBER', true, true, '100px', null));
            columns.add(column('currency', 'Currency', 'TEXT', true, true, '90px', null));
            columns.add(column('created_at', 'Order Date', 'DATETIME', true, true, '160px', null));
        } else if ('customers'.equals(resource)) {
            columns.add(column('first_name', 'First Name', 'TEXT', false, true, null, null));
            columns.add(column('last_name', 'Last Name', 'TEXT', false, true, null, null));
            columns.add(column('email', 'Email', 'TEXT', false, true, null, null));
            columns.add(column('phone', 'Phone', 'TEXT', false, true, '140px', null));
            columns.add(column('orders_count', 'Orders Count', 'NUMBER', true, true, '110px', null));
            columns.add(column('total_spent', 'Total Spent', 'NUMBER', true, true, '110px', null));

            List<appcg.GridDataProviderTypesV1.Option> stateOptions = new List<appcg.GridDataProviderTypesV1.Option>{
                option('enabled', 'Enabled'),
                option('invited', 'Invited'),
                option('declined', 'Declined'),
                option('disabled', 'Disabled')
            };
            columns.add(column('state', 'State', 'PICKLIST', true, true, '110px', stateOptions));
            columns.add(column('tags', 'Tags', 'TEXT', false, true, '140px', null));
            columns.add(column('created_at', 'Created Date', 'DATETIME', true, true, '160px', null));
        }
        return columns;
    }

    private static appcg.GridDataProviderTypesV1.ColumnDefinition column(
        String id, String label, String fieldType,
        Boolean isReadOnly, Boolean visible, String width,
        List<appcg.GridDataProviderTypesV1.Option> options
    ) {
        appcg.GridDataProviderTypesV1.ColumnDefinition col = new appcg.GridDataProviderTypesV1.ColumnDefinition();
        col.id = id;
        col.label = label;
        col.fieldType = fieldType;
        col.isReadOnly = isReadOnly;
        col.visible = visible;
        col.columnWidth = width;
        col.picklistOptions = options;
        return col;
    }

    private static appcg.GridDataProviderTypesV1.Option option(String value, String label) {
        appcg.GridDataProviderTypesV1.Option opt = new appcg.GridDataProviderTypesV1.Option();
        opt.value = value;
        opt.label = label;
        return opt;
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
