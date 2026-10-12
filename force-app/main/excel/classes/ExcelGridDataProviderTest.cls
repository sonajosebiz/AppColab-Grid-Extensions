@IsTest
private class ExcelGridDataProviderTest {

    private static void setupConfig() {
    }

    private static String sampleUsedRangeJson() {
        return '{' +
            '"address":"Sheet1!A1:C3",' +
            '"values":[' +
                '["Name","Amount","Email"],' +
                '["Acme Corp",1500,"info@acme.com"],' +
                '["Beta LLC",2500,"contact@beta.com"]' +
            ']' +
        '}';
    }

    @IsTest
    static void getCapabilities_buildsColumnsFromHeaders() {
        setupConfig();

        ExcelTestSupport.SingleResponseMock mock = new ExcelTestSupport.SingleResponseMock();
        mock.statusCode = 200;
        mock.body = sampleUsedRangeJson();
        Test.setMock(HttpCalloutMock.class, mock);

        appcg__Grid_Definition__c mockDef = new appcg__Grid_Definition__c();
        mockDef.appcg__Data_Provider_Config__c = '{"workbookId":"wb123","sheetName":"Sheet1"}';
        ExcelGridDataProvider.testGridDef = mockDef;

        ExcelGridDataProvider provider = new ExcelGridDataProvider();
        appcg.GridDataProviderTypesV1.ProviderContext context = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities capabilities = provider.getCapabilities(context);
        Test.stopTest();

        ExcelGridDataProvider.testGridDef = null;

        System.assertNotEquals(null, capabilities);
        System.assertEquals(4, capabilities.columns.size()); // Id + 3 headers
        System.assert(capabilities.supportedFeatures.contains('ADD'));
        System.assert(capabilities.supportedFeatures.contains('EDIT'));
        System.assert(capabilities.supportedFeatures.contains('DELETE'));

        Map<String, appcg.GridDataProviderTypesV1.ColumnDefinition> colMap = new Map<String, appcg.GridDataProviderTypesV1.ColumnDefinition>();
        for (appcg.GridDataProviderTypesV1.ColumnDefinition col : capabilities.columns) {
            colMap.put(col.id, col);
        }
        System.assert(colMap.containsKey('Id'));
        System.assert(colMap.containsKey('Name'));
        System.assert(colMap.containsKey('Amount'));
        System.assert(colMap.containsKey('Email'));
        System.assertEquals(false, colMap.get('Id').visible);
    }

    @IsTest
    static void getData_returnsParsedRecords() {
        setupConfig();

        ExcelTestSupport.SingleResponseMock mock = new ExcelTestSupport.SingleResponseMock();
        mock.statusCode = 200;
        mock.body = sampleUsedRangeJson();
        Test.setMock(HttpCalloutMock.class, mock);

        appcg__Grid_Definition__c mockDef = new appcg__Grid_Definition__c();
        mockDef.appcg__Data_Provider_Config__c = '{"workbookId":"wb123","sheetName":"Sheet1"}';
        ExcelGridDataProvider.testGridDef = mockDef;

        ExcelGridDataProvider provider = new ExcelGridDataProvider();
        appcg.GridDataProviderTypesV1.QueryRequest request = new appcg.GridDataProviderTypesV1.QueryRequest();
        request.context = new appcg.GridDataProviderTypesV1.ProviderContext();
        request.pageSize = 10;

        Test.startTest();
        appcg.GridDataProviderTypesV1.PageResult result = provider.getData(request);
        Test.stopTest();

        ExcelGridDataProvider.testGridDef = null;

        System.assertNotEquals(null, result);
        System.assertEquals(2, result.records.size());
        System.assertEquals('2', result.records[0].get('Id'));
        System.assertEquals('Acme Corp', result.records[0].get('Name'));
        System.assertEquals(1500, result.records[0].get('Amount'));
    }

    @IsTest
    static void getData_withSearch_filtersRecords() {
        setupConfig();

        ExcelTestSupport.SingleResponseMock mock = new ExcelTestSupport.SingleResponseMock();
        mock.statusCode = 200;
        mock.body = sampleUsedRangeJson();
        Test.setMock(HttpCalloutMock.class, mock);

        appcg__Grid_Definition__c mockDef = new appcg__Grid_Definition__c();
        mockDef.appcg__Data_Provider_Config__c = '{"workbookId":"wb123","sheetName":"Sheet1"}';
        ExcelGridDataProvider.testGridDef = mockDef;

        ExcelGridDataProvider provider = new ExcelGridDataProvider();
        appcg.GridDataProviderTypesV1.QueryRequest request = new appcg.GridDataProviderTypesV1.QueryRequest();
        request.context = new appcg.GridDataProviderTypesV1.ProviderContext();
        request.searchTerm = 'Beta';
        request.pageSize = 10;

        Test.startTest();
        appcg.GridDataProviderTypesV1.PageResult result = provider.getData(request);
        Test.stopTest();

        ExcelGridDataProvider.testGridDef = null;

        System.assertNotEquals(null, result);
        System.assertEquals(1, result.records.size());
        System.assertEquals('Beta LLC', result.records[0].get('Name'));
    }

    @IsTest
    static void saveRecords_updatesExistingAndAppendsNew() {
        setupConfig();

        ExcelTestSupport.SingleResponseMock mock = new ExcelTestSupport.SingleResponseMock();
        mock.statusCode = 200;
        mock.body = sampleUsedRangeJson();
        Test.setMock(HttpCalloutMock.class, mock);

        appcg__Grid_Definition__c mockDef = new appcg__Grid_Definition__c();
        mockDef.appcg__Data_Provider_Config__c = '{"workbookId":"wb123","sheetName":"Sheet1"}';
        ExcelGridDataProvider.testGridDef = mockDef;

        ExcelGridDataProvider provider = new ExcelGridDataProvider();
        appcg.GridDataProviderTypesV1.SaveRequest request = new appcg.GridDataProviderTypesV1.SaveRequest();
        request.context = new appcg.GridDataProviderTypesV1.ProviderContext();

        Map<String, Object> existingRow = new Map<String, Object>{
            'Id' => '2',
            'Name' => 'Acme Updated',
            'Amount' => 1800,
            'Email' => 'info@acme.com'
        };
        Map<String, Object> newRow = new Map<String, Object>{
            'Id' => 'TEMP_1',
            'Name' => 'Gamma Inc',
            'Amount' => 3000,
            'Email' => 'gamma@example.com'
        };
        request.records = new List<Map<String, Object>>{ existingRow, newRow };

        Test.startTest();
        appcg.GridDataProviderTypesV1.SaveResult saveRes = provider.saveRecords(request);
        Test.stopTest();

        ExcelGridDataProvider.testGridDef = null;

        System.assertNotEquals(null, saveRes);
        System.assertEquals(2, saveRes.records.size());
        System.assertEquals('4', newRow.get('Id')); // Appended after row 3
    }

    @IsTest
    static void deleteRecords_deletesSpecifiedRows() {
        setupConfig();

        ExcelTestSupport.SingleResponseMock mock = new ExcelTestSupport.SingleResponseMock();
        mock.statusCode = 200;
        mock.body = sampleUsedRangeJson();
        Test.setMock(HttpCalloutMock.class, mock);

        appcg__Grid_Definition__c mockDef = new appcg__Grid_Definition__c();
        mockDef.appcg__Data_Provider_Config__c = '{"workbookId":"wb123","sheetName":"Sheet1"}';
        ExcelGridDataProvider.testGridDef = mockDef;

        ExcelGridDataProvider provider = new ExcelGridDataProvider();
        appcg.GridDataProviderTypesV1.DeleteRequest request = new appcg.GridDataProviderTypesV1.DeleteRequest();
        request.context = new appcg.GridDataProviderTypesV1.ProviderContext();
        request.recordIds = new List<String>{ '2', '3' };

        Test.startTest();
        provider.deleteRecords(request);
        Test.stopTest();

        ExcelGridDataProvider.testGridDef = null;

        System.assertNotEquals(null, mock.lastMethod);
    }

    @IsTest
    static void resolveParentMatchValue_withContact_returnsId() {
        Contact c = new Contact(LastName = 'ExcelTest');
        insert c;

        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();
        ctx.parentId = c.Id;

        ExcelGridDataProvider.ExcelConfig cfg = new ExcelGridDataProvider.ExcelConfig();
        cfg.parentMatchField = 'Id';

        String val = ExcelGridDataProvider.resolveParentMatchValue(cfg, ctx);
        System.assertEquals(c.Id, val);
    }

    @IsTest
    static void helperMethods_extractHeadersAndColumns() {
        List<Object> row1 = new List<Object>{ 'ColA', 'ColB' };
        List<Object> allRows = new List<Object>{ row1 };
        List<String> headers = ExcelGridDataProvider.extractHeaders(allRows, 1);
        System.assertEquals(2, headers.size());
        System.assertEquals('ColA', headers[0]);

        System.assertEquals('A', ExcelGridDataProvider.getColumnLetter(1));
        System.assertEquals('Z', ExcelGridDataProvider.getColumnLetter(26));
        System.assertEquals('AA', ExcelGridDataProvider.getColumnLetter(27));
    }
}
