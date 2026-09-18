global with sharing class QuickBooksGridDataProvider implements appcg.GridDataProviderV1 {

    public class ProviderException extends Exception {}


    // ─── Instance Cache ───────────────────────────────────────────────
    private List<Map<String, Object>> cachedRecords;
    private Integer cachedTotalCount;

    // ─── Config ───────────────────────────────────────────────────────

    @TestVisible
    private class QuickBooksConfig {
        public String realmId;
        public String resource;
        public Integer recordLimit;
        public String whereClause;
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
    private static QuickBooksConfig parseConfig(appcg.GridDataProviderTypesV1.ProviderContext context) {
        appcg__Grid_Definition__c gridDef = getGridDefinition(context);
        String configJson = gridDef != null ? gridDef.appcg__Data_Provider_Config__c : null;
        if (String.isBlank(configJson)) {
            throw new ProviderException(
                'QuickBooks provider requires configuration. ' +
                'Set Data Provider Configuration with {"realmId":"9341452...","resource":"invoices"}'
            );
        }

        QuickBooksConfig cfg = new QuickBooksConfig();
        cfg.resource = 'invoices';
        cfg.recordLimit = (gridDef?.appcg__Record_Limit__c != null && gridDef.appcg__Record_Limit__c > 0)
            ? (Integer) gridDef.appcg__Record_Limit__c
            : 100;

        try {
            Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(configJson);
            if (raw.containsKey('realmId')) {
                cfg.realmId = String.valueOf(raw.get('realmId')).trim();
            } else if (raw.containsKey('companyId')) {
                cfg.realmId = String.valueOf(raw.get('companyId')).trim();
            }

            if (raw.containsKey('resource')) {
                cfg.resource = String.valueOf(raw.get('resource')).trim().toLowerCase();
            } else if (raw.containsKey('entity')) {
                cfg.resource = String.valueOf(raw.get('entity')).trim().toLowerCase();
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

            if (raw.containsKey('where')) {
                cfg.whereClause = String.valueOf(raw.get('where')).trim();
            } else if (raw.containsKey('whereClause')) {
                cfg.whereClause = String.valueOf(raw.get('whereClause')).trim();
            }
        } catch (Exception e) {
            throw new ProviderException('Invalid QuickBooks provider configuration: ' + e.getMessage());
        }

        if (String.isBlank(cfg.realmId)) {
            throw new ProviderException('realmId (Company ID) is required in configuration (e.g. "9341452...").');
        }

        return cfg;
    }

    // ─── GridDataProviderV1 ───────────────────────────────────────────

    global appcg.GridDataProviderTypesV1.Capabilities getCapabilities(
        appcg.GridDataProviderTypesV1.ProviderContext context
    ) {
        QuickBooksConfig cfg = parseConfig(context);
        try {
            QuickBooksClient client = new QuickBooksClient();
            String entityName = resolveEntityName(cfg.resource);
            cachedTotalCount = client.count(cfg.realmId, entityName, cfg.whereClause);
            Map<String, Object> response = client.query(
                cfg.realmId,
                entityName,
                1,
                20,
                cfg.whereClause
            );

            cachedRecords = parseQuickBooksRecords(cfg.resource, response);

            appcg.GridDataProviderTypesV1.Capabilities capabilities = new appcg.GridDataProviderTypesV1.Capabilities();
            capabilities.supportedFeatures = new Set<String>{
                'SEARCH', 'REFRESH', 'DOWNLOAD_CSV'
            };
            capabilities.supportedRowActions = new Set<String>();
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
            List<Map<String, Object>> records;
            Integer totalCount;

            appcg__Grid_Definition__c gridDef = getGridDefinition(request?.context);
            String paginationType = gridDef?.appcg__Pagination_Type__c;
            Integer recordLimit = (gridDef?.appcg__Record_Limit__c != null && gridDef.appcg__Record_Limit__c > 0)
                ? (Integer) gridDef.appcg__Record_Limit__c
                : 1000;

            Integer startIndex = request.startIndex != null ? Math.max(0, request.startIndex) : 0;
            Integer startPosition = startIndex + 1;
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

            if (cachedRecords != null && startIndex == 0) {
                records = cachedRecords;
                totalCount = cachedTotalCount;
                cachedRecords = null;
            } else {
                QuickBooksConfig cfg = parseConfig(request.context);
                QuickBooksClient client = new QuickBooksClient();
                String entityName = resolveEntityName(cfg.resource);

                totalCount = client.count(cfg.realmId, entityName, cfg.whereClause);
                Map<String, Object> response = client.query(
                    cfg.realmId,
                    entityName,
                    startPosition,
                    pageSize,
                    cfg.whereClause
                );
                records = parseQuickBooksRecords(cfg.resource, response);
            }

            while (records != null && records.size() > pageSize) {
                records.remove(records.size() - 1);
            }

            // Apply search filter
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

    // ─── Record Parsers ───────────────────────────────────────────────

    @TestVisible
    private static List<Map<String, Object>> parseQuickBooksRecords(
        String resource,
        Map<String, Object> response
    ) {
        List<Map<String, Object>> records = new List<Map<String, Object>>();
        if (response == null || !response.containsKey('QueryResponse')) {
            return records;
        }

        Map<String, Object> queryResp = (Map<String, Object>) response.get('QueryResponse');
        String entityKey = resolveEntityName(resource);

        if (!queryResp.containsKey(entityKey) || queryResp.get(entityKey) == null) {
            return records;
        }

        List<Object> rawList = (List<Object>) queryResp.get(entityKey);
        for (Object item : rawList) {
            if (item instanceof Map<String, Object>) {
                Map<String, Object> orig = (Map<String, Object>) item;
                Map<String, Object> row = new Map<String, Object>();
                row.put('Id', String.valueOf(orig.get('Id')));

                if ('invoices'.equals(resource) || 'invoice'.equals(resource)) {
                    row.put('docNumber', str(orig.get('DocNumber')));
                    row.put('customerName', nestedStr(orig, 'CustomerRef', 'name'));
                    row.put('txnDate', str(orig.get('TxnDate')));
                    row.put('dueDate', str(orig.get('DueDate')));
                    Decimal total = dec(orig.get('TotalAmt'));
                    Decimal bal = dec(orig.get('Balance'));
                    row.put('totalAmt', total);
                    row.put('balance', bal);
                    row.put('status', resolveInvoiceStatus(bal, str(orig.get('DueDate'))));
                    row.put('emailStatus', str(orig.get('EmailStatus')));
                } else if ('customers'.equals(resource) || 'customer'.equals(resource)) {
                    row.put('displayName', str(orig.get('DisplayName')));
                    row.put('email', nestedStr(orig, 'PrimaryEmailAddr', 'Address'));
                    row.put('phone', nestedStr(orig, 'PrimaryPhone', 'FreeFormNumber'));
                    row.put('companyName', str(orig.get('CompanyName')));
                    row.put('balance', dec(orig.get('Balance')));
                    row.put('active', orig.containsKey('Active') ? (Boolean) orig.get('Active') : true);
                } else if ('payments'.equals(resource) || 'payment'.equals(resource)) {
                    row.put('paymentRefNum', str(orig.get('PaymentRefNum')));
                    row.put('customerName', nestedStr(orig, 'CustomerRef', 'name'));
                    row.put('txnDate', str(orig.get('TxnDate')));
                    row.put('totalAmt', dec(orig.get('TotalAmt')));
                    row.put('paymentMethod', nestedStr(orig, 'PaymentMethodRef', 'name'));
                } else if ('items'.equals(resource) || 'item'.equals(resource)) {
                    row.put('name', str(orig.get('Name')));
                    row.put('sku', str(orig.get('Sku')));
                    row.put('unitPrice', dec(orig.get('UnitPrice')));
                    row.put('qtyOnHand', dec(orig.get('QtyOnHand')));
                    row.put('type', str(orig.get('Type')));
                    row.put('active', orig.containsKey('Active') ? (Boolean) orig.get('Active') : true);
                } else if ('bills'.equals(resource) || 'bill'.equals(resource)) {
                    row.put('docNumber', str(orig.get('DocNumber')));
                    row.put('vendorName', nestedStr(orig, 'VendorRef', 'name'));
                    row.put('txnDate', str(orig.get('TxnDate')));
                    row.put('dueDate', str(orig.get('DueDate')));
                    row.put('totalAmt', dec(orig.get('TotalAmt')));
                    row.put('balance', dec(orig.get('Balance')));
                } else {
                    // Generic fallback
                    for (String k : orig.keySet()) {
                        Object v = orig.get(k);
                        if (!(v instanceof Map<String, Object>) && !(v instanceof List<Object>)) {
                            row.put(k, v);
                        }
                    }
                }
                records.add(row);
            }
        }
        return records;
    }

    private static String resolveInvoiceStatus(Decimal balance, String dueDateStr) {
        if (balance == null || balance <= 0) {
            return 'Paid';
        }
        if (String.isNotBlank(dueDateStr)) {
            try {
                Date due = Date.valueOf(dueDateStr);
                if (due < Date.today()) {
                    return 'Overdue';
                }
            } catch (Exception e) {}
        }
        return 'Open';
    }

    // ─── Column Definitions ───────────────────────────────────────────

    private static List<appcg.GridDataProviderTypesV1.ColumnDefinition> buildColumnDefinitions(String resource) {
        List<appcg.GridDataProviderTypesV1.ColumnDefinition> columns =
            new List<appcg.GridDataProviderTypesV1.ColumnDefinition>();

        // Hidden Id column
        columns.add(column('Id', 'ID', 'TEXT', true, false, '100px'));

        if ('invoices'.equals(resource) || 'invoice'.equals(resource)) {
            columns.add(column('docNumber', 'Invoice Number', 'TEXT', true, true, '120px'));
            columns.add(column('customerName', 'Customer', 'TEXT', true, true, '200px'));
            columns.add(column('txnDate', 'Invoice Date', 'TEXT', true, true, '130px'));
            columns.add(column('dueDate', 'Due Date', 'TEXT', true, true, '130px'));
            columns.add(column('totalAmt', 'Amount', 'NUMBER', true, true, '130px'));
            columns.add(column('balance', 'Balance Due', 'NUMBER', true, true, '130px'));
            columns.add(column('status', 'Status', 'TEXT', true, true, '110px'));
            columns.add(column('emailStatus', 'Email Status', 'TEXT', true, true, '120px'));
        } else if ('customers'.equals(resource) || 'customer'.equals(resource)) {
            columns.add(column('displayName', 'Name', 'TEXT', true, true, '200px'));
            columns.add(column('email', 'Email', 'EMAIL', true, true, '220px'));
            columns.add(column('phone', 'Phone', 'PHONE', true, true, '150px'));
            columns.add(column('companyName', 'Company', 'TEXT', true, true, '180px'));
            columns.add(column('balance', 'Open Balance', 'NUMBER', true, true, '130px'));
            columns.add(column('active', 'Active?', 'BOOLEAN', true, true, '100px'));
        } else if ('payments'.equals(resource) || 'payment'.equals(resource)) {
            columns.add(column('paymentRefNum', 'Payment #', 'TEXT', true, true, '140px'));
            columns.add(column('customerName', 'Customer', 'TEXT', true, true, '200px'));
            columns.add(column('txnDate', 'Payment Date', 'TEXT', true, true, '130px'));
            columns.add(column('totalAmt', 'Amount', 'NUMBER', true, true, '130px'));
            columns.add(column('paymentMethod', 'Payment Method', 'TEXT', true, true, '150px'));
        } else if ('items'.equals(resource) || 'item'.equals(resource)) {
            columns.add(column('name', 'Name', 'TEXT', true, true, '220px'));
            columns.add(column('sku', 'SKU', 'TEXT', true, true, '130px'));
            columns.add(column('unitPrice', 'Price ($)', 'NUMBER', true, true, '120px'));
            columns.add(column('qtyOnHand', 'Qty on Hand', 'NUMBER', true, true, '120px'));
            columns.add(column('type', 'Item Type', 'TEXT', true, true, '130px'));
            columns.add(column('active', 'Active?', 'BOOLEAN', true, true, '100px'));
        } else if ('bills'.equals(resource) || 'bill'.equals(resource)) {
            columns.add(column('docNumber', 'Bill #', 'TEXT', true, true, '120px'));
            columns.add(column('vendorName', 'Vendor', 'TEXT', true, true, '200px'));
            columns.add(column('txnDate', 'Bill Date', 'TEXT', true, true, '130px'));
            columns.add(column('dueDate', 'Due Date', 'TEXT', true, true, '130px'));
            columns.add(column('totalAmt', 'Amount', 'NUMBER', true, true, '130px'));
            columns.add(column('balance', 'Balance Due', 'NUMBER', true, true, '130px'));
        } else {
            columns.add(column('displayName', 'Name', 'TEXT', true, true, '200px'));
        }

        return columns;
    }

    // ─── Helpers ──────────────────────────────────────────────────────

    @TestVisible
    private static String resolveEntityName(String resource) {
        if ('invoices'.equals(resource) || 'invoice'.equals(resource)) return 'Invoice';
        if ('customers'.equals(resource) || 'customer'.equals(resource)) return 'Customer';
        if ('payments'.equals(resource) || 'payment'.equals(resource)) return 'Payment';
        if ('items'.equals(resource) || 'item'.equals(resource)) return 'Item';
        if ('bills'.equals(resource) || 'bill'.equals(resource)) return 'Bill';
        return 'Invoice';
    }

    private static String str(Object val) {
        return (val == null) ? '' : String.valueOf(val);
    }

    private static Decimal dec(Object val) {
        if (val == null) return 0;
        try {
            return Decimal.valueOf(String.valueOf(val));
        } catch (Exception e) {
            return 0;
        }
    }

    private static String nestedStr(Map<String, Object> obj, String parentKey, String childKey) {
        if (obj != null && obj.containsKey(parentKey) && obj.get(parentKey) instanceof Map<String, Object>) {
            Map<String, Object> child = (Map<String, Object>) obj.get(parentKey);
            if (child != null && child.containsKey(childKey)) {
                return str(child.get(childKey));
            }
        }
        return '';
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
        String lowerTerm = searchTerm.toLowerCase();
        List<Map<String, Object>> filtered = new List<Map<String, Object>>();
        for (Map<String, Object> rec : records) {
            Boolean matched = false;
            for (String key : rec.keySet()) {
                if ('Id'.equalsIgnoreCase(key)) continue;
                Object val = rec.get(key);
                if (val != null && String.valueOf(val).toLowerCase().contains(lowerTerm)) {
                    matched = true;
                    break;
                }
            }
            if (matched) {
                filtered.add(rec);
            }
        }
        return filtered;
    }
}
