@IsTest
private class ShopifyGridDataProviderTest {
    private static void setupConfig() {
    }

    private static String sampleProductsJson() {
        return '{"products":[' +
            '{"id":101,"title":"Summer T-Shirt","vendor":"Acme","product_type":"Apparel","status":"active","tags":"summer, cotton","created_at":"2024-01-15T10:30:00Z","variants":[{"price":"24.99","inventory_quantity":50}]},' +
            '{"id":102,"title":"Winter Jacket","vendor":"North","product_type":"Outerwear","status":"draft","tags":"winter","created_at":"2024-01-16T11:00:00Z","variants":[]}' +
        ']}';
    }

    private static String sampleOrdersJson() {
        return '{"orders":[' +
            '{"id":201,"name":"#1001","email":"buyer@test.com","financial_status":"paid","fulfillment_status":"fulfilled","total_price":"49.98","currency":"USD","created_at":"2024-01-15T10:30:00Z","customer":{"first_name":"Jane","last_name":"Doe","email":"buyer@test.com"}}' +
        ']}';
    }

    private static String sampleCustomersJson() {
        return '{"customers":[' +
            '{"id":301,"first_name":"Alice","last_name":"Smith","email":"alice@test.com","phone":"+1234567890","orders_count":2,"total_spent":"99.96","state":"enabled","tags":"vip","created_at":"2024-01-15T10:30:00Z"}' +
        ']}';
    }

    @IsTest
    static void getCapabilities_and_getData_products_withCache() {
        setupConfig();

        ShopifyTestSupport.RoutingMock mock = new ShopifyTestSupport.RoutingMock();
        mock.byEndpointContains.put('/products.json', ShopifyTestSupport.makeResponse(200, sampleProductsJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        ShopifyGridDataProvider provider = new ShopifyGridDataProvider();
        ShopifyGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"resource":"products"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(ctx);

        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;
        req.searchTerm = 'summer';

        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assertNotEquals(null, caps);
        System.assertEquals(9, caps.columns.size());
        System.assert(caps.supportedFeatures.contains('ADD'));
        System.assert(caps.supportedFeatures.contains('EDIT'));
        System.assert(caps.supportedFeatures.contains('DELETE'));
        System.assert(caps.supportedFeatures.contains('SEARCH'));

        System.assertEquals(1, page.records.size());
        System.assertEquals('101', page.records[0].get('Id'));
        System.assertEquals('Summer T-Shirt', page.records[0].get('title'));
        System.assertEquals('24.99', page.records[0].get('price'));
        System.assertEquals(50, page.records[0].get('inventory_quantity'));
    }

    @IsTest
    static void getData_standalone_orders() {
        setupConfig();

        ShopifyTestSupport.RoutingMock mock = new ShopifyTestSupport.RoutingMock();
        mock.byEndpointContains.put('/orders.json', ShopifyTestSupport.makeResponse(200, sampleOrdersJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        ShopifyGridDataProvider provider = new ShopifyGridDataProvider();
        ShopifyGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"resource":"orders"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(ctx);

        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assertEquals(9, caps.columns.size());
        System.assertEquals(1, page.records.size());
        System.assertEquals('201', page.records[0].get('Id'));
        System.assertEquals('#1001', page.records[0].get('name'));
        System.assertEquals('Jane Doe', page.records[0].get('customer_name'));
        System.assertEquals('paid', page.records[0].get('financial_status'));
    }

    @IsTest
    static void getData_customers() {
        setupConfig();

        ShopifyTestSupport.RoutingMock mock = new ShopifyTestSupport.RoutingMock();
        mock.byEndpointContains.put('/customers.json', ShopifyTestSupport.makeResponse(200, sampleCustomersJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        ShopifyGridDataProvider provider = new ShopifyGridDataProvider();
        ShopifyGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"resource":"customers"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(ctx);

        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assertEquals(10, caps.columns.size());
        System.assertEquals(1, page.records.size());
        System.assertEquals('301', page.records[0].get('Id'));
        System.assertEquals('Alice', page.records[0].get('first_name'));
        System.assertEquals('Smith', page.records[0].get('last_name'));
        System.assertEquals('99.96', page.records[0].get('total_spent'));
    }

    @IsTest
    static void saveRecords_products_createsNewAndEditsExisting() {
        setupConfig();

        ShopifyTestSupport.RoutingMock mock = new ShopifyTestSupport.RoutingMock();
        mock.byEndpointContains.put('/products/101.json', ShopifyTestSupport.makeResponse(200, '{"product":{"id":101,"title":"Updated T-Shirt","variants":[{"price":"29.99"}]}}'));
        mock.byEndpointContains.put('/products.json', ShopifyTestSupport.makeResponse(200, '{"product":{"id":103,"title":"Brand New Hoodie","variants":[{"price":"59.99"}]}}'));
        Test.setMock(HttpCalloutMock.class, mock);

        ShopifyGridDataProvider provider = new ShopifyGridDataProvider();
        appcg.GridDataProviderTypesV1.SaveRequest req = new appcg.GridDataProviderTypesV1.SaveRequest();
        ShopifyGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"resource":"products"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();
        req.context = ctx;
        req.records = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Id' => '101', 'title' => 'Updated T-Shirt', 'price' => '29.99' },
            new Map<String, Object>{ 'title' => 'Brand New Hoodie', 'vendor' => 'Acme', 'price' => '59.99' }
        };

        Test.startTest();
        appcg.GridDataProviderTypesV1.SaveResult result = provider.saveRecords(req);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(2, result.records.size());
        System.assertEquals('101', result.records[0].get('Id'));
        System.assertEquals('103', result.records[1].get('Id'));
    }

    @IsTest
    static void saveRecords_customers_createsNewAndEditsExisting() {
        setupConfig();

        ShopifyTestSupport.RoutingMock mock = new ShopifyTestSupport.RoutingMock();
        mock.byEndpointContains.put('/customers/301.json', ShopifyTestSupport.makeResponse(200, '{"customer":{"id":301,"first_name":"Alice","last_name":"Updated"}}'));
        mock.byEndpointContains.put('/customers.json', ShopifyTestSupport.makeResponse(200, '{"customer":{"id":302,"first_name":"Bob","last_name":"New","email":"bob@test.com"}}'));
        Test.setMock(HttpCalloutMock.class, mock);

        ShopifyGridDataProvider provider = new ShopifyGridDataProvider();
        appcg.GridDataProviderTypesV1.SaveRequest req = new appcg.GridDataProviderTypesV1.SaveRequest();
        ShopifyGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"resource":"customers"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();
        req.context = ctx;
        req.records = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Id' => '301', 'first_name' => 'Alice', 'last_name' => 'Updated' },
            new Map<String, Object>{ 'first_name' => 'Bob', 'last_name' => 'New', 'email' => 'bob@test.com' }
        };

        Test.startTest();
        appcg.GridDataProviderTypesV1.SaveResult result = provider.saveRecords(req);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(2, result.records.size());
        System.assertEquals('301', result.records[0].get('Id'));
        System.assertEquals('302', result.records[1].get('Id'));
    }

    @IsTest
    static void deleteRecords_products() {
        setupConfig();

        ShopifyTestSupport.RoutingMock mock = new ShopifyTestSupport.RoutingMock();
        mock.byEndpointContains.put('/products/101.json', ShopifyTestSupport.makeResponse(200, '{}'));
        Test.setMock(HttpCalloutMock.class, mock);

        ShopifyGridDataProvider provider = new ShopifyGridDataProvider();
        appcg.GridDataProviderTypesV1.DeleteRequest req = new appcg.GridDataProviderTypesV1.DeleteRequest();
        ShopifyGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"resource":"products"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();
        req.context = ctx;
        req.recordIds = new List<String>{ '101' };

        Test.startTest();
        provider.deleteRecords(req);
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void saveRecords_ordersThrowsException() {
        setupConfig();

        ShopifyGridDataProvider provider = new ShopifyGridDataProvider();
        appcg.GridDataProviderTypesV1.SaveRequest req = new appcg.GridDataProviderTypesV1.SaveRequest();
        ShopifyGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"resource":"orders"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();
        req.context = ctx;
        req.records = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Id' => '201', 'financial_status' => 'paid' }
        };

        try {
            provider.saveRecords(req);
            System.assert(false, 'Expected GridUiException');
        } catch (ShopifyGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('Inline editing is only supported for products and customers'));
        }
    }

    @IsTest
    static void deleteRecords_ordersThrowsException() {
        setupConfig();

        ShopifyGridDataProvider provider = new ShopifyGridDataProvider();
        appcg.GridDataProviderTypesV1.DeleteRequest req = new appcg.GridDataProviderTypesV1.DeleteRequest();
        ShopifyGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"resource":"orders"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();
        req.context = ctx;
        req.recordIds = new List<String>{ '201' };

        try {
            provider.deleteRecords(req);
            System.assert(false, 'Expected GridUiException');
        } catch (ShopifyGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('Deletion is only supported for products and customers'));
        }
    }

    @IsTest
    static void parseConfig_invalidJsonThrowsException() {
        ShopifyGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = 'INVALID JSON'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();
        try {
            ShopifyGridDataProvider.parseConfig(ctx);
            System.assert(false, 'Expected GridUiException');
        } catch (ShopifyGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('Invalid Shopify provider configuration'));
        }
    }

    @IsTest
    static void formatIsoDate_handlesFormats() {
        System.assertEquals('2024-01-15 10:30:00', ShopifyGridDataProvider.formatIsoDate('2024-01-15T10:30:00Z'));
        System.assertEquals('', ShopifyGridDataProvider.formatIsoDate(null));
        System.assertEquals('short', ShopifyGridDataProvider.formatIsoDate('short'));
    }
}
