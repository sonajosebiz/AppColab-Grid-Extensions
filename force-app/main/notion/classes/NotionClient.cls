public with sharing class NotionClient {
    public class ClientException extends Exception {}
    public class HttpException extends Exception {}

    private static final String NAMED_CREDENTIAL = 'Notion';
    private static final Set<Integer> RETRYABLE_STATUS_CODES = new Set<Integer>{ 408, 429, 500, 502, 503, 504 };

    public NotionClient() {}

    /**
     * Retrieve a database definition and schema.
     * GET /v1/databases/{database_id}
     */
    public Map<String, Object> getDatabase(String databaseId) {
        String path = '/v1/databases/' + enc(databaseId);
        HttpResponse res = get(path);
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Query records (pages) in a database.
     * POST /v1/databases/{database_id}/query
     */
    public Map<String, Object> queryDatabase(
        String databaseId,
        Integer pageSize,
        String startCursor,
        Map<String, Object> filterMap,
        List<Object> sortsList
    ) {
        String path = '/v1/databases/' + enc(databaseId) + '/query';
        Map<String, Object> bodyMap = new Map<String, Object>();
        if (pageSize != null && pageSize > 0) {
            bodyMap.put('page_size', Math.min(pageSize, 100));
        }
        if (String.isNotBlank(startCursor)) {
            bodyMap.put('start_cursor', startCursor);
        }
        if (filterMap != null && !filterMap.isEmpty()) {
            bodyMap.put('filter', filterMap);
        }
        if (sortsList != null && !sortsList.isEmpty()) {
            bodyMap.put('sorts', sortsList);
        }
        HttpResponse res = post(path, JSON.serialize(bodyMap));
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Retrieve a specific page by ID.
     * GET /v1/pages/{page_id}
     */
    public Map<String, Object> getPage(String pageId) {
        String path = '/v1/pages/' + enc(pageId);
        HttpResponse res = get(path);
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Create a new page (record) in a database.
     * POST /v1/pages
     */
    public Map<String, Object> createPage(
        String databaseId,
        Map<String, Object> properties
    ) {
        String path = '/v1/pages';
        Map<String, Object> bodyMap = new Map<String, Object>{
            'parent' => new Map<String, Object>{ 'database_id' => databaseId },
            'properties' => properties
        };
        HttpResponse res = post(path, JSON.serialize(bodyMap));
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Update page properties.
     * PATCH /v1/pages/{page_id}
     */
    public Map<String, Object> updatePage(
        String pageId,
        Map<String, Object> properties
    ) {
        String path = '/v1/pages/' + enc(pageId);
        Map<String, Object> bodyMap = new Map<String, Object>{
            'properties' => properties
        };
        HttpResponse res = patch(path, JSON.serialize(bodyMap));
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Archive (delete) a page.
     * PATCH /v1/pages/{page_id}
     */
    public Map<String, Object> archivePage(String pageId) {
        String path = '/v1/pages/' + enc(pageId);
        Map<String, Object> bodyMap = new Map<String, Object>{
            'archived' => true
        };
        HttpResponse res = patch(path, JSON.serialize(bodyMap));
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    private static String enc(String value) {
        if (String.isBlank(value)) return '';
        return EncodingUtil.urlEncode(value, 'UTF-8').replace('+', '%20');
    }

    private HttpResponse get(String path) {
        return send(newRequest('GET', path, null));
    }

    private HttpResponse post(String path, String body) {
        return send(newRequest('POST', path, body));
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
        if (request.getHeader('Notion-Version') == null) {
            request.setHeader('Notion-Version', '2022-06-28');
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
                'Notion API returned HTTP ' + response.getStatusCode() +
                (String.isBlank(response.getBody()) ? '' : ': ' + response.getBody())
            );
        }
        return response;
    }
}
