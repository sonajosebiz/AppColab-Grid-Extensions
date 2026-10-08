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
}
