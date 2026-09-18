@IsTest
private class AsanaClientTest {

    private static AsanaTestSupport.SingleResponseMock arrange(String responseBody) {

        AsanaTestSupport.SingleResponseMock mock = new AsanaTestSupport.SingleResponseMock();
        mock.statusCode = 200;
        mock.body = responseBody;
        Test.setMock(HttpCalloutMock.class, mock);
        return mock;
    }

    @IsTest
    static void getProjectTasks_dispatchesGet_withPagination() {
        AsanaTestSupport.SingleResponseMock mock = arrange(
            '{"data":[{"gid":"123","name":"Task Alpha","completed":false}],"next_page":{"offset":"next_tok"}}'
        );

        Test.startTest();
        Map<String, Object> result = new AsanaClient().getProjectTasks('proj_100', 50, 'prev_tok');
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/api/1.0/projects/proj_100/tasks'), mock.lastEndpoint);
        System.assert(mock.lastEndpoint.contains('limit=50'), mock.lastEndpoint);
        System.assert(mock.lastEndpoint.contains('offset=prev_tok'), mock.lastEndpoint);
        System.assert(result.containsKey('data'));
    }

    @IsTest
    static void getSectionTasks_dispatchesGet() {
        AsanaTestSupport.SingleResponseMock mock = arrange(
            '{"data":[{"gid":"123","name":"Section Task"}]}'
        );

        Test.startTest();
        Map<String, Object> result = new AsanaClient().getSectionTasks('sec_200', 20, null);
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/api/1.0/sections/sec_200/tasks'), mock.lastEndpoint);
    }

    @IsTest
    static void getUserTasks_dispatchesGet() {
        AsanaTestSupport.SingleResponseMock mock = arrange(
            '{"data":[{"gid":"123","name":"My Task"}]}'
        );

        Test.startTest();
        Map<String, Object> result = new AsanaClient().getUserTasks('utl_300', 20, null);
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/api/1.0/user_task_lists/utl_300/tasks'), mock.lastEndpoint);
    }

    @IsTest
    static void getProjectSections_dispatchesGet() {
        AsanaTestSupport.SingleResponseMock mock = arrange(
            '{"data":[{"gid":"sec_1","name":"To Do"},{"gid":"sec_2","name":"Done"}]}'
        );

        Test.startTest();
        Map<String, Object> result = new AsanaClient().getProjectSections('proj_100');
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/api/1.0/projects/proj_100/sections'), mock.lastEndpoint);
    }

    @IsTest
    static void getProjects_dispatchesGet() {
        AsanaTestSupport.SingleResponseMock mock = arrange(
            '{"data":[{"gid":"p1","name":"Sprint 1"}]}'
        );

        Test.startTest();
        Map<String, Object> result = new AsanaClient().getProjects('ws_10');
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/api/1.0/workspaces/ws_10/projects'), mock.lastEndpoint);
    }

    @IsTest
    static void getWorkspaces_dispatchesGet() {
        AsanaTestSupport.SingleResponseMock mock = arrange(
            '{"data":[{"gid":"ws_10","name":"My Workspace"}]}'
        );

        Test.startTest();
        Map<String, Object> result = new AsanaClient().getWorkspaces();
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/api/1.0/workspaces'), mock.lastEndpoint);
    }

    @IsTest
    static void getTask_dispatchesGet() {
        AsanaTestSupport.SingleResponseMock mock = arrange(
            '{"data":{"gid":"task_1","name":"Detailed Task"}}'
        );

        Test.startTest();
        Map<String, Object> result = new AsanaClient().getTask('task_1');
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/api/1.0/tasks/task_1'), mock.lastEndpoint);
    }

    @IsTest
    static void createTask_dispatchesPost() {
        AsanaTestSupport.SingleResponseMock mock = arrange(
            '{"data":{"gid":"task_new","name":"Brand New Task"}}'
        );

        Test.startTest();
        Map<String, Object> result = new AsanaClient().createTask(
            new Map<String, Object>{ 'name' => 'Brand New Task', 'projects' => new List<String>{ 'proj_100' } }
        );
        Test.stopTest();

        System.assertEquals('POST', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/api/1.0/tasks'), mock.lastEndpoint);
        System.assert(mock.lastBody.contains('Brand New Task'), mock.lastBody);
        System.assertEquals('application/json', mock.capturedHeaders.get('Content-Type'));
    }

    @IsTest
    static void updateTask_dispatchesPut() {
        AsanaTestSupport.SingleResponseMock mock = arrange(
            '{"data":{"gid":"task_1","completed":true}}'
        );

        Test.startTest();
        Map<String, Object> result = new AsanaClient().updateTask(
            'task_1',
            new Map<String, Object>{ 'completed' => true }
        );
        Test.stopTest();

        System.assertEquals('PUT', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/api/1.0/tasks/task_1'), mock.lastEndpoint);
        System.assert(mock.lastBody.contains('completed'), mock.lastBody);
    }

    @IsTest
    static void deleteTask_dispatchesDel() {
        AsanaTestSupport.SingleResponseMock mock = arrange('{"data":{}}');

        Test.startTest();
        Map<String, Object> result = new AsanaClient().deleteTask('task_1');
        Test.stopTest();

        System.assertEquals('DELETE', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/api/1.0/tasks/task_1'), mock.lastEndpoint);
    }

    @IsTest
    static void validationErrors() {
        arrange('{}');
        AsanaClient client = new AsanaClient();

        try {
            client.getProjectTasks(null, 10, null);
            System.assert(false, 'Expected AsanaClient.ClientException');
        } catch (AsanaClient.ClientException e) {
            System.assert(e.getMessage().contains('projectGid'));
        }

        try {
            client.getSectionTasks('', 10, null);
            System.assert(false, 'Expected AsanaClient.ClientException');
        } catch (AsanaClient.ClientException e) {
            System.assert(e.getMessage().contains('sectionGid'));
        }

        try {
            client.updateTask('', new Map<String, Object>());
            System.assert(false, 'Expected AsanaClient.ClientException');
        } catch (AsanaClient.ClientException e) {
            System.assert(e.getMessage().contains('taskGid'));
        }
    }
}
