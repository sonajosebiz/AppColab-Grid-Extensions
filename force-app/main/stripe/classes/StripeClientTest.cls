@IsTest
private class StripeClientTest {
    private static StripeTestSupport.SingleResponseMock arrange(String responseBody) {

        StripeTestSupport.SingleResponseMock mock = new StripeTestSupport.SingleResponseMock();
        mock.statusCode = 200;
        mock.body = responseBody;
        Test.setMock(HttpCalloutMock.class, mock);
        return mock;
    }

    @IsTest
    static void listResources_dispatchesGet() {
        StripeTestSupport.SingleResponseMock mock = arrange('{"object":"list","data":[{"id":"cus_123","name":"John Doe"}]}');

        Test.startTest();
        Map<String, Object> result = new StripeClient().listResources('customers', 10, 'cus_000');
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/v1/customers?limit=10&starting_after=cus_000'), mock.lastEndpoint);
        List<Object> data = (List<Object>) result.get('data');
        System.assertEquals(1, data.size());
    }

    @IsTest
    static void getResource_dispatchesGet() {
        StripeTestSupport.SingleResponseMock mock = arrange('{"id":"cus_123","name":"John Doe"}');

        Test.startTest();
        Map<String, Object> result = new StripeClient().getResource('customers', 'cus_123');
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/v1/customers/cus_123'), mock.lastEndpoint);
        System.assertEquals('cus_123', result.get('id'));
    }

    @IsTest
    static void createResource_dispatchesPostWithFormEncoding() {
        StripeTestSupport.SingleResponseMock mock = arrange('{"id":"cus_new","name":"Jane Doe"}');

        Map<String, Object> fields = new Map<String, Object>{
            'name' => 'Jane Doe',
            'email' => 'jane@example.com',
            'metadata' => new Map<String, Object>{ 'tier' => 'gold' }
        };

        Test.startTest();
        Map<String, Object> result = new StripeClient().createResource('customers', fields);
        Test.stopTest();

        System.assertEquals('POST', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/v1/customers'), mock.lastEndpoint);
        System.assertEquals('application/x-www-form-urlencoded', mock.capturedHeaders.get('Content-Type'));
        System.assert(mock.lastBody.contains('name=Jane+Doe'), mock.lastBody);
        System.assert(mock.lastBody.contains('email=jane%40example.com'), mock.lastBody);
        System.assert(mock.lastBody.contains('metadata%5Btier%5D=gold'), mock.lastBody);
        System.assertEquals('cus_new', result.get('id'));
    }

    @IsTest
    static void updateResource_dispatchesPostWithFormEncoding() {
        StripeTestSupport.SingleResponseMock mock = arrange('{"id":"cus_123","name":"John Updated"}');

        Map<String, Object> fields = new Map<String, Object>{
            'name' => 'John Updated'
        };

        Test.startTest();
        Map<String, Object> result = new StripeClient().updateResource('customers', 'cus_123', fields);
        Test.stopTest();

        System.assertEquals('POST', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/v1/customers/cus_123'), mock.lastEndpoint);
        System.assertEquals('application/x-www-form-urlencoded', mock.capturedHeaders.get('Content-Type'));
        System.assert(mock.lastBody.contains('name=John+Updated'), mock.lastBody);
        System.assertEquals('cus_123', result.get('id'));
    }

    @IsTest
    static void deleteResource_dispatchesDelete() {
        StripeTestSupport.SingleResponseMock mock = arrange('{"id":"cus_123","deleted":true}');

        Test.startTest();
        Map<String, Object> result = new StripeClient().deleteResource('customers', 'cus_123');
        Test.stopTest();

        System.assertEquals('DELETE', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/v1/customers/cus_123'), mock.lastEndpoint);
        System.assertEquals(true, result.get('deleted'));
    }

    @IsTest
    static void formEncode_handlesEmpty() {
        System.assertEquals('', StripeClient.formEncode(null));
        System.assertEquals('', StripeClient.formEncode(new Map<String, Object>()));
    }
}
