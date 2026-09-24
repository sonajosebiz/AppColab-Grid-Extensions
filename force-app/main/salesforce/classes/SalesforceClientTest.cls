@IsTest
private class SalesforceClientTest {
    private static SalesforceTestSupport.SingleResponseMock arrange(String responseBody) {
        SalesforceTestSupport.SingleResponseMock mock = new SalesforceTestSupport.SingleResponseMock();
        mock.statusCode = 200;
        mock.body = responseBody;
        Test.setMock(HttpCalloutMock.class, mock);
        return mock;
    }

    @IsTest
    static void query_dispatchesGet() {
        SalesforceTestSupport.SingleResponseMock mock = arrange('{"totalSize":1,"done":true,"records":[{"Id":"003000000000001","LastName":"Doe"}]}');

        Test.startTest();
        Map<String, Object> result = new SalesforceClient().query('SELECT Id, LastName FROM Contact');
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/services/data/v61.0/query/?q='), mock.lastEndpoint);
        List<Object> records = (List<Object>) result.get('records');
        System.assertEquals(1, records.size());
    }

    @IsTest
    static void queryMore_usesQueryLocator() {
        SalesforceTestSupport.SingleResponseMock mock = arrange(
            '{"totalSize":2,"done":true,"records":[{"Id":"003000000000002"}]}'
        );

        Test.startTest();
        Map<String, Object> result = new SalesforceClient().queryMore(
            '/services/data/v61.0/query/01gLocator-2000'
        );
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.endsWith('/services/data/v61.0/query/01gLocator-2000'));
        System.assertEquals(true, result.get('done'));
    }

    @IsTest
    static void describeSObject_dispatchesGet() {
        SalesforceTestSupport.SingleResponseMock mock = arrange('{"name":"Contact","label":"Contact","fields":[{"name":"LastName","label":"Last Name"}]}');

        Test.startTest();
        Map<String, Object> result = new SalesforceClient().describeSObject('Contact');
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/services/data/v61.0/sobjects/Contact/describe'), mock.lastEndpoint);
        System.assertEquals('Contact', result.get('name'));
    }

    @IsTest
    static void getRecord_dispatchesGet() {
        SalesforceTestSupport.SingleResponseMock mock = arrange('{"Id":"003000000000001","LastName":"Doe"}');

        Test.startTest();
        Map<String, Object> result = new SalesforceClient().getRecord('Contact', '003000000000001', new List<String>{ 'Id', 'LastName' });
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/services/data/v61.0/sobjects/Contact/003000000000001?fields=Id%2CLastName'), mock.lastEndpoint);
        System.assertEquals('003000000000001', result.get('Id'));
    }

    @IsTest
    static void createRecord_dispatchesPostWithJson() {
        SalesforceTestSupport.SingleResponseMock mock = arrange('{"id":"003000000000002","success":true,"errors":[]}');

        Map<String, Object> fields = new Map<String, Object>{
            'FirstName' => 'John',
            'LastName' => 'Smith'
        };

        Test.startTest();
        Map<String, Object> result = new SalesforceClient().createRecord('Contact', fields);
        Test.stopTest();

        System.assertEquals('POST', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/services/data/v61.0/sobjects/Contact'), mock.lastEndpoint);
        System.assertEquals('application/json', mock.capturedHeaders.get('Content-Type'));
        System.assert(mock.lastBody.contains('FirstName'), mock.lastBody);
        System.assert(mock.lastBody.contains('John'), mock.lastBody);
        System.assertEquals('003000000000002', result.get('id'));
    }

    @IsTest
    static void updateRecord_dispatchesPatchWithJson() {
        SalesforceTestSupport.SingleResponseMock mock = arrange('');

        Map<String, Object> fields = new Map<String, Object>{
            'LastName' => 'Updated'
        };

        Test.startTest();
        Map<String, Object> result = new SalesforceClient().updateRecord('Contact', '003000000000001', fields);
        Test.stopTest();

        System.assertEquals('PATCH', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/services/data/v61.0/sobjects/Contact/003000000000001'), mock.lastEndpoint);
        System.assertEquals('application/json', mock.capturedHeaders.get('Content-Type'));
        System.assert(mock.lastBody.contains('LastName'), mock.lastBody);
        System.assert(mock.lastBody.contains('Updated'), mock.lastBody);
    }

    @IsTest
    static void deleteRecord_dispatchesDelete() {
        SalesforceTestSupport.SingleResponseMock mock = arrange('');

        Test.startTest();
        Map<String, Object> result = new SalesforceClient().deleteRecord('Contact', '003000000000001');
        Test.stopTest();

        System.assertEquals('DELETE', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/services/data/v61.0/sobjects/Contact/003000000000001'), mock.lastEndpoint);
    }

    @IsTest
    static void clientValidation_handlesBlankInputs() {
        SalesforceClient client = new SalesforceClient();

        try {
            client.query('');
            System.assert(false, 'Expected SalesforceClient.ClientException');
        } catch (SalesforceClient.ClientException e) {
            System.assert(e.getMessage().contains('SOQL query cannot be blank'));
        }

        try {
            client.describeSObject('');
            System.assert(false, 'Expected SalesforceClient.ClientException');
        } catch (SalesforceClient.ClientException e) {
            System.assert(e.getMessage().contains('sObjectName cannot be blank'));
        }

        try {
            client.getRecord('', '', null);
            System.assert(false, 'Expected SalesforceClient.ClientException');
        } catch (SalesforceClient.ClientException e) {
            System.assert(e.getMessage().contains('sObjectName and recordId are required'));
        }
    }
}
