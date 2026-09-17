@IsTest
private class GoogleSheetsGridDataProviderTest {
    private static void setupConfig() {
        GoogleSheetsGridDataProvider.testGridDef = null;
    }

    private static String sampleSheetJson() {
        return '{"range":"Sheet1!A1:C3","values":[' +
            '["Name","Email","Role"],' +
            '["Alice","alice@example.com","Admin"],' +
            '["Bob","bob@example.com","User"]' +
            ']}';
    }

    private static String parentSheetJson() {
        return '{"range":"Onboarding!A1:C4","values":[' +
            '["Salesforce Account Id","Milestone","Status"],' +
            '["001000000000001","Security questionnaire","In Progress"],' +
            '["001000000000002","Data validation","Planned"],' +
            '["001000000000001","Admin training","Planned"]' +
            ']}';
    }

    private static appcg.GridDataProviderTypesV1.ProviderContext createValidContext() {
        GoogleSheetsGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"spreadsheetId":"test-sheet-id","sheetName":"Sheet1","headerRow":1}'
        );
        return new appcg.GridDataProviderTypesV1.ProviderContext();
    }

    private static appcg.GridDataProviderTypesV1.ProviderContext createParentContext() {
        GoogleSheetsGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"spreadsheetId":"test-sheet-id","sheetName":"Onboarding","headerRow":1,' +
                '"parentMatchColumn":"Salesforce Account Id","parentMatchField":"Id",' +
                '"autoPopulateParent":true}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext context = new appcg.GridDataProviderTypesV1.ProviderContext();
        context.parentId = '001000000000001AAA';
        return context;
    }

    @IsTest
    static void getCapabilities_and_getData_withCache() {
        setupConfig();

        GoogleSheetsTestSupport.RoutingMock mock = new GoogleSheetsTestSupport.RoutingMock();
        mock.byEndpointContains.put('/values/', GoogleSheetsTestSupport.makeResponse(200, sampleSheetJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        GoogleSheetsGridDataProvider provider = new GoogleSheetsGridDataProvider();
        appcg.GridDataProviderTypesV1.ProviderContext context = createValidContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities capabilities = provider.getCapabilities(context);

        appcg.GridDataProviderTypesV1.QueryRequest request = new appcg.GridDataProviderTypesV1.QueryRequest();
        request.context = context;
        request.searchTerm = 'alice';

        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(request);
        Test.stopTest();

        // Check capabilities
        System.assertNotEquals(null, capabilities);
        System.assertEquals(4, capabilities.columns.size()); // Id, Name, Email, Role
        System.assert(capabilities.supportedFeatures.contains('ADD'));
        System.assert(capabilities.supportedFeatures.contains('EDIT'));
        System.assert(capabilities.supportedFeatures.contains('DELETE'));
        System.assert(capabilities.supportedFeatures.contains('SEARCH'));
        System.assertEquals(new Set<String>{ 'DELETE' }, capabilities.supportedRowActions);
        System.assertEquals(false, capabilities.supportsServerPagination);

        // Check search-filtered data
        System.assertEquals(1, page.records.size());
        System.assertEquals('2', page.records[0].get('Id')); // Row 2 (1-based)
        System.assertEquals('Alice', page.records[0].get('Name'));
        System.assertEquals('alice@example.com', page.records[0].get('Email'));
        System.assertEquals('Admin', page.records[0].get('Role'));
    }

    @IsTest
    static void getData_standalone_withoutCache() {
        setupConfig();

        GoogleSheetsTestSupport.RoutingMock mock = new GoogleSheetsTestSupport.RoutingMock();
        mock.byEndpointContains.put('/values/', GoogleSheetsTestSupport.makeResponse(200, sampleSheetJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        GoogleSheetsGridDataProvider provider = new GoogleSheetsGridDataProvider();
        appcg.GridDataProviderTypesV1.QueryRequest request = new appcg.GridDataProviderTypesV1.QueryRequest();
        request.context = createValidContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(request);
        Test.stopTest();

        System.assertEquals(2, page.records.size());
        System.assertEquals('2', page.records[0].get('Id'));
        System.assertEquals('3', page.records[1].get('Id'));
    }

    @IsTest
    static void getData_filtersByParent_andLocksMatchColumn() {
        setupConfig();

        GoogleSheetsTestSupport.RoutingMock mock = new GoogleSheetsTestSupport.RoutingMock();
        mock.byEndpointContains.put('/values/', GoogleSheetsTestSupport.makeResponse(200, parentSheetJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        GoogleSheetsGridDataProvider provider = new GoogleSheetsGridDataProvider();
        appcg.GridDataProviderTypesV1.ProviderContext context = createParentContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities capabilities = provider.getCapabilities(context);
        appcg.GridDataProviderTypesV1.QueryRequest request = new appcg.GridDataProviderTypesV1.QueryRequest();
        request.context = context;
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(request);
        Test.stopTest();

        System.assertEquals(2, page.records.size());
        System.assertEquals('2', page.records[0].get('Id'));
        System.assertEquals('4', page.records[1].get('Id'));
        for (Map<String, Object> row : page.records) {
            System.assertEquals('001000000000001', row.get('Salesforce Account Id'));
        }

        appcg.GridDataProviderTypesV1.ColumnDefinition parentColumn;
        for (appcg.GridDataProviderTypesV1.ColumnDefinition candidate : capabilities.columns) {
            if (candidate.id == 'Salesforce Account Id') {
                parentColumn = candidate;
                break;
            }
        }
        System.assertNotEquals(null, parentColumn);
        System.assertEquals(true, parentColumn.isReadOnly);
    }

    @IsTest
    static void getData_returnsCompleteSheetWithoutParentContext() {
        setupConfig();

        GoogleSheetsTestSupport.RoutingMock mock = new GoogleSheetsTestSupport.RoutingMock();
        mock.byEndpointContains.put('/values/', GoogleSheetsTestSupport.makeResponse(200, parentSheetJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        GoogleSheetsGridDataProvider provider = new GoogleSheetsGridDataProvider();
        appcg.GridDataProviderTypesV1.ProviderContext context = createParentContext();
        context.parentId = null;

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities capabilities = provider.getCapabilities(context);
        appcg.GridDataProviderTypesV1.QueryRequest request = new appcg.GridDataProviderTypesV1.QueryRequest();
        request.context = context;
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(request);
        Test.stopTest();

        System.assertEquals(3, page.records.size());
        for (appcg.GridDataProviderTypesV1.ColumnDefinition candidate : capabilities.columns) {
            if (candidate.id == 'Salesforce Account Id') {
                System.assertEquals(false, candidate.isReadOnly);
            }
        }
    }

    @IsTest
    static void saveRecords_updatesExistingAndAppendsNew() {
        setupConfig();

        GoogleSheetsTestSupport.RoutingMock mock = new GoogleSheetsTestSupport.RoutingMock();
        // 1. Header row fetch
        mock.byEndpointContains.put(
            '!1:1',
            GoogleSheetsTestSupport.makeResponse(200, '{"values":[["Name","Email","Role"]]}')
        );
        // 2. Batch update values (for existing)
        mock.byEndpointContains.put(
            'values:batchUpdate',
            GoogleSheetsTestSupport.makeResponse(200, '{"totalUpdatedRows":1}')
        );
        // 3. Full data fetch to get current row count
        mock.byEndpointContains.put('/values/Sheet1', GoogleSheetsTestSupport.makeResponse(200, sampleSheetJson()));
        // 4. Append values (for new)
        mock.byEndpointContains.put(
            ':append',
            GoogleSheetsTestSupport.makeResponse(200, '{"updates":{"updatedRows":1}}')
        );

        Test.setMock(HttpCalloutMock.class, mock);

        GoogleSheetsGridDataProvider provider = new GoogleSheetsGridDataProvider();
        appcg.GridDataProviderTypesV1.SaveRequest request = new appcg.GridDataProviderTypesV1.SaveRequest();
        request.context = createValidContext();
        request.records = new List<Map<String, Object>>{
            new Map<String, Object>{
                'Id' => '2',
                'Name' => 'Alice Updated',
                'Email' => 'alice@example.com',
                'Role' => 'Admin'
            },
            new Map<String, Object>{ 'Name' => 'Charlie', 'Email' => 'charlie@example.com', 'Role' => 'Viewer' }
        };

        Test.startTest();
        appcg.GridDataProviderTypesV1.SaveResult result = provider.saveRecords(request);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(2, result.records.size());
        System.assertEquals('2', result.records[0].get('Id'));
        System.assertEquals('Alice Updated', result.records[0].get('Name'));
        System.assertEquals('4', result.records[1].get('Id')); // 3 existing rows + 1 = 4
        System.assertEquals('Charlie', result.records[1].get('Name'));
    }

    @IsTest
    static void saveRecords_autoPopulatesParentForNewRows() {
        setupConfig();

        GoogleSheetsTestSupport.RoutingMock mock = new GoogleSheetsTestSupport.RoutingMock();
        mock.byEndpointContains.put(
            '!1:1',
            GoogleSheetsTestSupport.makeResponse(200, '{"values":[["Salesforce Account Id","Milestone","Status"]]}')
        );
        mock.byEndpointContains.put('/values/Onboarding', GoogleSheetsTestSupport.makeResponse(200, parentSheetJson()));
        mock.byEndpointContains.put(
            ':append',
            GoogleSheetsTestSupport.makeResponse(200, '{"updates":{"updatedRows":1}}')
        );
        Test.setMock(HttpCalloutMock.class, mock);

        GoogleSheetsGridDataProvider provider = new GoogleSheetsGridDataProvider();
        appcg.GridDataProviderTypesV1.SaveRequest request = new appcg.GridDataProviderTypesV1.SaveRequest();
        request.context = createParentContext();
        request.records = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Milestone' => 'Go-live review', 'Status' => 'Planned' }
        };

        Test.startTest();
        appcg.GridDataProviderTypesV1.SaveResult result = provider.saveRecords(request);
        Test.stopTest();

        System.assertEquals(1, result.records.size());
        System.assertEquals('001000000000001AAA', result.records[0].get('Salesforce Account Id'));
        System.assertEquals('5', result.records[0].get('Id'));
    }

    @IsTest
    static void resolveParentMatchValue_readsConfiguredSalesforceField() {
        Account parent = new Account(Name = 'ACME-ONBOARDING');
        insert parent;

        GoogleSheetsGridDataProvider.SheetConfig cfg = new GoogleSheetsGridDataProvider.SheetConfig();
        cfg.parentMatchField = 'Name';
        appcg.GridDataProviderTypesV1.ProviderContext context = new appcg.GridDataProviderTypesV1.ProviderContext();
        context.parentId = parent.Id;

        Test.startTest();
        String value = GoogleSheetsGridDataProvider.resolveParentMatchValue(cfg, context);
        Test.stopTest();

        System.assertEquals('ACME-ONBOARDING', value);
    }

    @IsTest
    static void deleteRecords_sendsBatchUpdate() {
        setupConfig();

        GoogleSheetsTestSupport.RoutingMock mock = new GoogleSheetsTestSupport.RoutingMock();
        mock.byEndpointContains.put(
            'fields=sheets.properties',
            GoogleSheetsTestSupport.makeResponse(200, '{"sheets":[{"properties":{"sheetId":101,"title":"Sheet1"}}]}')
        );
        mock.byEndpointContains.put(':batchUpdate', GoogleSheetsTestSupport.makeResponse(200, '{"replies":[]}'));
        Test.setMock(HttpCalloutMock.class, mock);

        GoogleSheetsGridDataProvider provider = new GoogleSheetsGridDataProvider();
        appcg.GridDataProviderTypesV1.DeleteRequest request = new appcg.GridDataProviderTypesV1.DeleteRequest();
        request.context = createValidContext();
        request.recordIds = new List<String>{ '2', '3' };

        Test.startTest();
        provider.deleteRecords(request);
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void parseConfig_validatesInput() {
        GoogleSheetsGridDataProvider.testGridDef = null;
        appcg.GridDataProviderTypesV1.ProviderContext emptyCtx = new appcg.GridDataProviderTypesV1.ProviderContext();
        try {
            GoogleSheetsGridDataProvider.parseConfig(emptyCtx);
            System.assert(false, 'Expected missing config error');
        } catch (GoogleSheetsGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('requires configuration'));
        }

        GoogleSheetsGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{invalid-json}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext badJsonCtx = new appcg.GridDataProviderTypesV1.ProviderContext();
        try {
            GoogleSheetsGridDataProvider.parseConfig(badJsonCtx);
            System.assert(false, 'Expected invalid json error');
        } catch (GoogleSheetsGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('Invalid Google Sheets provider configuration'));
        }

        GoogleSheetsGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"sheetName":"Sheet1"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext missingIdCtx = new appcg.GridDataProviderTypesV1.ProviderContext();
        try {
            GoogleSheetsGridDataProvider.parseConfig(missingIdCtx);
            System.assert(false, 'Expected missing spreadsheetId error');
        } catch (GoogleSheetsGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('spreadsheetId is required'));
        }

        GoogleSheetsGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"spreadsheetId":"test-sheet-id","sheetName":"Sheet1","autoPopulateParent":true}'
        );
        try {
            GoogleSheetsGridDataProvider.parseConfig(new appcg.GridDataProviderTypesV1.ProviderContext());
            System.assert(false, 'Expected parentMatchColumn validation error');
        } catch (GoogleSheetsGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('parentMatchColumn is required'));
        }
    }

    @IsTest
    static void resolveSheetGid_notFound_throwsException() {
        setupConfig();

        GoogleSheetsTestSupport.SingleResponseMock mock = new GoogleSheetsTestSupport.SingleResponseMock();
        mock.statusCode = 200;
        mock.body = '{"sheets":[{"properties":{"sheetId":0,"title":"DifferentSheet"}}]}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        try {
            GoogleSheetsClient client = new GoogleSheetsClient();
            GoogleSheetsGridDataProvider.resolveSheetGid(client, 'sheet-123', 'NonExistentSheet');
            System.assert(false, 'Expected sheet not found error');
        } catch (GoogleSheetsGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('not found in spreadsheet'));
        }
        Test.stopTest();
    }
}
