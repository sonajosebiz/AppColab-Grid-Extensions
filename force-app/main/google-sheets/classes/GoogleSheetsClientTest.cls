@IsTest
private class GoogleSheetsClientTest {
    private static GoogleSheetsTestSupport.SingleResponseMock arrange(String responseBody) {
        GoogleSheetsTestSupport.SingleResponseMock mock = new GoogleSheetsTestSupport.SingleResponseMock();
        mock.statusCode = 200;
        mock.body = responseBody;
        Test.setMock(HttpCalloutMock.class, mock);
        return mock;
    }

    @IsTest
    static void getValues_dispatchesGet() {
        GoogleSheetsTestSupport.SingleResponseMock mock = arrange('{"range":"Sheet1!A1:D10","values":[["Name","Email"]]}');

        Test.startTest();
        Map<String, Object> result = new GoogleSheetsClient().getValues('sheet-123', 'Sheet1!A1:D10');
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/v4/spreadsheets/sheet-123/values/Sheet1%21A1%3AD10'), mock.lastEndpoint);
        System.assertEquals('Sheet1!A1:D10', result.get('range'));
    }

    @IsTest
    static void batchUpdateValues_dispatchesPost() {
        GoogleSheetsTestSupport.SingleResponseMock mock = arrange('{"totalUpdatedRows":1}');

        List<Map<String, Object>> updateData = new List<Map<String, Object>>{
            new Map<String, Object>{
                'range' => 'Sheet1!A2',
                'values' => new List<List<Object>>{ new List<Object>{ 'John', 'john@example.com' } }
            }
        };

        Test.startTest();
        Map<String, Object> result = new GoogleSheetsClient().batchUpdateValues('sheet-123', updateData);
        Test.stopTest();

        System.assertEquals('POST', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/v4/spreadsheets/sheet-123/values:batchUpdate'), mock.lastEndpoint);
        System.assertEquals(1, result.get('totalUpdatedRows'));
    }

    @IsTest
    static void appendValues_dispatchesPost() {
        GoogleSheetsTestSupport.SingleResponseMock mock = arrange('{"updates":{"updatedRows":1}}');

        List<List<Object>> values = new List<List<Object>>{
            new List<Object>{ 'Jane', 'jane@example.com' }
        };

        Test.startTest();
        Map<String, Object> result = new GoogleSheetsClient().appendValues('sheet-123', 'Sheet1', values);
        Test.stopTest();

        System.assertEquals('POST', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/v4/spreadsheets/sheet-123/values/Sheet1:append'), mock.lastEndpoint);
        System.assert(mock.lastEndpoint.contains('valueInputOption=USER_ENTERED'), mock.lastEndpoint);
    }

    @IsTest
    static void batchUpdate_dispatchesPost() {
        GoogleSheetsTestSupport.SingleResponseMock mock = arrange('{"replies":[]}');

        List<Map<String, Object>> requests = new List<Map<String, Object>>{
            new Map<String, Object>{
                'deleteDimension' => new Map<String, Object>{
                    'range' => new Map<String, Object>{
                        'sheetId' => 0,
                        'dimension' => 'ROWS',
                        'startIndex' => 1,
                        'endIndex' => 2
                    }
                }
            }
        };

        Test.startTest();
        Map<String, Object> result = new GoogleSheetsClient().batchUpdate('sheet-123', requests);
        Test.stopTest();

        System.assertEquals('POST', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/v4/spreadsheets/sheet-123:batchUpdate'), mock.lastEndpoint);
    }

    @IsTest
    static void getMetadata_dispatchesGet() {
        GoogleSheetsTestSupport.SingleResponseMock mock = arrange('{"sheets":[{"properties":{"sheetId":0,"title":"Sheet1"}}]}');

        Test.startTest();
        Map<String, Object> result = new GoogleSheetsClient().getMetadata('sheet-123');
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/v4/spreadsheets/sheet-123?fields=sheets.properties'), mock.lastEndpoint);
        List<Object> sheets = (List<Object>) result.get('sheets');
        System.assertEquals(1, sheets.size());
    }

    @IsTest
    static void transientFailure_isRetriedOnce() {
        GoogleSheetsTestSupport.SequenceMock mock = new GoogleSheetsTestSupport.SequenceMock();
        mock.statusCodes = new List<Integer>{ 503, 200 };
        mock.body = '{"values":[]}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        new GoogleSheetsClient().getValues('sheet-123', 'Sheet1');
        Test.stopTest();

        System.assertEquals(2, mock.callCount);
    }

    @IsTest
    static void nonSuccess_raisesClientException() {
        GoogleSheetsTestSupport.SingleResponseMock mock = arrange('{"error":"denied"}');
        mock.statusCode = 403;
        mock.status = 'Forbidden';

        Test.startTest();
        try {
            new GoogleSheetsClient().getValues('sheet-123', 'Sheet1');
            System.assert(false, 'Expected a GoogleSheetsClientException.');
        } catch (GoogleSheetsClient.GoogleSheetsClientException e) {
            System.assert(e.getMessage().contains('HTTP 403 Forbidden'));
        }
        Test.stopTest();
    }
}
