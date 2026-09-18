@IsTest
private class TrelloClientTest {
    private static TrelloTestSupport.SingleResponseMock arrange(String responseBody) {

        TrelloTestSupport.SingleResponseMock mock = new TrelloTestSupport.SingleResponseMock();
        mock.statusCode = 200;
        mock.body = responseBody;
        Test.setMock(HttpCalloutMock.class, mock);
        return mock;
    }

    @IsTest
    static void getBoardCards_dispatchesGet() {
        TrelloTestSupport.SingleResponseMock mock = arrange('[{"id":"card1","name":"Card 1","idList":"list1"}]');

        Test.startTest();
        List<Object> cards = new TrelloClient().getBoardCards('board123');
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/1/boards/board123/cards'), mock.lastEndpoint);
        System.assertEquals(1, cards.size());
    }

    @IsTest
    static void getBoardLists_dispatchesGet() {
        TrelloTestSupport.SingleResponseMock mock = arrange('[{"id":"list1","name":"To Do"}]');

        Test.startTest();
        List<Object> lists = new TrelloClient().getBoardLists('board123');
        Test.stopTest();

        System.assertEquals('GET', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/1/boards/board123/lists'), mock.lastEndpoint);
        System.assertEquals(1, lists.size());
    }

    @IsTest
    static void createCard_dispatchesPost() {
        TrelloTestSupport.SingleResponseMock mock = arrange('{"id":"cardNew","name":"New Card"}');

        Map<String, Object> fields = new Map<String, Object>{
            'name' => 'New Card',
            'idList' => 'list1',
            'desc' => 'Card Description'
        };

        Test.startTest();
        Map<String, Object> result = new TrelloClient().createCard(fields);
        Test.stopTest();

        System.assertEquals('POST', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/1/cards'), mock.lastEndpoint);
        System.assertEquals('cardNew', result.get('id'));
    }

    @IsTest
    static void updateCard_dispatchesPut() {
        TrelloTestSupport.SingleResponseMock mock = arrange('{"id":"card1","name":"Updated Card"}');

        Map<String, Object> fields = new Map<String, Object>{
            'name' => 'Updated Card',
            'dueComplete' => true
        };

        Test.startTest();
        Map<String, Object> result = new TrelloClient().updateCard('card1', fields);
        Test.stopTest();

        System.assertEquals('PUT', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/1/cards/card1'), mock.lastEndpoint);
        System.assertEquals('card1', result.get('id'));
    }

    @IsTest
    static void deleteCard_dispatchesDelete() {
        TrelloTestSupport.SingleResponseMock mock = arrange('{"limits":{}}');

        Test.startTest();
        Map<String, Object> result = new TrelloClient().deleteCard('card1');
        Test.stopTest();

        System.assertEquals('DELETE', mock.lastMethod);
        System.assert(mock.lastEndpoint.contains('/1/cards/card1'), mock.lastEndpoint);
    }
}
