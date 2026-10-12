global with sharing class QuickBooksGridDataProvider implements appcg.GridDataProviderV1 {

    public class ProviderException extends Exception {}


    private static final Integer MAX_RECORDS = 10000;
    private static final Integer MAX_PAGE_SIZE = 1000;

    // ─── Config ───────────────────────────────────────────────────────

    @TestVisible
    private class QuickBooksConfig {
        public String realmId;
        public String resource;
        public Integer recordLimit;
        public String whereClause;
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
            : 1000;

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
            if (raw.get('parentMatchColumn') != null) {
                cfg.parentMatchColumn = String.valueOf(raw.get('parentMatchColumn')).trim();
            }
            if (raw.get('parentMatchField') != null) {
                cfg.parentMatchField = String.valueOf(raw.get('parentMatchField')).trim();
            }
        } catch (Exception e) {
            throw new ProviderException('Invalid QuickBooks provider configuration: ' + e.getMessage());
        }

        if (String.isBlank(cfg.realmId)) {
            throw new ProviderException('realmId (Company ID) is required in configuration (e.g. "9341452...").');
        }
        cfg.resource = resolveEntityName(cfg.resource);
        cfg.recordLimit = cfg.recordLimit == null || cfg.recordLimit <= 0
            ? 1000 : Math.min(cfg.recordLimit, MAX_RECORDS);
        if (String.isNotBlank(cfg.parentMatchColumn)) {
            if (!Pattern.compile('[A-Za-z][A-Za-z0-9_]*').matcher(cfg.parentMatchColumn).matches()) {
                throw new ProviderException('parentMatchColumn must be a QuickBooks field name.');
            }
            if (String.isBlank(cfg.parentMatchField)) cfg.parentMatchField = 'Id';
        }

        return cfg;
    }

    // ─── GridDataProviderV1 ───────────────────────────────────────────

    global appcg.GridDataProviderTypesV1.Capabilities getCapabilities(
        appcg.GridDataProviderTypesV1.ProviderContext context
    ) {
        QuickBooksConfig cfg = parseConfig(context);
        appcg.GridDataProviderTypesV1.Capabilities capabilities = new appcg.GridDataProviderTypesV1.Capabilities();
        capabilities.supportedFeatures = new Set<String>{ 'SEARCH', 'REFRESH', 'DOWNLOAD_CSV' };
        capabilities.supportedRowActions = new Set<String>();
        capabilities.supportsServerPagination = true;
        capabilities.maxPageSize = MAX_PAGE_SIZE;
        capabilities.columns = buildColumnDefinitions(cfg.resource);
        return capabilities;
    }

    global appcg.GridDataProviderTypesV1.PageResult getData(
        appcg.GridDataProviderTypesV1.QueryRequest request
    ) {
        QuickBooksConfig cfg = parseConfig(request?.context);
        appcg__Grid_Definition__c gridDef = getGridDefinition(request?.context);
        Boolean clientSide = gridDef?.appcg__Pagination_Type__c == 'Client-Side';
        Integer requestedSize = request?.pageSize != null && request.pageSize > 0
            ? request.pageSize : (gridDef?.appcg__Page_Size__c != null
                ? Integer.valueOf(gridDef.appcg__Page_Size__c) : 20);
        Integer pageSize = clientSide ? cfg.recordLimit : Math.min(requestedSize, MAX_PAGE_SIZE);
        Integer startIndex = clientSide ? 0 : Math.max(0, request?.startIndex ?? 0);
        appcg.GridDataProviderTypesV1.PageResult result = new appcg.GridDataProviderTypesV1.PageResult();
        result.records = new List<Map<String, Object>>();

        String whereClause = cfg.whereClause;
        if (String.isNotBlank(cfg.parentMatchColumn) && String.isNotBlank(request?.context?.parentId)) {
            String parentValue = resolveParentMatchValue(cfg, request.context);
            if (String.isBlank(parentValue)) {
                result.totalCount = 0;
                return result;
            }
            String predicate = cfg.parentMatchColumn + ' = \'' + escapeQueryValue(parentValue) + '\'';
            whereClause = String.isBlank(whereClause) ? predicate : whereClause + ' AND ' + predicate;
        }

        QuickBooksClient client = new QuickBooksClient();
        Integer totalCount = Math.min(cfg.recordLimit, client.count(cfg.realmId, cfg.resource, whereClause));
        if (totalCount == 0) {
            result.totalCount = 0;
            return result;
        }
        Boolean searching = String.isNotBlank(request?.searchTerm);
        if (!searching && !clientSide) {
            result.totalCount = totalCount;
            if (startIndex < totalCount) {
                Integer fetchSize = Math.min(pageSize, totalCount - startIndex);
                result.records = parseQuickBooksRecords(cfg.resource,
                    client.query(cfg.realmId, cfg.resource, startIndex + 1, fetchSize, whereClause));
            }
            return result;
        }

        Integer examined = 0;
        Integer matched = 0;
        while (examined < totalCount) {
            Integer fetchSize = Math.min(MAX_PAGE_SIZE, totalCount - examined);
            List<Map<String, Object>> batch = parseQuickBooksRecords(cfg.resource,
                client.query(cfg.realmId, cfg.resource, examined + 1, fetchSize, whereClause));
            if (batch.isEmpty()) break;
            for (Map<String, Object> row : batch) {
                if (!searching || matchesSearch(row, request.searchTerm.toLowerCase())) {
                    if (clientSide || (matched >= startIndex && matched < startIndex + pageSize)) {
                        result.records.add(row);
                    }
                    matched++;
                }
            }
            examined += batch.size();
            if (batch.size() < fetchSize) break;
        }
        result.totalCount = searching ? matched : examined;
        return result;
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

                if ('Invoice'.equals(entityKey)) {
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
                } else if ('Customer'.equals(entityKey)) {
                    row.put('displayName', str(orig.get('DisplayName')));
                    row.put('email', nestedStr(orig, 'PrimaryEmailAddr', 'Address'));
                    row.put('phone', nestedStr(orig, 'PrimaryPhone', 'FreeFormNumber'));
                    row.put('companyName', str(orig.get('CompanyName')));
                    row.put('balance', dec(orig.get('Balance')));
                    row.put('active', orig.containsKey('Active') ? (Boolean) orig.get('Active') : true);
                } else if ('Payment'.equals(entityKey)) {
                    row.put('paymentRefNum', str(orig.get('PaymentRefNum')));
                    row.put('customerName', nestedStr(orig, 'CustomerRef', 'name'));
                    row.put('txnDate', str(orig.get('TxnDate')));
                    row.put('totalAmt', dec(orig.get('TotalAmt')));
                    row.put('paymentMethod', nestedStr(orig, 'PaymentMethodRef', 'name'));
                } else if ('Item'.equals(entityKey)) {
                    row.put('name', str(orig.get('Name')));
                    row.put('sku', str(orig.get('Sku')));
                    row.put('unitPrice', dec(orig.get('UnitPrice')));
                    row.put('qtyOnHand', dec(orig.get('QtyOnHand')));
                    row.put('type', str(orig.get('Type')));
                    row.put('active', orig.containsKey('Active') ? (Boolean) orig.get('Active') : true);
                } else if ('Bill'.equals(entityKey)) {
                    row.put('docNumber', str(orig.get('DocNumber')));
                    row.put('vendorName', nestedStr(orig, 'VendorRef', 'name'));
                    row.put('txnDate', str(orig.get('TxnDate')));
                    row.put('dueDate', str(orig.get('DueDate')));
                    row.put('totalAmt', dec(orig.get('TotalAmt')));
                    row.put('balance', dec(orig.get('Balance')));
                } else {
                    for (String spec : extraFieldSpecs(entityKey)) {
                        List<String> parts = spec.split('\\|');
                        Object value = fieldValue(orig, parts[3]);
                        if (parts[2] == 'NUMBER') {
                            value = value == null ? null : dec(value);
                        } else if (parts[2] == 'BOOLEAN') {
                            value = value == null ? null : (Boolean) value;
                        } else {
                            value = str(value);
                        }
                        row.put(parts[0], value);
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

        if ('Invoice'.equals(resource)) {
            columns.add(column('docNumber', 'Invoice Number', 'TEXT', true, true, '120px'));
            columns.add(column('customerName', 'Customer', 'TEXT', true, true, '200px'));
            columns.add(column('txnDate', 'Invoice Date', 'TEXT', true, true, '130px'));
            columns.add(column('dueDate', 'Due Date', 'TEXT', true, true, '130px'));
            columns.add(column('totalAmt', 'Amount', 'NUMBER', true, true, '130px'));
            columns.add(column('balance', 'Balance Due', 'NUMBER', true, true, '130px'));
            columns.add(column('status', 'Status', 'TEXT', true, true, '110px'));
            columns.add(column('emailStatus', 'Email Status', 'TEXT', true, true, '120px'));
        } else if ('Customer'.equals(resource)) {
            columns.add(column('displayName', 'Name', 'TEXT', true, true, '200px'));
            columns.add(column('email', 'Email', 'EMAIL', true, true, '220px'));
            columns.add(column('phone', 'Phone', 'PHONE', true, true, '150px'));
            columns.add(column('companyName', 'Company', 'TEXT', true, true, '180px'));
            columns.add(column('balance', 'Open Balance', 'NUMBER', true, true, '130px'));
            columns.add(column('active', 'Active?', 'BOOLEAN', true, true, '100px'));
        } else if ('Payment'.equals(resource)) {
            columns.add(column('paymentRefNum', 'Payment #', 'TEXT', true, true, '140px'));
            columns.add(column('customerName', 'Customer', 'TEXT', true, true, '200px'));
            columns.add(column('txnDate', 'Payment Date', 'TEXT', true, true, '130px'));
            columns.add(column('totalAmt', 'Amount', 'NUMBER', true, true, '130px'));
            columns.add(column('paymentMethod', 'Payment Method', 'TEXT', true, true, '150px'));
        } else if ('Item'.equals(resource)) {
            columns.add(column('name', 'Name', 'TEXT', true, true, '220px'));
            columns.add(column('sku', 'SKU', 'TEXT', true, true, '130px'));
            columns.add(column('unitPrice', 'Price ($)', 'NUMBER', true, true, '120px'));
            columns.add(column('qtyOnHand', 'Qty on Hand', 'NUMBER', true, true, '120px'));
            columns.add(column('type', 'Item Type', 'TEXT', true, true, '130px'));
            columns.add(column('active', 'Active?', 'BOOLEAN', true, true, '100px'));
        } else if ('Bill'.equals(resource)) {
            columns.add(column('docNumber', 'Bill #', 'TEXT', true, true, '120px'));
            columns.add(column('vendorName', 'Vendor', 'TEXT', true, true, '200px'));
            columns.add(column('txnDate', 'Bill Date', 'TEXT', true, true, '130px'));
            columns.add(column('dueDate', 'Due Date', 'TEXT', true, true, '130px'));
            columns.add(column('totalAmt', 'Amount', 'NUMBER', true, true, '130px'));
            columns.add(column('balance', 'Balance Due', 'NUMBER', true, true, '130px'));
        } else {
            for (String spec : extraFieldSpecs(resource)) {
                List<String> parts = spec.split('\\|');
                columns.add(column(parts[0], parts[1], parts[2], true, true, parts[4]));
            }
        }

        return columns;
    }

    // ─── Helpers ──────────────────────────────────────────────────────

    @TestVisible
    private static String resolveEntityName(String resource) {
        String normalized = String.isBlank(resource) ? '' : resource.trim().toLowerCase().replace('_', '').replace('-', '');
        Map<String, String> names = new Map<String, String>{
            'invoice' => 'Invoice', 'invoices' => 'Invoice',
            'customer' => 'Customer', 'customers' => 'Customer',
            'payment' => 'Payment', 'payments' => 'Payment',
            'item' => 'Item', 'items' => 'Item',
            'bill' => 'Bill', 'bills' => 'Bill',
            'vendor' => 'Vendor', 'vendors' => 'Vendor',
            'estimate' => 'Estimate', 'estimates' => 'Estimate',
            'salesreceipt' => 'SalesReceipt', 'salesreceipts' => 'SalesReceipt',
            'creditmemo' => 'CreditMemo', 'creditmemos' => 'CreditMemo',
            'purchaseorder' => 'PurchaseOrder', 'purchaseorders' => 'PurchaseOrder',
            'account' => 'Account', 'accounts' => 'Account',
            'deposit' => 'Deposit', 'deposits' => 'Deposit',
            'journalentry' => 'JournalEntry', 'journalentries' => 'JournalEntry',
            'purchase' => 'Purchase', 'purchases' => 'Purchase'
        };
        if (!names.containsKey(normalized)) {
            throw new ProviderException('Unsupported QuickBooks resource: ' + resource);
        }
        return names.get(normalized);
    }

    // id | label | grid type | QuickBooks field path | width
    private static List<String> extraFieldSpecs(String entityName) {
        if (entityName == 'Vendor') return new List<String>{
            'displayName|Name|TEXT|DisplayName|200px', 'companyName|Company|TEXT|CompanyName|180px',
            'email|Email|EMAIL|PrimaryEmailAddr.Address|220px',
            'phone|Phone|PHONE|PrimaryPhone.FreeFormNumber|150px',
            'balance|Balance|NUMBER|Balance|130px', 'active|Active|BOOLEAN|Active|100px'
        };
        if (entityName == 'Estimate') return new List<String>{
            'docNumber|Estimate Number|TEXT|DocNumber|140px', 'customerName|Customer|TEXT|CustomerRef.name|200px',
            'txnDate|Date|TEXT|TxnDate|130px', 'expirationDate|Expiration|TEXT|ExpirationDate|130px',
            'totalAmt|Amount|NUMBER|TotalAmt|130px', 'status|Status|TEXT|TxnStatus|110px'
        };
        if (entityName == 'SalesReceipt' || entityName == 'CreditMemo') return new List<String>{
            'docNumber|Number|TEXT|DocNumber|140px', 'customerName|Customer|TEXT|CustomerRef.name|200px',
            'txnDate|Date|TEXT|TxnDate|130px', 'totalAmt|Amount|NUMBER|TotalAmt|130px',
            'balance|Balance|NUMBER|Balance|130px', 'privateNote|Memo|TEXT|PrivateNote|220px'
        };
        if (entityName == 'PurchaseOrder') return new List<String>{
            'docNumber|PO Number|TEXT|DocNumber|140px', 'vendorName|Vendor|TEXT|VendorRef.name|200px',
            'txnDate|Date|TEXT|TxnDate|130px', 'dueDate|Due Date|TEXT|DueDate|130px',
            'totalAmt|Amount|NUMBER|TotalAmt|130px', 'status|Status|TEXT|POStatus|110px'
        };
        if (entityName == 'Account') return new List<String>{
            'name|Name|TEXT|Name|200px', 'accountNumber|Account Number|TEXT|AcctNum|140px',
            'accountType|Type|TEXT|AccountType|150px', 'accountSubType|Subtype|TEXT|AccountSubType|170px',
            'currentBalance|Balance|NUMBER|CurrentBalance|130px', 'active|Active|BOOLEAN|Active|100px'
        };
        if (entityName == 'Deposit') return new List<String>{
            'txnDate|Date|TEXT|TxnDate|130px', 'accountName|Account|TEXT|DepositToAccountRef.name|200px',
            'totalAmt|Amount|NUMBER|TotalAmt|130px', 'privateNote|Memo|TEXT|PrivateNote|220px'
        };
        if (entityName == 'JournalEntry') return new List<String>{
            'docNumber|Journal Number|TEXT|DocNumber|140px', 'txnDate|Date|TEXT|TxnDate|130px',
            'totalAmt|Amount|NUMBER|TotalAmt|130px', 'privateNote|Memo|TEXT|PrivateNote|220px'
        };
        if (entityName == 'Purchase') return new List<String>{
            'txnDate|Date|TEXT|TxnDate|130px', 'paymentType|Payment Type|TEXT|PaymentType|140px',
            'accountName|Account|TEXT|AccountRef.name|200px', 'entityName|Payee|TEXT|EntityRef.name|200px',
            'totalAmt|Amount|NUMBER|TotalAmt|130px', 'privateNote|Memo|TEXT|PrivateNote|220px'
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

    @TestVisible
    private static String resolveParentMatchValue(
        QuickBooksConfig cfg, appcg.GridDataProviderTypesV1.ProviderContext context
    ) {
        if (context == null || String.isBlank(context.parentId)) return null;
        if (cfg.parentMatchField == 'Id' || String.isBlank(cfg.parentMatchField)) return context.parentId;
        try {
            Id parentId = (Id) context.parentId;
            Schema.DescribeSObjectResult describe = parentId.getSObjectType().getDescribe();
            String fieldName;
            for (String candidate : describe.fields.getMap().keySet()) {
                if (candidate.equalsIgnoreCase(cfg.parentMatchField)) {
                    fieldName = candidate;
                    break;
                }
            }
            if (fieldName == null) {
                throw new ProviderException('Parent match field "' + cfg.parentMatchField + '" does not exist on ' + describe.getName() + '.');
            }
            List<SObject> parents = Database.query('SELECT ' + fieldName + ' FROM ' + describe.getName() +
                ' WHERE Id = :parentId WITH USER_MODE LIMIT 1');
            Object value = parents.isEmpty() ? null : parents[0].get(fieldName);
            return value == null ? null : String.valueOf(value);
        } catch (ProviderException e) {
            throw e;
        } catch (Exception e) {
            throw new ProviderException('Unable to resolve the parent match value: ' + e.getMessage());
        }
    }

    private static String escapeQueryValue(String value) {
        return String.escapeSingleQuotes(value);
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

    private static Boolean matchesSearch(Map<String, Object> record, String lowerTerm) {
        for (String key : record.keySet()) {
            if ('Id'.equalsIgnoreCase(key)) continue;
            Object value = record.get(key);
            if (value != null && String.valueOf(value).toLowerCase().contains(lowerTerm)) {
                return true;
            }
        }
        return false;
    }
}
