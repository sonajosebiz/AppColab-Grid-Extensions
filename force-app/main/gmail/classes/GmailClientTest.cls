@IsTest
private class GmailClientTest {
    private static GmailTestSupport.SingleResponseMock arrange(String responseBody) {

        GmailTestSupport.SingleResponseMock mock = new GmailTestSupport.SingleResponseMock();
        mock.statusCode = 200;
        mock.body = responseBody;
        Test.setMock(HttpCalloutMock.class, mock);
        return mock;
    }

    @IsTest
    static void sendEmail_dispatchesPostWithBase64UrlRawMime() {
        GmailTestSupport.SingleResponseMock mock = arrange('{"id":"msg-1","labelIds":["SENT"]}');

        Test.startTest();
        Map<String, Object> result = new GmailClient().sendEmail(
            'someone@example.com',
            'Hello from Salesforce',
            '<p>It works</p>'
        );
        Test.stopTest();

        System.assertEquals('POST', mock.lastMethod);
        System.assert(mock.lastEndpoint.endsWith('/gmail/v1/users/me/messages/send'));
        System.assertEquals('msg-1', result.get('id'));

        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(mock.lastBody);
        String raw = (String) payload.get('raw');
        System.assert(!raw.contains('+') && !raw.contains('/') && !raw.contains('='),
            'raw must be base64url without padding: ' + raw);

        String mime = base64UrlDecode(raw).toString();
        System.assert(mime.contains('To: someone@example.com'), mime);
        System.assert(mime.contains('Subject: Hello from Salesforce'), mime);
        System.assert(mime.contains('<p>It works</p>'), mime);
    }

    @IsTest
    static void getProfile_dispatchesGet() {
        GmailTestSupport.SingleResponseMock mock = arrange('{"emailAddress":"me@example.com"}');

        Test.startTest();
        Map<String, Object> profile = new GmailClient().getProfile();
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.endsWith('/gmail/v1/users/me/profile'));
        System.assertEquals('me@example.com', profile.get('emailAddress'));
    }

    @IsTest
    static void listMessages_encodesQueryAndCapsDefault() {
        GmailTestSupport.SingleResponseMock mock = arrange('{"messages":[],"resultSizeEstimate":0}');

        Test.startTest();
        new GmailClient().listMessages('from:boss@example.com is:unread', null);
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/gmail/v1/users/me/messages?maxResults=10'), mock.lastEndpoint);
        System.assert(mock.lastEndpoint.contains('q=from%3Aboss%40example.com'), mock.lastEndpoint);
        System.assert(!mock.lastEndpoint.contains(' '), mock.lastEndpoint);
    }

    @IsTest
    static void getMessage_dispatchesGetById() {
        GmailTestSupport.SingleResponseMock mock = arrange('{"id":"abc123"}');

        Test.startTest();
        Map<String, Object> msg = new GmailClient().getMessage('abc123');
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.endsWith('/gmail/v1/users/me/messages/abc123'));
        System.assertEquals('abc123', msg.get('id'));
    }

    private static Blob base64UrlDecode(String input) {
        String s = input.replace('-', '+').replace('_', '/');
        while (Math.mod(s.length(), 4) != 0) {
            s += '=';
        }
        return EncodingUtil.base64Decode(s);
    }
}