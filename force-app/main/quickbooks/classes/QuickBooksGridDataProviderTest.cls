@IsTest
private class QuickBooksGridDataProviderTest {

    private static void setupConfig() {
    }

    private static String sampleInvoicesJson() {
        return '{"QueryResponse":{"Invoice":[' +
            '{"Id":"1","DocNumber":"1001","CustomerRef":{"name":"Amy Bird"},"TxnDate":"2026-08-20","DueDate":"2026-09-20","TotalAmt":450.0,"Balance":450.0,"EmailStatus":"NotSent"},' +
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
        System.assertEquals(100, caps.maxPageSize);
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
    }
}
