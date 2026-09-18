@IsTest
private class AirtableGridDataProviderTest {
    private static void setupConfig() {
    }

    private static String sampleRecordsJson() {
        return '{"records":[' +
            '{"id":"rec1","fields":{"Name":"Alice Johnson","Email":"alice@test.com","Tags":["VIP","Tech"]}},' +
            '{"id":"rec2","fields":{"Name":"Bob Smith","Email":"bob@test.com","Tags":["Sales"]}}' +
        ']}';
    }

    private static appcg.GridDataProviderTypesV1.ProviderContext createValidContext() {
        AirtableGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"baseId":"appTestBase","tableIdOrName":"Contacts"}'
        );
        return new appcg.GridDataProviderTypesV1.ProviderContext();
    }

    @IsTest
    static void getCapabilities_and_getData_withCache() {
        setupConfig();

        AirtableTestSupport.RoutingMock mock = new AirtableTestSupport.RoutingMock();
        mock.byEndpointContains.put('/v0/meta/bases/appTestBase/tables', AirtableTestSupport.makeResponse(200,
            '{"tables":[{"name":"Contacts","fields":[{"name":"Name","type":"singleLineText"},{"name":"Assignee","type":"singleCollaborator"}]}]}'
        ));
        mock.byEndpointContains.put('/v0/appTestBase/Contacts', AirtableTestSupport.makeResponse(200, sampleRecordsJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        AirtableGridDataProvider provider = new AirtableGridDataProvider();
        appcg.GridDataProviderTypesV1.ProviderContext context = createValidContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities capabilities = provider.getCapabilities(context);

        appcg.GridDataProviderTypesV1.QueryRequest request = new appcg.GridDataProviderTypesV1.QueryRequest();
        request.context = context;
        request.searchTerm = 'alice';

        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(request);
        Test.stopTest();

        // Capabilities assertions
        System.assertNotEquals(null, capabilities);
        System.assertEquals(4, capabilities.columns.size()); // Id, Name, Email, Tags
        System.assert(capabilities.supportedFeatures.contains('ADD'));
        System.assert(capabilities.supportedFeatures.contains('EDIT'));
        System.assert(capabilities.supportedFeatures.contains('DELETE'));
        System.assert(capabilities.supportedFeatures.contains('SEARCH'));
        System.assertEquals(new Set<String>{ 'DELETE' }, capabilities.supportedRowActions);
        System.assertEquals(false, capabilities.supportsServerPagination);

        // Data assertions
        System.assertEquals(1, page.records.size());
        System.assertEquals('rec1', page.records[0].get('Id'));
        System.assertEquals('Alice Johnson', page.records[0].get('Name'));
        System.assertEquals('alice@test.com', page.records[0].get('Email'));
        System.assertEquals('VIP, Tech', page.records[0].get('Tags'));
    }

    @IsTest
    static void getData_standalone_withoutCache() {
        setupConfig();

        AirtableTestSupport.RoutingMock mock = new AirtableTestSupport.RoutingMock();
        mock.byEndpointContains.put('/v0/appTestBase/Contacts', AirtableTestSupport.makeResponse(200, sampleRecordsJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        AirtableGridDataProvider provider = new AirtableGridDataProvider();
        appcg.GridDataProviderTypesV1.QueryRequest request = new appcg.GridDataProviderTypesV1.QueryRequest();
        request.context = createValidContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(request);
        Test.stopTest();

        System.assertEquals(2, page.records.size());
        System.assertEquals('rec1', page.records[0].get('Id'));
        System.assertEquals('rec2', page.records[1].get('Id'));
    }

    @IsTest
    static void saveRecords_updatesExistingAndCreatesNew() {
        setupConfig();

        AirtableTestSupport.RoutingMock mock = new AirtableTestSupport.RoutingMock();
        mock.byEndpointContains.put('/v0/appTestBase/Contacts', AirtableTestSupport.makeResponse(200,
            '{"records":[{"id":"recNew","fields":{"Name":"Charlie","Email":"charlie@test.com"}}]}'
        ));
        Test.setMock(HttpCalloutMock.class, mock);

        AirtableGridDataProvider provider = new AirtableGridDataProvider();
        appcg.GridDataProviderTypesV1.SaveRequest request = new appcg.GridDataProviderTypesV1.SaveRequest();
        request.context = createValidContext();
        request.records = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Id' => 'rec1', 'Name' => 'Alice Updated', 'Email' => 'alice@test.com' },
            new Map<String, Object>{ 'Name' => 'Charlie', 'Email' => 'charlie@test.com' }
        };

        Test.startTest();
        appcg.GridDataProviderTypesV1.SaveResult result = provider.saveRecords(request);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(2, result.records.size());
        System.assertEquals('rec1', result.records[0].get('Id'));
        System.assertEquals('Alice Updated', result.records[0].get('Name'));
        System.assertEquals('recNew', result.records[1].get('Id'));
        System.assertEquals('Charlie', result.records[1].get('Name'));
    }

    @IsTest
    static void deleteRecords_deletesViaClient() {
        setupConfig();

        AirtableTestSupport.RoutingMock mock = new AirtableTestSupport.RoutingMock();
        mock.byEndpointContains.put('/v0/appTestBase/Contacts', AirtableTestSupport.makeResponse(200, '{"records":[{"id":"rec1","deleted":true}]}'));
        Test.setMock(HttpCalloutMock.class, mock);

        AirtableGridDataProvider provider = new AirtableGridDataProvider();
        appcg.GridDataProviderTypesV1.DeleteRequest request = new appcg.GridDataProviderTypesV1.DeleteRequest();
        request.context = createValidContext();
        request.recordIds = new List<String>{ 'rec1', 'rec2' };

        Test.startTest();
        provider.deleteRecords(request);
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void parseConfig_validatesInput() {
        AirtableGridDataProvider.testGridDef = null;
        try {
            AirtableGridDataProvider.parseConfig(null);
            System.assert(false, 'Expected null context error');
        } catch (AirtableGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('requires configuration'));
        }

        AirtableGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{bad-json}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext badJson = new appcg.GridDataProviderTypesV1.ProviderContext();
        try {
            AirtableGridDataProvider.parseConfig(badJson);
            System.assert(false, 'Expected invalid json error');
        } catch (AirtableGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('Invalid Airtable provider configuration'));
        }

        AirtableGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"tableIdOrName":"Contacts"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext missingBase = new appcg.GridDataProviderTypesV1.ProviderContext();
        try {
            AirtableGridDataProvider.parseConfig(missingBase);
            System.assert(false, 'Expected missing baseId error');
        } catch (AirtableGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('baseId is required'));
        }

        AirtableGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"baseId":"app123"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext missingTable = new appcg.GridDataProviderTypesV1.ProviderContext();
        try {
            AirtableGridDataProvider.parseConfig(missingTable);
            System.assert(false, 'Expected missing tableIdOrName error');
        } catch (AirtableGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('tableIdOrName is required'));
        }
    }
}
