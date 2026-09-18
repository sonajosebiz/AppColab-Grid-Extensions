global with sharing class XeroGridDataProvider implements appcg.GridDataProviderV1 {

    public class ProviderException extends Exception {}


    // ─── Instance Cache ───────────────────────────────────────────────
    // getCapabilities() and getData() are called on the same instance during
    // the initial grid load. We read from Xero once in getCapabilities() and
    // reuse the cached data in getData() to avoid a second callout.

    private List<Map<String, Object>> cachedRecords;

    // ─── Config ───────────────────────────────────────────────────────

    @TestVisible
    private class XeroConfig {
        public String tenantId;
        public String resource;
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
    private static XeroConfig parseConfig(appcg.GridDataProviderTypesV1.ProviderContext context) {
        appcg__Grid_Definition__c gridDef = getGridDefinition(context);
        String configJson = gridDef != null ? gridDef.appcg__Data_Provider_Config__c : null;
        if (String.isBlank(configJson)) {
            throw new ProviderException(
                'Xero provider requires configuration. ' +
                'Set Data Provider Configuration with {"tenantId":"xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx","resource":"invoices"}'
            );
        }

        XeroConfig cfg = new XeroConfig();
        cfg.resource = 'invoices';

        try {
            Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(configJson);
            if (raw.containsKey('tenantId')) {
                cfg.tenantId = String.valueOf(raw.get('tenantId')).trim();
            }

            if (raw.containsKey('resource')) {
                cfg.resource = String.valueOf(raw.get('resource')).trim().toLowerCase();
            }

            if (raw.containsKey('where')) {
                cfg.whereClause = String.valueOf(raw.get('where')).trim();
            } else if (raw.containsKey('whereClause')) {
                cfg.whereClause = String.valueOf(raw.get('whereClause')).trim();
            }
        } catch (Exception e) {
            throw new ProviderException('Invalid Xero provider configuration: ' + e.getMessage());
        }

        if (String.isBlank(cfg.tenantId)) {
            throw new ProviderException(
                'tenantId is required in the Xero provider configuration. ' +
                'You can find your Tenant ID by calling GET /connections from the Xero API.'
            );
        }

        return cfg;
    }

    // ─── GridDataProviderV1 ───────────────────────────────────────────

    global appcg.GridDataProviderTypesV1.Capabilities getCapabilities(
        appcg.GridDataProviderTypesV1.ProviderContext context
    ) {
        XeroConfig cfg = parseConfig(context);
        try {
            XeroClient client = new XeroClient();
            Map<String, Object> response = fetchResourceData(client, cfg, 1);

            cachedRecords = parseXeroRecords(cfg.resource, response);

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
            Integer pageNumber = (startIndex / 100) + 1;

            if (cachedRecords != null && startIndex == 0) {
                records = cachedRecords;
                cachedRecords = null;
            } else {
                XeroConfig cfg = parseConfig(request.context);
                XeroClient client = new XeroClient();
                Map<String, Object> response = fetchResourceData(client, cfg, pageNumber);
                records = parseXeroRecords(cfg.resource, response);
            }

            while (records != null && records.size() > pageSize) {
                records.remove(records.size() - 1);
            }

            // Estimate total count based on 100-record page blocks
            if (records != null && records.size() >= pageSize) {
                totalCount = startIndex + records.size() + 1;
            } else {
                totalCount = startIndex + (records != null ? records.size() : 0);
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

    // ─── Data Fetcher ─────────────────────────────────────────────────

    private static Map<String, Object> fetchResourceData(XeroClient client, XeroConfig cfg, Integer page) {
        if ('invoices'.equals(cfg.resource) || 'invoice'.equals(cfg.resource)) {
            String whereFilter = cfg.whereClause;
            if (String.isBlank(whereFilter)) {
                whereFilter = 'Type=="ACCREC"';
            }
            return client.listInvoices(cfg.tenantId, page, whereFilter);
        }
        if ('bills'.equals(cfg.resource) || 'bill'.equals(cfg.resource)) {
            return client.listInvoices(cfg.tenantId, page, 'Type=="ACCPAY"');
        }
        if ('contacts'.equals(cfg.resource) || 'contact'.equals(cfg.resource)) {
            return client.listContacts(cfg.tenantId, page, null);
        }
        if ('accounts'.equals(cfg.resource) || 'account'.equals(cfg.resource)) {
            return client.listAccounts(cfg.tenantId, cfg.whereClause);
        }
        if ('payments'.equals(cfg.resource) || 'payment'.equals(cfg.resource)) {
            return client.listPayments(cfg.tenantId, page, null);
        }
        if ('banktransactions'.equals(cfg.resource) || 'banktransaction'.equals(cfg.resource)) {
            return client.listBankTransactions(cfg.tenantId, page, null);
        }
        // Default to invoices
        return client.listInvoices(cfg.tenantId, page, cfg.whereClause);
    }

    // ─── Record Parsers ───────────────────────────────────────────────

    @TestVisible
    private static List<Map<String, Object>> parseXeroRecords(
        String resource,
        Map<String, Object> response
    ) {
        List<Map<String, Object>> records = new List<Map<String, Object>>();
        if (response == null) {
            return records;
        }

        String entityKey = resolveEntityKey(resource);
        if (!response.containsKey(entityKey) || response.get(entityKey) == null) {
            return records;
        }

        List<Object> rawList = (List<Object>) response.get(entityKey);
        for (Object item : rawList) {
            if (item instanceof Map<String, Object>) {
                Map<String, Object> orig = (Map<String, Object>) item;
                Map<String, Object> row = new Map<String, Object>();

                if ('invoices'.equals(resource) || 'invoice'.equals(resource) ||
                    'bills'.equals(resource) || 'bill'.equals(resource)) {
                    row.put('Id', str(orig.get('InvoiceID')));
                    row.put('invoiceNumber', str(orig.get('InvoiceNumber')));
                    row.put('reference', str(orig.get('Reference')));
                    row.put('contactName', nestedStr(orig, 'Contact', 'Name'));
                    row.put('date', str(orig.get('Date')));
                    row.put('dueDate', str(orig.get('DueDate')));
                    row.put('total', dec(orig.get('Total')));
                    row.put('amountDue', dec(orig.get('AmountDue')));
                    row.put('amountPaid', dec(orig.get('AmountPaid')));
                    row.put('status', str(orig.get('Status')));
                    row.put('currencyCode', str(orig.get('CurrencyCode')));
                } else if ('contacts'.equals(resource) || 'contact'.equals(resource)) {
                    row.put('Id', str(orig.get('ContactID')));
                    row.put('name', str(orig.get('Name')));
                    row.put('firstName', str(orig.get('FirstName')));
                    row.put('lastName', str(orig.get('LastName')));
                    row.put('emailAddress', str(orig.get('EmailAddress')));
                    row.put('contactStatus', str(orig.get('ContactStatus')));
                    row.put('isSupplier', orig.containsKey('IsSupplier') ? (Boolean) orig.get('IsSupplier') : false);
                    row.put('isCustomer', orig.containsKey('IsCustomer') ? (Boolean) orig.get('IsCustomer') : false);

                    // Phone numbers — Xero nests phones in an array
                    if (orig.containsKey('Phones') && orig.get('Phones') instanceof List<Object>) {
                        List<Object> phones = (List<Object>) orig.get('Phones');
                        for (Object phoneObj : phones) {
                            Map<String, Object> phone = (Map<String, Object>) phoneObj;
                            if ('DEFAULT'.equals(str(phone.get('PhoneType')))) {
                                row.put('phone', str(phone.get('PhoneNumber')));
                                break;
                            }
                        }
                    }
                    if (!row.containsKey('phone')) {
                        row.put('phone', '');
                    }

                    // Outstanding balance
                    if (orig.containsKey('Balances') && orig.get('Balances') instanceof Map<String, Object>) {
                        Map<String, Object> balances = (Map<String, Object>) orig.get('Balances');
                        if (balances.containsKey('AccountsReceivable') && balances.get('AccountsReceivable') instanceof Map<String, Object>) {
                            Map<String, Object> ar = (Map<String, Object>) balances.get('AccountsReceivable');
                            row.put('outstandingBalance', dec(ar.get('Outstanding')));
                        }
                    }
                    if (!row.containsKey('outstandingBalance')) {
                        row.put('outstandingBalance', 0);
                    }
                } else if ('accounts'.equals(resource) || 'account'.equals(resource)) {
                    row.put('Id', str(orig.get('AccountID')));
                    row.put('code', str(orig.get('Code')));
                    row.put('name', str(orig.get('Name')));
                    row.put('type', str(orig.get('Type')));
                    row.put('taxType', str(orig.get('TaxType')));
                    row.put('status', str(orig.get('Status')));
                    row.put('accountClass', str(orig.get('Class')));
                    row.put('description', str(orig.get('Description')));
                    row.put('enablePayments', orig.containsKey('EnablePaymentsToAccount')
                        ? (Boolean) orig.get('EnablePaymentsToAccount') : false);
                } else if ('payments'.equals(resource) || 'payment'.equals(resource)) {
                    row.put('Id', str(orig.get('PaymentID')));
                    row.put('date', str(orig.get('Date')));
                    row.put('invoiceNumber', nestedStr(orig, 'Invoice', 'InvoiceNumber'));
                    row.put('accountName', nestedStr(orig, 'Account', 'Name'));
                    row.put('accountCode', nestedStr(orig, 'Account', 'Code'));
                    row.put('amount', dec(orig.get('Amount')));
                    row.put('currencyRate', dec(orig.get('CurrencyRate')));
                    row.put('reference', str(orig.get('Reference')));
                    row.put('status', str(orig.get('Status')));
                    row.put('paymentType', str(orig.get('PaymentType')));
                } else if ('banktransactions'.equals(resource) || 'banktransaction'.equals(resource)) {
                    row.put('Id', str(orig.get('BankTransactionID')));
                    row.put('date', str(orig.get('Date')));
                    row.put('contactName', nestedStr(orig, 'Contact', 'Name'));
                    row.put('accountName', nestedStr(orig, 'BankAccount', 'Name'));
                    row.put('type', str(orig.get('Type')));
                    row.put('reference', str(orig.get('Reference')));
                    row.put('total', dec(orig.get('Total')));
                    row.put('status', str(orig.get('Status')));
                    row.put('isReconciled', orig.containsKey('IsReconciled') ? (Boolean) orig.get('IsReconciled') : false);
                } else {
                    // Generic fallback
                    for (String k : orig.keySet()) {
                        Object v = orig.get(k);
                        if (!(v instanceof Map<String, Object>) && !(v instanceof List<Object>)) {
                            row.put(k, v);
                        }
                    }
                    if (!row.containsKey('Id')) {
                        row.put('Id', String.valueOf(records.size() + 1));
                    }
                }
                records.add(row);
            }
        }
        return records;
    }

    // ─── Column Definitions ───────────────────────────────────────────

    private static List<appcg.GridDataProviderTypesV1.ColumnDefinition> buildColumnDefinitions(String resource) {
        List<appcg.GridDataProviderTypesV1.ColumnDefinition> columns =
            new List<appcg.GridDataProviderTypesV1.ColumnDefinition>();

        // Hidden Id column
        columns.add(column('Id', 'ID', 'TEXT', true, false, '100px'));

        if ('invoices'.equals(resource) || 'invoice'.equals(resource)) {
            columns.add(column('invoiceNumber', 'Invoice Number', 'TEXT', true, true, '130px'));
            columns.add(column('contactName', 'Customer', 'TEXT', true, true, '200px'));
            columns.add(column('reference', 'Reference', 'TEXT', true, true, '140px'));
            columns.add(column('date', 'Date', 'TEXT', true, true, '120px'));
            columns.add(column('dueDate', 'Due Date', 'TEXT', true, true, '120px'));
            columns.add(column('total', 'Total', 'NUMBER', true, true, '120px'));
            columns.add(column('amountDue', 'Amount Due', 'NUMBER', true, true, '130px'));
            columns.add(column('amountPaid', 'Amount Paid', 'NUMBER', true, true, '130px'));
            columns.add(column('status', 'Status', 'TEXT', true, true, '120px'));
            columns.add(column('currencyCode', 'Currency', 'TEXT', true, true, '100px'));
        } else if ('bills'.equals(resource) || 'bill'.equals(resource)) {
            columns.add(column('invoiceNumber', 'Bill #', 'TEXT', true, true, '130px'));
            columns.add(column('contactName', 'Supplier', 'TEXT', true, true, '200px'));
            columns.add(column('reference', 'Reference', 'TEXT', true, true, '140px'));
            columns.add(column('date', 'Date', 'TEXT', true, true, '120px'));
            columns.add(column('dueDate', 'Due Date', 'TEXT', true, true, '120px'));
            columns.add(column('total', 'Total', 'NUMBER', true, true, '120px'));
            columns.add(column('amountDue', 'Amount Due', 'NUMBER', true, true, '130px'));
            columns.add(column('status', 'Status', 'TEXT', true, true, '120px'));
        } else if ('contacts'.equals(resource) || 'contact'.equals(resource)) {
            columns.add(column('name', 'Name', 'TEXT', true, true, '220px'));
            columns.add(column('firstName', 'First Name', 'TEXT', true, true, '140px'));
            columns.add(column('lastName', 'Last Name', 'TEXT', true, true, '140px'));
            columns.add(column('emailAddress', 'Email', 'EMAIL', true, true, '220px'));
            columns.add(column('phone', 'Phone', 'PHONE', true, true, '150px'));
            columns.add(column('contactStatus', 'Status', 'TEXT', true, true, '120px'));
            columns.add(column('isCustomer', 'Customer?', 'BOOLEAN', true, true, '100px'));
            columns.add(column('isSupplier', 'Supplier?', 'BOOLEAN', true, true, '100px'));
        } else if ('accounts'.equals(resource) || 'account'.equals(resource)) {
            columns.add(column('code', 'Code', 'TEXT', true, true, '100px'));
            columns.add(column('name', 'Account Name', 'TEXT', true, true, '220px'));
            columns.add(column('type', 'Type', 'TEXT', true, true, '150px'));
            columns.add(column('accountClass', 'Class', 'TEXT', true, true, '120px'));
            columns.add(column('taxType', 'Tax Type', 'TEXT', true, true, '130px'));
            columns.add(column('description', 'Description', 'TEXT', true, true, '250px'));
            columns.add(column('status', 'Status', 'TEXT', true, true, '110px'));
            columns.add(column('enablePayments', 'Payments Enabled', 'BOOLEAN', true, true, '130px'));
        } else if ('payments'.equals(resource) || 'payment'.equals(resource)) {
            columns.add(column('date', 'Date', 'TEXT', true, true, '120px'));
            columns.add(column('invoiceNumber', 'Invoice Number', 'TEXT', true, true, '130px'));
            columns.add(column('accountName', 'Account', 'TEXT', true, true, '180px'));
            columns.add(column('accountCode', 'Account Code', 'TEXT', true, true, '120px'));
            columns.add(column('amount', 'Amount', 'NUMBER', true, true, '120px'));
            columns.add(column('reference', 'Reference', 'TEXT', true, true, '150px'));
            columns.add(column('status', 'Status', 'TEXT', true, true, '110px'));
            columns.add(column('paymentType', 'Payment Type', 'TEXT', true, true, '130px'));
        } else if ('banktransactions'.equals(resource) || 'banktransaction'.equals(resource)) {
            columns.add(column('date', 'Date', 'TEXT', true, true, '120px'));
            columns.add(column('contactName', 'Contact', 'TEXT', true, true, '200px'));
            columns.add(column('accountName', 'Bank Account', 'TEXT', true, true, '180px'));
            columns.add(column('type', 'Type', 'TEXT', true, true, '120px'));
            columns.add(column('reference', 'Reference', 'TEXT', true, true, '150px'));
            columns.add(column('total', 'Total', 'NUMBER', true, true, '120px'));
            columns.add(column('status', 'Status', 'TEXT', true, true, '110px'));
            columns.add(column('isReconciled', 'Reconciled', 'BOOLEAN', true, true, '110px'));
        } else {
            columns.add(column('Name', 'Name', 'TEXT', true, true, '200px'));
        }

        return columns;
    }

    // ─── Helpers ──────────────────────────────────────────────────────

    @TestVisible
    private static String resolveEntityKey(String resource) {
        if ('invoices'.equals(resource) || 'invoice'.equals(resource)) return 'Invoices';
        if ('bills'.equals(resource) || 'bill'.equals(resource)) return 'Invoices';
        if ('contacts'.equals(resource) || 'contact'.equals(resource)) return 'Contacts';
        if ('accounts'.equals(resource) || 'account'.equals(resource)) return 'Accounts';
        if ('payments'.equals(resource) || 'payment'.equals(resource)) return 'Payments';
        if ('banktransactions'.equals(resource) || 'banktransaction'.equals(resource)) return 'BankTransactions';
        return 'Invoices';
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
