@IsTest
private class GmailGridDataProviderTest {

    private static void setupConfig() {
    }

    private static String sampleMessageJson(String id, String subject, String fromAddr, String toAddr) {
        return '{' +
            '"id":"' + id + '",' +
            '"threadId":"' + id + '",' +
            '"snippet":"Preview of ' + subject + '",' +
            '"internalDate":"1723417200000",' +
            '"labelIds":["UNREAD","INBOX"],' +
            '"payload":{' +
                '"headers":[' +
                    '{"name":"From","value":"' + fromAddr + '"},' +
                    '{"name":"To","value":"' + toAddr + '"},' +
                    '{"name":"Subject","value":"' + subject + '"},' +
                    '{"name":"Date","value":"Tue, 11 Aug 2026 23:00:00 GMT"}' +
                '],' +
                '"body":{},' +
                '"parts":[]' +
            '}' +
        '}';
    }

    @IsTest
    static void getCapabilities_returnsColumnsAndFeatures() {
        GmailGridDataProvider provider = new GmailGridDataProvider();
        appcg.GridDataProviderTypesV1.ProviderContext context = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities capabilities = provider.getCapabilities(context);
        Test.stopTest();

        System.assertNotEquals(null, capabilities);
        System.assertEquals(7, capabilities.columns.size());
        System.assertEquals(true, capabilities.supportsServerPagination);
        System.assertEquals(20, capabilities.maxPageSize);
        System.assert(capabilities.supportedFeatures.contains('SEARCH'));
        System.assert(capabilities.supportedFeatures.contains('REFRESH'));
        System.assertEquals(0, capabilities.supportedRowActions.size());

        // Verify column details
        Map<String, appcg.GridDataProviderTypesV1.ColumnDefinition> colMap = new Map<String, appcg.GridDataProviderTypesV1.ColumnDefinition>();
        for (appcg.GridDataProviderTypesV1.ColumnDefinition col : capabilities.columns) {
            colMap.put(col.id, col);
        }
        System.assert(colMap.containsKey('Id'));
        System.assert(colMap.containsKey('From'));
        System.assert(colMap.containsKey('Subject'));
        System.assert(colMap.containsKey('IsUnread'));
        System.assertEquals('BOOLEAN', colMap.get('IsUnread').fieldType);
        System.assertEquals(false, colMap.get('Id').visible);
    }

    @IsTest
    static void getData_returnsEmailRows() {
        setupConfig();

        Map<String, String> responseMap = new Map<String, String>();
        responseMap.put(
            'maxResults=20',
            '{"messages":[{"id":"msg-1","threadId":"msg-1"},{"id":"msg-2","threadId":"msg-2"}],"resultSizeEstimate":2}'
        );
        responseMap.put(
            '/msg-1',
            sampleMessageJson('msg-1', 'Welcome Email', 'sender@example.com', 'recipient@example.com')
        );
        responseMap.put(
            '/msg-2',
            sampleMessageJson('msg-2', 'Follow Up', 'recipient@example.com', 'sender@example.com')
        );

        Test.setMock(HttpCalloutMock.class, new MultiEndpointMock(responseMap));

        GmailGridDataProvider provider = new GmailGridDataProvider();
        appcg.GridDataProviderTypesV1.QueryRequest request = new appcg.GridDataProviderTypesV1.QueryRequest();
        request.context = new appcg.GridDataProviderTypesV1.ProviderContext();
        request.startIndex = 0;
        request.pageSize = 20;

        Test.startTest();
        appcg.GridDataProviderTypesV1.PageResult result = provider.getData(request);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(2, result.totalCount);
        System.assertEquals(2, result.records.size());

        Map<String, Object> row1 = result.records[0];
        System.assertEquals('msg-1', row1.get('Id'));
        System.assertEquals('Welcome Email', row1.get('Subject'));
        System.assertEquals('sender@example.com', row1.get('From'));
        System.assertEquals('recipient@example.com', row1.get('To'));
        System.assertEquals(true, row1.get('IsUnread'));
    }

    @IsTest
    static void getData_withSearchTerm_passesQueryToGmail() {
        setupConfig();

        Map<String, String> responseMap = new Map<String, String>();
        responseMap.put('maxResults=20', '{"messages":[],"resultSizeEstimate":0}');

        Test.setMock(HttpCalloutMock.class, new MultiEndpointMock(responseMap));

        GmailGridDataProvider provider = new GmailGridDataProvider();
        appcg.GridDataProviderTypesV1.QueryRequest request = new appcg.GridDataProviderTypesV1.QueryRequest();
        request.context = new appcg.GridDataProviderTypesV1.ProviderContext();
        request.searchTerm = 'from:testcolabconnect@gmail.com';
        request.startIndex = 0;
        request.pageSize = 20;

        Test.startTest();
        appcg.GridDataProviderTypesV1.PageResult result = provider.getData(request);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(0, result.records.size());
    }

    @IsTest
    static void getData_emptyMailbox_returnsEmptyResult() {
        setupConfig();

        Test.setMock(HttpCalloutMock.class, new MultiEndpointMock(
            new Map<String, String>{ 'maxResults' => '{"resultSizeEstimate":0}' }
        ));

        GmailGridDataProvider provider = new GmailGridDataProvider();
        appcg.GridDataProviderTypesV1.QueryRequest request = new appcg.GridDataProviderTypesV1.QueryRequest();
        request.context = new appcg.GridDataProviderTypesV1.ProviderContext();
        request.startIndex = 0;
        request.pageSize = 10;

        Test.startTest();
        appcg.GridDataProviderTypesV1.PageResult result = provider.getData(request);
        Test.stopTest();

        System.assertEquals(0, result.records.size());
        System.assertEquals(0, result.totalCount);
    }

    @IsTest
    static void buildGmailQuery_combinesSearchAndFilters() {
        appcg.GridDataProviderTypesV1.QueryRequest request = new appcg.GridDataProviderTypesV1.QueryRequest();
        request.searchTerm = 'is:unread';

        appcg.GridDataProviderTypesV1.Filter adminFilter = new appcg.GridDataProviderTypesV1.Filter();
        appcg.GridDataProviderTypesV1.FilterRule rule = new appcg.GridDataProviderTypesV1.FilterRule();
        rule.field = 'label';
        rule.value = 'INBOX';
        adminFilter.rules = new List<appcg.GridDataProviderTypesV1.FilterRule>{ rule };
        request.adminFilter = adminFilter;
        request.userFilter = null;

        String query = GmailGridDataProvider.buildGmailQuery(request);

        System.assertEquals('is:unread label:INBOX', query);
    }

    @IsTest
    static void buildGmailQuery_nullSearchAndFilters_returnsNull() {
        appcg.GridDataProviderTypesV1.QueryRequest request = new appcg.GridDataProviderTypesV1.QueryRequest();
        request.searchTerm = null;
        request.adminFilter = null;
        request.userFilter = null;

        String query = GmailGridDataProvider.buildGmailQuery(request);

        System.assertEquals(null, query);
    }

    @IsTest
    static void parseToGridRow_handlesMinimalMessage() {
        Map<String, Object> raw = new Map<String, Object>{
            'id' => 'msg-minimal',
            'threadId' => 'msg-minimal',
            'snippet' => 'A snippet',
            'labelIds' => new List<Object>{ 'INBOX' }
        };

        Map<String, Object> row = GmailGridDataProvider.parseToGridRow(raw);

        System.assertEquals('msg-minimal', row.get('Id'));
        System.assertEquals('(No Subject)', row.get('Subject'));
        System.assertEquals('', row.get('From'));
        System.assertEquals('', row.get('To'));
        System.assertEquals(false, row.get('IsUnread'));
        System.assertEquals('A snippet', row.get('Snippet'));
    }

    // ──── Multi-Endpoint Mock ─────────────────────────────────────────

    public class MultiEndpointMock implements HttpCalloutMock {
        private Map<String, String> responses;
        public MultiEndpointMock(Map<String, String> responses) {
            this.responses = responses;
        }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            for (String endpointSuffix : responses.keySet()) {
                if (req.getEndpoint().contains(endpointSuffix)) {
                    res.setBody(responses.get(endpointSuffix));
                    return res;
                }
            }
            res.setBody('{}');
            return res;
        }
    }
}
