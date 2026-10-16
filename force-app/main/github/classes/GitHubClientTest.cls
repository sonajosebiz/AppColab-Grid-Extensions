@IsTest
private class GitHubClientTest {
    @IsTest
    static void listIssues_dispatchesGetWithParams() {
        GitHubTestSupport.SingleResponseMock mock = new GitHubTestSupport.SingleResponseMock();
        mock.body = '[{"id":1001,"number":1,"title":"Bug in auth","state":"open"}]';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        List<Object> issues = new GitHubClient().listIssues('octocat', 'Hello-World', 'open', 1, 30);
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/repos/octocat/Hello-World/issues'), mock.lastEndpoint);
        System.assert(mock.lastEndpoint.contains('state=open'), mock.lastEndpoint);
        System.assert(mock.lastEndpoint.contains('page=1'), mock.lastEndpoint);
        System.assert(mock.lastEndpoint.contains('per_page=30'), mock.lastEndpoint);
        System.assertEquals(1, issues.size());
    }

    @IsTest
    static void getIssue_dispatchesGet() {
        GitHubTestSupport.SingleResponseMock mock = new GitHubTestSupport.SingleResponseMock();
        mock.body = '{"id":1001,"number":42,"title":"Single Issue","state":"closed"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        Map<String, Object> issue = new GitHubClient().getIssue('octocat', 'Hello-World', 42);
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/repos/octocat/Hello-World/issues/42'), mock.lastEndpoint);
        System.assertEquals(42, issue.get('number'));
    }

    @IsTest
    static void createIssue_dispatchesPost() {
        GitHubTestSupport.SingleResponseMock mock = new GitHubTestSupport.SingleResponseMock();
        mock.body = '{"id":2001,"number":99,"title":"New Feature"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Map<String, Object> payload = new Map<String, Object>{
            'title' => 'New Feature',
            'body' => 'Feature description'
        };

        Test.startTest();
        Map<String, Object> result = new GitHubClient().createIssue('octocat', 'Hello-World', payload);
        Test.stopTest();

        System.assertEquals('POST', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/repos/octocat/Hello-World/issues'), mock.lastEndpoint);
        System.assert(mock.lastBody.contains('New Feature'));
        System.assertEquals(99, result.get('number'));
    }

    @IsTest
    static void updateIssue_dispatchesPatch() {
        GitHubTestSupport.SingleResponseMock mock = new GitHubTestSupport.SingleResponseMock();
        mock.body = '{"id":1001,"number":42,"title":"Updated Title","state":"closed"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Map<String, Object> payload = new Map<String, Object>{
            'title' => 'Updated Title',
            'state' => 'closed'
        };

        Test.startTest();
        Map<String, Object> result = new GitHubClient().updateIssue('octocat', 'Hello-World', 42, payload);
        Test.stopTest();

        System.assertEquals('PATCH', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/repos/octocat/Hello-World/issues/42'), mock.lastEndpoint);
        System.assert(mock.lastBody.contains('Updated Title'));
        System.assertEquals('closed', result.get('state'));
    }

    @IsTest
    static void send_retriesOnRetryableStatusCode() {
        GitHubTestSupport.SingleResponseMock mock = new GitHubTestSupport.SingleResponseMock();
        mock.statusCode = 429;
        mock.body = '{"message":"Rate limit exceeded"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        try {
            new GitHubClient().listIssues('octocat', 'Hello-World', 'all', 1, 10);
            System.assert(false, 'Expected HttpException');
        } catch (GitHubClient.HttpException e) {
            System.assert(e.getMessage().contains('429'), e.getMessage());
        }
        Test.stopTest();

        System.assertEquals(3, mock.callCount);
    }

    @IsTest
    static void validation_throwsClientExceptionOnMissingParams() {
        GitHubClient client = new GitHubClient();

        try {
            client.listIssues('', 'repo', 'all', 1, 10);
            System.assert(false, 'Expected ClientException');
        } catch (GitHubClient.ClientException e) {
            System.assert(e.getMessage().contains('owner is required'));
        }

        try {
            client.listIssues('owner', '', 'all', 1, 10);
            System.assert(false, 'Expected ClientException');
        } catch (GitHubClient.ClientException e) {
            System.assert(e.getMessage().contains('name is required'));
        }

        try {
            client.getIssue('owner', 'repo', 0);
            System.assert(false, 'Expected ClientException');
        } catch (GitHubClient.ClientException e) {
            System.assert(e.getMessage().contains('issueNumber is required'));
        }

        try {
            client.createIssue('owner', 'repo', new Map<String, Object>());
            System.assert(false, 'Expected ClientException');
        } catch (GitHubClient.ClientException e) {
            System.assert(e.getMessage().contains('title is required'));
        }

        try {
            client.updateIssue('owner', 'repo', 0, new Map<String, Object>());
            System.assert(false, 'Expected ClientException');
        } catch (GitHubClient.ClientException e) {
            System.assert(e.getMessage().contains('issueNumber is required'));
        }
    }
}