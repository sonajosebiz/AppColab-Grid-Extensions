@IsTest
private class ShopifyClientTest {
    private static ShopifyTestSupport.SingleResponseMock arrange(String responseBody) {

        ShopifyTestSupport.SingleResponseMock mock = new ShopifyTestSupport.SingleResponseMock();
        mock.statusCode = 200;
        mock.body = responseBody;
        Test.setMock(HttpCalloutMock.class, mock);
        return mock;
    }

    @IsTest
    static void listResources_dispatchesGet_products() {
        ShopifyTestSupport.SingleResponseMock mock = arrange('{"products":[{"id":123,"title":"T-Shirt"}]}');

        Test.startTest();
        Map<String, Object> result = new ShopifyClient().listResources('products', 10, '100', null);
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/admin/api/2024-01/products.json?limit=10&since_id=100'), mock.lastEndpoint);
        List<Object> products = (List<Object>) result.get('products');
        System.assertEquals(1, products.size());
    }

    @IsTest
    static void listResources_dispatchesGet_orders_withStatus() {
        ShopifyTestSupport.SingleResponseMock mock = arrange('{"orders":[{"id":456,"name":"#1001"}]}');

        Test.startTest();
        Map<String, Object> result = new ShopifyClient().listResources('orders', 20, null, new Map<String, String>{ 'status' => 'open' });
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/admin/api/2024-01/orders.json?limit=20&status=open'), mock.lastEndpoint);
        List<Object> orders = (List<Object>) result.get('orders');
        System.assertEquals(1, orders.size());
    }

    @IsTest
    static void getResource_dispatchesGet() {
        ShopifyTestSupport.SingleResponseMock mock = arrange('{"product":{"id":123,"title":"T-Shirt"}}');

        Test.startTest();
        Map<String, Object> result = new ShopifyClient().getResource('products', '123');
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/admin/api/2024-01/products/123.json'), mock.lastEndpoint);
        Map<String, Object> prod = (Map<String, Object>) result.get('product');
        System.assertEquals(123, prod.get('id'));
    }

    @IsTest
    static void createResource_dispatchesPostWithJson() {
        ShopifyTestSupport.SingleResponseMock mock = arrange('{"product":{"id":789,"title":"New Shoes"}}');

        Map<String, Object> fields = new Map<String, Object>{
            'title' => 'New Shoes',
            'vendor' => 'Nike'
        };

        Test.startTest();
        Map<String, Object> result = new ShopifyClient().createResource('products', fields);
        Test.stopTest();

        System.assertEquals('POST', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/admin/api/2024-01/products.json'), mock.lastEndpoint);
        System.assertEquals('application/json', mock.capturedHeaders.get('Content-Type'));
        System.assert(mock.lastBody.contains('"title":"New Shoes"'), mock.lastBody);
        System.assert(mock.lastBody.contains('"vendor":"Nike"'), mock.lastBody);
        Map<String, Object> prod = (Map<String, Object>) result.get('product');
        System.assertEquals(789, prod.get('id'));
    }

    @IsTest
    static void updateResource_dispatchesPutWithJson() {
        ShopifyTestSupport.SingleResponseMock mock = arrange('{"product":{"id":123,"title":"Updated Shoes"}}');

        Map<String, Object> fields = new Map<String, Object>{
            'title' => 'Updated Shoes'
        };

        Test.startTest();
        Map<String, Object> result = new ShopifyClient().updateResource('products', '123', fields);
        Test.stopTest();

        System.assertEquals('PUT', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/admin/api/2024-01/products/123.json'), mock.lastEndpoint);
        System.assertEquals('application/json', mock.capturedHeaders.get('Content-Type'));
        System.assert(mock.lastBody.contains('"product":{"title":"Updated Shoes"}'), mock.lastBody);
        Map<String, Object> prod = (Map<String, Object>) result.get('product');
        System.assertEquals(123, prod.get('id'));
    }

    @IsTest
    static void deleteResource_dispatchesDelete() {
        ShopifyTestSupport.SingleResponseMock mock = arrange('{}');

        Test.startTest();
        Map<String, Object> result = new ShopifyClient().deleteResource('products', '123');
        Test.stopTest();

        System.assertEquals('DELETE', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/admin/api/2024-01/products/123.json'), mock.lastEndpoint);
    }

    @IsTest
    static void toSingular_handlesPatterns() {
        System.assertEquals('product', ShopifyClient.toSingular('products'));
        System.assertEquals('category', ShopifyClient.toSingular('categories'));
        System.assertEquals('order', ShopifyClient.toSingular('orders'));
        System.assertEquals('item', ShopifyClient.toSingular(''));
    }
}
