@IsTest
private class ClickUpGridDataProviderTest {
    private static String sampleListMetaJson() {
        return '{' +
            '"id":"list123",' +
            '"name":"Project 1",' +
            '"statuses":[' +
                '{"status":"to do"},' +
                '{"status":"in progress"},' +
                '{"status":"complete"}' +
            ']' +
        '}';
    }

    private static String sampleTasksJson() {
        return '{' +
            '"tasks":[' +
                '{' +
                    '"id":"t1",' +
                    '"name":"Fix Login Bug",' +
                    '"status":{"status":"in progress"},' +
                    '"priority":{"priority":"urgent"},' +
                    '"assignees":[{"username":"Alan"}],' +
                    '"due_date":"1729000000000",' +
                    '"start_date":"1728900000000",' +
                    '"date_created":"1728800000000",' +
                    '"description":"Fix bug in auth",' +
                    '"url":"https://app.clickup.com/t/t1"' +
                '},' +
                '{' +
                    '"id":"t2",' +
                    '"name":"Deploy Grid Release",' +
                    '"status":{"status":"complete"},' +
                    '"priority":{"priority":"normal"},' +
                    '"assignees":[],' +
                    '"due_date":null,' +
                    '"start_date":null,' +
                    '"date_created":"1728800000000",' +
                    '"description":null,' +
                    '"url":"https://app.clickup.com/t/t2"' +
                '}' +
            ']' +
        '}';
    }

    private static appcg.GridDataProviderTypesV1.ProviderContext createValidContext() {
        ClickUpGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"listId":"list123"}'
        );
        return new appcg.GridDataProviderTypesV1.ProviderContext();
    }

    @IsTest
    static void getCapabilities_and_getData_withCache() {
        ClickUpTestSupport.RoutingMock mock = new ClickUpTestSupport.RoutingMock();
        mock.byEndpointContains.put('/api/v2/list/list123/task', ClickUpTestSupport.makeResponse(200, sampleTasksJson()));
        mock.byEndpointContains.put('/api/v2/list/list123', ClickUpTestSupport.makeResponse(200, sampleListMetaJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        ClickUpGridDataProvider provider = new ClickUpGridDataProvider();
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

        // Verify columns
        Boolean hasStatusCol = false;
        Boolean hasPriorityCol = false;
        for (appcg.GridDataProviderTypesV1.ColumnDefinition col : capabilities.columns) {
            if (col.id == 'status') {
                hasStatusCol = true;
                System.assertEquals('PICKLIST', col.fieldType);
                System.assertNotEquals(null, col.picklistOptions);
                System.assertEquals(3, col.picklistOptions.size());
            }
            if (col.id == 'priority') {
                hasPriorityCol = true;
                System.assertEquals('PICKLIST', col.fieldType);
                System.assertNotEquals(null, col.picklistOptions);
                System.assertEquals(5, col.picklistOptions.size());
            }
        }
        System.assert(hasStatusCol, 'Expected status column with picklist options');
        System.assert(hasPriorityCol, 'Expected priority column with picklist options');

        // Verify Data filtered by search term 'Login'
        System.assertEquals(1, page.records.size());
        System.assertEquals('t1', page.records[0].get('Id'));
        System.assertEquals('Fix Login Bug', page.records[0].get('name'));
        System.assertEquals('in progress', page.records[0].get('status'));
        System.assertEquals('Urgent', page.records[0].get('priority'));
        System.assertEquals('Alan', page.records[0].get('assignee'));
        System.assertNotEquals(null, page.records[0].get('dueDate'));
        System.assertEquals('https://app.clickup.com/t/t1', page.records[0].get('url'));
    }

    @IsTest
    static void getData_standalone_withoutCache() {
        ClickUpTestSupport.RoutingMock mock = new ClickUpTestSupport.RoutingMock();
        mock.byEndpointContains.put('/api/v2/list/list123/task', ClickUpTestSupport.makeResponse(200, sampleTasksJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        ClickUpGridDataProvider provider = new ClickUpGridDataProvider();
        appcg.GridDataProviderTypesV1.QueryRequest request = new appcg.GridDataProviderTypesV1.QueryRequest();
        request.context = createValidContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(request);
        Test.stopTest();

        System.assertEquals(2, page.records.size());
        System.assertEquals('t1', page.records[0].get('Id'));
        System.assertEquals('t2', page.records[1].get('Id'));
    }

    @IsTest
    static void saveRecords_updatesExistingAndCreatesNew() {
        ClickUpTestSupport.RoutingMock mock = new ClickUpTestSupport.RoutingMock();
        mock.byEndpointContains.put('/api/v2/task/t1', ClickUpTestSupport.makeResponse(200, '{"id":"t1","name":"Updated"}'));
        mock.byEndpointContains.put('/api/v2/list/list123/task', ClickUpTestSupport.makeResponse(200, '{"id":"created-t3","url":"https://app.clickup.com/t/created-t3"}'));
        Test.setMock(HttpCalloutMock.class, mock);

        ClickUpGridDataProvider provider = new ClickUpGridDataProvider();
        appcg.GridDataProviderTypesV1.SaveRequest request = new appcg.GridDataProviderTypesV1.SaveRequest();
        request.context = createValidContext();
        request.records = new List<Map<String, Object>>{
            new Map<String, Object>{
                'Id' => 't1',
                'name' => 'Fix Login Bug (Updated)',
                'status' => 'complete',
                'priority' => 'High',
                'dueDate' => '2026-10-30',
                'startDate' => '2026-10-25',
                'description' => 'Updated task description'
            },
            new Map<String, Object>{
                'Id' => 'TEMP_1',
                'name' => 'New Feature Task',
                'status' => 'to do',
                'priority' => 'Normal',
                'dueDate' => '2026-11-01'
            }
        };

        Test.startTest();
        appcg.GridDataProviderTypesV1.SaveResult result = provider.saveRecords(request);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(2, result.records.size());
        System.assertEquals('t1', result.records[0].get('Id'));
        System.assertEquals('created-t3', result.records[1].get('Id'));
        System.assertEquals('https://app.clickup.com/t/created-t3', result.records[1].get('url'));
    }

    @IsTest
    static void deleteRecords_callsDelete() {
        ClickUpTestSupport.RoutingMock mock = new ClickUpTestSupport.RoutingMock();
        mock.byEndpointContains.put('/api/v2/task/t1', ClickUpTestSupport.makeResponse(200, '{}'));
        Test.setMock(HttpCalloutMock.class, mock);

        ClickUpGridDataProvider provider = new ClickUpGridDataProvider();
        appcg.GridDataProviderTypesV1.DeleteRequest request = new appcg.GridDataProviderTypesV1.DeleteRequest();
        request.context = createValidContext();
        request.recordIds = new List<String>{ 't1' };

        Test.startTest();
        provider.deleteRecords(request);
        Test.stopTest();

        System.assertEquals(1, mock.endpointLog.size());
        System.assert(mock.endpointLog[0].contains('/api/v2/task/t1'));
    }

    @IsTest
    static void missingConfig_throwsProviderException() {
        ClickUpGridDataProvider.testGridDef = new appcg__Grid_Definition__c();
        ClickUpGridDataProvider provider = new ClickUpGridDataProvider();
        appcg.GridDataProviderTypesV1.ProviderContext context = new appcg.GridDataProviderTypesV1.ProviderContext();

        try {
            provider.getCapabilities(context);
            System.assert(false, 'Expected ProviderException');
        } catch (ClickUpGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('ClickUp provider requires configuration'));
        }
    }

    @IsTest
    static void dateHelpersAndPriorityMapping() {
        // Priority mapping
        System.assertEquals(1, ClickUpGridDataProvider.mapPriorityToClickUp('urgent'));
        System.assertEquals(2, ClickUpGridDataProvider.mapPriorityToClickUp('High'));
        System.assertEquals(3, ClickUpGridDataProvider.mapPriorityToClickUp('normal'));
        System.assertEquals(4, ClickUpGridDataProvider.mapPriorityToClickUp('low'));
        System.assertEquals(null, ClickUpGridDataProvider.mapPriorityToClickUp('none'));
        System.assertEquals(null, ClickUpGridDataProvider.mapPriorityToClickUp(null));

        // Date formatting and parsing
        String dateIso = ClickUpGridDataProvider.formatEpochMsToDate(1729000000000L);
        System.assertNotEquals(null, dateIso);

        String datetimeIso = ClickUpGridDataProvider.formatEpochMsToDatetime(1729000000000L);
        System.assertNotEquals(null, datetimeIso);

        Long epochFromDate = ClickUpGridDataProvider.parseDateToEpochMs('2026-10-15');
        System.assertNotEquals(null, epochFromDate);

        Long epochFromMs = ClickUpGridDataProvider.parseDateToEpochMs('1729000000000');
        System.assertEquals(1729000000000L, epochFromMs);

        System.assertEquals(null, ClickUpGridDataProvider.parseDateToEpochMs(''));
        System.assertEquals(null, ClickUpGridDataProvider.formatEpochMsToDate(null));
        System.assertEquals(null, ClickUpGridDataProvider.formatEpochMsToDatetime(null));
    }
}