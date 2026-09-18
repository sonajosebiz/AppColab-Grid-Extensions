@IsTest
private class HubSpotClientTest {

    private static HubSpotTestSupport.SingleResponseMock arrange(String responseBody) {

        HubSpotTestSupport.SingleResponseMock mock = new HubSpotTestSupport.SingleResponseMock();
        mock.statusCode = 200;
        mock.body = responseBody;
        Test.setMock(HttpCalloutMock.class, mock);
        return mock;
    }

    @IsTest
    static void listObjects_dispatchesGet_withPagination() {
        HubSpotTestSupport.SingleResponseMock mock = arrange(
            '{"results":[{"id":"101","properties":{"firstname":"John","lastname":"Doe"}}],"paging":{"next":{"after":"101"}}}'
        );

        Test.startTest();
        Map<String, Object> result = new HubSpotClient().listObjects('contacts', 50, 'prev_cursor', new List<String>{'firstname', 'lastname'});
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/crm/v3/objects/contacts'), mock.lastEndpoint);
        System.assert(mock.lastEndpoint.contains('limit=50'), mock.lastEndpoint);
        System.assert(mock.lastEndpoint.contains('after=prev_cursor'), mock.lastEndpoint);
        System.assert(result.containsKey('results'));
    }

    @IsTest
    static void describeProperties_dispatchesGet() {
        HubSpotTestSupport.SingleResponseMock mock = arrange(
            '{"results":[{"name":"firstname","label":"First Name","type":"string"}]}'
        );

        Test.startTest();
        Map<String, Object> result = new HubSpotClient().describeProperties('contacts');
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/crm/v3/properties/contacts'), mock.lastEndpoint);
        System.assert(result.containsKey('results'));
    }

    @IsTest
    static void searchObjects_dispatchesPost() {
        HubSpotTestSupport.SingleResponseMock mock = arrange(
            '{"total":1,"results":[{"id":"101","properties":{"firstname":"Alice"}}]}'
        );

        Test.startTest();
        Map<String, Object> result = new HubSpotClient().searchObjects('contacts', 'Alice', 10, null, new List<String>{'firstname'});
        Test.stopTest();

        System.assertEquals('POST', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/crm/v3/objects/contacts/search'), mock.lastEndpoint);
        System.assert(result.containsKey('results'));
    }

    @IsTest
    static void searchObjectsByProperty_dispatchesPost() {
        HubSpotTestSupport.SingleResponseMock mock = arrange(
            '{"total":1,"results":[{"id":"101","properties":{"email":"alice@example.com"}}]}'
        );

        Test.startTest();
        Map<String, Object> result = new HubSpotClient().searchObjectsByProperty('contacts', 'email', 'alice@example.com', 10, null, new List<String>{'email'});
        Test.stopTest();

        System.assertEquals('POST', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/crm/v3/objects/contacts/search'), mock.lastEndpoint);
        System.assert(result.containsKey('results'));
    }

    @IsTest
    static void createObject_dispatchesPost() {
        HubSpotTestSupport.SingleResponseMock mock = arrange(
            '{"id":"201","properties":{"firstname":"Bob","email":"bob@example.com"}}'
        );

        Test.startTest();
        Map<String, Object> result = new HubSpotClient().createObject('contacts', new Map<String, Object>{
            'firstname' => 'Bob',
            'email' => 'bob@example.com'
        });
        Test.stopTest();

        System.assertEquals('POST', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/crm/v3/objects/contacts'), mock.lastEndpoint);
        System.assertEquals('201', result.get('id'));
    }

    @IsTest
    static void updateObject_dispatchesPatch() {
        HubSpotTestSupport.SingleResponseMock mock = arrange(
            '{"id":"201","properties":{"firstname":"Robert"}}'
        );

        Test.startTest();
        Map<String, Object> result = new HubSpotClient().updateObject('contacts', '201', new Map<String, Object>{
            'firstname' => 'Robert'
        });
        Test.stopTest();

        System.assertEquals('PATCH', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/crm/v3/objects/contacts/201'), mock.lastEndpoint);
        System.assertEquals('201', result.get('id'));
    }

    @IsTest
    static void deleteObject_dispatchesDelete() {
        HubSpotTestSupport.SingleResponseMock mock = arrange('');
        mock.statusCode = 204;

        Test.startTest();
        new HubSpotClient().deleteObject('contacts', '201');
        Test.stopTest();

        System.assertEquals('DELETE', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/crm/v3/objects/contacts/201'), mock.lastEndpoint);
    }

    @IsTest
    static void getAssociations_and_batchRead_and_filterGroups() {
        HubSpotTestSupport.SingleResponseMock mock = arrange(
            '{"results":[{"id":"901","properties":{"hs_email_subject":"Hello World"}}]}'
        );

        Test.startTest();
        HubSpotClient client = new HubSpotClient();
        Map<String, Object> assocRes = client.getAssociations('contacts', '101', 'emails');
        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/crm/v3/objects/contacts/101/associations/emails'));

        Map<String, Object> batchRes = client.batchReadObjects('emails', new List<String>{'901'}, new List<String>{'hs_email_subject'});
        System.assertEquals('POST', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/crm/v3/objects/emails/batch/read'));

        Map<String, Object> filterRes = client.searchObjectsWithFilterGroups('emails', new List<Map<String, Object>>(), 10, null, new List<String>{'hs_email_subject'});
        System.assertEquals('POST', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/crm/v3/objects/emails/search'));
        Test.stopTest();
    }

    @IsTest
    static void validation_throwsClientError() {
        arrange('{}');
        HubSpotClient client = new HubSpotClient();

        try {
            client.listObjects('', 10, null, null);
            System.assert(false, 'Expected HubSpotClient.ClientException');
        } catch (HubSpotClient.ClientException e) {
            System.assert(e.getMessage().contains('objectType is required'));
        }

        try {
            client.deleteObject('contacts', '');
            System.assert(false, 'Expected HubSpotClient.ClientException');
        } catch (HubSpotClient.ClientException e) {
            System.assert(e.getMessage().contains('recordId is required'));
        }
    }
}
