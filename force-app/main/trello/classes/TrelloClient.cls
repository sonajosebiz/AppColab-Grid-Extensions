public with sharing class TrelloClient {
    public class ClientException extends Exception {
    }
    public class HttpException extends Exception {
    }

    private static final String NAMED_CREDENTIAL = 'Trello';
    private static final Set<Integer> RETRYABLE_STATUS_CODES = new Set<Integer>{ 408, 429, 500, 502, 503, 504 };


    public TrelloClient() {
    }

    /**
     * Fetch all cards on a Trello Board.
     * GET /1/boards/{boardId}/cards
     */
    public List<Object> getBoardCards(String boardId) {
        String path = '/1/boards/' + enc(boardId) +
            '/cards?fields=name,desc,due,dueComplete,idList,labels,shortUrl,closed,dateLastActivity&members=true&member_fields=fullName';
        HttpResponse res = get(path);
        return (List<Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Fetch all lists (columns) on a Trello Board.
     * GET /1/boards/{boardId}/lists
     */
    public List<Object> getBoardLists(String boardId) {
        String path = '/1/boards/' + enc(boardId) + '/lists?fields=name,closed';
        HttpResponse res = get(path);
        return (List<Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Create a new card in a list.
     * POST /1/cards
     */
    public Map<String, Object> createCard(Map<String, Object> fields) {
        String path = '/1/cards';
        HttpResponse res = post(path, JSON.serialize(fields));
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Update an existing card (name, desc, due, dueComplete, idList, closed).
     * PUT /1/cards/{cardId}
     */
    public Map<String, Object> updateCard(String cardId, Map<String, Object> fields) {
        String path = '/1/cards/' + enc(cardId);
        HttpResponse res = put(path, JSON.serialize(fields));
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Delete a card from Trello.
     * DELETE /1/cards/{cardId}
     */
    public Map<String, Object> deleteCard(String cardId) {
        String path = '/1/cards/' + enc(cardId);
        HttpResponse res = del(path);
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    // ─── Helpers ──────────────────────────────────────────────────────

    private static String enc(String value) {
        return value == null ? '' : EncodingUtil.urlEncode(value, 'UTF-8');
    }

    private HttpResponse get(String path) {
        return send(newRequest('GET', path, null));
    }

    private HttpResponse post(String path, String body) {
        return send(newRequest('POST', path, body));
    }

    private HttpResponse put(String path, String body) {
        return send(newRequest('PUT', path, body));
    }

    private HttpResponse patch(String path, String body) {
        return send(newRequest('PATCH', path, body));
    }

    private HttpResponse del(String path) {
        return send(newRequest('DELETE', path, null));
    }

    private HttpRequest newRequest(String method, String requestPath, String body) {
        HttpRequest request = new HttpRequest();
        request.setMethod(method);
        request.setEndpoint(requestPath);
        if (body != null) {
            request.setBody(body);
        }
        return request;
    }

    private HttpResponse send(HttpRequest request) {
        String endpoint = request.getEndpoint();
        if (String.isBlank(endpoint)) {
            endpoint = '';
        }
        if (!endpoint.startsWith('callout:')) {
            endpoint = 'callout:' + NAMED_CREDENTIAL + (endpoint.startsWith('/') ? endpoint : '/' + endpoint);
        }
        request.setEndpoint(endpoint);
        request.setTimeout(60000);
        if (request.getHeader('Accept') == null) {
            request.setHeader('Accept', 'application/json');
        }
        if (request.getBody() != null && request.getHeader('Content-Type') == null) {
            request.setHeader('Content-Type', 'application/json');
        }

        HttpResponse response;
        System.CalloutException lastException;
        for (Integer attempt = 0; attempt <= 1; attempt++) {
            try {
                response = new Http().send(request);
                lastException = null;
                if (!RETRYABLE_STATUS_CODES.contains(response.getStatusCode()) || attempt == 1) {
                    break;
                }
            } catch (System.CalloutException e) {
                lastException = e;
                response = null;
                if (attempt == 1) {
                    break;
                }
            }
        }
        if (response == null) {
            throw new HttpException('Callout failed: ' + (lastException == null ? 'No response.' : lastException.getMessage()));
        }
        if (response.getStatusCode() < 200 || response.getStatusCode() >= 400) {
            throw new HttpException(
                'Trello API returned HTTP ' + response.getStatusCode() +
                (String.isBlank(response.getBody()) ? '' : ': ' + response.getBody())
            );
        }
        return response;
    }

    private void setHeader(HttpRequest request, String name, String value) {
        request.setHeader(name, value);
    }
}
