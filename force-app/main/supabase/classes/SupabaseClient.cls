public with sharing class SupabaseClient {
    public class ClientException extends Exception {
    }
    public class HttpException extends Exception {
    }

    private static final String NAMED_CREDENTIAL = 'Supabase';
    private static final Set<Integer> RETRYABLE_STATUS_CODES = new Set<Integer>{ 408, 429, 500, 502, 503, 504 };


    public class QueryResult {
        public List<Object> records;
        public Integer totalCount;

        public QueryResult() {
            this.records = new List<Object>();
            this.totalCount = 0;
        }
    }

    public SupabaseClient() {
    }

    /**
     * Query records with exact totalCount from PostgREST Content-Range header for Server-Side Pagination.
     * GET /rest/v1/{table}?select=*&order={order}&limit={limit}&offset={offset}
     * Header: Prefer: count=exact
     */
    public QueryResult queryTableWithCount(
        String table,
        String selectFields,
        String orderClause,
        Integer limitCount,
        Integer offsetCount,
        String filterQuery
    ) {
        validateTable(table);

        String path = '/rest/v1/' + enc(table);
        List<String> queryParams = new List<String>();

        queryParams.add('select=' + (String.isNotBlank(selectFields) ? enc(selectFields) : '*'));

        if (String.isNotBlank(orderClause)) {
            queryParams.add('order=' + enc(orderClause));
        }

        if (limitCount != null && limitCount > 0) {
            queryParams.add('limit=' + Math.min(limitCount, 1000));
        }

        if (offsetCount != null && offsetCount > 0) {
            queryParams.add('offset=' + offsetCount);
        }

        if (String.isNotBlank(filterQuery)) {
            queryParams.add(filterQuery);
        }

        path += '?' + String.join(queryParams, '&');

        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setEndpoint(path);
        setHeader(req, 'Prefer', 'count=exact');

        HttpResponse res = send(req);
        QueryResult qr = new QueryResult();

        // Extract total count from Content-Range header (e.g. "0-19/350" or "*/350")
        String contentRange = res.getHeader('Content-Range');
        if (String.isNotBlank(contentRange) && contentRange.contains('/')) {
            String totalPart = contentRange.substringAfterLast('/').trim();
            if (!'*'.equals(totalPart)) {
                try {
                    qr.totalCount = Integer.valueOf(totalPart);
                } catch (Exception ignored) {}
            }
        }

        String body = res.getBody();
        if (String.isNotBlank(body)) {
            Object parsed = JSON.deserializeUntyped(body);
            if (parsed instanceof List<Object>) {
                qr.records = (List<Object>) parsed;
            } else if (parsed instanceof Map<String, Object>) {
                qr.records = new List<Object>{ parsed };
            }
        }

        if (qr.totalCount == 0 && !qr.records.isEmpty()) {
            qr.totalCount = (offsetCount != null ? offsetCount : 0) + qr.records.size();
        }

        return qr;
    }

    /**
     * Query records from a Supabase PostgreSQL table via PostgREST.
     * GET /rest/v1/{table}?select=*&order={order}&limit={limit}
     */
    public List<Object> queryTable(
        String table,
        String selectFields,
        String orderClause,
        Integer limitCount,
        String filterQuery
    ) {
        QueryResult res = queryTableWithCount(table, selectFields, orderClause, limitCount, null, filterQuery);
        return res.records;
    }

    /**
     * Insert a new record into a Supabase PostgreSQL table.
     * POST /rest/v1/{table}
     */
    public List<Object> insertRecord(String table, Map<String, Object> fields) {
        validateTable(table);
        String path = '/rest/v1/' + enc(table);
        String body = JSON.serialize(fields);
        HttpResponse res = post(path, body);
        return parseListResponse(res.getBody());
    }

    /**
     * Insert multiple records into a Supabase PostgreSQL table in a single request.
     * POST /rest/v1/{table}
     */
    public List<Object> insertRecords(String table, List<Map<String, Object>> records) {
        validateTable(table);
        if (records == null || records.isEmpty()) {
            return new List<Object>();
        }
        String path = '/rest/v1/' + enc(table);
        String body = JSON.serialize(records);
        HttpResponse res = post(path, body);
        return parseListResponse(res.getBody());
    }

    /**
     * Update an existing record in a Supabase table.
     * PATCH /rest/v1/{table}?{idColumn}=eq.{idValue}
     */
    public List<Object> updateRecord(
        String table,
        String idColumn,
        String idValue,
        Map<String, Object> fields
    ) {
        if (String.isBlank(table) || String.isBlank(idColumn) || String.isBlank(idValue)) {
            throw new ClientException('Table name, ID column, and ID value are required for update.');
        }
        String path = '/rest/v1/' + enc(table) + '?' + enc(idColumn) + '=eq.' + enc(idValue);
        String body = JSON.serialize(fields);
        HttpResponse res = patch(path, body);
        return parseListResponse(res.getBody());
    }

    /**
     * Delete a record from a Supabase table.
     * DELETE /rest/v1/{table}?{idColumn}=eq.{idValue}
     */
    public Integer deleteRecord(String table, String idColumn, String idValue) {
        if (String.isBlank(table) || String.isBlank(idColumn) || String.isBlank(idValue)) {
            throw new ClientException('Table name, ID column, and ID value are required for deletion.');
        }
        String path = '/rest/v1/' + enc(table) + '?' + enc(idColumn) + '=eq.' + enc(idValue);
        HttpResponse res = del(path);
        return res.getStatusCode();
    }

    // ─── Helpers ──────────────────────────────────────────────────────

    private static void validateTable(String table) {
        if (String.isBlank(table)) {
            throw new ClientException('Supabase table name is required.');
        }
    }

    private static List<Object> parseListResponse(String resBody) {
        if (String.isBlank(resBody)) {
            return new List<Object>();
        }
        Object parsed = JSON.deserializeUntyped(resBody);
        if (parsed instanceof List<Object>) {
            return (List<Object>) parsed;
        } else if (parsed instanceof Map<String, Object>) {
            return new List<Object>{ parsed };
        }
        return new List<Object>();
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
                'Supabase API returned HTTP ' + response.getStatusCode() +
                (String.isBlank(response.getBody()) ? '' : ': ' + response.getBody())
            );
        }
        return response;
    }

    private void setHeader(HttpRequest request, String name, String value) {
        request.setHeader(name, value);
    }
}
