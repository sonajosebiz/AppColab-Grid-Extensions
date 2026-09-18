@IsTest
private class StripeGridDataProviderTest {
    private static void setupConfig() {
    }

    private static String sampleCustomersJson() {
        return '{"object":"list","data":[' +
            '{"id":"cus_1","name":"Alice Johnson","email":"alice@test.com","currency":"usd","balance":5000,"delinquent":false,"created":1609459200},' +
            '{"id":"cus_2","name":"Bob Smith","email":"bob@test.com","currency":"eur","balance":0,"delinquent":true,"created":1609545600}' +
        ']}';
    }

    private static String sampleInvoicesJson() {
        return '{"object":"list","data":[' +
            '{"id":"in_1","number":"INV-001","customer_name":"Alice","customer_email":"alice@test.com","status":"paid","amount_due":5000,"amount_paid":5000,"currency":"usd","created":1609459200}' +
        ']}';
    }

    private static String sampleSubscriptionsJson() {
        return '{"object":"list","data":[' +
            '{"id":"sub_1","customer":"cus_1","status":"active","current_period_start":1609459200,"current_period_end":1612137600,"cancel_at_period_end":false,"created":1609459200}' +
        ']}';
    }

    private static String sampleChargesJson() {
        return '{"object":"list","data":[' +
            '{"id":"ch_1","amount":2500,"currency":"usd","status":"succeeded","customer":"cus_1","description":"Test charge","paid":true,"refunded":false,"created":1609459200}' +
        ']}';
    }

    @IsTest
    static void getCapabilities_and_getData_customers_withCache() {
        setupConfig();

        StripeTestSupport.RoutingMock mock = new StripeTestSupport.RoutingMock();
        mock.byEndpointContains.put('/v1/customers', StripeTestSupport.makeResponse(200, sampleCustomersJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        StripeGridDataProvider provider = new StripeGridDataProvider();
        StripeGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"resource":"customers"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(ctx);

        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;
        req.searchTerm = 'alice';

        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assertNotEquals(null, caps);
        System.assertEquals(9, caps.columns.size());
        System.assert(caps.supportedFeatures.contains('EDIT'));
        System.assert(caps.supportedFeatures.contains('DELETE'));
        System.assert(caps.supportedFeatures.contains('SEARCH'));
        System.assertEquals(true, caps.supportsServerPagination);
        System.assertEquals(100, caps.maxPageSize);

        System.assertEquals(1, page.records.size());
        System.assertEquals('cus_1', page.records[0].get('Id'));
        System.assertEquals('Alice Johnson', page.records[0].get('name'));
        System.assertEquals('alice@test.com', page.records[0].get('email'));
        System.assertEquals('50.00', page.records[0].get('balance'));
        System.assertEquals('USD', page.records[0].get('currency'));
    }

    @IsTest
    static void getData_standalone_invoices() {
        setupConfig();

        StripeTestSupport.RoutingMock mock = new StripeTestSupport.RoutingMock();
        mock.byEndpointContains.put('/v1/invoices', StripeTestSupport.makeResponse(200, sampleInvoicesJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        StripeGridDataProvider provider = new StripeGridDataProvider();
        StripeGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"resource":"invoices"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(ctx);

        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assertEquals(1, page.records.size());
        System.assertEquals('in_1', page.records[0].get('Id'));
        System.assertEquals('INV-001', page.records[0].get('number'));
        System.assertEquals('50.00', page.records[0].get('amount_due'));
    }

    @IsTest
    static void getData_subscriptions_and_charges() {
        setupConfig();

        StripeTestSupport.RoutingMock mock = new StripeTestSupport.RoutingMock();
        mock.byEndpointContains.put('/v1/subscriptions', StripeTestSupport.makeResponse(200, sampleSubscriptionsJson()));
        mock.byEndpointContains.put('/v1/charges', StripeTestSupport.makeResponse(200, sampleChargesJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        StripeGridDataProvider provider = new StripeGridDataProvider();

        // Subscriptions
        StripeGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"resource":"subscriptions"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext subCtx = new appcg.GridDataProviderTypesV1.ProviderContext();
        appcg.GridDataProviderTypesV1.Capabilities subCaps = provider.getCapabilities(subCtx);
        System.assert(subCaps.supportedFeatures.contains('DELETE'));

        // Charges
        StripeGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"resource":"charges"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext chgCtx = new appcg.GridDataProviderTypesV1.ProviderContext();
        appcg.GridDataProviderTypesV1.Capabilities chgCaps = provider.getCapabilities(chgCtx);
        System.assert(chgCaps.supportedFeatures.contains('SEARCH'));
    }

    @IsTest
    static void saveRecords_customers_createAndEdit() {
        setupConfig();

        StripeTestSupport.RoutingMock mock = new StripeTestSupport.RoutingMock();
        mock.byEndpointContains.put('/v1/customers/cus_1', StripeTestSupport.makeResponse(200, '{"id":"cus_1","name":"Alice Updated"}'));
        mock.byEndpointContains.put('/v1/customers', StripeTestSupport.makeResponse(200, '{"id":"cus_new","name":"Charlie","created":1609459200}'));
        Test.setMock(HttpCalloutMock.class, mock);

        StripeGridDataProvider provider = new StripeGridDataProvider();
        appcg.GridDataProviderTypesV1.SaveRequest req = new appcg.GridDataProviderTypesV1.SaveRequest();
        StripeGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"resource":"customers"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();
        req.context = ctx;

        req.records = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Id' => 'cus_1', 'name' => 'Alice Updated', 'email' => 'alice@test.com' },
            new Map<String, Object>{ 'name' => 'Charlie', 'email' => 'charlie@test.com' }
        };

        Test.startTest();
        appcg.GridDataProviderTypesV1.SaveResult result = provider.saveRecords(req);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(2, result.records.size());
        System.assertEquals('cus_1', result.records[0].get('Id'));
        System.assertEquals('cus_new', result.records[1].get('Id'));
    }

    @IsTest
    static void saveRecords_invalidResource_throws() {
        StripeGridDataProvider provider = new StripeGridDataProvider();
        appcg.GridDataProviderTypesV1.SaveRequest req = new appcg.GridDataProviderTypesV1.SaveRequest();
        StripeGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"resource":"invoices"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();
        req.context = ctx;
        req.records = new List<Map<String, Object>>{ new Map<String, Object>{ 'Id' => 'in_1' } };

        try {
            provider.saveRecords(req);
            System.assert(false, 'Expected exception for non-customer editing');
        } catch (StripeGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('only supported for the customers resource'));
        }
    }

    @IsTest
    static void deleteRecords_customers() {
        setupConfig();

        StripeTestSupport.RoutingMock mock = new StripeTestSupport.RoutingMock();
        mock.byEndpointContains.put('/v1/customers/cus_1', StripeTestSupport.makeResponse(200, '{"id":"cus_1","deleted":true}'));
        Test.setMock(HttpCalloutMock.class, mock);

        StripeGridDataProvider provider = new StripeGridDataProvider();
        appcg.GridDataProviderTypesV1.DeleteRequest req = new appcg.GridDataProviderTypesV1.DeleteRequest();
        StripeGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"resource":"customers"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();
        req.context = ctx;
        req.recordIds = new List<String>{ 'cus_1' };

        Test.startTest();
        provider.deleteRecords(req);
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void parseConfig_handlesDefaultAndInvalid() {
        StripeGridDataProvider.testGridDef = null;
        StripeGridDataProvider.StripeConfig cfgDefault = StripeGridDataProvider.parseConfig(null);
        System.assertEquals('customers', cfgDefault.resource);

        StripeGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{invalid-json}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext badJson = new appcg.GridDataProviderTypesV1.ProviderContext();
        try {
            StripeGridDataProvider.parseConfig(badJson);
            System.assert(false, 'Expected invalid json exception');
        } catch (StripeGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('Invalid Stripe provider configuration'));
        }
    }

    @IsTest
    static void helpers_test() {
        System.assertEquals('10.50', StripeGridDataProvider.formatAmount(1050));
        System.assertEquals('0.00', StripeGridDataProvider.formatAmount(null));
        System.assertNotEquals('', StripeGridDataProvider.formatTimestamp(1609459200));
        System.assertEquals('', StripeGridDataProvider.formatTimestamp(null));
    }
}
