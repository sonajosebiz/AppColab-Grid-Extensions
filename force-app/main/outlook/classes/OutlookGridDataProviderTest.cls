@IsTest
private class OutlookGridDataProviderTest {

    private static void setupConfig() {
    }

    private static String sampleMessagesResponseJson() {
        return '{' +
            '"@odata.count":2,' +
            '"@odata.nextLink":"https://graph.microsoft.com/v1.0/me/messages?$skip=2",' +
            '"value":[' +
                '{' +
                    '"id":"msg-1",' +
                    '"subject":"Project Update",' +
                    '"bodyPreview":"Latest progress report...",' +
                    '"receivedDateTime":"2026-09-30T14:30:00Z",' +
                    '"isRead":false,' +
                    '"hasAttachments":true,' +
                    '"webLink":"https://outlook.live.com/mail/msg-1",' +
                    '"from":{"emailAddress":{"name":"John Doe","address":"john@example.com"}},' +
                    '"toRecipients":[{"emailAddress":{"name":"Jane Smith","address":"jane@example.com"}}]' +
                '},' +
                '{' +
                    '"id":"msg-2",' +
                    '"subject":"Invoice Due",' +
                    '"bodyPreview":"Please find invoice attached",' +
                    '"receivedDateTime":"2026-09-29T11:00:00Z",' +
                    '"isRead":true,' +
                    '"hasAttachments":false,' +
                    '"webLink":"https://outlook.live.com/mail/msg-2",' +
                    '"from":{"emailAddress":{"name":"billing@acme.com","address":"billing@acme.com"}},' +
                    '"toRecipients":[]' +
                '}' +
            ']' +
        '}';
    }

    private static String sampleEventsResponseJson() {
        return '{' +
            '"@odata.count":1,' +
            '"value":[' +
                '{' +
                    '"id":"evt-1",' +
                    '"subject":"Client Demo",' +
                    '"start":{"dateTime":"2026-10-05T15:00:00.0000000Z"},' +
                    '"end":{"dateTime":"2026-10-05T16:00:00.0000000Z"},' +
                    '"organizer":{"emailAddress":{"name":"Demo Lead","address":"demo@example.com"}},' +
                    '"location":{"displayName":"Meeting Room 1"},' +
                    '"isAllDay":false,' +
                    '"webLink":"https://outlook.live.com/calendar/evt-1"' +
                '}' +
            ']' +
        '}';
    }

    @IsTest
    static void getCapabilities_messagesResource_returnsMessageColumns() {
        OutlookGridDataProvider provider = new OutlookGridDataProvider();
        appcg.GridDataProviderTypesV1.ProviderContext context = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities capabilities = provider.getCapabilities(context);
        Test.stopTest();

        System.assertNotEquals(null, capabilities);
        System.assertEquals(9, capabilities.columns.size());
        System.assertEquals(true, capabilities.supportsServerPagination);
        System.assertEquals(50, capabilities.maxPageSize);
        System.assert(capabilities.supportedFeatures.contains('SEARCH'));
        System.assert(capabilities.supportedFeatures.contains('REFRESH'));

        Map<String, appcg.GridDataProviderTypesV1.ColumnDefinition> colMap = new Map<String, appcg.GridDataProviderTypesV1.ColumnDefinition>();
        for (appcg.GridDataProviderTypesV1.ColumnDefinition col : capabilities.columns) {
            colMap.put(col.id, col);
        }
        System.assert(colMap.containsKey('Id'));
        System.assert(colMap.containsKey('From'));
        System.assert(colMap.containsKey('To'));
        System.assert(colMap.containsKey('Subject'));
        System.assert(colMap.containsKey('Date'));
        System.assert(colMap.containsKey('Snippet'));
        System.assert(colMap.containsKey('IsRead'));
        System.assert(colMap.containsKey('HasAttachments'));
        System.assert(colMap.containsKey('WebLink'));
        System.assertEquals(false, colMap.get('Id').visible);
        System.assertEquals('BOOLEAN', colMap.get('IsRead').fieldType);
        System.assertEquals('URL', colMap.get('WebLink').fieldType);
    }

    @IsTest
    static void getCapabilities_eventsResource_returnsEventColumns() {
        OutlookGridDataProvider provider = new OutlookGridDataProvider();
        appcg.GridDataProviderTypesV1.ProviderContext context = new appcg.GridDataProviderTypesV1.ProviderContext();

        appcg__Grid_Definition__c mockDef = new appcg__Grid_Definition__c();
        mockDef.appcg__Data_Provider_Config__c = '{"resource":"events"}';
        OutlookGridDataProvider.testGridDef = mockDef;

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities capabilities = provider.getCapabilities(context);
        Test.stopTest();

        OutlookGridDataProvider.testGridDef = null;

        System.assertNotEquals(null, capabilities);
        System.assertEquals(8, capabilities.columns.size());
        Map<String, appcg.GridDataProviderTypesV1.ColumnDefinition> colMap = new Map<String, appcg.GridDataProviderTypesV1.ColumnDefinition>();
        for (appcg.GridDataProviderTypesV1.ColumnDefinition col : capabilities.columns) {
            colMap.put(col.id, col);
        }
        System.assert(colMap.containsKey('Subject'));
        System.assert(colMap.containsKey('Start'));
        System.assert(colMap.containsKey('End'));
        System.assert(colMap.containsKey('Organizer'));
        System.assert(colMap.containsKey('Location'));
        System.assert(colMap.containsKey('IsAllDay'));
    }

    @IsTest
    static void getData_messages_returnsParsedRecords() {
        setupConfig();

        OutlookTestSupport.SingleResponseMock mock = new OutlookTestSupport.SingleResponseMock();
        mock.statusCode = 200;
        mock.body = sampleMessagesResponseJson();
        Test.setMock(HttpCalloutMock.class, mock);

        OutlookGridDataProvider provider = new OutlookGridDataProvider();
        appcg.GridDataProviderTypesV1.QueryRequest request = new appcg.GridDataProviderTypesV1.QueryRequest();
        request.context = new appcg.GridDataProviderTypesV1.ProviderContext();
        request.startIndex = 0;
        request.pageSize = 20;

        Test.startTest();
        appcg.GridDataProviderTypesV1.PageResult result = provider.getData(request);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(2, result.records.size());
        System.assertEquals(2, result.totalCount);

        Map<String, Object> row1 = result.records[0];
        System.assertEquals('msg-1', row1.get('Id'));
        System.assertEquals('Project Update', row1.get('Subject'));
        System.assertEquals('John Doe <john@example.com>', row1.get('From'));
        System.assertEquals('jane@example.com', row1.get('To'));
        System.assertEquals(false, row1.get('IsRead'));
        System.assertEquals(true, row1.get('HasAttachments'));
        System.assertEquals('https://outlook.live.com/mail/msg-1', row1.get('WebLink'));

        Map<String, Object> row2 = result.records[1];
        System.assertEquals('msg-2', row2.get('Id'));
        System.assertEquals('billing@acme.com', row2.get('From'));
        System.assertEquals('', row2.get('To'));
        System.assertEquals(true, row2.get('IsRead'));
    }

    @IsTest
    static void getData_events_returnsParsedRecords() {
        setupConfig();

        OutlookTestSupport.SingleResponseMock mock = new OutlookTestSupport.SingleResponseMock();
        mock.statusCode = 200;
        mock.body = sampleEventsResponseJson();
        Test.setMock(HttpCalloutMock.class, mock);

        appcg__Grid_Definition__c mockDef = new appcg__Grid_Definition__c();
        mockDef.appcg__Data_Provider_Config__c = '{"resource":"events"}';
        OutlookGridDataProvider.testGridDef = mockDef;

        OutlookGridDataProvider provider = new OutlookGridDataProvider();
        appcg.GridDataProviderTypesV1.QueryRequest request = new appcg.GridDataProviderTypesV1.QueryRequest();
        request.context = new appcg.GridDataProviderTypesV1.ProviderContext();
        request.startIndex = 0;
        request.pageSize = 10;

        Test.startTest();
        appcg.GridDataProviderTypesV1.PageResult result = provider.getData(request);
        Test.stopTest();

        OutlookGridDataProvider.testGridDef = null;

        System.assertNotEquals(null, result);
        System.assertEquals(1, result.records.size());
        Map<String, Object> eventRow = result.records[0];
        System.assertEquals('evt-1', eventRow.get('Id'));
        System.assertEquals('Client Demo', eventRow.get('Subject'));
        System.assertEquals('Demo Lead', eventRow.get('Organizer'));
        System.assertEquals('Meeting Room 1', eventRow.get('Location'));
        System.assertEquals(false, eventRow.get('IsAllDay'));
    }

    @IsTest
    static void buildFilterExpression_combinesFilters() {
        OutlookGridDataProvider.OutlookConfig cfg = new OutlookGridDataProvider.OutlookConfig();
        cfg.filter = 'isRead eq false';

        appcg.GridDataProviderTypesV1.QueryRequest request = new appcg.GridDataProviderTypesV1.QueryRequest();

        appcg.GridDataProviderTypesV1.Filter adminFilter = new appcg.GridDataProviderTypesV1.Filter();
        appcg.GridDataProviderTypesV1.FilterRule adminRule = new appcg.GridDataProviderTypesV1.FilterRule();
        adminRule.field = 'hasAttachments';
        adminRule.value = 'true';
        adminFilter.rules = new List<appcg.GridDataProviderTypesV1.FilterRule>{ adminRule };
        request.adminFilter = adminFilter;

        appcg.GridDataProviderTypesV1.Filter userFilter = new appcg.GridDataProviderTypesV1.Filter();
        appcg.GridDataProviderTypesV1.FilterRule userRule = new appcg.GridDataProviderTypesV1.FilterRule();
        userRule.field = 'importance';
        userRule.value = 'high';
        userFilter.rules = new List<appcg.GridDataProviderTypesV1.FilterRule>{ userRule };
        request.userFilter = userFilter;

        String filter = OutlookGridDataProvider.buildFilterExpression(request, cfg);

        System.assertNotEquals(null, filter);
        System.assert(filter.contains('(isRead eq false)'));
        System.assert(filter.contains('(hasAttachments eq \'true\')'));
        System.assert(filter.contains('(importance eq \'high\')'));
    }

    @IsTest
    static void resolveParentFieldValue_withContact_returnsEmail() {
        Contact testContact = new Contact(FirstName = 'Test', LastName = 'Contact', Email = 'contact@example.com');
        insert testContact;

        appcg.GridDataProviderTypesV1.ProviderContext context = new appcg.GridDataProviderTypesV1.ProviderContext();
        context.parentId = testContact.Id;

        String resolved = OutlookGridDataProvider.resolveParentFieldValue(context, 'Email');
        System.assertEquals('contact@example.com', resolved);

        // Null context handling
        System.assertEquals(null, OutlookGridDataProvider.resolveParentFieldValue(null, 'Email'));
    }

    @IsTest
    static void parseMinimalMessageAndEventRows() {
        Map<String, Object> msgRow = OutlookGridDataProvider.parseMessageRow(new Map<String, Object>{ 'id' => 'm1' });
        System.assertEquals('m1', msgRow.get('Id'));
        System.assertEquals('(No Subject)', msgRow.get('Subject'));
        System.assertEquals('', msgRow.get('From'));
        System.assertEquals('', msgRow.get('To'));
        System.assertEquals(false, msgRow.get('IsRead'));

        Map<String, Object> evtRow = OutlookGridDataProvider.parseEventRow(new Map<String, Object>{ 'id' => 'e1' });
        System.assertEquals('e1', evtRow.get('Id'));
        System.assertEquals('(No Subject)', evtRow.get('Subject'));
        System.assertEquals('', evtRow.get('Organizer'));
        System.assertEquals('', evtRow.get('Location'));
    }

    @IsTest
    static void formatIsoDateTime_formatsCorrectly() {
        String formatted = OutlookGridDataProvider.formatIsoDateTime('2026-09-30T14:30:00Z');
        System.assertNotEquals('', formatted);
        System.assertNotEquals('2026-09-30T14:30:00Z', formatted);

        System.assertEquals('', OutlookGridDataProvider.formatIsoDateTime(null));
        System.assertEquals('invalid-date', OutlookGridDataProvider.formatIsoDateTime('invalid-date'));
    }
}
