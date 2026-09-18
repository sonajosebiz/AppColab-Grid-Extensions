@IsTest
private class QuickBooksClientTest {

    private static QuickBooksTestSupport.SingleResponseMock arrange(String responseBody) {

        QuickBooksTestSupport.SingleResponseMock mock = new QuickBooksTestSupport.SingleResponseMock();
        mock.statusCode = 200;
        mock.body = responseBody;
        Test.setMock(HttpCalloutMock.class, mock);
        return mock;
    }

    @IsTest
    static void query_dispatchesGet_withSql() {
        QuickBooksTestSupport.SingleResponseMock mock = arrange(
            '{"QueryResponse":{"Invoice":[{"Id":"101","DocNumber":"INV-101","TotalAmt":500.0}]}}'
        );

        Test.startTest();
        Map<String, Object> result = new QuickBooksClient().query('9341452000', 'Invoice', 21, 50, 'Balance > 0');
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/v3/company/9341452000/query'), mock.lastEndpoint);
        System.assert(mock.lastEndpoint.contains('query=select'), mock.lastEndpoint);
        System.assert(result.containsKey('QueryResponse'));
    }

    @IsTest
    static void count_dispatchesGet_returnsInteger() {
        QuickBooksTestSupport.SingleResponseMock mock = arrange(
            '{"QueryResponse":{"totalCount":42}}'
        );

        Test.startTest();
        Integer total = new QuickBooksClient().count('9341452000', 'Invoice', 'Balance > 0');
        Test.stopTest();

        System.assertEquals(42, total);
        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('count'), mock.lastEndpoint);
    }

    @IsTest
    static void getRecord_dispatchesGet() {
        QuickBooksTestSupport.SingleResponseMock mock = arrange(
            '{"Invoice":{"Id":"101","DocNumber":"INV-101"}}'
        );

        Test.startTest();
        Map<String, Object> result = new QuickBooksClient().getRecord('9341452000', 'Invoice', '101');
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/v3/company/9341452000/invoice/101'), mock.lastEndpoint);
        System.assert(result.containsKey('Invoice'));
    }

    @IsTest
    static void createRecord_dispatchesPost() {
        QuickBooksTestSupport.SingleResponseMock mock = arrange(
            '{"Customer":{"Id":"1","DisplayName":"Acme Corp"}}'
        );

        Test.startTest();
        Map<String, Object> result = new QuickBooksClient().createRecord(
            '9341452000',
            'Customer',
            new Map<String, Object>{ 'DisplayName' => 'Acme Corp' }
        );
        Test.stopTest();

        System.assertEquals('POST', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/v3/company/9341452000/customer'), mock.lastEndpoint);
        System.assert(result.containsKey('Customer'));
    }

    @IsTest
    static void validationErrors() {
        arrange('{}');
        QuickBooksClient client = new QuickBooksClient();

        try {
            client.query(null, 'Invoice', 10, null);
            System.assert(false, 'Expected QuickBooksClient.ClientException');
        } catch (QuickBooksClient.ClientException e) {
            System.assert(e.getMessage().contains('realmId'));
        }

        try {
            client.getRecord('123', null, '1');
            System.assert(false, 'Expected QuickBooksClient.ClientException');
        } catch (QuickBooksClient.ClientException e) {
            System.assert(e.getMessage().contains('required'));
        }

        try {
            client.createRecord(null, 'Invoice', new Map<String, Object>());
            System.assert(false, 'Expected QuickBooksClient.ClientException');
        } catch (QuickBooksClient.ClientException e) {
            System.assert(e.getMessage().contains('required'));
        }
    }
}
