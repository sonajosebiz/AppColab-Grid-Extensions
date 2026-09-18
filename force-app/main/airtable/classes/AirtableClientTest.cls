@IsTest
private class AirtableClientTest {
    private static AirtableTestSupport.SingleResponseMock arrange(String responseBody) {

        AirtableTestSupport.SingleResponseMock mock = new AirtableTestSupport.SingleResponseMock();
        mock.statusCode = 200;
        mock.body = responseBody;
        Test.setMock(HttpCalloutMock.class, mock);
        return mock;
    }

    @IsTest
    static void listRecords_dispatchesGet() {
        AirtableTestSupport.SingleResponseMock mock = arrange('{"records":[{"id":"rec1","fields":{"Name":"Alice"}}]}');

        Test.startTest();
        Map<String, Object> result = new AirtableClient().listRecords('app123', 'Contacts', 25, 'offsetToken');
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/v0/app123/Contacts?pageSize=25&offset=offsetToken'), mock.lastEndpoint);
        List<Object> records = (List<Object>) result.get('records');
        System.assertEquals(1, records.size());
    }

    @IsTest
    static void createRecords_dispatchesPost() {
        AirtableTestSupport.SingleResponseMock mock = arrange('{"records":[{"id":"recNew","fields":{"Name":"Bob"}}]}');

        List<Map<String, Object>> newRecords = new List<Map<String, Object>>{
            new Map<String, Object>{ 'fields' => new Map<String, Object>{ 'Name' => 'Bob' } }
        };

        Test.startTest();
        Map<String, Object> result = new AirtableClient().createRecords('app123', 'Contacts', newRecords);
        Test.stopTest();

        System.assertEquals('POST', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/v0/app123/Contacts'), mock.lastEndpoint);
        System.assert(mock.lastEndpoint.startsWith('callout:Airtable'));
    }

    @IsTest
    static void updateRecords_dispatchesPatch() {
        AirtableTestSupport.SingleResponseMock mock = arrange('{"records":[{"id":"rec1","fields":{"Name":"Alice Updated"}}]}');

        List<Map<String, Object>> updateRecords = new List<Map<String, Object>>{
            new Map<String, Object>{ 'id' => 'rec1', 'fields' => new Map<String, Object>{ 'Name' => 'Alice Updated' } }
        };

        Test.startTest();
        Map<String, Object> result = new AirtableClient().updateRecords('app123', 'Contacts', updateRecords);
        Test.stopTest();

        System.assertEquals('PATCH', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/v0/app123/Contacts'), mock.lastEndpoint);
    }

    @IsTest
    static void deleteRecords_dispatchesDelete() {
        AirtableTestSupport.SingleResponseMock mock = arrange('{"records":[{"id":"rec1","deleted":true}]}');

        Test.startTest();
        Map<String, Object> result = new AirtableClient().deleteRecords('app123', 'Contacts', new List<String>{ 'rec1', 'rec2' });
        Test.stopTest();

        System.assertEquals('DELETE', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/v0/app123/Contacts?records%5B%5D=rec1&records%5B%5D=rec2'), mock.lastEndpoint);
    }

    @IsTest
    static void getBaseSchema_dispatchesGet() {
        AirtableTestSupport.SingleResponseMock mock = arrange('{"tables":[{"id":"tbl1","name":"Contacts","fields":[{"name":"Name","type":"singleLineText"}]}]}');

        Test.startTest();
        Map<String, Object> result = new AirtableClient().getBaseSchema('app123');
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/v0/meta/bases/app123/tables'), mock.lastEndpoint);
    }
}
