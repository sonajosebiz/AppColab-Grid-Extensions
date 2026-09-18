public with sharing class SalesforceClient {
    public class ClientException extends Exception {
    }
    public class HttpException extends Exception {
    }

    private static final String NAMED_CREDENTIAL = 'Salesforce_Org';
    private static final Set<Integer> RETRYABLE_STATUS_CODES = new Set<Integer>{ 408, 429, 500, 502, 503, 504 };

    public static final String API_VERSION = 'v61.0';

    public SalesforceClient() {
    }

    /**
     * Executes a SOQL query against the remote Salesforce org.
     * GET /services/data/{version}/query/?q={soql}
     */
    public Map<String, Object> query(String soql) {
        if (String.isBlank(soql)) {
            throw new ClientException('SOQL query cannot be blank.');
        }
        String path = '/services/data/' + API_VERSION + '/query/?q=' + enc(soql);
        HttpResponse res = get(path);
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Fetches metadata describe for an SObject from the remote Salesforce org.
     * GET /services/data/{version}/sobjects/{sObjectName}/describe
     */
    public Map<String, Object> describeSObject(String sObjectName) {
        if (String.isBlank(sObjectName)) {
            throw new ClientException('sObjectName cannot be blank.');
        }
        String path = '/services/data/' + API_VERSION + '/sobjects/' + enc(sObjectName) + '/describe';
        HttpResponse res = get(path);
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Fetches a single SObject record by Id from the remote Salesforce org.
     * GET /services/data/{version}/sobjects/{sObjectName}/{recordId}
     */
    public Map<String, Object> getRecord(String sObjectName, String recordId, List<String> fields) {
        if (String.isBlank(sObjectName) || String.isBlank(recordId)) {
            throw new ClientException('sObjectName and recordId are required.');
        }
        String path = '/services/data/' + API_VERSION + '/sobjects/' + enc(sObjectName) + '/' + enc(recordId);
        if (fields != null && !fields.isEmpty()) {
            path += '?fields=' + enc(String.join(fields, ','));
        }
        HttpResponse res = get(path);
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Creates a new SObject record in the remote Salesforce org.
     * POST /services/data/{version}/sobjects/{sObjectName}
     */
    public Map<String, Object> createRecord(String sObjectName, Map<String, Object> fields) {
        if (String.isBlank(sObjectName)) {
            throw new ClientException('sObjectName cannot be blank.');
        }
        String path = '/services/data/' + API_VERSION + '/sobjects/' + enc(sObjectName);
        HttpResponse res = post(path, JSON.serialize(fields == null ? new Map<String, Object>() : fields));
        String body = res.getBody();
        if (String.isNotBlank(body)) {
            return (Map<String, Object>) JSON.deserializeUntyped(body);
        }
        return new Map<String, Object>();
    }

    /**
     * Updates an existing SObject record in the remote Salesforce org.
     * PATCH /services/data/{version}/sobjects/{sObjectName}/{recordId}
     */
    public Map<String, Object> updateRecord(String sObjectName, String recordId, Map<String, Object> fields) {
        if (String.isBlank(sObjectName) || String.isBlank(recordId)) {
            throw new ClientException('sObjectName and recordId are required.');
        }
        String path = '/services/data/' + API_VERSION + '/sobjects/' + enc(sObjectName) + '/' + enc(recordId);
        HttpResponse res = patch(path, JSON.serialize(fields == null ? new Map<String, Object>() : fields));
        String body = res.getBody();
        if (String.isNotBlank(body)) {
            return (Map<String, Object>) JSON.deserializeUntyped(body);
        }
        return new Map<String, Object>();
    }

    /**
     * Deletes an SObject record from the remote Salesforce org.
     * DELETE /services/data/{version}/sobjects/{sObjectName}/{recordId}
     */
    public Map<String, Object> deleteRecord(String sObjectName, String recordId) {
        if (String.isBlank(sObjectName) || String.isBlank(recordId)) {
            throw new ClientException('sObjectName and recordId are required.');
        }
        String path = '/services/data/' + API_VERSION + '/sobjects/' + enc(sObjectName) + '/' + enc(recordId);
        HttpResponse res = del(path);
        String body = res.getBody();
        if (String.isNotBlank(body)) {
            return (Map<String, Object>) JSON.deserializeUntyped(body);
        }
        return new Map<String, Object>();
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
                'Salesforce API returned HTTP ' + response.getStatusCode() +
                (String.isBlank(response.getBody()) ? '' : ': ' + response.getBody())
            );
        }
        return response;
    }

    private void setHeader(HttpRequest request, String name, String value) {
        request.setHeader(name, value);
    }
}
