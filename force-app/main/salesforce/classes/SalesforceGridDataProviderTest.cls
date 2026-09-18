@IsTest
private class SalesforceGridDataProviderTest {
    private static void setupConfig() {
    }

    private static String sampleDescribeJson() {
        return '{"name":"Contact","label":"Contact","fields":[' +
            '{"name":"Id","label":"Contact ID","type":"id","updateable":false,"createable":false,"calculated":false},' +
            '{"name":"FirstName","label":"First Name","type":"string","updateable":true,"createable":true,"calculated":false},' +
            '{"name":"LastName","label":"Last Name","type":"string","updateable":true,"createable":true,"calculated":false},' +
            '{"name":"Email","label":"Email","type":"email","updateable":true,"createable":true,"calculated":false},' +
            '{"name":"LeadSource","label":"Lead Source","type":"picklist","updateable":true,"createable":true,"calculated":false,"picklistValues":[' +
                '{"active":true,"label":"Web","value":"Web"},' +
                '{"active":true,"label":"Phone","value":"Phone"}' +
            ']},' +
            '{"name":"CreatedDate","label":"Created Date","type":"datetime","updateable":false,"createable":false,"calculated":false}' +
        ']}';
    }

    private static String sampleQueryJson() {
        return '{"totalSize":2,"done":true,"records":[' +
            '{"attributes":{"type":"Contact"},"Id":"003000000000001","FirstName":"John","LastName":"Doe","Email":"john@test.com","LeadSource":"Web","CreatedDate":"2024-01-01T12:00:00.000+0000"},' +
            '{"attributes":{"type":"Contact"},"Id":"003000000000002","FirstName":"Jane","LastName":"Smith","Email":"jane@test.com","LeadSource":"Phone","CreatedDate":"2024-01-02T12:00:00.000+0000"}' +
        ']}';
    }

    @IsTest
    static void getCapabilities_and_getData_withCacheAndSearch() {
        setupConfig();

        SalesforceTestSupport.RoutingMock mock = new SalesforceTestSupport.RoutingMock();
        mock.byEndpointContains.put('/sobjects/Contact/describe', SalesforceTestSupport.makeResponse(200, sampleDescribeJson()));
        mock.byEndpointContains.put('/query/?q=', SalesforceTestSupport.makeResponse(200, sampleQueryJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        SalesforceGridDataProvider provider = new SalesforceGridDataProvider();
        SalesforceGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"sObject":"Contact","fields":"FirstName, LastName, Email, LeadSource, CreatedDate","whereClause":"Email != null","orderBy":"CreatedDate DESC","limit":50}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(ctx);

        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;
        req.searchTerm = 'Jane';

        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assertNotEquals(null, caps);
        System.assertEquals(6, caps.columns.size());
        System.assert(caps.supportedFeatures.contains('ADD'));
        System.assert(caps.supportedFeatures.contains('EDIT'));
        System.assert(caps.supportedFeatures.contains('DELETE'));
        System.assert(caps.supportedFeatures.contains('SEARCH'));

        // Verify picklist options on LeadSource
        appcg.GridDataProviderTypesV1.ColumnDefinition leadCol;
        for (appcg.GridDataProviderTypesV1.ColumnDefinition col : caps.columns) {
            if (col.id == 'LeadSource') leadCol = col;
        }
        System.assertNotEquals(null, leadCol);
        System.assertEquals('PICKLIST', leadCol.fieldType);
        System.assertEquals(2, leadCol.picklistOptions.size());

        // Verify search filtered results
        System.assertEquals(1, page.records.size());
        System.assertEquals('003000000000002', page.records[0].get('Id'));
        System.assertEquals('Jane', page.records[0].get('FirstName'));
    }

    @IsTest
    static void getData_standalone() {
        setupConfig();

        SalesforceTestSupport.RoutingMock mock = new SalesforceTestSupport.RoutingMock();
        mock.byEndpointContains.put('/sobjects/Contact/describe', SalesforceTestSupport.makeResponse(200, sampleDescribeJson()));
        mock.byEndpointContains.put('/query/?q=', SalesforceTestSupport.makeResponse(200, sampleQueryJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        SalesforceGridDataProvider provider = new SalesforceGridDataProvider();
        SalesforceGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"sObject":"Contact"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;

        Test.startTest();
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assertEquals(2, page.records.size());
    }

    @IsTest
    static void saveRecords_createsNewAndUpdatesExisting() {
        setupConfig();

        SalesforceTestSupport.RoutingMock mock = new SalesforceTestSupport.RoutingMock();
        mock.byEndpointContains.put('/sobjects/Contact/describe', SalesforceTestSupport.makeResponse(200, sampleDescribeJson()));
        mock.byEndpointContains.put('/sobjects/Contact/003000000000001', SalesforceTestSupport.makeResponse(204, ''));
        mock.byEndpointContains.put('/sobjects/Contact', SalesforceTestSupport.makeResponse(201, '{"id":"003000000000003","success":true,"errors":[]}'));
        Test.setMock(HttpCalloutMock.class, mock);

        SalesforceGridDataProvider provider = new SalesforceGridDataProvider();
        SalesforceGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"sObject":"Contact","fields":"FirstName, LastName, Email"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        appcg.GridDataProviderTypesV1.SaveRequest req = new appcg.GridDataProviderTypesV1.SaveRequest();
        req.context = ctx;
        req.records = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Id' => '003000000000001', 'FirstName' => 'John', 'LastName' => 'Updated' },
            new Map<String, Object>{ 'FirstName' => 'New', 'LastName' => 'User', 'Email' => 'new@test.com' }
        };

        Test.startTest();
        appcg.GridDataProviderTypesV1.SaveResult result = provider.saveRecords(req);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(2, result.records.size());
        System.assertEquals('003000000000001', result.records[0].get('Id'));
        System.assertEquals('003000000000003', result.records[1].get('Id'));
    }

    @IsTest
    static void deleteRecords_dispatchesDelete() {
        setupConfig();

        SalesforceTestSupport.RoutingMock mock = new SalesforceTestSupport.RoutingMock();
        mock.byEndpointContains.put('/sobjects/Contact/003000000000001', SalesforceTestSupport.makeResponse(204, ''));
        Test.setMock(HttpCalloutMock.class, mock);

        SalesforceGridDataProvider provider = new SalesforceGridDataProvider();
        SalesforceGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"sObject":"Contact"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();

        appcg.GridDataProviderTypesV1.DeleteRequest req = new appcg.GridDataProviderTypesV1.DeleteRequest();
        req.context = ctx;
        req.recordIds = new List<String>{ '003000000000001' };

        Test.startTest();
        provider.deleteRecords(req);
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void parseConfig_validationAndErrors() {
        SalesforceGridDataProvider.testGridDef = null;
        try {
            SalesforceGridDataProvider.parseConfig(null);
            System.assert(false, 'Expected GridUiException');
        } catch (SalesforceGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('requires configuration'));
        }

        SalesforceGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"fields":"FirstName"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();
        try {
            SalesforceGridDataProvider.parseConfig(ctx);
            System.assert(false, 'Expected GridUiException');
        } catch (SalesforceGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('sObject is required'));
        }

        SalesforceGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"sObject":"Account","limit":5000}'
        );
        SalesforceGridDataProvider.SalesforceConfig cfg = SalesforceGridDataProvider.parseConfig(ctx);
        System.assertEquals('Account', cfg.sObjectName);
        System.assertEquals(2000, cfg.recordLimit);
    }

    @IsTest
    static void helperMethods_coverage() {
        System.assertEquals('BOOLEAN', SalesforceGridDataProvider.mapFieldType('boolean'));
        System.assertEquals('NUMBER', SalesforceGridDataProvider.mapFieldType('currency'));
        System.assertEquals('DATETIME', SalesforceGridDataProvider.mapFieldType('datetime'));
        System.assertEquals('PHONE', SalesforceGridDataProvider.mapFieldType('phone'));
        System.assertEquals('EMAIL', SalesforceGridDataProvider.mapFieldType('email'));
        System.assertEquals('URL', SalesforceGridDataProvider.mapFieldType('url'));
        System.assertEquals('TEXT', SalesforceGridDataProvider.mapFieldType('unknown'));

        String soql = SalesforceGridDataProvider.buildSoqlQuery('Account', new List<String>{'Id', 'Name'}, 'Type = \'Customer\'', 'Name ASC', 25);
        System.assertEquals('SELECT Id, Name FROM Account WHERE Type = \'Customer\' ORDER BY Name ASC LIMIT 25', soql);
    }
}
