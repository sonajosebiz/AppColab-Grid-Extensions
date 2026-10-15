@IsTest
private class NotionClientTest {
    @IsTest
    static void getDatabase_dispatchesGet() {
        NotionTestSupport.SingleResponseMock mock = new NotionTestSupport.SingleResponseMock();
        mock.body = '{"object":"database","id":"db123","title":[{"plain_text":"Project Tasks"}]}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Map<String, Object> result = new NotionClient().getDatabase('db123');
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/v1/databases/db123'), mock.lastEndpoint);
        System.assertEquals('database', result.get('object'));
    }

    @IsTest
    static void queryDatabase_dispatchesPostWithFiltersAndSorts() {
        NotionTestSupport.SingleResponseMock mock = new NotionTestSupport.SingleResponseMock();
        mock.body = '{"object":"list","results":[{"id":"page1","properties":{}}],"has_more":false}';
        Test.setMock(HttpCalloutMock.class, mock);

        Map<String, Object> filterMap = new Map<String, Object>{
            'property' => 'Status',
            'status' => new Map<String, Object>{ 'equals' => 'In Progress' }
        };
        List<Object> sortsList = new List<Object>{
            new Map<String, Object>{ 'property' => 'Due Date', 'direction' => 'ascending' }
        };

        Test.startTest();
        Map<String, Object> result = new NotionClient().queryDatabase('db123', 50, 'cursorToken', filterMap, sortsList);
        Test.stopTest();

        System.assertEquals('POST', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/v1/databases/db123/query'), mock.lastEndpoint);
        System.assert(mock.lastBody.contains('cursorToken'));
        System.assert(mock.lastBody.contains('In Progress'));
        List<Object> results = (List<Object>) result.get('results');
        System.assertEquals(1, results.size());
    }

    @IsTest
    static void getPage_dispatchesGet() {
        NotionTestSupport.SingleResponseMock mock = new NotionTestSupport.SingleResponseMock();
        mock.body = '{"object":"page","id":"page123"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Map<String, Object> result = new NotionClient().getPage('page123');
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/v1/pages/page123'), mock.lastEndpoint);
        System.assertEquals('page123', result.get('id'));
    }

    @IsTest
    static void createPage_dispatchesPost() {
        NotionTestSupport.SingleResponseMock mock = new NotionTestSupport.SingleResponseMock();
        mock.body = '{"object":"page","id":"newPageId"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Map<String, Object> props = new Map<String, Object>{
            'Name' => new Map<String, Object>{
                'title' => new List<Object>{
                    new Map<String, Object>{ 'text' => new Map<String, Object>{ 'content' => 'Test Task' } }
                }
            }
        };

        Test.startTest();
        Map<String, Object> result = new NotionClient().createPage('db123', props);
        Test.stopTest();

        System.assertEquals('POST', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/v1/pages'), mock.lastEndpoint);
        System.assert(mock.lastBody.contains('Test Task'));
        System.assertEquals('newPageId', result.get('id'));
    }

    @IsTest
    static void updatePage_dispatchesPatch() {
        NotionTestSupport.SingleResponseMock mock = new NotionTestSupport.SingleResponseMock();
        mock.body = '{"object":"page","id":"page123"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Map<String, Object> props = new Map<String, Object>{
            'Status' => new Map<String, Object>{
                'status' => new Map<String, Object>{ 'name' => 'Done' }
            }
        };

        Test.startTest();
        Map<String, Object> result = new NotionClient().updatePage('page123', props);
        Test.stopTest();

        System.assertEquals('PATCH', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/v1/pages/page123'), mock.lastEndpoint);
        System.assert(mock.lastBody.contains('Done'));
    }

    @IsTest
    static void archivePage_dispatchesPatchWithArchivedTrue() {
        NotionTestSupport.SingleResponseMock mock = new NotionTestSupport.SingleResponseMock();
        mock.body = '{"object":"page","id":"page123","archived":true}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Map<String, Object> result = new NotionClient().archivePage('page123');
        Test.stopTest();

        System.assertEquals('PATCH', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/v1/pages/page123'), mock.lastEndpoint);
        System.assert(mock.lastBody.contains('"archived":true'));
        System.assertEquals(true, result.get('archived'));
    }

    @IsTest
    static void httpError_throwsHttpException() {
        NotionTestSupport.SingleResponseMock mock = new NotionTestSupport.SingleResponseMock();
        mock.statusCode = 404;
        mock.body = '{"object":"error","message":"Database not found"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        try {
            new NotionClient().getDatabase('invalid_db');
            System.assert(false, 'Expected NotionClient.HttpException');
        } catch (NotionClient.HttpException ex) {
            System.assert(ex.getMessage().contains('404'));
        }
        Test.stopTest();
    }
}
