public with sharing class XeroClient {
    public class ClientException extends Exception {
    }
    public class HttpException extends Exception {
    }

    private static final String NAMED_CREDENTIAL = 'Xero';
    private static final Set<Integer> RETRYABLE_STATUS_CODES = new Set<Integer>{ 408, 429, 500, 502, 503, 504 };


    public XeroClient() {
    }

    /**
     * List all connections (tenants) the authenticated user has access to.
     * GET /connections
     * Note: This endpoint does NOT require the xero-tenant-id header.
     */
    public List<Object> getConnections() {
        HttpResponse res = get('/connections');
        return (List<Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * List Invoices with page number support for Server-Side Pagination.
     * GET /api.xro/2.0/Invoices?page={page}&where={where}
     */
    public Map<String, Object> listInvoices(String tenantId, Integer page, String whereClause) {
        validateTenantId(tenantId);
        String path = '/api.xro/2.0/Invoices';
        List<String> queryParams = new List<String>();
        if (page != null && page > 0) {
            queryParams.add('page=' + page);
        }
        if (String.isNotBlank(whereClause)) {
            queryParams.add('where=' + enc(whereClause));
        }
        if (!queryParams.isEmpty()) {
            path += '?' + String.join(queryParams, '&');
        }
        return doTenantGet(tenantId, path);
    }

    public Map<String, Object> listInvoices(String tenantId, String whereClause) {
        return listInvoices(tenantId, 1, whereClause);
    }

    /**
     * List Contacts with page number support.
     * GET /api.xro/2.0/Contacts?page={page}&where={where}
     */
    public Map<String, Object> listContacts(String tenantId, Integer page, String whereClause) {
        validateTenantId(tenantId);
        String path = '/api.xro/2.0/Contacts';
        List<String> queryParams = new List<String>();
        if (page != null && page > 0) {
            queryParams.add('page=' + page);
        }
        if (String.isNotBlank(whereClause)) {
            queryParams.add('where=' + enc(whereClause));
        }
        if (!queryParams.isEmpty()) {
            path += '?' + String.join(queryParams, '&');
        }
        return doTenantGet(tenantId, path);
    }

    public Map<String, Object> listContacts(String tenantId) {
        return listContacts(tenantId, 1, null);
    }

    /**
     * List Accounts (Chart of Accounts).
     * GET /api.xro/2.0/Accounts?where={where}
     */
    public Map<String, Object> listAccounts(String tenantId, String whereClause) {
        validateTenantId(tenantId);
        String path = '/api.xro/2.0/Accounts';
        if (String.isNotBlank(whereClause)) {
            path += '?where=' + enc(whereClause);
        }
        return doTenantGet(tenantId, path);
    }

    public Map<String, Object> listAccounts(String tenantId) {
        return listAccounts(tenantId, null);
    }

    /**
     * List Payments with page number support.
     * GET /api.xro/2.0/Payments?page={page}&where={where}
     */
    public Map<String, Object> listPayments(String tenantId, Integer page, String whereClause) {
        validateTenantId(tenantId);
        String path = '/api.xro/2.0/Payments';
        List<String> queryParams = new List<String>();
        if (page != null && page > 0) {
            queryParams.add('page=' + page);
        }
        if (String.isNotBlank(whereClause)) {
            queryParams.add('where=' + enc(whereClause));
        }
        if (!queryParams.isEmpty()) {
            path += '?' + String.join(queryParams, '&');
        }
        return doTenantGet(tenantId, path);
    }

    public Map<String, Object> listPayments(String tenantId) {
        return listPayments(tenantId, 1, null);
    }

    /**
     * List Bank Transactions with page number support.
     * GET /api.xro/2.0/BankTransactions?page={page}&where={where}
     */
    public Map<String, Object> listBankTransactions(String tenantId, Integer page, String whereClause) {
        validateTenantId(tenantId);
        String path = '/api.xro/2.0/BankTransactions';
        List<String> queryParams = new List<String>();
        if (page != null && page > 0) {
            queryParams.add('page=' + page);
        }
        if (String.isNotBlank(whereClause)) {
            queryParams.add('where=' + enc(whereClause));
        }
        if (!queryParams.isEmpty()) {
            path += '?' + String.join(queryParams, '&');
        }
        return doTenantGet(tenantId, path);
    }

    public Map<String, Object> listBankTransactions(String tenantId) {
        return listBankTransactions(tenantId, 1, null);
    }

    // ─── Helpers ──────────────────────────────────────────────────────

    private Map<String, Object> doTenantGet(String tenantId, String path) {
        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setEndpoint(path);
        req.setHeader('xero-tenant-id', tenantId);
        HttpResponse res = send(req);
        String body = res.getBody();
        if (String.isBlank(body)) {
            return new Map<String, Object>();
        }
        return (Map<String, Object>) JSON.deserializeUntyped(body);
    }

    private static void validateTenantId(String tenantId) {
        if (String.isBlank(tenantId)) {
            throw new ClientException('Xero tenantId is required.');
        }
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
                'Xero API returned HTTP ' + response.getStatusCode() +
                (String.isBlank(response.getBody()) ? '' : ': ' + response.getBody())
            );
        }
        return response;
    }

    private void setHeader(HttpRequest request, String name, String value) {
        request.setHeader(name, value);
    }
}
