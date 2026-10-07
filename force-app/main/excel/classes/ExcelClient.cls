public with sharing class ExcelClient {
    public ExcelClient() {}

    /**
     * Resolves the base path for a workbook in OneDrive.
     * Supports either Drive Item ID (e.g. "01ABCDEF...") or file path (e.g. "/Documents/Sales.xlsx").
     */
    public static String getWorkbookPrefix(String workbookRef) {
        if (String.isBlank(workbookRef)) {
            throw new ClientException('Workbook reference cannot be blank.');
        }
        String ref = workbookRef.trim();
        if (ref.contains('/') || ref.toLowerCase().endsWith('.xlsx') || ref.toLowerCase().endsWith('.xls')) {
            String path = ref.startsWith('/') ? ref : '/' + ref;
            return '/v1.0/me/drive/root:' + enc(path).replace('%2F', '/') + ':/workbook';
        }
        return '/v1.0/me/drive/items/' + enc(ref) + '/workbook';
    }

    public Map<String, Object> getWorksheets(String workbookRef) {
        HttpResponse res = get(getWorkbookPrefix(workbookRef) + '/worksheets');
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    public Map<String, Object> getUsedRange(String workbookRef, String worksheetName) {
        String sheet = String.isBlank(worksheetName) ? 'Sheet1' : worksheetName.trim();
        String path = getWorkbookPrefix(workbookRef) + '/worksheets/' + enc(sheet) + '/usedRange(valuesOnly=true)';
        HttpResponse res = get(path);
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    public Map<String, Object> getRange(String workbookRef, String worksheetName, String rangeAddress) {
        String sheet = String.isBlank(worksheetName) ? 'Sheet1' : worksheetName.trim();
        String path = getWorkbookPrefix(workbookRef) + '/worksheets/' + enc(sheet) +
            '/range(address=\'' + literal(rangeAddress) + '\')';
        HttpResponse res = get(path);
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    public Map<String, Object> updateRange(String workbookRef, String worksheetName, String rangeAddress, List<List<Object>> values) {
        String sheet = String.isBlank(worksheetName) ? 'Sheet1' : worksheetName.trim();
        String path = getWorkbookPrefix(workbookRef) + '/worksheets/' + enc(sheet) +
            '/range(address=\'' + literal(rangeAddress) + '\')';
        Map<String, Object> payload = new Map<String, Object>{ 'values' => values };
        HttpResponse res = patch(path, JSON.serialize(payload));
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    public Map<String, Object> deleteRowRange(String workbookRef, String worksheetName, String rangeAddress) {
        String sheet = String.isBlank(worksheetName) ? 'Sheet1' : worksheetName.trim();
        String path = getWorkbookPrefix(workbookRef) + '/worksheets/' + enc(sheet) +
            '/range(address=\'' + literal(rangeAddress) + '\')/delete';
        HttpResponse res = post(path, '{"shift":"Up"}');
        if (String.isNotBlank(res.getBody())) {
            return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        }
        return new Map<String, Object>{ 'status' => 'DELETED' };
    }

    public Map<String, Object> searchFiles(String query) {
        String q = String.isBlank(query) ? '.xlsx' : query;
        HttpResponse res = get('/v1.0/me/drive/root/search(q=\'' + literal(q) + '\')?$select=id,name,webUrl,size,lastModifiedDateTime');
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }
    public class ClientException extends Exception {}
    public class HttpException extends Exception {}

    private static final String NAMED_CREDENTIAL = 'Excel';
    private static final Set<Integer> RETRYABLE_STATUS_CODES = new Set<Integer>{ 408, 429, 500, 502, 503, 504 };

    private static String enc(String value) {
        return EncodingUtil.urlEncode(value, 'UTF-8').replace('+', '%20');
    }

    // OData string literals escape apostrophes before URI encoding.
    private static String literal(String value) {
        if (String.isBlank(value)) throw new ClientException('Range or search value cannot be blank.');
        return enc(value.replace('\'', '\'\''));
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
        // A range-delete POST shifts rows and cannot safely be replayed.
        Integer maxRetries = request.getMethod() == 'POST' ? 0 : 1;
        for (Integer attempt = 0; attempt <= maxRetries; attempt++) {
            try {
                response = new Http().send(request);
                lastException = null;
                if (!RETRYABLE_STATUS_CODES.contains(response.getStatusCode()) || attempt == maxRetries) {
                    break;
                }
            } catch (System.CalloutException e) {
                lastException = e;
                response = null;
                if (attempt == maxRetries) {
                    break;
                }
            }
        }
        if (response == null) {
            throw new HttpException('Callout failed: ' + (lastException == null ? 'No response.' : lastException.getMessage()));
        }
        if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
            throw new HttpException(
                'Excel API returned HTTP ' + response.getStatusCode() +
                (String.isBlank(response.getBody()) ? '' : ': ' + response.getBody())
            );
        }
        return response;
    }

}
