public with sharing class QuickBooksClient {
    public class ClientException extends Exception {
    }
    public class HttpException extends Exception {
    }

    private static final String NAMED_CREDENTIAL = 'QuickBooks';
    private static final Set<Integer> RETRYABLE_STATUS_CODES = new Set<Integer>{ 408, 429, 500, 502, 503, 504 };


    public QuickBooksClient() {
    }

    /**
     * Query QuickBooks entities using QuickBooks SQL-like query language (default startposition 1).
     */
    public Map<String, Object> query(
        String realmId,
        String entityName,
        Integer limitCount,
        String whereClause
    ) {
        return query(realmId, entityName, 1, limitCount, whereClause);
    }

    /**
     * Query QuickBooks entities with explicit STARTPOSITION for Server-Side Pagination.
     * GET /v3/company/{realmId}/query?query=select * from {entityName} where ... startposition {start} maxresults {limit}
     */
    public Map<String, Object> query(
        String realmId,
        String entityName,
        Integer startPosition,
        Integer limitCount,
        String whereClause
    ) {
        validateRealmAndEntity(realmId, entityName);

        String sql = 'select * from ' + entityName;
        if (String.isNotBlank(whereClause)) {
            sql += ' where ' + whereClause;
        }

        Integer startPos = (startPosition != null && startPosition > 0) ? startPosition : 1;
        Integer maxResults = (limitCount != null && limitCount > 0) ? Math.min(limitCount, 1000) : 100;
        sql += ' startposition ' + startPos + ' maxresults ' + maxResults;

        String path = '/v3/company/' + enc(realmId) + '/query?query=' + enc(sql);
        HttpResponse res = get(path);
        return deserialize(res);
    }

    /**
     * Get the total record count for an entity matching optional where clause.
     * GET /v3/company/{realmId}/query?query=select count(*) from {entityName} where ...
     */
    public Integer count(String realmId, String entityName, String whereClause) {
        validateRealmAndEntity(realmId, entityName);

        String sql = 'select count(*) from ' + entityName;
        if (String.isNotBlank(whereClause)) {
            sql += ' where ' + whereClause;
        }

        String path = '/v3/company/' + enc(realmId) + '/query?query=' + enc(sql);
        HttpResponse res = get(path);
        Map<String, Object> parsed = deserialize(res);

        if (parsed.containsKey('QueryResponse') && parsed.get('QueryResponse') instanceof Map<String, Object>) {
            Map<String, Object> qr = (Map<String, Object>) parsed.get('QueryResponse');
            if (qr.containsKey('totalCount')) {
                return Integer.valueOf(qr.get('totalCount'));
            }
        }
        return 0;
    }

    /**
     * Retrieve a single QuickBooks entity by ID.
     * GET /v3/company/{realmId}/{entityName}/{recordId}
     */
    public Map<String, Object> getRecord(
        String realmId,
        String entityName,
        String recordId
    ) {
        validateRealmAndEntity(realmId, entityName);
        if (String.isBlank(recordId)) {
            throw new ClientException('recordId is required.');
        }

        String path = '/v3/company/' + enc(realmId) + '/' + enc(entityName.toLowerCase()) + '/' + enc(recordId);
        HttpResponse res = get(path);
        return deserialize(res);
    }

    /**
     * Create a new entity in QuickBooks.
     * POST /v3/company/{realmId}/{entityName}
     */
    public Map<String, Object> createRecord(
        String realmId,
        String entityName,
        Map<String, Object> fields
    ) {
        validateRealmAndEntity(realmId, entityName);

        String path = '/v3/company/' + enc(realmId) + '/' + enc(entityName.toLowerCase());
        HttpResponse res = post(path, JSON.serialize(fields));
        return deserialize(res);
    }

    // ─── Helpers ──────────────────────────────────────────────────────

    private static void validateRealmAndEntity(String realmId, String entityName) {
        if (String.isBlank(realmId)) {
            throw new ClientException('QuickBooks realmId (Company ID) is required.');
        }
        if (String.isBlank(entityName)) {
            throw new ClientException('QuickBooks entityName is required.');
        }
    }

    private static Map<String, Object> deserialize(HttpResponse res) {
        String body = res.getBody();
        if (String.isBlank(body)) {
            return new Map<String, Object>();
        }
        return (Map<String, Object>) JSON.deserializeUntyped(body);
    }

    private static String enc(String val) {
        return (val == null) ? '' : EncodingUtil.urlEncode(val, 'UTF-8');
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
                'QuickBooks API returned HTTP ' + response.getStatusCode() +
                (String.isBlank(response.getBody()) ? '' : ': ' + response.getBody())
            );
        }
        return response;
    }

    private void setHeader(HttpRequest request, String name, String value) {
        request.setHeader(name, value);
    }
}
