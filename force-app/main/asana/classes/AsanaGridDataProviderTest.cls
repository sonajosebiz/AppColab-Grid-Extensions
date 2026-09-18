@IsTest
private class AsanaGridDataProviderTest {

    private static void setupConfig() {
    }

    private static String sampleTasksJson() {
        return '{"data":[' +
            '{"gid":"101","name":"Design Sprint","completed":false,"due_on":"2026-09-10",' +
            '"assignee":{"name":"Sarah Connor","email":"sarah@example.com"},' +
            '"memberships":[{"section":{"name":"In Progress"}}],"notes":"UX specs"}' +
        '],"next_page":{"offset":"tok_page2"}}';
    }

    private static String sampleProjectsJson() {
        return '{"data":[' +
            '{"gid":"p10","name":"Mobile App","color":"blue","archived":false}' +
        ']}';
    }

    private static String sampleSectionsJson() {
        return '{"data":[' +
            '{"gid":"s1","name":"To Do"},' +
            '{"gid":"s2","name":"In Progress"},' +
            '{"gid":"s3","name":"Done"}' +
        ']}';
    }

    @IsTest
    static void getCapabilities_and_getData_tasks_withServerPagination() {
        setupConfig();

        AsanaTestSupport.RoutingMock mock = new AsanaTestSupport.RoutingMock();
        mock.byEndpointContains.put('/sections?opt_fields=gid,name',
            AsanaTestSupport.makeResponse(200, sampleSectionsJson()));
        mock.byEndpointContains.put('/tasks?',
            AsanaTestSupport.makeResponse(200, sampleTasksJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        AsanaGridDataProvider provider = new AsanaGridDataProvider();
        AsanaGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"projectId":"proj_100","resource":"tasks"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(ctx);

        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;
        req.startIndex = 0;
        req.pageSize = 20;
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assertEquals(true, caps.supportsServerPagination);
        System.assertEquals(100, caps.maxPageSize);
        System.assertEquals(9, caps.columns.size());
        System.assertEquals(1, page.records.size());
        System.assertEquals('Design Sprint', page.records[0].get('name'));
        System.assertEquals('Sarah Connor', page.records[0].get('assigneeName'));
        System.assertEquals('In Progress', page.records[0].get('sectionName'));
        System.assertEquals(2, page.totalCount, 'Total count reflects next_page offset indication');
    }

    @IsTest
    static void getCapabilities_projects_resource() {
        setupConfig();

        AsanaTestSupport.RoutingMock mock = new AsanaTestSupport.RoutingMock();
        mock.byEndpointContains.put('/workspaces/ws_1/projects',
            AsanaTestSupport.makeResponse(200, sampleProjectsJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        AsanaGridDataProvider provider = new AsanaGridDataProvider();
        AsanaGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"workspaceId":"ws_1","resource":"projects"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(ctx);
        Test.stopTest();

        System.assertEquals(6, caps.columns.size());
        System.assertEquals(true, caps.supportsServerPagination);
    }

    @IsTest
    static void getData_pageTraversal_withSearch() {
        setupConfig();

        AsanaTestSupport.RoutingMock mock = new AsanaTestSupport.RoutingMock();
        mock.byEndpointContains.put('/tasks?',
            AsanaTestSupport.makeResponse(200, sampleTasksJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        AsanaGridDataProvider provider = new AsanaGridDataProvider();
        AsanaGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"projectId":"proj_100"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;
        req.startIndex = 20;
        req.pageSize = 20;
        req.searchTerm = 'Design';

        Test.startTest();
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assertEquals(1, page.records.size());
        System.assertEquals('Design Sprint', page.records[0].get('name'));
    }

    @IsTest
    static void saveRecords_createAndModify() {
        setupConfig();

        AsanaTestSupport.RoutingMock mock = new AsanaTestSupport.RoutingMock();
        mock.byEndpointContains.put('/tasks',
            AsanaTestSupport.makeResponse(200, '{"data":{"gid":"new_task_99"}}'));
        Test.setMock(HttpCalloutMock.class, mock);

        AsanaGridDataProvider provider = new AsanaGridDataProvider();
        AsanaGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"projectId":"proj_100"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        appcg.GridDataProviderTypesV1.SaveRequest req = new appcg.GridDataProviderTypesV1.SaveRequest();
        req.context = ctx;
        req.records = new List<Map<String, Object>>{
            new Map<String, Object>{
                'Id' => 'TEMP_1',
                'name' => 'New Task',
                'dueOn' => '2026-10-01',
                'notes' => 'New Task Details'
            },
            new Map<String, Object>{
                'Id' => 'existing_55',
                'name' => 'Updated Task',
                'completed' => true
            }
        };

        Test.startTest();
        appcg.GridDataProviderTypesV1.SaveResult result = provider.saveRecords(req);
        Test.stopTest();

        System.assertNotEquals(null, result.records);
        System.assertEquals(2, result.records.size());
        System.assertEquals('new_task_99', result.records[0].get('Id'), 'Temp ID replaced by Asana GID');
    }

    @IsTest
    static void deleteRecords() {
        setupConfig();

        AsanaTestSupport.RoutingMock mock = new AsanaTestSupport.RoutingMock();
        mock.byEndpointContains.put('/tasks/task_to_del',
            AsanaTestSupport.makeResponse(200, '{"data":{}}'));
        Test.setMock(HttpCalloutMock.class, mock);

        AsanaGridDataProvider provider = new AsanaGridDataProvider();
        AsanaGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"projectId":"proj_100"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        appcg.GridDataProviderTypesV1.DeleteRequest req = new appcg.GridDataProviderTypesV1.DeleteRequest();
        req.context = ctx;
        req.recordIds = new List<String>{ 'task_to_del', 'TEMP_9' };

        Test.startTest();
        provider.deleteRecords(req);
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void parseConfig_validationErrors() {
        AsanaGridDataProvider.testGridDef = null;
        try {
            AsanaGridDataProvider.parseConfig(null);
            System.assert(false, 'Expected GridUiException');
        } catch (AsanaGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('requires configuration'));
        }

        AsanaGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"resource":"tasks"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();
        try {
            AsanaGridDataProvider.parseConfig(ctx);
            System.assert(false, 'Expected GridUiException');
        } catch (AsanaGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('projectId'));
        }

        AsanaGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"resource":"projects"}'
        );
        try {
            AsanaGridDataProvider.parseConfig(ctx);
            System.assert(false, 'Expected GridUiException');
        } catch (AsanaGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('workspaceId'));
        }
    }
}
