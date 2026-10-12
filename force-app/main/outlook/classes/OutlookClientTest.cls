@IsTest
private class OutlookClientTest {
    private static OutlookTestSupport.SingleResponseMock arrange(String responseBody) {
        OutlookTestSupport.SingleResponseMock mock = new OutlookTestSupport.SingleResponseMock();
        mock.statusCode = 200;
        mock.body = responseBody;
        Test.setMock(HttpCalloutMock.class, mock);
        return mock;
    }

    @IsTest
    static void listMessages_dispatchesGetWithOrderAndSelect() {
        String jsonRes = '{"@odata.count":1,"value":[{"id":"msg-123","subject":"Project Kickoff","bodyPreview":"Hello team"}]}';
        OutlookTestSupport.SingleResponseMock mock = arrange(jsonRes);

        Test.startTest();
        Map<String, Object> result = new OutlookClient().listMessages(20, 0, null, null);
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/v1.0/me/messages'), mock.lastEndpoint);
        System.assert(mock.lastEndpoint.contains('%24top=20') || mock.lastEndpoint.contains('$top=20'), mock.lastEndpoint);
        System.assert(mock.lastEndpoint.contains('receivedDateTime'), mock.lastEndpoint);
        System.assert(result.containsKey('value'));
        List<Object> items = (List<Object>) result.get('value');
        System.assertEquals(1, items.size());
    }

    @IsTest
    static void listMessages_withSearch_omitsOrderBy() {
        String jsonRes = '{"value":[]}';
        OutlookTestSupport.SingleResponseMock mock = arrange(jsonRes);

        Test.startTest();
        new OutlookClient().listMessages(10, null, null, 'salesforce');
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('%24search=') || mock.lastEndpoint.contains('$search='), mock.lastEndpoint);
        System.assert(!mock.lastEndpoint.contains('$orderby='), 'Graph API does not allow $orderby with $search: ' + mock.lastEndpoint);
    }

    @IsTest
    static void listMessages_withFilter_includesFilterParam() {
        String jsonRes = '{"value":[]}';
        OutlookTestSupport.SingleResponseMock mock = arrange(jsonRes);

        Test.startTest();
        new OutlookClient().listMessages(10, 5, 'isRead eq false', null);
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('%24filter=') || mock.lastEndpoint.contains('$filter='), mock.lastEndpoint);
        System.assert(mock.lastEndpoint.contains('%24skip=5') || mock.lastEndpoint.contains('$skip=5'), mock.lastEndpoint);
    }

    @IsTest
    static void getMessage_dispatchesGetById() {
        String jsonRes = '{"id":"msg-abc","subject":"Test Single Message"}';
        OutlookTestSupport.SingleResponseMock mock = arrange(jsonRes);

        Test.startTest();
        Map<String, Object> result = new OutlookClient().getMessage('msg-abc');
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.endsWith('/v1.0/me/messages/msg-abc'), mock.lastEndpoint);
        System.assertEquals('msg-abc', result.get('id'));
    }

    @IsTest
    static void listEvents_dispatchesGet() {
        String jsonRes = '{"value":[{"id":"evt-1","subject":"Team Sync"}]}';
        OutlookTestSupport.SingleResponseMock mock = arrange(jsonRes);

        Test.startTest();
        Map<String, Object> result = new OutlookClient().listEvents(15, 0, null);
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/v1.0/me/events'), mock.lastEndpoint);
        System.assert(mock.lastEndpoint.contains('start%2FdateTime') || mock.lastEndpoint.contains('start/dateTime'), mock.lastEndpoint);
        System.assert(result.containsKey('value'));
    }

    @IsTest
    static void sendMail_dispatchesPostWithPayload() {
        OutlookTestSupport.SingleResponseMock mock = arrange('');

        Test.startTest();
        Map<String, Object> result = new OutlookClient().sendMail(
            'partner@example.com',
            'Proposal Update',
            '<p>Please review attached updates</p>'
        );
        Test.stopTest();

        System.assertEquals('POST', mock.lastMethod);
        System.assert(mock.lastEndpoint.endsWith('/v1.0/me/sendMail'), mock.lastEndpoint);
        System.assertEquals('SENT', result.get('status'));

        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(mock.lastBody);
        Map<String, Object> message = (Map<String, Object>) payload.get('message');
        System.assertEquals('Proposal Update', message.get('subject'));
        List<Object> recipients = (List<Object>) message.get('toRecipients');
        System.assertEquals(1, recipients.size());
    }

    @IsTest
    static void getProfile_dispatchesGet() {
        String jsonRes = '{"displayName":"Jane Doe","mail":"jane@example.com"}';
        OutlookTestSupport.SingleResponseMock mock = arrange(jsonRes);

        Test.startTest();
        Map<String, Object> profile = new OutlookClient().getProfile();
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.endsWith('/v1.0/me'), mock.lastEndpoint);
        System.assertEquals('Jane Doe', profile.get('displayName'));
    }
}
