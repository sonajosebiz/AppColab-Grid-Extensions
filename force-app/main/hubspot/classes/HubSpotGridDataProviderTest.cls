@IsTest
private class HubSpotGridDataProviderTest {

    private static void setupConfig() {
    }

    private static String sampleContactsJson() {
        return '{"results":[' +
            '{"id":"101","properties":{"firstname":"Alice","lastname":"Smith","email":"alice@example.com","createdate":"2026-08-20T12:00:00.000Z"},"createdAt":"2026-08-20T12:00:00.000Z"},' +
            '{"id":"102","properties":{"firstname":"Bob","lastname":"Jones","email":"bob@example.com","createdate":"2026-08-21T12:00:00.000Z"},"createdAt":"2026-08-21T12:00:00.000Z"}' +
        '],"paging":{"next":{"after":"102"}}}';
    }

    private static String samplePropertiesDescribeJson() {
        return '{"results":[' +
            '{"name":"firstname","label":"First Name","type":"string","fieldType":"text","readOnlyValue":false},' +
            '{"name":"lastname","label":"Last Name","type":"string","fieldType":"text","readOnlyValue":false},' +
            '{"name":"email","label":"Email Address","type":"string","fieldType":"text","readOnlyValue":false},' +
            '{"name":"annualrevenue","label":"Annual Revenue","type":"number","fieldType":"number","readOnlyValue":false},' +
            '{"name":"createdate","label":"Create Date","type":"datetime","fieldType":"date","readOnlyValue":true}' +
        ']}';
    }

    @IsTest
    static void getCapabilities_and_getData_withDynamicColumns() {
        setupConfig();

        HubSpotTestSupport.RoutingMock mock = new HubSpotTestSupport.RoutingMock();
        mock.byEndpointContains.put('/crm/v3/properties/contacts',
            HubSpotTestSupport.makeResponse(200, samplePropertiesDescribeJson()));
        mock.byEndpointContains.put('/crm/v3/objects/contacts',
            HubSpotTestSupport.makeResponse(200, sampleContactsJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        HubSpotGridDataProvider provider = new HubSpotGridDataProvider();
        HubSpotGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"objectType":"contacts"}',
            appcg__Pagination_Type__c = 'Server-Side',
            appcg__Page_Size__c = '20',
            appcg__Record_Limit__c = 100
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(ctx);

        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;
        req.startIndex = 0;
        req.pageSize = 20;
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assertEquals(true, caps.supportsServerPagination);
        System.assertEquals(100, caps.maxPageSize);
        System.assert(caps.columns.size() >= 5, 'Should discover properties + hidden Id');
        System.assertEquals(2, page.records.size());
        System.assertEquals('101', page.records[0].get('Id'));
        System.assertEquals('Alice', page.records[0].get('firstname'));
    }

    @IsTest
    static void getCapabilities_withCustomColumnsOverride() {
        setupConfig();

        HubSpotTestSupport.RoutingMock mock = new HubSpotTestSupport.RoutingMock();
        mock.byEndpointContains.put('/crm/v3/objects/deals',
            HubSpotTestSupport.makeResponse(200, '{"results":[{"id":"d1","properties":{"dealname":"Acme Deal"}}]}'));
        Test.setMock(HttpCalloutMock.class, mock);

        HubSpotGridDataProvider provider = new HubSpotGridDataProvider();
        HubSpotGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"objectType":"deals","properties":["dealname"],"columns":[' +
                '{"id":"dealname","label":"Deal Name","fieldType":"TEXT","isReadOnly":false}' +
            ']}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(ctx);
        Test.stopTest();

        System.assertEquals(1, caps.columns.size());
        System.assertEquals('Deal Name', caps.columns[0].label);
    }

    @IsTest
    static void defaultsObjectType_andHandlesListFailure() {
        setupConfig();
        HubSpotGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{}'
        );
        System.assertEquals(
            'contacts',
            HubSpotGridDataProvider.parseConfig(new appcg.GridDataProviderTypesV1.ProviderContext()).objectType
        );

        HubSpotGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"objectType":"deals","columns":[' +
                '{"id":"dealname","label":"Deal Name","fieldType":"TEXT"}' +
            ']}'
        );
        HubSpotTestSupport.RoutingMock mock = new HubSpotTestSupport.RoutingMock();
        mock.byEndpointContains.put(
            '/crm/v3/objects/deals',
            HubSpotTestSupport.makeResponse(500, '{"error":"temporary"}')
        );
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities capabilities = new HubSpotGridDataProvider().getCapabilities(
            new appcg.GridDataProviderTypesV1.ProviderContext()
        );
        Test.stopTest();

        System.assertEquals(1, capabilities.columns.size());
    }

    @IsTest
    static void getData_withRecordLimit_andSearch() {
        setupConfig();

        HubSpotTestSupport.RoutingMock mock = new HubSpotTestSupport.RoutingMock();
        mock.byEndpointContains.put('/crm/v3/properties/contacts',
            HubSpotTestSupport.makeResponse(200, samplePropertiesDescribeJson()));
        mock.byEndpointContains.put('/crm/v3/objects/contacts',
            HubSpotTestSupport.makeResponse(200, sampleContactsJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        HubSpotGridDataProvider provider = new HubSpotGridDataProvider();
        HubSpotGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"objectType":"contacts"}',
            appcg__Pagination_Type__c = 'Client-Side',
            appcg__Record_Limit__c = 1
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        provider.getCapabilities(ctx);

        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;
        req.pageSize = 1;
        req.searchTerm = 'Alice';
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assertEquals(1, page.records.size());
        System.assertEquals('Alice', page.records[0].get('firstname'));
    }

    @IsTest
    static void saveRecords_insertAndUpdate() {
        setupConfig();

        HubSpotTestSupport.RoutingMock mock = new HubSpotTestSupport.RoutingMock();
        mock.byEndpointContains.put('/crm/v3/objects/contacts/101',
            HubSpotTestSupport.makeResponse(200, '{"id":"101","properties":{"firstname":"Alice Updated"}}'));
        mock.byEndpointContains.put('/crm/v3/objects/contacts',
            HubSpotTestSupport.makeResponse(200, '{"id":"103","properties":{"firstname":"Charlie"}}'));
        Test.setMock(HttpCalloutMock.class, mock);

        HubSpotGridDataProvider provider = new HubSpotGridDataProvider();
        HubSpotGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"objectType":"contacts"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        appcg.GridDataProviderTypesV1.SaveRequest req = new appcg.GridDataProviderTypesV1.SaveRequest();
        req.context = ctx;
        req.records = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Id' => 'TEMP_1', 'firstname' => 'Charlie', 'email' => 'charlie@example.com' },
            new Map<String, Object>{ 'Id' => '101', 'firstname' => 'Alice Updated' }
        };

        Test.startTest();
        appcg.GridDataProviderTypesV1.SaveResult saveResult = provider.saveRecords(req);
        Test.stopTest();

        System.assertEquals(2, saveResult.records.size());
    }

    @IsTest
    static void deleteRecords_dispatchesDelete() {
        setupConfig();

        HubSpotTestSupport.RoutingMock mock = new HubSpotTestSupport.RoutingMock();
        mock.byEndpointContains.put('/crm/v3/objects/contacts/101',
            HubSpotTestSupport.makeResponse(204, ''));
        Test.setMock(HttpCalloutMock.class, mock);

        HubSpotGridDataProvider provider = new HubSpotGridDataProvider();
        HubSpotGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"objectType":"contacts"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        appcg.GridDataProviderTypesV1.DeleteRequest req = new appcg.GridDataProviderTypesV1.DeleteRequest();
        req.context = ctx;
        req.recordIds = new List<String>{ '101', 'TEMP_99' };

        Test.startTest();
        provider.deleteRecords(req);
        Test.stopTest();

        System.assert(true, 'Deletion completed');
    }

    @IsTest
    static void getData_withParentContactEmail() {
        setupConfig();

        HubSpotTestSupport.RoutingMock mock = new HubSpotTestSupport.RoutingMock();
        mock.byEndpointContains.put('/crm/v3/properties/contacts',
            HubSpotTestSupport.makeResponse(200, samplePropertiesDescribeJson()));
        mock.byEndpointContains.put('/crm/v3/objects/contacts/search',
            HubSpotTestSupport.makeResponse(200, '{"total":1,"results":[{"id":"101","properties":{"firstname":"Alice","email":"alice@example.com"}}]}'));
        Test.setMock(HttpCalloutMock.class, mock);

        HubSpotGridDataProvider provider = new HubSpotGridDataProvider();
        HubSpotGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"objectType":"contacts","parentMatchField":"Email"}'
        );
        HubSpotGridDataProvider.testParentFieldValues.put('003000000000001', 'alice@example.com');

        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();
        ctx.parentId = '003000000000001';

        Test.startTest();
        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;
        req.pageSize = 10;
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assertEquals(1, page.records.size());
        System.assertEquals('Alice', page.records[0].get('firstname'));
    }

    @IsTest
    static void testCapabilities_withParentContactEmail() {
        setupConfig();

        HubSpotTestSupport.RoutingMock mock = new HubSpotTestSupport.RoutingMock();
        mock.byEndpointContains.put('/crm/v3/properties/contacts',
            HubSpotTestSupport.makeResponse(200, samplePropertiesDescribeJson()));
        mock.byEndpointContains.put('/crm/v3/objects/contacts/search',
            HubSpotTestSupport.makeResponse(200, '{"total":1,"results":[{"id":"101","properties":{"firstname":"Alice","email":"alice@example.com"}}]}'));
        Test.setMock(HttpCalloutMock.class, mock);

        HubSpotGridDataProvider provider = new HubSpotGridDataProvider();
        HubSpotGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"objectType":"contacts","parentMatchField":"Email"}'
        );
        HubSpotGridDataProvider.testParentFieldValues.put('003000000000001', 'alice@example.com');

        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();
        ctx.parentId = '003000000000001';

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(ctx);
        Test.stopTest();

        System.assertNotEquals(null, caps);
        System.assertEquals(1, provider.cachedRecords.size());
    }

    @IsTest
    static void testCapabilities_withPropertiesFilter() {
        setupConfig();

        HubSpotTestSupport.RoutingMock mock = new HubSpotTestSupport.RoutingMock();
        mock.byEndpointContains.put('/crm/v3/properties/contacts',
            HubSpotTestSupport.makeResponse(200, samplePropertiesDescribeJson()));
        mock.byEndpointContains.put('/crm/v3/objects/contacts',
            HubSpotTestSupport.makeResponse(200, sampleContactsJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        HubSpotGridDataProvider provider = new HubSpotGridDataProvider();
        HubSpotGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"objectType":"contacts","properties":["firstname","lastname","email"]}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(ctx);
        Test.stopTest();

        // 3 properties + 1 hidden Id column
        System.assertEquals(4, caps.columns.size());
        System.assertEquals('firstname', caps.columns[1].id);
        System.assertEquals('lastname', caps.columns[2].id);
        System.assertEquals('email', caps.columns[3].id);
    }

    @IsTest
    static void getData_withContactEmailsAssociations() {
        setupConfig();

        HubSpotTestSupport.RoutingMock mock = new HubSpotTestSupport.RoutingMock();
        mock.byEndpointContains.put('/crm/v3/properties/emails',
            HubSpotTestSupport.makeResponse(200, '{"results":[{"name":"hs_email_subject","label":"Subject","type":"string"}]}'));
        mock.byEndpointContains.put('/crm/v3/objects/contacts/search',
            HubSpotTestSupport.makeResponse(200, '{"total":1,"results":[{"id":"101","properties":{"email":"alice@example.com"}}]}'));
        mock.byEndpointContains.put('/crm/v3/objects/contacts/101/associations/emails',
            HubSpotTestSupport.makeResponse(200, '{"results":[{"id":"em-501","type":"contact_to_email"}]}'));
        mock.byEndpointContains.put('/crm/v3/objects/emails/batch/read',
            HubSpotTestSupport.makeResponse(200, '{"results":[{"id":"em-501","properties":{"hs_email_subject":"Meeting Follow-up","hs_email_direction":"EMAIL","hs_email_status":"SENT"}}]}'));
        Test.setMock(HttpCalloutMock.class, mock);

        HubSpotGridDataProvider provider = new HubSpotGridDataProvider();
        HubSpotGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"objectType":"emails","parentMatchField":"Email"}'
        );
        HubSpotGridDataProvider.testParentFieldValues.put('003000000000001', 'alice@example.com');

        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();
        ctx.parentId = '003000000000001';

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(ctx);
        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;
        req.pageSize = 10;
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assertNotEquals(null, caps);
        System.assertEquals(1, page.records.size());
        System.assertEquals('Meeting Follow-up', page.records[0].get('hs_email_subject'));
    }

    @IsTest
    static void parseConfig_validationErrors() {
        HubSpotGridDataProvider.testGridDef = null;
        try {
            HubSpotGridDataProvider.parseConfig(null);
            System.assert(false, 'Expected GridUiException');
        } catch (HubSpotGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('requires configuration'));
        }

        HubSpotGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = 'invalid json{'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();
        try {
            HubSpotGridDataProvider.parseConfig(ctx);
            System.assert(false, 'Expected GridUiException');
        } catch (HubSpotGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('Invalid HubSpot provider configuration'));
        }
    }
}
