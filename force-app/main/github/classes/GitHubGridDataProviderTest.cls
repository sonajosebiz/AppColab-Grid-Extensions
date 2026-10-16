@IsTest
private class GitHubGridDataProviderTest {
    private static String sampleIssuesJson() {
        return '[' +
            '{' +
                '"id":101,' +
                '"number":1,' +
                '"title":"Fix OAuth token refresh race condition",' +
                '"state":"open",' +
                '"user":{"login":"testcolabconnect"},' +
                '"assignees":[{"login":"developer1"}],' +
                '"labels":[{"name":"bug"},{"name":"priority: high"}],' +
                '"comments":3,' +
                '"created_at":"2026-10-15T09:00:00Z",' +
                '"updated_at":"2026-10-15T10:00:00Z",' +
                '"body":"Details on race condition",' +
                '"html_url":"https://github.com/octocat/repo/issues/1"' +
            '},' +
            '{' +
                '"id":102,' +
                '"number":2,' +
                '"title":"Support pagination headers",' +
                '"state":"closed",' +
                '"user":{"login":"sarah"},' +
                '"assignees":[],' +
                '"labels":[],' +
                '"comments":0,' +
                '"created_at":"2026-10-14T09:00:00Z",' +
                '"updated_at":"2026-10-15T09:30:00Z",' +
                '"body":"PR implementation",' +
                '"html_url":"https://github.com/octocat/repo/pull/2",' +
                '"pull_request":{"url":"https://api.github.com/repos/octocat/repo/pulls/2"}' +
            '}' +
        ']';
    }

    private static appcg.GridDataProviderTypesV1.ProviderContext createValidContext(Boolean includePRs) {
        GitHubGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"owner":"octocat","repo":"repo","state":"all","includePullRequests":' + (includePRs ? 'true' : 'false') + '}'
        );
        return new appcg.GridDataProviderTypesV1.ProviderContext();
    }

    @IsTest
    static void getCapabilities_and_getData_withCache() {
        GitHubTestSupport.SingleResponseMock mock = new GitHubTestSupport.SingleResponseMock();
        mock.body = sampleIssuesJson();
        Test.setMock(HttpCalloutMock.class, mock);

        GitHubGridDataProvider provider = new GitHubGridDataProvider();
        appcg.GridDataProviderTypesV1.ProviderContext context = createValidContext(false);

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities capabilities = provider.getCapabilities(context);

        appcg.GridDataProviderTypesV1.QueryRequest request = new appcg.GridDataProviderTypesV1.QueryRequest();
        request.context = context;
        request.searchTerm = 'OAuth';

        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(request);
        Test.stopTest();

        // Capabilities assertions
        System.assertNotEquals(null, capabilities);
        System.assert(capabilities.supportedFeatures.contains('ADD'));
        System.assert(capabilities.supportedFeatures.contains('EDIT'));
        System.assert(capabilities.supportedFeatures.contains('SEARCH'));
        System.assert(capabilities.supportedFeatures.contains('DOWNLOAD_CSV'));

        Boolean hasStateCol = false;
        for (appcg.GridDataProviderTypesV1.ColumnDefinition col : capabilities.columns) {
            if (col.id == 'state') {
                hasStateCol = true;
                System.assertEquals('PICKLIST', col.fieldType);
                System.assertNotEquals(null, col.picklistOptions);
                System.assertEquals(2, col.picklistOptions.size());
            }
        }
        System.assert(hasStateCol, 'Expected state column with picklist options');

        // PR #2 should be filtered out because includePullRequests = false
        // Search term 'OAuth' matches issue #1
        System.assertEquals(1, page.records.size());
        System.assertEquals('1', page.records[0].get('Id'));
        System.assertEquals('Fix OAuth token refresh race condition', page.records[0].get('title'));
        System.assertEquals('open', page.records[0].get('state'));
        System.assertEquals('testcolabconnect', page.records[0].get('author'));
        System.assertEquals('developer1', page.records[0].get('assignees'));
        System.assertEquals('bug, priority: high', page.records[0].get('labels'));
        System.assertEquals(3, page.records[0].get('comments'));
        System.assertEquals('https://github.com/octocat/repo/issues/1', page.records[0].get('url'));
    }

    @IsTest
    static void getData_standalone_withoutCache() {
        GitHubTestSupport.SingleResponseMock mock = new GitHubTestSupport.SingleResponseMock();
        mock.body = sampleIssuesJson();
        Test.setMock(HttpCalloutMock.class, mock);

        GitHubGridDataProvider provider = new GitHubGridDataProvider();
        appcg.GridDataProviderTypesV1.QueryRequest request = new appcg.GridDataProviderTypesV1.QueryRequest();
        request.context = createValidContext(false);

        Test.startTest();
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(request);
        Test.stopTest();

        System.assertEquals(1, page.records.size());
        System.assertEquals('1', page.records[0].get('Id'));
    }

    @IsTest
    static void includePullRequests_retainsPRWhenConfigured() {
        GitHubTestSupport.SingleResponseMock mock = new GitHubTestSupport.SingleResponseMock();
        mock.body = sampleIssuesJson();
        Test.setMock(HttpCalloutMock.class, mock);

        GitHubGridDataProvider provider = new GitHubGridDataProvider();
        appcg.GridDataProviderTypesV1.QueryRequest request = new appcg.GridDataProviderTypesV1.QueryRequest();
        request.context = createValidContext(true); // include PRs

        Test.startTest();
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(request);
        Test.stopTest();

        // Both issue #1 and PR #2 should be returned
        System.assertEquals(2, page.records.size());
    }

    @IsTest
    static void saveRecords_updatesExistingAndCreatesNew() {
        GitHubTestSupport.RoutingMock mock = new GitHubTestSupport.RoutingMock();
        mock.byEndpointContains.put('/repos/octocat/repo/issues/1', GitHubTestSupport.makeResponse(200, '{"id":101,"number":1,"state":"closed"}'));
        mock.byEndpointContains.put('/repos/octocat/repo/issues', GitHubTestSupport.makeResponse(200, '{"id":103,"number":3,"html_url":"https://github.com/octocat/repo/issues/3"}'));
        Test.setMock(HttpCalloutMock.class, mock);

        GitHubGridDataProvider provider = new GitHubGridDataProvider();
        appcg.GridDataProviderTypesV1.SaveRequest request = new appcg.GridDataProviderTypesV1.SaveRequest();
        request.context = createValidContext(false);
        request.records = new List<Map<String, Object>>{
            new Map<String, Object>{
                'Id' => '1',
                'title' => 'Fix OAuth token refresh (Updated)',
                'state' => 'closed',
                'body' => 'Resolved issue'
            },
            new Map<String, Object>{
                'Id' => 'TEMP_1',
                'title' => 'Brand New Issue',
                'body' => 'Feature request details'
            }
        };

        Test.startTest();
        appcg.GridDataProviderTypesV1.SaveResult result = provider.saveRecords(request);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(2, result.records.size());
        System.assertEquals('1', result.records[0].get('Id'));
        System.assertEquals('3', result.records[1].get('Id'));
        System.assertEquals('https://github.com/octocat/repo/issues/3', result.records[1].get('url'));
    }

    @IsTest
    static void deleteRecords_closesIssues() {
        GitHubTestSupport.RoutingMock mock = new GitHubTestSupport.RoutingMock();
        mock.byEndpointContains.put('/repos/octocat/repo/issues/1', GitHubTestSupport.makeResponse(200, '{"id":101,"number":1,"state":"closed"}'));
        Test.setMock(HttpCalloutMock.class, mock);

        GitHubGridDataProvider provider = new GitHubGridDataProvider();
        appcg.GridDataProviderTypesV1.DeleteRequest request = new appcg.GridDataProviderTypesV1.DeleteRequest();
        request.context = createValidContext(false);
        request.recordIds = new List<String>{ '1' };

        Test.startTest();
        provider.deleteRecords(request);
        Test.stopTest();

        System.assertEquals(1, mock.endpointLog.size());
        System.assert(mock.endpointLog[0].contains('/repos/octocat/repo/issues/1'));
    }

    @IsTest
    static void missingConfig_throwsProviderException() {
        GitHubGridDataProvider.testGridDef = new appcg__Grid_Definition__c();
        GitHubGridDataProvider provider = new GitHubGridDataProvider();
        appcg.GridDataProviderTypesV1.ProviderContext context = new appcg.GridDataProviderTypesV1.ProviderContext();

        try {
            provider.getCapabilities(context);
            System.assert(false, 'Expected ProviderException');
        } catch (GitHubGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('GitHub provider requires configuration'));
        }
    }

    @IsTest
    static void formatIsoDatetime_handlesNulls() {
        System.assertEquals(null, GitHubGridDataProvider.formatIsoDatetime(null));
        System.assertEquals(null, GitHubGridDataProvider.formatIsoDatetime(''));
        System.assertNotEquals(null, GitHubGridDataProvider.formatIsoDatetime('2026-10-15T09:00:00Z'));
    }
}