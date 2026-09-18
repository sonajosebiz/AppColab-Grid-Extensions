public with sharing class AirtableClient {
    public class ClientException extends Exception {
    }
    public class HttpException extends Exception {
    }

    private static final String NAMED_CREDENTIAL = 'Airtable';
    private static final Set<Integer> RETRYABLE_STATUS_CODES = new Set<Integer>{ 408, 429, 500, 502, 503, 504 };

    public AirtableClient() {
    }

    /**
     * List records from a table.
     * GET /v0/{baseId}/{tableIdOrName}
     */
    public Map<String, Object> listRecords(
        String baseId,
        String tableIdOrName,
        Integer pageSize,
        String offset
    ) {
        String path = '/v0/' + enc(baseId) + '/' + enc(tableIdOrName);
        List<String> queryParams = new List<String>();
        if (pageSize != null && pageSize > 0) {
            queryParams.add('pageSize=' + Math.min(pageSize, 100));
        }
        if (String.isNotBlank(offset)) {
            queryParams.add('offset=' + enc(offset));
        }
        if (!queryParams.isEmpty()) {
            path += '?' + String.join(queryParams, '&');
        }
        HttpResponse res = get(path);
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Batch create new records.
     * POST /v0/{baseId}/{tableIdOrName}
     */
    public Map<String, Object> createRecords(
        String baseId,
        String tableIdOrName,
        List<Map<String, Object>> records
    ) {
        String path = '/v0/' + enc(baseId) + '/' + enc(tableIdOrName);
        String body = JSON.serialize(new Map<String, Object>{
            'records' => records,
            'typecast' => true
        });
        HttpResponse res = post(path, body);
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Batch update existing records.
     * PATCH /v0/{baseId}/{tableIdOrName}
     */
    public Map<String, Object> updateRecords(
        String baseId,
        String tableIdOrName,
        List<Map<String, Object>> records
    ) {
        String path = '/v0/' + enc(baseId) + '/' + enc(tableIdOrName);
        String body = JSON.serialize(new Map<String, Object>{
            'records' => records,
            'typecast' => true
        });
        HttpResponse res = patch(path, body);
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Batch delete records by record ID.
     * DELETE /v0/{baseId}/{tableIdOrName}?records[]=rec1&records[]=rec2
     */
    public Map<String, Object> deleteRecords(
        String baseId,
        String tableIdOrName,
        List<String> recordIds
    ) {
        String path = '/v0/' + enc(baseId) + '/' + enc(tableIdOrName);
        List<String> params = new List<String>();
        for (String recId : recordIds) {
            params.add('records%5B%5D=' + enc(recId));
        }
        if (!params.isEmpty()) {
            path += '?' + String.join(params, '&');
        }
        HttpResponse res = del(path);
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Get base table schema (if user has schema access).
     * GET /v0/meta/bases/{baseId}/tables
     */
    public Map<String, Object> getBaseSchema(String baseId) {
        String path = '/v0/meta/bases/' + enc(baseId) + '/tables';
        HttpResponse res = get(path);
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    private static String enc(String value) {
        return EncodingUtil.urlEncode(value, 'UTF-8').replace('+', '%20');
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
                'Airtable API returned HTTP ' + response.getStatusCode() +
                (String.isBlank(response.getBody()) ? '' : ': ' + response.getBody())
            );
        }
        return response;
    }

    private void setHeader(HttpRequest request, String name, String value) {
        request.setHeader(name, value);
    }
}
