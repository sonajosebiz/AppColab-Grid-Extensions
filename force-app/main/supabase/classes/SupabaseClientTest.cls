@IsTest
private class SupabaseClientTest {

    private static SupabaseTestSupport.SingleResponseMock arrange(String responseBody) {

        SupabaseTestSupport.SingleResponseMock mock = new SupabaseTestSupport.SingleResponseMock();
        mock.statusCode = 200;
        mock.body = responseBody;
        Test.setMock(HttpCalloutMock.class, mock);
        return mock;
    }

    @IsTest
    static void queryTable_dispatchesGet_withQueryParams() {
        SupabaseTestSupport.SingleResponseMock mock = arrange(
            '[{"id":1,"name":"Alice","email":"alice@example.com"}]'
        );

        Test.startTest();
        List<Object> result = new SupabaseClient().queryTable(
            'contacts',
            'id,name,email',
            'created_at.desc',
            50,
            'status=eq.active'
        );
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/rest/v1/contacts'), mock.lastEndpoint);
        System.assert(mock.lastEndpoint.contains('select=id%2Cname%2Cemail'), mock.lastEndpoint);
        System.assert(mock.lastEndpoint.contains('order=created_at.desc'), mock.lastEndpoint);
        System.assert(mock.lastEndpoint.contains('limit=50'), mock.lastEndpoint);
        System.assert(mock.lastEndpoint.contains('status=eq.active'), mock.lastEndpoint);
        System.assertEquals(1, result.size());
    }

    @IsTest
    static void queryTableWithCount_parsesContentRange() {
        SupabaseTestSupport.SingleResponseMock mock = arrange(
            '[{"id":1,"name":"Alice"}]'
        );
        mock.responseHeaders = new Map<String, String>{ 'Content-Range' => '0-19/350' };

        Test.startTest();
        SupabaseClient.QueryResult result = new SupabaseClient().queryTableWithCount(
            'contacts',
            'id,name',
            'id.asc',
            20,
            0,
            null
        );
        Test.stopTest();

        System.assertEquals(1, result.records.size());
        System.assertEquals(350, result.totalCount);
    }

    @IsTest
    static void insertRecord_dispatchesPost() {
        SupabaseTestSupport.SingleResponseMock mock = arrange(
            '[{"id":2,"name":"Bob","email":"bob@example.com"}]'
        );

        Map<String, Object> fields = new Map<String, Object>{
            'name' => 'Bob',
            'email' => 'bob@example.com'
        };

        Test.startTest();
        List<Object> result = new SupabaseClient().insertRecord('contacts', fields);
        Test.stopTest();

        System.assertEquals('POST', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/rest/v1/contacts'), mock.lastEndpoint);
        System.assert(mock.lastBody.contains('Bob'), mock.lastBody);
        System.assertEquals(1, result.size());
    }

    @IsTest
    static void insertRecords_dispatchesPostArray() {
        SupabaseTestSupport.SingleResponseMock mock = arrange(
            '[{"id":2,"name":"Bob"},{"id":3,"name":"Charlie"}]'
        );

        List<Map<String, Object>> records = new List<Map<String, Object>>{
            new Map<String, Object>{ 'name' => 'Bob' },
            new Map<String, Object>{ 'name' => 'Charlie' }
        };

        Test.startTest();
        List<Object> result = new SupabaseClient().insertRecords('contacts', records);
        Test.stopTest();

        System.assertEquals('POST', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/rest/v1/contacts'), mock.lastEndpoint);
        System.assert(mock.lastBody.contains('Bob'), mock.lastBody);
        System.assert(mock.lastBody.contains('Charlie'), mock.lastBody);
        System.assertEquals(2, result.size());
    }

    @IsTest
    static void updateRecord_dispatchesPatch() {
        SupabaseTestSupport.SingleResponseMock mock = arrange(
            '[{"id":2,"name":"Robert","email":"bob@example.com"}]'
        );

        Map<String, Object> fields = new Map<String, Object>{
            'name' => 'Robert'
        };

        Test.startTest();
        List<Object> result = new SupabaseClient().updateRecord('contacts', 'id', '2', fields);
        Test.stopTest();

        System.assertEquals('PATCH', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/rest/v1/contacts?id=eq.2'), mock.lastEndpoint);
        System.assert(mock.lastBody.contains('Robert'), mock.lastBody);
        System.assertEquals(1, result.size());
    }

    @IsTest
    static void deleteRecord_dispatchesDelete() {
        SupabaseTestSupport.SingleResponseMock mock = arrange('');
        mock.statusCode = 204;

        Test.startTest();
        Integer statusCode = new SupabaseClient().deleteRecord('contacts', 'id', '2');
        Test.stopTest();

        System.assertEquals('DELETE', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/rest/v1/contacts?id=eq.2'), mock.lastEndpoint);
        System.assertEquals(204, statusCode);
    }

    @IsTest
    static void validationErrors() {
        arrange('[]');
        SupabaseClient client = new SupabaseClient();

        try {
            client.queryTable('', null, null, null, null);
            System.assert(false, 'Expected SupabaseClient.ClientException');
        } catch (SupabaseClient.ClientException e) {
            System.assert(e.getMessage().contains('required'));
        }

        try {
            client.insertRecord(null, new Map<String, Object>());
            System.assert(false, 'Expected SupabaseClient.ClientException');
        } catch (SupabaseClient.ClientException e) {
            System.assert(e.getMessage().contains('required'));
        }

        try {
            client.updateRecord('contacts', null, '1', new Map<String, Object>());
            System.assert(false, 'Expected SupabaseClient.ClientException');
        } catch (SupabaseClient.ClientException e) {
            System.assert(e.getMessage().contains('required'));
        }

        try {
            client.deleteRecord('contacts', 'id', null);
            System.assert(false, 'Expected SupabaseClient.ClientException');
        } catch (SupabaseClient.ClientException e) {
            System.assert(e.getMessage().contains('required'));
        }
    }
}
