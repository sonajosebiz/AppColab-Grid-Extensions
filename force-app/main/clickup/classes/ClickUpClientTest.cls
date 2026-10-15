@IsTest
private class ClickUpClientTest {
    @IsTest
    static void getList_dispatchesGet() {
        ClickUpTestSupport.SingleResponseMock mock = new ClickUpTestSupport.SingleResponseMock();
        mock.body = '{"id":"list123","name":"Project 1","statuses":[{"status":"to do"},{"status":"complete"}]}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Map<String, Object> result = new ClickUpClient().getList('list123');
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/api/v2/list/list123'), mock.lastEndpoint);
        System.assertEquals('Project 1', result.get('name'));
    }

    @IsTest
    static void getTasks_dispatchesGetWithParams() {
        ClickUpTestSupport.SingleResponseMock mock = new ClickUpTestSupport.SingleResponseMock();
        mock.body = '{"tasks":[{"id":"task1","name":"Task 1"}]}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Map<String, Object> result = new ClickUpClient().getTasks('list123', 0, true, true);
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/api/v2/list/list123/task'), mock.lastEndpoint);
        System.assert(mock.lastEndpoint.contains('page=0'), mock.lastEndpoint);
        System.assert(mock.lastEndpoint.contains('subtasks=true'), mock.lastEndpoint);
        System.assert(mock.lastEndpoint.contains('include_closed=true'), mock.lastEndpoint);
        List<Object> tasks = (List<Object>) result.get('tasks');
        System.assertEquals(1, tasks.size());
    }

    @IsTest
    static void getTask_dispatchesGet() {
        ClickUpTestSupport.SingleResponseMock mock = new ClickUpTestSupport.SingleResponseMock();
        mock.body = '{"id":"task123","name":"Task 123"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Map<String, Object> result = new ClickUpClient().getTask('task123');
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/api/v2/task/task123'), mock.lastEndpoint);
        System.assertEquals('Task 123', result.get('name'));
    }

    @IsTest
    static void createTask_dispatchesPost() {
        ClickUpTestSupport.SingleResponseMock mock = new ClickUpTestSupport.SingleResponseMock();
        mock.body = '{"id":"newTaskId","name":"New Task"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Map<String, Object> payload = new Map<String, Object>{
            'name' => 'New Task',
            'status' => 'to do',
            'priority' => 3
        };

        Test.startTest();
        Map<String, Object> result = new ClickUpClient().createTask('list123', payload);
        Test.stopTest();

        System.assertEquals('POST', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/api/v2/list/list123/task'), mock.lastEndpoint);
        System.assert(mock.lastBody.contains('New Task'), mock.lastBody);
        System.assertEquals('newTaskId', result.get('id'));
    }

    @IsTest
    static void updateTask_dispatchesPut() {
        ClickUpTestSupport.SingleResponseMock mock = new ClickUpTestSupport.SingleResponseMock();
        mock.body = '{"id":"task123","name":"Updated Task"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Map<String, Object> payload = new Map<String, Object>{
            'name' => 'Updated Task',
            'status' => 'complete'
        };

        Test.startTest();
        Map<String, Object> result = new ClickUpClient().updateTask('task123', payload);
        Test.stopTest();

        System.assertEquals('PUT', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/api/v2/task/task123'), mock.lastEndpoint);
        System.assert(mock.lastBody.contains('Updated Task'), mock.lastBody);
        System.assertEquals('task123', result.get('id'));
    }

    @IsTest
    static void deleteTask_dispatchesDelete() {
        ClickUpTestSupport.SingleResponseMock mock = new ClickUpTestSupport.SingleResponseMock();
        mock.body = '{}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        new ClickUpClient().deleteTask('task123');
        Test.stopTest();

        System.assertEquals('DELETE', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/api/v2/task/task123'), mock.lastEndpoint);
    }

    @IsTest
    static void send_retriesOnRetryableStatusCode() {
        ClickUpTestSupport.SingleResponseMock mock = new ClickUpTestSupport.SingleResponseMock();
        mock.statusCode = 429;
        mock.body = '{"err":"Rate limited"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        try {
            new ClickUpClient().getList('list123');
            System.assert(false, 'Expected HttpException');
        } catch (ClickUpClient.HttpException e) {
            System.assert(e.getMessage().contains('429'), e.getMessage());
        }
        Test.stopTest();

        System.assertEquals(3, mock.callCount, 'Expected 3 attempts for retryable error');
    }

    @IsTest
    static void validation_throwsClientExceptionOnMissingIds() {
        ClickUpClient client = new ClickUpClient();

        try {
            client.getList('');
            System.assert(false, 'Expected ClientException');
        } catch (ClickUpClient.ClientException e) {
            System.assert(e.getMessage().contains('listId is required'));
        }

        try {
            client.getTasks(null, 0, false, false);
            System.assert(false, 'Expected ClientException');
        } catch (ClickUpClient.ClientException e) {
            System.assert(e.getMessage().contains('listId is required'));
        }

        try {
            client.getTask('');
            System.assert(false, 'Expected ClientException');
        } catch (ClickUpClient.ClientException e) {
            System.assert(e.getMessage().contains('taskId is required'));
        }

        try {
            client.createTask('', new Map<String, Object>());
            System.assert(false, 'Expected ClientException');
        } catch (ClickUpClient.ClientException e) {
            System.assert(e.getMessage().contains('listId is required'));
        }

        try {
            client.updateTask('', new Map<String, Object>());
            System.assert(false, 'Expected ClientException');
        } catch (ClickUpClient.ClientException e) {
            System.assert(e.getMessage().contains('taskId is required'));
        }

        try {
            client.deleteTask('');
            System.assert(false, 'Expected ClientException');
        } catch (ClickUpClient.ClientException e) {
            System.assert(e.getMessage().contains('taskId is required'));
        }
    }
}