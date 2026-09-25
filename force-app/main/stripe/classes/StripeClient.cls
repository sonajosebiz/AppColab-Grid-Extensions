public with sharing class StripeClient {
    public class ClientException extends Exception {
    }
    public class HttpException extends Exception {
    }

    private static final String NAMED_CREDENTIAL = 'Stripe';
    private static final Set<Integer> RETRYABLE_STATUS_CODES = new Set<Integer>{ 408, 429, 500, 502, 503, 504 };


    public StripeClient() {
    }

    /**
     * List records of a given Stripe resource (customers, invoices, subscriptions, charges, payment_intents).
     * GET /v1/{resource}
     */
    public Map<String, Object> listResources(
        String resource,
        Integer limitCount,
        String startingAfter
    ) {
        return listResources(resource, limitCount, startingAfter, null);
    }

    public Map<String, Object> listResources(
        String resource,
        Integer limitCount,
        String startingAfter,
        String customerId
    ) {
        String path = '/v1/' + enc(resource);
        List<String> queryParams = new List<String>();
        if (limitCount != null && limitCount > 0) {
            queryParams.add('limit=' + Math.min(limitCount, 100));
        }
        if (String.isNotBlank(startingAfter)) {
            queryParams.add('starting_after=' + enc(startingAfter));
        }
        if (String.isNotBlank(customerId)) {
            queryParams.add('customer=' + enc(customerId));
        }
        if (!queryParams.isEmpty()) {
            path += '?' + String.join(queryParams, '&');
        }
        HttpResponse res = get(path);
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Retrieve a single Stripe resource by ID.
     * GET /v1/{resource}/{id}
     */
    public Map<String, Object> getResource(String resource, String recordId) {
        String path = '/v1/' + enc(resource) + '/' + enc(recordId);
        HttpResponse res = get(path);
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Create a new Stripe resource.
     * POST /v1/{resource} (x-www-form-urlencoded)
     */
    public Map<String, Object> createResource(String resource, Map<String, Object> fields) {
        String path = '/v1/' + enc(resource);
        String body = formEncode(fields);
        HttpResponse res = post(path, body);
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Update an existing Stripe resource.
     * POST /v1/{resource}/{id} (x-www-form-urlencoded)
     */
    public Map<String, Object> updateResource(
        String resource,
        String recordId,
        Map<String, Object> fields
    ) {
        String path = '/v1/' + enc(resource) + '/' + enc(recordId);
        String body = formEncode(fields);
        HttpResponse res = post(path, body);
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Delete/Cancel a Stripe resource.
     * DELETE /v1/{resource}/{id}
     */
    public Map<String, Object> deleteResource(String resource, String recordId) {
        String path = '/v1/' + enc(resource) + '/' + enc(recordId);
        HttpResponse res = del(path);
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    // ─── Helpers ──────────────────────────────────────────────────────

    @TestVisible
    private static String formEncode(Map<String, Object> params) {
        if (params == null || params.isEmpty()) {
            return '';
        }
        List<String> pairs = new List<String>();
        for (String key : params.keySet()) {
            Object val = params.get(key);
            if (val == null) continue;

            if (val instanceof Map<String, Object>) {
                Map<String, Object> subMap = (Map<String, Object>) val;
                for (String subKey : subMap.keySet()) {
                    Object subVal = subMap.get(subKey);
                    if (subVal != null) {
                        pairs.add(enc(key) + '%5B' + enc(subKey) + '%5D=' + enc(String.valueOf(subVal)));
                    }
                }
            } else {
                pairs.add(enc(key) + '=' + enc(String.valueOf(val)));
            }
        }
        return String.join(pairs, '&');
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
            request.setHeader('Content-Type', 'application/x-www-form-urlencoded');
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
                'Stripe API returned HTTP ' + response.getStatusCode() +
                (String.isBlank(response.getBody()) ? '' : ': ' + response.getBody())
            );
        }
        return response;
    }

    private void setHeader(HttpRequest request, String name, String value) {
        request.setHeader(name, value);
    }
}
