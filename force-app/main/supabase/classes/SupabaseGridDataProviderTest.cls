@IsTest
private class SupabaseGridDataProviderTest {

    private static void setupConfig() {
    }

    private static String sampleContactsJson() {
        return '[' +
            '{"id":1,"name":"Alice Johnson","email":"alice@example.com","is_active":true,"score":98.5,"created_at":"2026-08-20T12:30:00Z"},' +
            '{"id":2,"name":"Bob Smith","email":"bob@example.com","is_active":false,"score":82.0,"created_at":"2026-08-21T14:15:00Z"}' +
        ']';
    }

    @IsTest
    static void getCapabilities_and_getData_withDynamicColumnInference() {
        setupConfig();

        SupabaseTestSupport.RoutingMock mock = new SupabaseTestSupport.RoutingMock();
        mock.byEndpointContains.put('/rest/v1/contacts', SupabaseTestSupport.makeResponse(200, sampleContactsJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        SupabaseGridDataProvider provider = new SupabaseGridDataProvider();
        SupabaseGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"tableName":"contacts","idColumn":"id"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(ctx);

        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assert(caps.supportedFeatures.contains('SEARCH'));
        System.assertEquals(true, caps.supportsServerPagination);
        System.assertEquals(100, caps.maxPageSize);
        System.assert(caps.columns.size() >= 5, 'Should infer all fields + hidden Id');

        System.assertEquals(2, page.records.size());
        System.assertEquals('1', page.records[0].get('Id'));
        System.assertEquals('Alice Johnson', page.records[0].get('name'));
    }

    @IsTest
    static void getCapabilities_withCustomColumnsOverride() {
        setupConfig();

        SupabaseTestSupport.RoutingMock mock = new SupabaseTestSupport.RoutingMock();
        mock.byEndpointContains.put('/rest/v1/products', SupabaseTestSupport.makeResponse(200, '[{"sku":"PRD-1","price":29.99}]'));
        Test.setMock(HttpCalloutMock.class, mock);

        SupabaseGridDataProvider provider = new SupabaseGridDataProvider();
        SupabaseGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"tableName":"products","columns":[' +
                '{"id":"sku","label":"Product SKU","type":"TEXT","isReadOnly":true,"width":"150px"},' +
                '{"id":"price","label":"Price ($)","type":"NUMBER","isReadOnly":false}' +
            ']}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(ctx);
        Test.stopTest();

        System.assertEquals(2, caps.columns.size());
        System.assertEquals('Product SKU', caps.columns[0].label);
        System.assertEquals('Price ($)', caps.columns[1].label);
    }

    @IsTest
    static void getData_withSearchFilter() {
        setupConfig();

        SupabaseTestSupport.RoutingMock mock = new SupabaseTestSupport.RoutingMock();
        mock.byEndpointContains.put('/rest/v1/contacts', SupabaseTestSupport.makeResponse(200, sampleContactsJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        SupabaseGridDataProvider provider = new SupabaseGridDataProvider();
        SupabaseGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"tableName":"contacts"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;
        req.searchTerm = 'Bob';

        Test.startTest();
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assertEquals(1, page.records.size());
        System.assertEquals('Bob Smith', page.records[0].get('name'));
    }

    @IsTest
    static void saveRecords_insertAndEdit() {
        setupConfig();

        SupabaseTestSupport.RoutingMock mock = new SupabaseTestSupport.RoutingMock();
        mock.byEndpointContains.put('/rest/v1/contacts', SupabaseTestSupport.makeResponse(200, '[{"id":3,"name":"Charlie"}]'));
        Test.setMock(HttpCalloutMock.class, mock);

        SupabaseGridDataProvider provider = new SupabaseGridDataProvider();
        SupabaseGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"tableName":"contacts","idColumn":"id"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        appcg.GridDataProviderTypesV1.SaveRequest req = new appcg.GridDataProviderTypesV1.SaveRequest();
        req.context = ctx;
        req.records = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Id' => 'TEMP_1', 'name' => 'Charlie', 'email' => 'charlie@example.com' },
            new Map<String, Object>{ 'Id' => '1', 'name' => 'Alice Updated' }
        };

        Test.startTest();
        appcg.GridDataProviderTypesV1.SaveResult saveResult = provider.saveRecords(req);
        Test.stopTest();

        System.assertEquals(2, saveResult.records.size());
        System.assertEquals('3', saveResult.records[0].get('Id'));
    }

    @IsTest
    static void deleteRecords_dispatchesDelete() {
        setupConfig();

        SupabaseTestSupport.RoutingMock mock = new SupabaseTestSupport.RoutingMock();
        mock.byEndpointContains.put('/rest/v1/contacts', SupabaseTestSupport.makeResponse(204, ''));
        Test.setMock(HttpCalloutMock.class, mock);

        SupabaseGridDataProvider provider = new SupabaseGridDataProvider();
        SupabaseGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"tableName":"contacts","idColumn":"id"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        appcg.GridDataProviderTypesV1.DeleteRequest req = new appcg.GridDataProviderTypesV1.DeleteRequest();
        req.context = ctx;
        req.recordIds = new List<String>{ '1', '2' };

        Test.startTest();
        provider.deleteRecords(req);
        Test.stopTest();

        System.assert(true, 'Deletion completed successfully');
    }

    @IsTest
    static void parseConfig_validationErrors() {
        SupabaseGridDataProvider.testGridDef = null;
        try {
            SupabaseGridDataProvider.parseConfig(null);
            System.assert(false, 'Expected GridUiException');
        } catch (SupabaseGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('requires configuration'));
        }

        SupabaseGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"select":"*"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();
        try {
            SupabaseGridDataProvider.parseConfig(ctx);
            System.assert(false, 'Expected GridUiException');
        } catch (SupabaseGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('tableName is required'));
        }
    }

    @IsTest
    static void getData_withRecordLimit() {
        setupConfig();

        SupabaseTestSupport.RoutingMock mock = new SupabaseTestSupport.RoutingMock();
        mock.byEndpointContains.put('/rest/v1/contacts', SupabaseTestSupport.makeResponse(200, sampleContactsJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        SupabaseGridDataProvider provider = new SupabaseGridDataProvider();
        SupabaseGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"tableName":"contacts"}',
            appcg__Pagination_Type__c = 'Client-Side',
            appcg__Record_Limit__c = 1
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        provider.getCapabilities(ctx);

        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;
        req.pageSize = 1;
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assertEquals(1, page.records.size(), 'Should trim records to appcg__Record_Limit__c');
    }

    @IsTest
    static void getData_withParentFiltering() {
        setupConfig();

        Account parent = new Account(Name = 'Supabase Parent');
        insert parent;

        SupabaseTestSupport.RoutingMock mock = new SupabaseTestSupport.RoutingMock();
        mock.byEndpointContains.put('/rest/v1/survey_items', SupabaseTestSupport.makeResponse(200, '[{"id":10,"question":"Q1","survey_id":"' + parent.Id + '"}]'));
        Test.setMock(HttpCalloutMock.class, mock);

        SupabaseGridDataProvider provider = new SupabaseGridDataProvider();
        SupabaseGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"tableName":"survey_items","parentMatchColumn":"survey_id"}'
        );

        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();
        ctx.parentId = parent.Id;

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(ctx);

        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assertEquals(1, page.records.size());
        System.assertEquals('10', page.records[0].get('Id'));
    }

    @IsTest
    static void getData_withSurveyIdAndCustomFilter() {
        setupConfig();

        String surveyId = 'SRV-0001';

        SupabaseTestSupport.RoutingMock mock = new SupabaseTestSupport.RoutingMock();
        mock.byEndpointContains.put('/rest/v1/survey_items', SupabaseTestSupport.makeResponse(200, '[{"id":11,"question":"Q2","score":8.5}]'));
        Test.setMock(HttpCalloutMock.class, mock);

        SupabaseGridDataProvider provider = new SupabaseGridDataProvider();
        SupabaseGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"tableName":"survey_items","parentMatchColumn":"survey_id","surveyId":"' + surveyId + '","filterQuery":"score=gte.8"}'
        );

        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assertEquals(1, page.records.size());
    }
}
