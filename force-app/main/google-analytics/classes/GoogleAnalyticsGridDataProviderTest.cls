@IsTest
private class GoogleAnalyticsGridDataProviderTest {
    private static void setupConfig() {
    }

    private static String sampleTopPagesJson() {
        return '{"rows":[' +
            '{"dimensionValues":[{"value":"AppColab – Software"},{"value":"/"}],"metricValues":[{"value":"16"},{"value":"12"},{"value":"120"}]},' +
            '{"dimensionValues":[{"value":"Barcode To Cloud – AppColab"},{"value":"/barcode-to-cloud"}],"metricValues":[{"value":"5"},{"value":"4"},{"value":"45"}]}' +
        ']}';
    }

    private static String sampleGeoJson() {
        return '{"rows":[' +
            '{"dimensionValues":[{"value":"United States"},{"value":"San Francisco"}],"metricValues":[{"value":"22"},{"value":"20"},{"value":"35"}]},' +
            '{"dimensionValues":[{"value":"India"},{"value":"Bengaluru"}],"metricValues":[{"value":"7"},{"value":"5"},{"value":"12"}]}' +
        ']}';
    }

    private static String sampleTrafficSourcesJson() {
        return '{"rows":[' +
            '{"dimensionValues":[{"value":"Direct"},{"value":"(direct) / (none)"}],"metricValues":[{"value":"35"},{"value":"25"},{"value":"20"}]},' +
            '{"dimensionValues":[{"value":"Organic Search"},{"value":"google / organic"}],"metricValues":[{"value":"15"},{"value":"10"},{"value":"8"}]}' +
        ']}';
    }

    private static String sampleUserActivityJson() {
        return '{"rows":[' +
            '{"dimensionValues":[{"value":"202608241730"},{"value":"Barcode To Cloud – AppColab"},{"value":"page_view"},{"value":"United States"}],"metricValues":[{"value":"1"}]}' +
        ']}';
    }

    @IsTest
    static void getCapabilities_and_getData_topPages_withCacheAndSearch() {
        setupConfig();

        GoogleAnalyticsTestSupport.RoutingMock mock = new GoogleAnalyticsTestSupport.RoutingMock();
        mock.byEndpointContains.put(':runReport', GoogleAnalyticsTestSupport.makeResponse(200, sampleTopPagesJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        GoogleAnalyticsGridDataProvider provider = new GoogleAnalyticsGridDataProvider();
        GoogleAnalyticsGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"propertyId":"446193663","reportType":"top_pages","dateRange":"last_30_days"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(ctx);

        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;
        req.searchTerm = 'Barcode';

        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assertNotEquals(null, caps);
        System.assertEquals(6, caps.columns.size());
        System.assert(caps.supportedFeatures.contains('SEARCH'));
        System.assert(caps.supportedFeatures.contains('REFRESH'));
        System.assert(caps.supportedFeatures.contains('DOWNLOAD_CSV'));

        // Search filtered
        System.assertEquals(1, page.records.size());
        System.assertEquals('Barcode To Cloud – AppColab', page.records[0].get('pageTitle'));
        System.assertEquals('/barcode-to-cloud', page.records[0].get('pagePath'));
        System.assertEquals(5, page.records[0].get('screenPageViews'));
    }

    @IsTest
    static void getData_geo_report() {
        setupConfig();

        GoogleAnalyticsTestSupport.RoutingMock mock = new GoogleAnalyticsTestSupport.RoutingMock();
        mock.byEndpointContains.put(':runReport', GoogleAnalyticsTestSupport.makeResponse(200, sampleGeoJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        GoogleAnalyticsGridDataProvider provider = new GoogleAnalyticsGridDataProvider();
        GoogleAnalyticsGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"propertyId":"446193663","reportType":"geo","dateRange":"last_7_days"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(ctx);

        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assertEquals(6, caps.columns.size());
        System.assertEquals(2, page.records.size());
        System.assertEquals('United States', page.records[0].get('country'));
        System.assertEquals(22, page.records[0].get('activeUsers'));
    }

    @IsTest
    static void getData_trafficSources_report() {
        setupConfig();

        GoogleAnalyticsTestSupport.RoutingMock mock = new GoogleAnalyticsTestSupport.RoutingMock();
        mock.byEndpointContains.put(':runReport', GoogleAnalyticsTestSupport.makeResponse(200, sampleTrafficSourcesJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        GoogleAnalyticsGridDataProvider provider = new GoogleAnalyticsGridDataProvider();
        GoogleAnalyticsGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"propertyId":"446193663","reportType":"traffic_sources","dateRange":"last_28_days"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(ctx);

        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assertEquals(6, caps.columns.size());
        System.assertEquals(2, page.records.size());
        System.assertEquals('Direct', page.records[0].get('sessionDefaultChannelGroup'));
        System.assertEquals(35, page.records[0].get('sessions'));
    }

    @IsTest
    static void getData_userActivity_report_withParentId() {
        setupConfig();

        GoogleAnalyticsTestSupport.RoutingMock mock = new GoogleAnalyticsTestSupport.RoutingMock();
        mock.byEndpointContains.put(':runReport', GoogleAnalyticsTestSupport.makeResponse(200, sampleUserActivityJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        GoogleAnalyticsGridDataProvider provider = new GoogleAnalyticsGridDataProvider();
        GoogleAnalyticsGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"propertyId":"446193663","reportType":"user_activity","dateRange":"last_90_days"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();
        ctx.parentId = '003000000000001';

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(ctx);

        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assertEquals(6, caps.columns.size());
        System.assertEquals(1, page.records.size());
        System.assertEquals('2026-08-24 17:30', page.records[0].get('dateHourMinute'));
        System.assertEquals('Barcode To Cloud – AppColab', page.records[0].get('pageTitle'));
        System.assertEquals('page_view', page.records[0].get('eventName'));
        System.assertEquals('United States', page.records[0].get('country'));
    }

    @IsTest
    static void parseConfig_validationAndErrors() {
        GoogleAnalyticsGridDataProvider.testGridDef = null;
        try {
            GoogleAnalyticsGridDataProvider.parseConfig(null);
            System.assert(false, 'Expected GridUiException');
        } catch (GoogleAnalyticsGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('requires configuration'));
        }

        GoogleAnalyticsGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"reportType":"top_pages"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();
        try {
            GoogleAnalyticsGridDataProvider.parseConfig(ctx);
            System.assert(false, 'Expected GridUiException');
        } catch (GoogleAnalyticsGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('propertyId is required'));
        }

        GoogleAnalyticsGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"propertyId":"12345","limit":5000}'
        );
        GoogleAnalyticsGridDataProvider.AnalyticsConfig cfg = GoogleAnalyticsGridDataProvider.parseConfig(ctx);
        System.assertEquals('12345', cfg.propertyId);
        System.assertEquals('top_pages', cfg.reportType);
        System.assertEquals('last_30_days', cfg.dateRange);
        System.assertEquals(1000, cfg.recordLimit);
    }

    @IsTest
    static void resolveDateRange_and_helpers() {
        System.assertEquals('7daysAgo', GoogleAnalyticsGridDataProvider.resolveDateRange('last_7_days').get('startDate'));
        System.assertEquals('28daysAgo', GoogleAnalyticsGridDataProvider.resolveDateRange('last_28_days').get('startDate'));
        System.assertEquals('90daysAgo', GoogleAnalyticsGridDataProvider.resolveDateRange('last_90_days').get('startDate'));
        System.assertEquals('today', GoogleAnalyticsGridDataProvider.resolveDateRange('today').get('startDate'));
        System.assertEquals('yesterday', GoogleAnalyticsGridDataProvider.resolveDateRange('yesterday').get('startDate'));

        System.assertEquals('2026-08-24 17:30', GoogleAnalyticsGridDataProvider.formatGaDateTime('202608241730'));
        System.assertEquals('', GoogleAnalyticsGridDataProvider.formatGaDateTime(''));
    }
}
