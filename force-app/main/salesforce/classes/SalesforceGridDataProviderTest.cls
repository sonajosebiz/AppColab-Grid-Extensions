@IsTest
private class SalesforceGridDataProviderTest {
    private static String sampleDescribeJson() {
        return '{"name":"Contact","label":"Contact","fields":[' +
            '{"name":"Id","label":"Contact ID","type":"id","updateable":false,"createable":false,"calculated":false},' +
            '{"name":"FirstName","label":"First Name","type":"string","updateable":true,"createable":true,"calculated":false},' +
            '{"name":"LastName","label":"Last Name","type":"string","updateable":true,"createable":true,"calculated":false},' +
            '{"name":"Email","label":"Email","type":"email","updateable":true,"createable":true,"calculated":false},' +
            '{"name":"AccountId","label":"Account ID","type":"reference","updateable":true,"createable":true,"calculated":false},' +
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

    private class ParentMock implements HttpCalloutMock {
        String soql;
        String createdBody;

        public HttpResponse respond(HttpRequest request) {
            String endpoint = request.getEndpoint();
            if (endpoint.contains('/describe')) {
                return SalesforceTestSupport.makeResponse(200, sampleDescribeJson());
            }
            if (endpoint.contains('/query/?q=')) {
                soql = EncodingUtil.urlDecode(endpoint.substring(endpoint.indexOf('/query/?q=') + 10), 'UTF-8');
                return SalesforceTestSupport.makeResponse(200, sampleQueryJson());
            }
            if (request.getMethod() == 'POST') {
                createdBody = request.getBody();
                return SalesforceTestSupport.makeResponse(201, '{"id":"003000000000003"}');
            }
            return SalesforceTestSupport.makeResponse(404, '{}');
        }
    }

    private class PaginationMock implements HttpCalloutMock {
        Integer queryCount = 0;
        Integer locatorCount = 0;

        public HttpResponse respond(HttpRequest request) {
            String endpoint = request.getEndpoint();
            if (endpoint.contains('/describe')) {
                return SalesforceTestSupport.makeResponse(200, sampleDescribeJson());
            }
            if (endpoint.contains('/query/?q=')) {
                queryCount++;
                List<Object> records = new List<Object>();
                for (Integer i = 0; i < 2000; i++) {
                    records.add(new Map<String, Object>{ 'Id' => 'row' + i, 'LastName' => 'Name' + i });
                }
                return SalesforceTestSupport.makeResponse(200, JSON.serialize(new Map<String, Object>{
                    'totalSize' => 2002, 'done' => false,
                    'nextRecordsUrl' => '/services/data/v61.0/query/locator-2000',
                    'records' => records
                }));
            }
            if (endpoint.contains('/query/locator-2000')) {
                locatorCount++;
                return SalesforceTestSupport.makeResponse(200, JSON.serialize(new Map<String, Object>{
                    'totalSize' => 2002, 'done' => true,
                    'records' => new List<Object>{
                        new Map<String, Object>{ 'Id' => 'row2000', 'LastName' => 'Name2000' },
                        new Map<String, Object>{ 'Id' => 'row2001', 'LastName' => 'Name2001' }
                    }
                }));
            }
            return SalesforceTestSupport.makeResponse(404, '{}');
        }
    }

    @IsTest
    static void getCapabilities_and_getData_withSearch() {

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
        System.assertEquals(true, caps.supportsServerPagination);
        System.assertEquals(2000, caps.maxPageSize);

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
        System.assertEquals(5000, cfg.recordLimit);

        SalesforceGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c =
                '{"sObject":"Contact","parentMatchColumn":"AccountId","limit":60000}'
        );
        cfg = SalesforceGridDataProvider.parseConfig(ctx);
        System.assertEquals(50000, cfg.recordLimit);
        System.assertEquals('Id', cfg.parentMatchField);

        SalesforceGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"sObject":"Contact","autoPopulateParent":true}'
        );
        try {
            SalesforceGridDataProvider.parseConfig(ctx);
            System.assert(false, 'Expected parentMatchColumn validation error');
        } catch (SalesforceGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('parentMatchColumn is required'));
        }
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

    @IsTest
    static void parentContext_filtersQueryAndPopulatesNewRecord() {
        ParentMock mock = new ParentMock();
        Test.setMock(HttpCalloutMock.class, mock);
        SalesforceGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c =
                '{"sObject":"Contact","fields":"LastName, AccountId",' +
                '"whereClause":"Email != null","parentMatchColumn":"AccountId",' +
                '"autoPopulateParent":true,"limit":5000}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();
        ctx.parentId = '001000000000001AAA';
        SalesforceGridDataProvider provider = new SalesforceGridDataProvider();
        appcg.GridDataProviderTypesV1.QueryRequest query = new appcg.GridDataProviderTypesV1.QueryRequest();
        query.context = ctx;
        query.pageSize = 20;

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(ctx);
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(query);
        Test.stopTest();

        System.assertEquals(2, page.totalCount);
        System.assert(
            mock.soql.contains('(Email != null) AND AccountId = \'001000000000001AAA\''),
            mock.soql
        );
        System.assert(mock.soql.contains('ORDER BY Id ASC'), mock.soql);
        for (appcg.GridDataProviderTypesV1.ColumnDefinition col : caps.columns) {
            if (col.id == 'AccountId') System.assertEquals(true, col.isReadOnly);
        }
    }

    @IsTest
    static void parentContext_populatesNewRecord() {
        ParentMock mock = new ParentMock();
        Test.setMock(HttpCalloutMock.class, mock);
        SalesforceGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c =
                '{"sObject":"Contact","fields":"LastName, AccountId",' +
                '"parentMatchColumn":"AccountId","autoPopulateParent":true}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext ctx = new appcg.GridDataProviderTypesV1.ProviderContext();
        ctx.parentId = '001000000000001AAA';
        appcg.GridDataProviderTypesV1.SaveRequest save = new appcg.GridDataProviderTypesV1.SaveRequest();
        save.context = ctx;
        save.records = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Id' => 'TEMP_1', 'LastName' => 'New', 'AccountId' => 'wrong-parent' }
        };

        Test.startTest();
        appcg.GridDataProviderTypesV1.SaveResult saved = new SalesforceGridDataProvider().saveRecords(save);
        Test.stopTest();

        System.assertEquals('003000000000003', saved.records[0].get('Id'));
        System.assertEquals('001000000000001AAA', saved.records[0].get('AccountId'));
        System.assertEquals('001000000000001AAA',
            ((Map<String, Object>) JSON.deserializeUntyped(mock.createdBody)).get('AccountId'));
    }

    @IsTest
    static void parentMatchField_resolvesLocalParentValue() {
        Account parent = new Account(Name = 'Parent match value');
        insert parent;
        SalesforceGridDataProvider.SalesforceConfig cfg = new SalesforceGridDataProvider.SalesforceConfig();
        cfg.parentMatchField = 'Name';
        appcg.GridDataProviderTypesV1.ProviderContext context = new appcg.GridDataProviderTypesV1.ProviderContext();
        context.parentId = String.valueOf(parent.Id);

        System.assertEquals(
            'Parent match value',
            SalesforceGridDataProvider.resolveParentMatchValue(cfg, context)
        );
    }

    @IsTest
    static void serverPageBeyondTwoThousand_usesQueryLocator() {
        PaginationMock mock = new PaginationMock();
        Test.setMock(HttpCalloutMock.class, mock);
        SalesforceGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"sObject":"Contact","fields":"LastName","limit":5000}',
            appcg__Pagination_Type__c = 'Server-Side'
        );
        appcg.GridDataProviderTypesV1.QueryRequest request = new appcg.GridDataProviderTypesV1.QueryRequest();
        request.context = new appcg.GridDataProviderTypesV1.ProviderContext();
        request.startIndex = 2000;
        request.pageSize = 2;

        Test.startTest();
        appcg.GridDataProviderTypesV1.PageResult page = new SalesforceGridDataProvider().getData(request);
        Test.stopTest();

        System.assertEquals(2002, page.totalCount);
        System.assertEquals(2, page.records.size());
        System.assertEquals('row2000', page.records[0].get('Id'));
        System.assertEquals('row2001', page.records[1].get('Id'));
        System.assertEquals(1, mock.queryCount);
        System.assertEquals(1, mock.locatorCount);
    }

    @IsTest
    static void clientSide_loadsAllQueryBatches() {
        PaginationMock mock = new PaginationMock();
        Test.setMock(HttpCalloutMock.class, mock);
        SalesforceGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"sObject":"Contact","fields":"LastName","limit":5000}',
            appcg__Pagination_Type__c = 'Client-Side'
        );
        appcg.GridDataProviderTypesV1.QueryRequest request = new appcg.GridDataProviderTypesV1.QueryRequest();
        request.context = new appcg.GridDataProviderTypesV1.ProviderContext();
        request.pageSize = 20;

        Test.startTest();
        appcg.GridDataProviderTypesV1.PageResult page = new SalesforceGridDataProvider().getData(request);
        Test.stopTest();

        System.assertEquals(2002, page.totalCount);
        System.assertEquals(2002, page.records.size());
        System.assertEquals('row2001', page.records[2001].get('Id'));
        System.assertEquals(1, mock.locatorCount);
    }

    @IsTest
    static void serverSearch_includesMatchesBeyondFirstBatch() {
        PaginationMock mock = new PaginationMock();
        Test.setMock(HttpCalloutMock.class, mock);
        SalesforceGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"sObject":"Contact","fields":"LastName","limit":5000}',
            appcg__Pagination_Type__c = 'Server-Side'
        );
        appcg.GridDataProviderTypesV1.QueryRequest request = new appcg.GridDataProviderTypesV1.QueryRequest();
        request.context = new appcg.GridDataProviderTypesV1.ProviderContext();
        request.searchTerm = 'Name2001';
        request.startIndex = 0;
        request.pageSize = 20;

        Test.startTest();
        appcg.GridDataProviderTypesV1.PageResult page = new SalesforceGridDataProvider().getData(request);
        Test.stopTest();

        System.assertEquals(1, page.totalCount);
        System.assertEquals(1, page.records.size());
        System.assertEquals('row2001', page.records[0].get('Id'));
        System.assertEquals(1, mock.locatorCount);
    }
}
