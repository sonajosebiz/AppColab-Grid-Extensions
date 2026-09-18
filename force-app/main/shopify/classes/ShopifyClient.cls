public with sharing class ShopifyClient {
    public class ClientException extends Exception {
    }
    public class HttpException extends Exception {
    }

    private static final String NAMED_CREDENTIAL = 'Shopify';
    private static final Set<Integer> RETRYABLE_STATUS_CODES = new Set<Integer>{ 408, 429, 500, 502, 503, 504 };


    public static final String API_VERSION = '2024-01';

    public ShopifyClient() {
    }

    /**
     * List records of a given Shopify resource (products, orders, customers).
     * GET /admin/api/2024-01/{resource}.json
     */
    public Map<String, Object> listResources(
        String resource,
        Integer limitCount,
        String sinceId,
        Map<String, String> extraParams
    ) {
        String path = '/admin/api/' + API_VERSION + '/' + enc(resource) + '.json';
        List<String> queryParams = new List<String>();

        if (limitCount != null && limitCount > 0) {
            queryParams.add('limit=' + Math.min(limitCount, 250));
        }
        if (String.isNotBlank(sinceId)) {
            queryParams.add('since_id=' + enc(sinceId));
        }
        if ('orders'.equalsIgnoreCase(resource) && (extraParams == null || !extraParams.containsKey('status'))) {
            queryParams.add('status=any');
        }
        if (extraParams != null) {
            for (String key : extraParams.keySet()) {
                String val = extraParams.get(key);
                if (String.isNotBlank(val)) {
                    queryParams.add(enc(key) + '=' + enc(val));
                }
            }
        }
        if (!queryParams.isEmpty()) {
            path += '?' + String.join(queryParams, '&');
        }

        HttpResponse res = get(path);
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Retrieve a single Shopify resource by ID.
     * GET /admin/api/2024-01/{resource}/{id}.json
     */
    public Map<String, Object> getResource(String resource, String recordId) {
        String singular = toSingular(resource);
        String path = '/admin/api/' + API_VERSION + '/' + enc(resource) + '/' + enc(recordId) + '.json';
        HttpResponse res = get(path);
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Create a new Shopify resource.
     * POST /admin/api/2024-01/{resource}.json
     * Body payload wrapped in singular key: {"product": {...}} or {"customer": {...}}
     */
    public Map<String, Object> createResource(String resource, Map<String, Object> fields) {
        String singular = toSingular(resource);
        Map<String, Object> payload = new Map<String, Object>{
            singular => fields
        };
        String path = '/admin/api/' + API_VERSION + '/' + enc(resource) + '.json';
        HttpResponse res = post(path, JSON.serialize(payload));
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Update an existing Shopify resource.
     * PUT /admin/api/2024-01/{resource}/{id}.json
     * Body payload wrapped in singular key: {"product": {...}} or {"customer": {...}}
     */
    public Map<String, Object> updateResource(
        String resource,
        String recordId,
        Map<String, Object> fields
    ) {
        String singular = toSingular(resource);
        Map<String, Object> payload = new Map<String, Object>{
            singular => fields
        };
        String path = '/admin/api/' + API_VERSION + '/' + enc(resource) + '/' + enc(recordId) + '.json';
        HttpResponse res = put(path, JSON.serialize(payload));
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Delete a Shopify resource.
     * DELETE /admin/api/2024-01/{resource}/{id}.json
     */
    public Map<String, Object> deleteResource(String resource, String recordId) {
        String path = '/admin/api/' + API_VERSION + '/' + enc(resource) + '/' + enc(recordId) + '.json';
        HttpResponse res = del(path);
        if (String.isNotBlank(res.getBody())) {
            return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        }
        return new Map<String, Object>();
    }

    // ─── Helpers ──────────────────────────────────────────────────────

    public static String toSingular(String resource) {
        if (String.isBlank(resource)) {
            return 'item';
        }
        String res = resource.trim().toLowerCase();
        if (res.endsWith('ies')) {
            return res.substring(0, res.length() - 3) + 'y';
        } else if (res.endsWith('s')) {
            return res.substring(0, res.length() - 1);
        }
        return res;
    }

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
                'Shopify API returned HTTP ' + response.getStatusCode() +
                (String.isBlank(response.getBody()) ? '' : ': ' + response.getBody())
            );
        }
        return response;
    }

    private void setHeader(HttpRequest request, String name, String value) {
        request.setHeader(name, value);
    }
}
