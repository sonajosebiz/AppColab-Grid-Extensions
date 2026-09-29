@IsTest
private class QuickBooksGridDataProviderTest {

    private class QueryMock implements HttpCalloutMock {
        Integer total;
        Map<Integer, String> pages = new Map<Integer, String>();
        List<String> queries = new List<String>();

        public HttpResponse respond(HttpRequest request) {
            String endpoint = request.getEndpoint();
            String sql = EncodingUtil.urlDecode(endpoint.substring(endpoint.indexOf('query=') + 6), 'UTF-8');
            queries.add(sql);
            if (sql.toLowerCase().contains('count(*)')) {
                return QuickBooksTestSupport.makeResponse(200,
                    '{"QueryResponse":{"totalCount":' + total + '}}');
            }
            for (Integer startPosition : pages.keySet()) {
                if (sql.toLowerCase().contains('startposition ' + startPosition + ' ')) {
                    return QuickBooksTestSupport.makeResponse(200, pages.get(startPosition));
                }
            }
            return QuickBooksTestSupport.makeResponse(400, '{"error":"Unexpected query"}');
        }
    }

    private static void setupConfig() {
    }

    private static String sampleInvoicesJson() {
        return '{"QueryResponse":{"Invoice":[' +
            '{"Id":"1","DocNumber":"1001","CustomerRef":{"name":"Amy Bird"},"TxnDate":"2026-08-20","DueDate":"2099-09-20","TotalAmt":450.0,"Balance":450.0,"EmailStatus":"NotSent"},' +
            '{"Id":"2","DocNumber":"1002","CustomerRef":{"name":"Bill Wind"},"TxnDate":"2026-08-21","DueDate":"2026-08-01","TotalAmt":300.0,"Balance":0.0,"EmailStatus":"Sent"}' +
        ']}}';
    }

    private static String sampleCustomersJson() {
        return '{"QueryResponse":{"Customer":[' +
            '{"Id":"1","DisplayName":"Amy Bird","PrimaryEmailAddr":{"Address":"amy@birds.com"},"PrimaryPhone":{"FreeFormNumber":"555-1234"},"CompanyName":"Bird Sanctuary","Balance":450.0,"Active":true}' +
        ']}}';
    }

    private static String samplePaymentsJson() {
        return '{"QueryResponse":{"Payment":[' +
            '{"Id":"10","PaymentRefNum":"PAY-100","CustomerRef":{"name":"Amy Bird"},"TxnDate":"2026-08-25","TotalAmt":300.0,"PaymentMethodRef":{"name":"CreditCard"}}' +
        ']}}';
    }

    private static String sampleItemsJson() {
        return '{"QueryResponse":{"Item":[' +
            '{"Id":"5","Name":"Concrete Pipe","Sku":"PIPE-01","UnitPrice":25.0,"QtyOnHand":50,"Type":"Inventory","Active":true}' +
        ']}}';
    }

    private static String sampleBillsJson() {
        return '{"QueryResponse":{"Bill":[' +
            '{"Id":"20","DocNumber":"BILL-500","VendorRef":{"name":"PG&E"},"TxnDate":"2026-08-15","DueDate":"2026-09-15","TotalAmt":120.50,"Balance":120.50}' +
        ']}}';
    }

    @IsTest
    static void getCapabilities_and_getData_invoices_withSearch() {
        setupConfig();

        QuickBooksTestSupport.RoutingMock mock = new QuickBooksTestSupport.RoutingMock();
        mock.byEndpointContains.put('/v3/company/9341452000/query', QuickBooksTestSupport.makeResponse(200, sampleInvoicesJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        QuickBooksGridDataProvider provider = new QuickBooksGridDataProvider();
        QuickBooksGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"realmId":"9341452000","resource":"invoices"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(ctx);

        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;
        req.searchTerm = '1001';
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assertEquals(9, caps.columns.size(), 'Invoices should have 9 columns');
        System.assertEquals(true, caps.supportsServerPagination);
        System.assertEquals(1000, caps.maxPageSize);
        System.assertEquals(1, page.records.size(), 'Search term 1001 should match 1 invoice');
        System.assertEquals('1001', page.records[0].get('docNumber'));
        System.assertEquals('Amy Bird', page.records[0].get('customerName'));
        System.assertEquals('Open', page.records[0].get('status'));
    }

    @IsTest
    static void getData_customers() {
        setupConfig();

        QuickBooksTestSupport.RoutingMock mock = new QuickBooksTestSupport.RoutingMock();
        mock.byEndpointContains.put('/v3/company/9341452000/query', QuickBooksTestSupport.makeResponse(200, sampleCustomersJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        QuickBooksGridDataProvider provider = new QuickBooksGridDataProvider();
        QuickBooksGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"realmId":"9341452000","resource":"customers"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(ctx);

        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assertEquals(1, page.records.size());
        System.assertEquals('Amy Bird', page.records[0].get('displayName'));
        System.assertEquals('amy@birds.com', page.records[0].get('email'));
        System.assertEquals(450.0, page.records[0].get('balance'));
    }

    @IsTest
    static void getData_payments() {
        setupConfig();

        QuickBooksTestSupport.RoutingMock mock = new QuickBooksTestSupport.RoutingMock();
        mock.byEndpointContains.put('/v3/company/9341452000/query', QuickBooksTestSupport.makeResponse(200, samplePaymentsJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        QuickBooksGridDataProvider provider = new QuickBooksGridDataProvider();
        QuickBooksGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"realmId":"9341452000","resource":"payments"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(ctx);

        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assertEquals(1, page.records.size());
        System.assertEquals('PAY-100', page.records[0].get('paymentRefNum'));
        System.assertEquals('CreditCard', page.records[0].get('paymentMethod'));
    }

    @IsTest
    static void getData_items() {
        setupConfig();

        QuickBooksTestSupport.RoutingMock mock = new QuickBooksTestSupport.RoutingMock();
        mock.byEndpointContains.put('/v3/company/9341452000/query', QuickBooksTestSupport.makeResponse(200, sampleItemsJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        QuickBooksGridDataProvider provider = new QuickBooksGridDataProvider();
        QuickBooksGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"realmId":"9341452000","resource":"items"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(ctx);

        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assertEquals(1, page.records.size());
        System.assertEquals('Concrete Pipe', page.records[0].get('name'));
        System.assertEquals('PIPE-01', page.records[0].get('sku'));
    }

    @IsTest
    static void getData_bills() {
        setupConfig();

        QuickBooksTestSupport.RoutingMock mock = new QuickBooksTestSupport.RoutingMock();
        mock.byEndpointContains.put('/v3/company/9341452000/query', QuickBooksTestSupport.makeResponse(200, sampleBillsJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        QuickBooksGridDataProvider provider = new QuickBooksGridDataProvider();
        QuickBooksGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"realmId":"9341452000","resource":"bills"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(ctx);

        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assertEquals(1, page.records.size());
        System.assertEquals('BILL-500', page.records[0].get('docNumber'));
        System.assertEquals('PG&E', page.records[0].get('vendorName'));
    }

    @IsTest
    static void parseConfig_validationErrors() {
        QuickBooksGridDataProvider.testGridDef = null;
        try {
            QuickBooksGridDataProvider.parseConfig(null);
            System.assert(false, 'Expected GridUiException');
        } catch (QuickBooksGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('requires configuration'));
        }

        QuickBooksGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"resource":"invoices"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();
        try {
            QuickBooksGridDataProvider.parseConfig(ctx);
            System.assert(false, 'Expected GridUiException');
        } catch (QuickBooksGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('realmId'));
        }

        QuickBooksGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"realmId":"9341452000","resource":"not-a-resource"}'
        );
        try {
            QuickBooksGridDataProvider.parseConfig(ctx);
            System.assert(false, 'Expected unsupported resource error');
        } catch (QuickBooksGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('Unsupported QuickBooks resource'));
        }
    }

    @IsTest
    static void serverPagination_usesRequestedOffsetAndLimit() {
        QueryMock mock = new QueryMock();
        mock.total = 3;
        mock.pages.put(2, '{"QueryResponse":{"Invoice":[' +
            '{"Id":"2","DocNumber":"INV-2","Balance":0,"TotalAmt":20},' +
            '{"Id":"3","DocNumber":"INV-3","Balance":0,"TotalAmt":30}]}}');
        Test.setMock(HttpCalloutMock.class, mock);
        QuickBooksGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"realmId":"9341452000","resource":"invoices"}'
        );
        appcg.GridDataProviderTypesV1.QueryRequest request = new appcg.GridDataProviderTypesV1.QueryRequest();
        request.context = new appcg.GridDataProviderTypesV1.ProviderContext();
        request.startIndex = 1;
        request.pageSize = 2;

        appcg.GridDataProviderTypesV1.PageResult page = new QuickBooksGridDataProvider().getData(request);

        System.assertEquals(3, page.totalCount);
        System.assertEquals(2, page.records.size());
        System.assertEquals('INV-2', page.records[0].get('docNumber'));
        System.assert(mock.queries[1].contains('startposition 2 maxresults 2'), mock.queries[1]);
    }

    @IsTest
    static void searchCountsMatchesAcrossQuickBooksPages() {
        QueryMock mock = new QueryMock();
        mock.total = 1001;
        List<String> first = new List<String>();
        for (Integer i = 1; i <= 1000; i++) {
            first.add('{"Id":"' + i + '","DocNumber":"ordinary","Balance":0}');
        }
        mock.pages.put(1, '{"QueryResponse":{"Invoice":[' + String.join(first, ',') + ']}}');
        mock.pages.put(1001, '{"QueryResponse":{"Invoice":[' +
            '{"Id":"1001","DocNumber":"TARGET-1001","Balance":0}]}}');
        Test.setMock(HttpCalloutMock.class, mock);
        QuickBooksGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"realmId":"9341452000","resource":"invoices","limit":1001}'
        );
        appcg.GridDataProviderTypesV1.QueryRequest request = new appcg.GridDataProviderTypesV1.QueryRequest();
        request.context = new appcg.GridDataProviderTypesV1.ProviderContext();
        request.searchTerm = 'TARGET';
        request.pageSize = 10;

        appcg.GridDataProviderTypesV1.PageResult page = new QuickBooksGridDataProvider().getData(request);

        System.assertEquals(1, page.totalCount);
        System.assertEquals('TARGET-1001', page.records[0].get('docNumber'));
        System.assert(mock.queries[2].contains('startposition 1001 maxresults 1'), mock.queries[2]);
    }

    @IsTest
    static void parentContextFiltersCountAndPage() {
        QueryMock mock = new QueryMock();
        mock.total = 1;
        mock.pages.put(1, '{"QueryResponse":{"Invoice":[' +
            '{"Id":"8","DocNumber":"INV-8","Balance":0}]}}');
        Test.setMock(HttpCalloutMock.class, mock);
        QuickBooksGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"realmId":"9341452000","resource":"invoices",' +
                '"where":"Balance > 0","parentMatchColumn":"CustomerRef"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext context = new appcg.GridDataProviderTypesV1.ProviderContext();
        context.parentId = UserInfo.getUserId();
        appcg.GridDataProviderTypesV1.QueryRequest request = new appcg.GridDataProviderTypesV1.QueryRequest();
        request.context = context;

        appcg.GridDataProviderTypesV1.PageResult page = new QuickBooksGridDataProvider().getData(request);

        System.assertEquals(1, page.records.size());
        String expectedPredicate = 'Balance > 0 AND CustomerRef = \'' + context.parentId + '\'';
        System.assert(mock.queries[0].contains(expectedPredicate), mock.queries[0]);
        System.assert(mock.queries[1].contains(expectedPredicate), mock.queries[1]);
    }

    @IsTest
    static void parentMatchFieldResolvesLocalValue() {
        Account parent = new Account(Name = 'Acme Parent');
        insert parent;
        QuickBooksGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"realmId":"9341452000","resource":"invoices",' +
                '"parentMatchColumn":"CustomerRef","parentMatchField":"Name"}'
        );
        QuickBooksGridDataProvider.QuickBooksConfig cfg = QuickBooksGridDataProvider.parseConfig(null);
        appcg.GridDataProviderTypesV1.ProviderContext context = new appcg.GridDataProviderTypesV1.ProviderContext();
        context.parentId = parent.Id;
        System.assertEquals('Acme Parent', QuickBooksGridDataProvider.resolveParentMatchValue(cfg, context));
    }

    @IsTest
    static void additionalEntityHasMatchingColumnsAndValues() {
        QueryMock mock = new QueryMock();
        mock.total = 1;
        mock.pages.put(1, '{"QueryResponse":{"Vendor":[' +
            '{"Id":"42","DisplayName":"Acme Supplies","PrimaryEmailAddr":{"Address":"ap@acme.com"},' +
            '"Balance":52.25,"Active":true}]}}');
        Test.setMock(HttpCalloutMock.class, mock);
        QuickBooksGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"realmId":"9341452000","resource":"vendors"}'
        );
        QuickBooksGridDataProvider provider = new QuickBooksGridDataProvider();
        appcg.GridDataProviderTypesV1.ProviderContext context = new appcg.GridDataProviderTypesV1.ProviderContext();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(context);
        appcg.GridDataProviderTypesV1.QueryRequest request = new appcg.GridDataProviderTypesV1.QueryRequest();
        request.context = context;

        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(request);

        System.assertEquals(7, caps.columns.size());
        System.assertEquals('Acme Supplies', page.records[0].get('displayName'));
        System.assertEquals('ap@acme.com', page.records[0].get('email'));
        System.assertEquals(52.25, page.records[0].get('balance'));
    }

    @IsTest
    static void everySupportedEntityMapsResponseFieldsToColumns() {
        for (String resource : new List<String>{
            'vendors', 'estimates', 'sales_receipts', 'credit_memos',
            'purchase_orders', 'accounts', 'deposits', 'journal_entries', 'purchases'
        }) {
            QuickBooksGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
                appcg__Data_Provider_Config__c = '{"realmId":"9341452000","resource":"' + resource + '"}'
            );
            appcg.GridDataProviderTypesV1.Capabilities caps =
                new QuickBooksGridDataProvider().getCapabilities(null);
            String entity = QuickBooksGridDataProvider.resolveEntityName(resource);
            Map<String, Object> response = (Map<String, Object>) JSON.deserializeUntyped(
                '{"QueryResponse":{"' + entity + '":[{"Id":"1"}]}}'
            );
            Map<String, Object> row = QuickBooksGridDataProvider.parseQuickBooksRecords(resource, response)[0];
            System.assert(caps.columns.size() > 1, resource);
            for (appcg.GridDataProviderTypesV1.ColumnDefinition column : caps.columns) {
                System.assert(row.containsKey(column.id), resource + ': missing ' + column.id);
            }
        }
    }
}
