@IsTest
private class NotionGridDataProviderTest {
    private static String sampleDatabaseMetaJson() {
        return '{' +
            '"object":"database",' +
            '"id":"db123",' +
            '"title":[{"plain_text":"Engineering Tasks"}],' +
            '"properties":{' +
                '"Task Name":{"id":"title","type":"title","title":{}},' +
                '"Description":{"id":"desc","type":"rich_text","rich_text":{}},' +
                '"Status":{"id":"st","type":"status","status":{"options":[{"name":"Not Started"},{"name":"In Progress"},{"name":"Done"}]}},' +
                '"Priority":{"id":"pr","type":"select","select":{"options":[{"name":"High"},{"name":"Medium"},{"name":"Low"}]}},' +
                '"Tags":{"id":"tg","type":"multi_select","multi_select":{"options":[{"name":"Frontend"},{"name":"Backend"}]}},' +
                '"Estimate":{"id":"est","type":"number","number":{"format":"number"}},' +
                '"Completed":{"id":"chk","type":"checkbox","checkbox":{}},' +
                '"Due Date":{"id":"dt","type":"date","date":{}},' +
                '"Website":{"id":"web","type":"url","url":{}},' +
                '"Contact Email":{"id":"em","type":"email","email":{}},' +
                '"Phone":{"id":"ph","type":"phone_number","phone_number":{}},' +
                '"Created Time":{"id":"ct","type":"created_time","created_time":{}},' +
                '"Created By":{"id":"cb","type":"created_by","created_by":{}},' +
                '"Assignee":{"id":"ppl","type":"people","people":{}},' +
                '"Score Formula":{"id":"frm","type":"formula","formula":{}},' +
                '"Rollup Sum":{"id":"rlp","type":"rollup","rollup":{}}' +
            '}' +
        '}';
    }

    private static String sampleQueryResultsJson() {
        return '{' +
            '"object":"list",' +
            '"results":[' +
                '{' +
                    '"object":"page",' +
                    '"id":"page-uuid-1",' +
                    '"properties":{' +
                        '"Task Name":{"type":"title","title":[{"plain_text":"Fix Login Bug"}]},' +
                        '"Description":{"type":"rich_text","rich_text":[{"plain_text":"Users cannot log in"}]},' +
                        '"Status":{"type":"status","status":{"name":"In Progress"}},' +
                        '"Priority":{"type":"select","select":{"name":"High"}},' +
                        '"Tags":{"type":"multi_select","multi_select":[{"name":"Frontend"},{"name":"Bug"}]},' +
                        '"Estimate":{"type":"number","number":8},' +
                        '"Completed":{"type":"checkbox","checkbox":false},' +
                        '"Due Date":{"type":"date","date":{"start":"2026-10-25","end":"2026-10-28"}},' +
                        '"Website":{"type":"url","url":"https://appcolab.com"},' +
                        '"Contact Email":{"type":"email","email":"dev@appcolab.com"},' +
                        '"Phone":{"type":"phone_number","phone_number":"+1234567890"},' +
                        '"Created Time":{"type":"created_time","created_time":"2026-10-14T09:00:00.000Z"},' +
                        '"Created By":{"type":"created_by","created_by":{"name":"Alan"}},' +
                        '"Assignee":{"type":"people","people":[{"name":"Alan"},{"name":"Sarah"}]},' +
                        '"Score Formula":{"type":"formula","formula":{"type":"number","number":42}},' +
                        '"Rollup Sum":{"type":"rollup","rollup":{"type":"number","number":100}}' +
                    '}' +
                '},' +
                '{' +
                    '"object":"page",' +
                    '"id":"page-uuid-2",' +
                    '"properties":{' +
                        '"Task Name":{"type":"title","title":[{"plain_text":"Deploy Grid Release"}]},' +
                        '"Status":{"type":"status","status":{"name":"Done"}},' +
                        '"Priority":{"type":"select","select":{"name":"Low"}},' +
                        '"Estimate":{"type":"number","number":4},' +
                        '"Completed":{"type":"checkbox","checkbox":true},' +
                        '"Due Date":{"type":"date","date":{"start":"2026-10-20"}}' +
                    '}' +
                '}' +
            '],' +
            '"has_more":false' +
        '}';
    }

    private static appcg.GridDataProviderTypesV1.ProviderContext createValidContext() {
        NotionGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"databaseId":"db123"}'
        );
        return new appcg.GridDataProviderTypesV1.ProviderContext();
    }

    @IsTest
    static void getCapabilities_and_getData_withCache() {
        NotionTestSupport.RoutingMock mock = new NotionTestSupport.RoutingMock();
        mock.byEndpointContains.put('/v1/databases/db123/query', NotionTestSupport.makeResponse(200, sampleQueryResultsJson()));
        mock.byEndpointContains.put('/v1/databases/db123', NotionTestSupport.makeResponse(200, sampleDatabaseMetaJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        NotionGridDataProvider provider = new NotionGridDataProvider();
        appcg.GridDataProviderTypesV1.ProviderContext context = createValidContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities capabilities = provider.getCapabilities(context);

        appcg.GridDataProviderTypesV1.QueryRequest request = new appcg.GridDataProviderTypesV1.QueryRequest();
        request.context = context;
        request.searchTerm = 'Login';

        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(request);
        Test.stopTest();

        // Capabilities assertions
        System.assertNotEquals(null, capabilities);
        System.assert(capabilities.supportedFeatures.contains('ADD'));
        System.assert(capabilities.supportedFeatures.contains('EDIT'));
        System.assert(capabilities.supportedFeatures.contains('DELETE'));
        System.assert(capabilities.supportedFeatures.contains('SEARCH'));
        System.assertEquals(new Set<String>{ 'DELETE' }, capabilities.supportedRowActions);
        System.assertEquals(false, capabilities.supportsServerPagination);

        // Verify columns discovered from schema
        Boolean hasStatusCol = false;
        Boolean hasCreatedTimeCol = false;
        for (appcg.GridDataProviderTypesV1.ColumnDefinition col : capabilities.columns) {
            if (col.id == 'Status') {
                hasStatusCol = true;
                System.assertEquals('PICKLIST', col.fieldType);
                System.assertNotEquals(null, col.picklistOptions);
                System.assertEquals(3, col.picklistOptions.size());
            }
            if (col.id == 'Created Time') {
                hasCreatedTimeCol = true;
                System.assertEquals(true, col.isReadOnly);
            }
        }
        System.assert(hasStatusCol, 'Expected Status column to be present with picklist options');
        System.assert(hasCreatedTimeCol, 'Expected Created Time to be marked read-only');

        // Verify Data filtered by search term
        System.assertEquals(1, page.records.size());
        System.assertEquals('page-uuid-1', page.records[0].get('Id'));
        System.assertEquals('Fix Login Bug', page.records[0].get('Task Name'));
        System.assertEquals('In Progress', page.records[0].get('Status'));
        System.assertEquals('High', page.records[0].get('Priority'));
        System.assertEquals('Frontend, Bug', page.records[0].get('Tags'));
        System.assertEquals(8, page.records[0].get('Estimate'));
        System.assertEquals(false, page.records[0].get('Completed'));
        System.assertEquals('2026-10-25 -> 2026-10-28', page.records[0].get('Due Date'));
        System.assertEquals('Alan, Sarah', page.records[0].get('Assignee'));
    }

    @IsTest
    static void getData_standalone_withoutCache() {
        NotionTestSupport.RoutingMock mock = new NotionTestSupport.RoutingMock();
        mock.byEndpointContains.put('/v1/databases/db123/query', NotionTestSupport.makeResponse(200, sampleQueryResultsJson()));
        mock.byEndpointContains.put('/v1/databases/db123', NotionTestSupport.makeResponse(200, sampleDatabaseMetaJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        NotionGridDataProvider provider = new NotionGridDataProvider();
        appcg.GridDataProviderTypesV1.QueryRequest request = new appcg.GridDataProviderTypesV1.QueryRequest();
        request.context = createValidContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(request);
        Test.stopTest();

        System.assertEquals(2, page.records.size());
        System.assertEquals('page-uuid-1', page.records[0].get('Id'));
        System.assertEquals('page-uuid-2', page.records[1].get('Id'));
    }

    @IsTest
    static void saveRecords_updatesExistingAndCreatesNew() {
        NotionTestSupport.RoutingMock mock = new NotionTestSupport.RoutingMock();
        mock.byEndpointContains.put('/v1/databases/db123', NotionTestSupport.makeResponse(200, sampleDatabaseMetaJson()));
        mock.byEndpointContains.put('/v1/pages/page-uuid-1', NotionTestSupport.makeResponse(200, '{"id":"page-uuid-1"}'));
        mock.byEndpointContains.put('/v1/pages', NotionTestSupport.makeResponse(200, '{"id":"page-uuid-created"}'));
        Test.setMock(HttpCalloutMock.class, mock);

        NotionGridDataProvider provider = new NotionGridDataProvider();
        appcg.GridDataProviderTypesV1.SaveRequest request = new appcg.GridDataProviderTypesV1.SaveRequest();
        request.context = createValidContext();
        request.records = new List<Map<String, Object>>{
            new Map<String, Object>{
                'Id' => 'page-uuid-1',
                'Task Name' => 'Fix Login Bug (Updated)',
                'Status' => 'Done',
                'Priority' => 'Medium',
                'Tags' => 'Frontend, Tech',
                'Estimate' => 12,
                'Completed' => true,
                'Due Date' => '2026-10-30',
                'Website' => 'https://appcolab.com',
                'Contact Email' => 'dev@appcolab.com',
                'Phone' => '+987654321'
            },
            new Map<String, Object>{
                'Id' => 'TEMP_1',
                'Task Name' => 'New Feature Task',
                'Status' => 'Not Started',
                'Priority' => 'High',
                'Estimate' => 5
            }
        };

        Test.startTest();
        appcg.GridDataProviderTypesV1.SaveResult result = provider.saveRecords(request);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(2, result.records.size());
        System.assertEquals('page-uuid-1', result.records[0].get('Id'));
        System.assertEquals('page-uuid-created', result.records[1].get('Id'));
    }

    @IsTest
    static void deleteRecords_archivesPages() {
        NotionTestSupport.RoutingMock mock = new NotionTestSupport.RoutingMock();
        mock.byEndpointContains.put('/v1/pages/page-uuid-1', NotionTestSupport.makeResponse(200, '{"id":"page-uuid-1","archived":true}'));
        Test.setMock(HttpCalloutMock.class, mock);

        NotionGridDataProvider provider = new NotionGridDataProvider();
        appcg.GridDataProviderTypesV1.DeleteRequest request = new appcg.GridDataProviderTypesV1.DeleteRequest();
        request.context = createValidContext();
        request.recordIds = new List<String>{ 'page-uuid-1' };

        Test.startTest();
        provider.deleteRecords(request);
        Test.stopTest();

        System.assertEquals(1, mock.endpointLog.size());
        System.assert(mock.endpointLog[0].contains('/v1/pages/page-uuid-1'));
    }

    @IsTest
    static void parseConfig_throwsOnMissingDatabaseId() {
        NotionGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{}'
        );
        NotionGridDataProvider provider = new NotionGridDataProvider();
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        try {
            provider.getCapabilities(ctx);
            System.assert(false, 'Expected ProviderException');
        } catch (NotionGridDataProvider.ProviderException ex) {
            System.assert(ex.getMessage().contains('databaseId is required'));
        }
    }

    @IsTest
    static void parseConfig_throwsOnMissingConfig() {
        NotionGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = null
        );
        NotionGridDataProvider provider = new NotionGridDataProvider();
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        try {
            provider.getCapabilities(ctx);
            System.assert(false, 'Expected ProviderException');
        } catch (NotionGridDataProvider.ProviderException ex) {
            System.assert(ex.getMessage().contains('Notion provider requires configuration'));
        }
    }

    @IsTest
    static void extractPropertyValue_handlesArrayRollupAndStringFormula() {
        Map<String, Object> formulaProp = new Map<String, Object>{
            'type' => 'formula',
            'formula' => new Map<String, Object>{ 'type' => 'string', 'string' => 'FormulaValue' }
        };
        Object resFormula = NotionGridDataProvider.extractPropertyValue(formulaProp, 'formula');
        System.assertEquals('FormulaValue', resFormula);

        Map<String, Object> rollupProp = new Map<String, Object>{
            'type' => 'rollup',
            'rollup' => new Map<String, Object>{ 'type' => 'array', 'array' => new List<Object>{ 'item1', 'item2' } }
        };
        Object resRollup = NotionGridDataProvider.extractPropertyValue(rollupProp, 'rollup');
        System.assertNotEquals(null, resRollup);
    }
}
