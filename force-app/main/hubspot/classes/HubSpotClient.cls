public with sharing class HubSpotClient {
    public class ClientException extends Exception {
    }
    public class HttpException extends Exception {
    }

    private static final String NAMED_CREDENTIAL = 'HubSpot';
    private static final Set<Integer> RETRYABLE_STATUS_CODES = new Set<Integer>{ 408, 429, 500, 502, 503, 504 };


    public HubSpotClient() {
    }

    /**
     * List CRM objects (contacts, companies, deals, tickets, products, etc.).
     * GET /crm/v3/objects/{objectType}?limit={limit}&after={after}&properties={properties}&archived=false
     */
    public Map<String, Object> listObjects(
        String objectType,
        Integer limitCount,
        String afterCursor,
        List<String> properties
    ) {
        validateObjectType(objectType);
        String path = '/crm/v3/objects/' + enc(objectType);
        List<String> params = new List<String>();
        if (limitCount != null && limitCount > 0) {
            params.add('limit=' + String.valueOf(Math.min(limitCount, 100)));
        }
        if (String.isNotBlank(afterCursor)) {
            params.add('after=' + enc(afterCursor));
        }
        if (properties != null && !properties.isEmpty()) {
            params.add('properties=' + enc(String.join(properties, ',')));
        }
        params.add('archived=false');
        path += '?' + String.join(params, '&');

        HttpResponse res = get(path);
        return deserialize(res);
    }

    /**
     * Get property schema definitions for an object type.
     * GET /crm/v3/properties/{objectType}
     */
    public Map<String, Object> describeProperties(String objectType) {
        validateObjectType(objectType);
        String path = '/crm/v3/properties/' + enc(objectType);
        HttpResponse res = get(path);
        return deserialize(res);
    }

    /**
     * Search CRM objects by query or text search.
     * POST /crm/v3/objects/{objectType}/search
     */
    public Map<String, Object> searchObjects(
        String objectType,
        String query,
        Integer limitCount,
        String afterCursor,
        List<String> properties
    ) {
        validateObjectType(objectType);
        String path = '/crm/v3/objects/' + enc(objectType) + '/search';
        Map<String, Object> body = new Map<String, Object>();
        if (String.isNotBlank(query)) {
            body.put('query', query);
        }
        if (limitCount != null && limitCount > 0) {
            body.put('limit', Math.min(limitCount, 100));
        }
        if (String.isNotBlank(afterCursor)) {
            body.put('after', afterCursor);
        }
        if (properties != null && !properties.isEmpty()) {
            body.put('properties', properties);
        }

        HttpResponse res = post(path, JSON.serialize(body));
        return deserialize(res);
    }

    /**
     * Search CRM objects by exact property filter (e.g. email = 'john@example.com').
     * POST /crm/v3/objects/{objectType}/search
     */
    public Map<String, Object> searchObjectsByProperty(
        String objectType,
        String propertyName,
        String propertyValue,
        Integer limitCount,
        String afterCursor,
        List<String> properties
    ) {
        validateObjectType(objectType);
        String path = '/crm/v3/objects/' + enc(objectType) + '/search';
        Map<String, Object> body = new Map<String, Object>();
        if (String.isNotBlank(propertyName) && String.isNotBlank(propertyValue)) {
            body.put('filterGroups', new List<Map<String, Object>>{
                new Map<String, Object>{
                    'filters' => new List<Map<String, Object>>{
                        new Map<String, Object>{
                            'propertyName' => propertyName,
                            'operator' => 'EQ',
                            'value' => propertyValue
                        }
                    }
                }
            });
        }
        if (limitCount != null && limitCount > 0) {
            body.put('limit', Math.min(limitCount, 100));
        }
        if (String.isNotBlank(afterCursor)) {
            body.put('after', afterCursor);
        }
        if (properties != null && !properties.isEmpty()) {
            body.put('properties', properties);
        }

        HttpResponse res = post(path, JSON.serialize(body));
        return deserialize(res);
    }

    /**
     * Get associations for a CRM object (e.g. contacts to emails).
     * GET /crm/v3/objects/{fromObjectType}/{fromObjectId}/associations/{toObjectType}
     */
    public Map<String, Object> getAssociations(String fromObjectType, String fromObjectId, String toObjectType) {
        validateObjectType(fromObjectType);
        validateRecordId(fromObjectId);
        validateObjectType(toObjectType);
        String path = '/crm/v3/objects/' + enc(fromObjectType) + '/' + enc(fromObjectId) + '/associations/' + enc(toObjectType);
        HttpResponse res = get(path);
        return deserialize(res);
    }

    /**
     * Batch read CRM objects by IDs.
     * POST /crm/v3/objects/{objectType}/batch/read
     */
    public Map<String, Object> batchReadObjects(String objectType, List<String> recordIds, List<String> properties) {
        validateObjectType(objectType);
        String path = '/crm/v3/objects/' + enc(objectType) + '/batch/read';
        List<Map<String, Object>> inputs = new List<Map<String, Object>>();
        if (recordIds != null) {
            for (String rid : recordIds) {
                if (String.isNotBlank(rid)) {
                    inputs.add(new Map<String, Object>{ 'id' => rid });
                }
            }
        }
        Map<String, Object> body = new Map<String, Object>{
            'inputs' => inputs
        };
        if (properties != null && !properties.isEmpty()) {
            body.put('properties', properties);
        }
        HttpResponse res = post(path, JSON.serialize(body));
        return deserialize(res);
    }

    /**
     * Search CRM objects by structured filter groups.
     * POST /crm/v3/objects/{objectType}/search
     */
    public Map<String, Object> searchObjectsWithFilterGroups(
        String objectType,
        List<Map<String, Object>> filterGroups,
        Integer limitCount,
        String afterCursor,
        List<String> properties
    ) {
        validateObjectType(objectType);
        String path = '/crm/v3/objects/' + enc(objectType) + '/search';
        Map<String, Object> body = new Map<String, Object>();
        if (filterGroups != null && !filterGroups.isEmpty()) {
            body.put('filterGroups', filterGroups);
        }
        if (limitCount != null && limitCount > 0) {
            body.put('limit', Math.min(limitCount, 100));
        }
        if (String.isNotBlank(afterCursor)) {
            body.put('after', afterCursor);
        }
        if (properties != null && !properties.isEmpty()) {
            body.put('properties', properties);
        }

        HttpResponse res = post(path, JSON.serialize(body));
        return deserialize(res);
    }

    /**
     * Create a CRM object.
     * POST /crm/v3/objects/{objectType}
     */
    public Map<String, Object> createObject(String objectType, Map<String, Object> properties) {
        validateObjectType(objectType);
        String path = '/crm/v3/objects/' + enc(objectType);
        Map<String, Object> body = new Map<String, Object>{
            'properties' => properties != null ? properties : new Map<String, Object>()
        };
        HttpResponse res = post(path, JSON.serialize(body));
        return deserialize(res);
    }

    /**
     * Update a CRM object.
     * PATCH /crm/v3/objects/{objectType}/{recordId}
     */
    public Map<String, Object> updateObject(String objectType, String recordId, Map<String, Object> properties) {
        validateObjectType(objectType);
        validateRecordId(recordId);
        String path = '/crm/v3/objects/' + enc(objectType) + '/' + enc(recordId);
        Map<String, Object> body = new Map<String, Object>{
            'properties' => properties != null ? properties : new Map<String, Object>()
        };
        HttpResponse res = patch(path, JSON.serialize(body));
        return deserialize(res);
    }

    /**
     * Delete a CRM object.
     * DELETE /crm/v3/objects/{objectType}/{recordId}
     */
    public void deleteObject(String objectType, String recordId) {
        validateObjectType(objectType);
        validateRecordId(recordId);
        String path = '/crm/v3/objects/' + enc(objectType) + '/' + enc(recordId);
        del(path);
    }

    // ─── Helpers ──────────────────────────────────────────────────────

    private static void validateObjectType(String objectType) {
        if (String.isBlank(objectType)) {
            throw new ClientException('HubSpot objectType is required.');
        }
    }

    private static void validateRecordId(String recordId) {
        if (String.isBlank(recordId)) {
            throw new ClientException('HubSpot recordId is required.');
        }
    }

    private static String enc(String val) {
        return val == null ? '' : EncodingUtil.urlEncode(val, 'UTF-8');
    }

    private static Map<String, Object> deserialize(HttpResponse res) {
        if (res == null || String.isBlank(res.getBody())) {
            return new Map<String, Object>();
        }
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
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
                'HubSpot API returned HTTP ' + response.getStatusCode() +
                (String.isBlank(response.getBody()) ? '' : ': ' + response.getBody())
            );
        }
        return response;
    }

    private void setHeader(HttpRequest request, String name, String value) {
        request.setHeader(name, value);
    }
}
