public with sharing class ExcelClient {
    public class ClientException extends Exception {}
    public class HttpException extends Exception {}
    public class ConfigurationException extends Exception {}

    private static final String NAMED_CREDENTIAL = 'Excel';
    private static final Set<Integer> RETRYABLE_STATUS_CODES = new Set<Integer>{ 408, 429, 500, 502, 503, 504 };

    public ExcelClient() {}

    /**
     * Resolves the base path for a workbook in OneDrive.
     * Supports either Drive Item ID (e.g. "01ABCDEF...") or file path (e.g. "/Documents/Sales.xlsx").
     */
    public static String getWorkbookPrefix(String workbookRef) {
        if (String.isBlank(workbookRef)) {
            throw new ConfigurationException('Workbook reference cannot be blank.');
        }
        String ref = workbookRef.trim();
        if (ref.contains('/') || ref.toLowerCase().endsWith('.xlsx') || ref.toLowerCase().endsWith('.xls')) {
            String path = ref.startsWith('/') ? ref : '/' + ref;
            return '/v1.0/me/drive/root:' + EncodingUtil.urlEncode(path, 'UTF-8') + ':/workbook';
        }
        return '/v1.0/me/drive/items/' + EncodingUtil.urlEncode(ref, 'UTF-8') + '/workbook';
    }

    public Map<String, Object> getWorksheets(String workbookRef) {
        HttpResponse res = get(getWorkbookPrefix(workbookRef) + '/worksheets');
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    public Map<String, Object> getUsedRange(String workbookRef, String worksheetName) {
        String sheet = String.isBlank(worksheetName) ? 'Sheet1' : worksheetName.trim();
        String path = getWorkbookPrefix(workbookRef) + '/worksheets/' + EncodingUtil.urlEncode(sheet, 'UTF-8') + '/usedRange';
        HttpResponse res = get(path);
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    public Map<String, Object> getRange(String workbookRef, String worksheetName, String rangeAddress) {
        String sheet = String.isBlank(worksheetName) ? 'Sheet1' : worksheetName.trim();
        String path = getWorkbookPrefix(workbookRef) + '/worksheets/' + EncodingUtil.urlEncode(sheet, 'UTF-8') +
            '/range(address=\'' + EncodingUtil.urlEncode(rangeAddress, 'UTF-8') + '\')';
        HttpResponse res = get(path);
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    public Map<String, Object> updateRange(String workbookRef, String worksheetName, String rangeAddress, List<List<Object>> values) {
        String sheet = String.isBlank(worksheetName) ? 'Sheet1' : worksheetName.trim();
        String path = getWorkbookPrefix(workbookRef) + '/worksheets/' + EncodingUtil.urlEncode(sheet, 'UTF-8') +
            '/range(address=\'' + EncodingUtil.urlEncode(rangeAddress, 'UTF-8') + '\')';
        Map<String, Object> payload = new Map<String, Object>{ 'values' => values };
        HttpResponse res = patch(path, JSON.serialize(payload));
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    public Map<String, Object> deleteRowRange(String workbookRef, String worksheetName, String rangeAddress) {
        String sheet = String.isBlank(worksheetName) ? 'Sheet1' : worksheetName.trim();
        String path = getWorkbookPrefix(workbookRef) + '/worksheets/' + EncodingUtil.urlEncode(sheet, 'UTF-8') +
            '/range(address=\'' + EncodingUtil.urlEncode(rangeAddress, 'UTF-8') + '\')/delete';
        HttpResponse res = post(path, '{"shift":"Up"}');
        if (String.isNotBlank(res.getBody())) {
            return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        }
        return new Map<String, Object>{ 'status' => 'DELETED' };
    }

    public Map<String, Object> searchFiles(String query) {
        String q = String.isBlank(query) ? '.xlsx' : query;
        HttpResponse res = get('/v1.0/me/drive/root/search(q=\'' + EncodingUtil.urlEncode(q, 'UTF-8') + '\')?$select=id,name,webUrl,size,lastModifiedDateTime');
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
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
                'Excel API returned HTTP ' + response.getStatusCode() +
                (String.isBlank(response.getBody()) ? '' : ': ' + response.getBody())
            );
        }
        return response;
    }
}
