@IsTest
private class ExcelClientTest {
    private static ExcelTestSupport.SingleResponseMock arrange(String responseBody) {

        ExcelTestSupport.SingleResponseMock mock = new ExcelTestSupport.SingleResponseMock();
        mock.statusCode = 200;
        mock.body = responseBody;
        Test.setMock(HttpCalloutMock.class, mock);
        return mock;
    }

    @IsTest
    static void getWorksheets_dispatchesGet() {
        String jsonRes = '{"value":[{"id":"{00000000-0001}","name":"Sheet1"}]}';
        ExcelTestSupport.SingleResponseMock mock = arrange(jsonRes);

        Test.startTest();
        Map<String, Object> result = new ExcelClient().getWorksheets('item123');
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/me/drive/items/item123/workbook/worksheets'), mock.lastEndpoint);
        System.assert(result.containsKey('value'));
    }

    @IsTest
    static void getUsedRange_dispatchesGet() {
        String jsonRes = '{"address":"Sheet1!A1:B2","values":[["Name","Amount"],["Acme",100]]}';
        ExcelTestSupport.SingleResponseMock mock = arrange(jsonRes);

        Test.startTest();
        Map<String, Object> result = new ExcelClient().getUsedRange('item123', 'Sheet1');
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/worksheets/Sheet1/usedRange'), mock.lastEndpoint);
        System.assertEquals('Sheet1!A1:B2', result.get('address'));
    }

    @IsTest
    static void getRange_dispatchesGet() {
        String jsonRes = '{"address":"Sheet1!A1:A1","values":[["Header"]]}';
        ExcelTestSupport.SingleResponseMock mock = arrange(jsonRes);

        Test.startTest();
        Map<String, Object> result = new ExcelClient().getRange('item123', 'Sheet1', 'A1:A1');
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('range(address='), mock.lastEndpoint);
    }

    @IsTest
    static void updateRange_dispatchesPatch() {
        String jsonRes = '{"address":"Sheet1!A2:B2"}';
        ExcelTestSupport.SingleResponseMock mock = arrange(jsonRes);

        List<List<Object>> values = new List<List<Object>>{
            new List<Object>{ 'New Name', 250 }
        };

        Test.startTest();
        Map<String, Object> result = new ExcelClient().updateRange('item123', 'Sheet1', 'A2:B2', values);
        Test.stopTest();

        System.assertEquals('PATCH', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('range(address='), mock.lastEndpoint);
        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(mock.lastBody);
        System.assert(payload.containsKey('values'));
    }

    @IsTest
    static void searchFiles_dispatchesGet() {
        String jsonRes = '{"value":[{"id":"item1","name":"Sales.xlsx"}]}';
        ExcelTestSupport.SingleResponseMock mock = arrange(jsonRes);

        Test.startTest();
        Map<String, Object> result = new ExcelClient().searchFiles('Sales');
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/me/drive/root/search'), mock.lastEndpoint);
    }

    @IsTest
    static void deleteRowRange_dispatchesPost() {
        String jsonRes = '{"status":"DELETED"}';
        ExcelTestSupport.SingleResponseMock mock = arrange(jsonRes);

        Test.startTest();
        Map<String, Object> result = new ExcelClient().deleteRowRange('item123', 'Sheet1', 'A2:C2');
        Test.stopTest();

        System.assertEquals('POST', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('range(address='), mock.lastEndpoint);
        System.assert(mock.lastEndpoint.endsWith('/delete'), mock.lastEndpoint);
    }

    @IsTest
    static void getWorkbookPrefix_handlesPathAndId() {
        String idPrefix = ExcelClient.getWorkbookPrefix('item456');
        System.assert(idPrefix.contains('/me/drive/items/item456/workbook'));

        String pathPrefix = ExcelClient.getWorkbookPrefix('/Documents/Reports.xlsx');
        System.assert(pathPrefix.contains('/me/drive/root:'), pathPrefix);
    }
    @IsTest
    static void workbookPathsAndSheetNames_areEncoded() {
        ExcelTestSupport.SingleResponseMock mock = arrange('{}');
        new ExcelClient().getUsedRange('/Documents/Sales #1.xlsx', 'Sales & Costs');
        System.assertEquals('callout:Excel/v1.0/me/drive/root:/Documents/Sales%20%231.xlsx:/workbook/worksheets/Sales%20%26%20Costs/usedRange(valuesOnly=true)', mock.lastEndpoint);
        System.assertEquals('application/json', mock.capturedHeaders.get('Accept'));
        new ExcelClient().getUsedRange('item123', null);
        System.assert(mock.lastEndpoint.contains('/worksheets/Sheet1/'));
    }

    @IsTest
    static void searchFiles_escapesODataStrings() {
        ExcelTestSupport.SingleResponseMock mock = arrange('{}');
        new ExcelClient().searchFiles('O\'Brien report');
        System.assert(mock.lastEndpoint.contains('q=\'O%27%27Brien%20report\''), mock.lastEndpoint);
        new ExcelClient().searchFiles(null);
        System.assert(mock.lastEndpoint.contains('q=\'.xlsx\''));
    }

    @IsTest
    static void deleteRange_acceptsEmptyResponse() {
        ExcelTestSupport.SingleResponseMock mock = arrange('');
        mock.statusCode = 204;
        System.assertEquals('DELETED', new ExcelClient().deleteRowRange('item123', null, 'A2:C2').get('status'));
        System.assertEquals('{"shift":"Up"}', mock.lastBody);
        System.assertEquals('application/json', mock.capturedHeaders.get('Content-Type'));
    }

    @IsTest
    static void transientReads_areRetriedOnce() {
        ExcelTestSupport.RetryMock mock = new ExcelTestSupport.RetryMock();
        Test.setMock(HttpCalloutMock.class, mock);
        new ExcelClient().getWorksheets('item123');
        System.assertEquals(2, mock.callCount);
    }

    @IsTest
    static void exhaustedRetry_reportsHttpStatus() {
        ExcelTestSupport.SingleResponseMock mock = arrange('{"error":"throttled"}');
        mock.statusCode = 429;
        try {
            new ExcelClient().getUsedRange('item123', 'Sheet1');
            System.assert(false, 'Expected HTTP failure');
        } catch (ExcelClient.HttpException e) {
            System.assert(e.getMessage().contains('HTTP 429'));
            System.assert(e.getMessage().contains('throttled'));
        }
        System.assertEquals(2, mock.callCount);
    }

    @IsTest
    static void permanentErrors_areNotRetried() {
        ExcelTestSupport.SingleResponseMock mock = arrange('');
        mock.statusCode = 403;
        try {
            new ExcelClient().getWorksheets('item123');
            System.assert(false, 'Expected HTTP failure');
        } catch (ExcelClient.HttpException e) {
            System.assert(e.getMessage().contains('HTTP 403'));
        }
        System.assertEquals(1, mock.callCount);
    }

    @IsTest
    static void ambiguousDeletion_isNotReplayed() {
        ExcelTestSupport.RetryMock mock = new ExcelTestSupport.RetryMock();
        Test.setMock(HttpCalloutMock.class, mock);
        try {
            new ExcelClient().deleteRowRange('item123', 'Sheet1', 'A2:B2');
            System.assert(false, 'Expected HTTP failure');
        } catch (ExcelClient.HttpException e) {
            System.assert(e.getMessage().contains('HTTP 503'));
        }
        System.assertEquals(1, mock.callCount);
    }

    @IsTest
    static void calloutExceptions_areWrappedAfterRetry() {
        ExcelTestSupport.RetryMock mock = new ExcelTestSupport.RetryMock();
        mock.throwCallout = true;
        Test.setMock(HttpCalloutMock.class, mock);
        try {
            new ExcelClient().getWorksheets('item123');
            System.assert(false, 'Expected callout failure');
        } catch (ExcelClient.HttpException e) {
            System.assert(e.getMessage().contains('Simulated timeout'));
        }
        System.assertEquals(2, mock.callCount);
    }

    @IsTest
    static void missingWorkbookAndRange_areRejected() {
        try {
            ExcelClient.getWorkbookPrefix(' ');
            System.assert(false, 'Expected missing workbook failure');
        } catch (ExcelClient.ClientException e) {
            System.assert(e.getMessage().contains('Workbook'));
        }
        try {
            new ExcelClient().getRange('item123', 'Sheet1', '');
            System.assert(false, 'Expected missing range failure');
        } catch (ExcelClient.ClientException e) {
            System.assert(e.getMessage().contains('blank'));
        }
    }
}
