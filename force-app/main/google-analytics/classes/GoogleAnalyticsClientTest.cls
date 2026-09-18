@IsTest
private class GoogleAnalyticsClientTest {
    @IsTest
    static void runReport_dispatchesPost() {

        GoogleAnalyticsTestSupport.SingleResponseMock mock = new GoogleAnalyticsTestSupport.SingleResponseMock();
        mock.statusCode = 200;
        mock.body = '{"rowCount":0,"rows":[]}';
        Test.setMock(HttpCalloutMock.class, mock);

        Map<String, Object> request = new Map<String, Object>{
            'dimensions' => new List<Object>{ new Map<String, Object>{ 'name' => 'country' } },
            'metrics' => new List<Object>{ new Map<String, Object>{ 'name' => 'activeUsers' } }
        };

        Test.startTest();
        Map<String, Object> report = new GoogleAnalyticsClient().runReport('12345', request);
        Test.stopTest();

        System.assertEquals('POST', mock.lastMethod);
        System.assert(mock.lastEndpoint.endsWith('/v1beta/properties/12345:runReport'));
        System.assertNotEquals(null, report);
    }

    @IsTest
    static void transientFailure_isRetried_andReported() {
        GoogleAnalyticsTestSupport.SingleResponseMock mock = new GoogleAnalyticsTestSupport.SingleResponseMock();
        mock.statusCode = 503;
        mock.body = '{"error":"temporarily unavailable"}';
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        try {
            new GoogleAnalyticsClient().runReport('12345', new Map<String, Object>());
            System.assert(false, 'Expected an HTTP exception.');
        } catch (GoogleAnalyticsClient.HttpException e) {
            System.assert(e.getMessage().contains('HTTP 503'));
        }
        Test.stopTest();

        System.assertEquals(2, mock.callCount);
    }
}
