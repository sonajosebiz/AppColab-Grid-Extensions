@IsTest
private class TrelloGridDataProviderTest {
    private static void setupConfig() {
    }

    private static String sampleListsJson() {
        return '[{"id":"list1","name":"To Do"},{"id":"list2","name":"Done"}]';
    }

    private static String sampleCardsJson() {
        return '[' +
            '{"id":"card1","name":"Card 1","desc":"Desc 1","idList":"list1","due":"2026-08-20T10:00:00.000Z","dueComplete":false,"labels":[{"name":"Bug"}],"members":[{"fullName":"John Doe"}],"shortUrl":"https://trello.com/c/123"},' +
            '{"id":"card2","name":"Card 2","desc":"Desc 2","idList":"list2","due":null,"dueComplete":true,"labels":[],"members":[],"shortUrl":"https://trello.com/c/456"}' +
        ']';
    }

    private static appcg.GridDataProviderTypesV1.ProviderContext createValidContext() {
        TrelloGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"boardId":"board1"}'
        );
        return new appcg.GridDataProviderTypesV1.ProviderContext();
    }

    @IsTest
    static void getCapabilities_and_getData_withCache() {
        setupConfig();

        TrelloTestSupport.RoutingMock mock = new TrelloTestSupport.RoutingMock();
        mock.byEndpointContains.put('/1/boards/board1/lists', TrelloTestSupport.makeResponse(200, sampleListsJson()));
        mock.byEndpointContains.put('/1/boards/board1/cards', TrelloTestSupport.makeResponse(200, sampleCardsJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        TrelloGridDataProvider provider = new TrelloGridDataProvider();
        appcg.GridDataProviderTypesV1.ProviderContext ctx = createValidContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.Capabilities caps = provider.getCapabilities(ctx);

        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = ctx;
        req.searchTerm = 'Card 1';
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assertNotEquals(null, caps);
        System.assertEquals(9, caps.columns.size());
        System.assertEquals('PICKLIST', caps.columns[2].fieldType);
        System.assertEquals(2, caps.columns[2].picklistOptions.size());
        System.assert(caps.supportedFeatures.contains('ADD'));
        System.assert(caps.supportedFeatures.contains('EDIT'));
        System.assert(caps.supportedFeatures.contains('DELETE'));
        System.assert(caps.supportedFeatures.contains('SEARCH'));

        System.assertEquals(1, page.records.size());
        System.assertEquals('card1', page.records[0].get('Id'));
        System.assertEquals('Card 1', page.records[0].get('name'));
        System.assertEquals('To Do', page.records[0].get('listName'));
        System.assertEquals(false, page.records[0].get('dueComplete'));
        System.assertEquals('Bug', page.records[0].get('labels'));
        System.assertEquals('John Doe', page.records[0].get('members'));
    }

    @IsTest
    static void getData_standalone_withoutCache() {
        setupConfig();

        TrelloTestSupport.RoutingMock mock = new TrelloTestSupport.RoutingMock();
        mock.byEndpointContains.put('/1/boards/board1/lists', TrelloTestSupport.makeResponse(200, sampleListsJson()));
        mock.byEndpointContains.put('/1/boards/board1/cards', TrelloTestSupport.makeResponse(200, sampleCardsJson()));
        Test.setMock(HttpCalloutMock.class, mock);

        TrelloGridDataProvider provider = new TrelloGridDataProvider();
        appcg.GridDataProviderTypesV1.QueryRequest req = new appcg.GridDataProviderTypesV1.QueryRequest();
        req.context = createValidContext();

        Test.startTest();
        appcg.GridDataProviderTypesV1.PageResult page = provider.getData(req);
        Test.stopTest();

        System.assertEquals(2, page.records.size());
        System.assertEquals('card1', page.records[0].get('Id'));
        System.assertEquals(false, page.records[0].get('dueComplete'));
        System.assertEquals('card2', page.records[1].get('Id'));
        System.assertEquals(true, page.records[1].get('dueComplete'));
    }

    @IsTest
    static void saveRecords_createsNewAndEditsExisting() {
        setupConfig();

        TrelloTestSupport.RoutingMock mock = new TrelloTestSupport.RoutingMock();
        mock.byEndpointContains.put('/1/boards/board1/lists', TrelloTestSupport.makeResponse(200, sampleListsJson()));
        mock.byEndpointContains.put('/1/cards/card1', TrelloTestSupport.makeResponse(200, '{"id":"card1","name":"Updated Card"}'));
        mock.byEndpointContains.put('/1/cards', TrelloTestSupport.makeResponse(200, '{"id":"cardNew","name":"New Card","shortUrl":"https://trello.com/c/new"}'));
        Test.setMock(HttpCalloutMock.class, mock);

        TrelloGridDataProvider provider = new TrelloGridDataProvider();
        appcg.GridDataProviderTypesV1.SaveRequest req = new appcg.GridDataProviderTypesV1.SaveRequest();
        req.context = createValidContext();
        req.records = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Id' => 'card1', 'name' => 'Updated Card', 'listName' => 'Done', 'dueComplete' => true, 'due' => '' },
            new Map<String, Object>{ 'name' => 'New Card', 'desc' => 'New Desc', 'listName' => 'To Do' }
        };

        Test.startTest();
        appcg.GridDataProviderTypesV1.SaveResult result = provider.saveRecords(req);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(2, result.records.size());
        System.assertEquals('card1', result.records[0].get('Id'));
        System.assertEquals('cardNew', result.records[1].get('Id'));
        System.assertEquals('https://trello.com/c/new', result.records[1].get('url'));
    }

    @IsTest
    static void deleteRecords_callsDelete() {
        setupConfig();

        TrelloTestSupport.RoutingMock mock = new TrelloTestSupport.RoutingMock();
        mock.byEndpointContains.put('/1/cards/card1', TrelloTestSupport.makeResponse(200, '{"limits":{}}'));
        Test.setMock(HttpCalloutMock.class, mock);

        TrelloGridDataProvider provider = new TrelloGridDataProvider();
        appcg.GridDataProviderTypesV1.DeleteRequest req = new appcg.GridDataProviderTypesV1.DeleteRequest();
        req.context = createValidContext();
        req.recordIds = new List<String>{ 'card1' };

        Test.startTest();
        provider.deleteRecords(req);
        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void parseConfig_validatesInput() {
        TrelloGridDataProvider.testGridDef = null;
        try {
            TrelloGridDataProvider.parseConfig(null);
            System.assert(false, 'Expected null config exception');
        } catch (TrelloGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('requires configuration'));
        }

        TrelloGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{bad-json}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext badJson = new appcg.GridDataProviderTypesV1.ProviderContext();
        try {
            TrelloGridDataProvider.parseConfig(badJson);
            System.assert(false, 'Expected invalid json exception');
        } catch (TrelloGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('Invalid Trello provider configuration'));
        }

        TrelloGridDataProvider.testGridDef = new appcg__Grid_Definition__c(
            appcg__Data_Provider_Config__c = '{"otherField":"val"}'
        );
        appcg.GridDataProviderTypesV1.ProviderContext missingBoard = new appcg.GridDataProviderTypesV1.ProviderContext();
        try {
            TrelloGridDataProvider.parseConfig(missingBoard);
            System.assert(false, 'Expected missing boardId exception');
        } catch (TrelloGridDataProvider.ProviderException e) {
            System.assert(e.getMessage().contains('boardId is required'));
        }
    }
}
