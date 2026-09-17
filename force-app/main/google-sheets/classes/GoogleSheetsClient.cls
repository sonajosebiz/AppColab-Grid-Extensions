public with sharing class GoogleSheetsClient {
    public class GoogleSheetsClientException extends Exception {
    }

    @TestVisible
    private static final String DEFAULT_NAMED_CREDENTIAL = 'Google_Sheets';
    @TestVisible
    private static final Integer DEFAULT_TIMEOUT_MS = 60000;
    @TestVisible
    private static final Integer MAX_RETRIES = 1;
    @TestVisible
    private static final Set<Integer> RETRYABLE_STATUS_CODES = new Set<Integer>{
        408,
        429,
        500,
        502,
        503,
        504
    };

    private final String namedCredential;

    public GoogleSheetsClient() {
        this(DEFAULT_NAMED_CREDENTIAL);
    }

    @TestVisible
    private GoogleSheetsClient(String namedCredential) {
        if (String.isBlank(namedCredential)) {
            throw new GoogleSheetsClientException('A Named Credential API name is required.');
        }
        this.namedCredential = namedCredential;
    }

    /** Read cell values from a sheet range. */
    public Map<String, Object> getValues(String spreadsheetId, String range) {
        String path = '/v4/spreadsheets/' + enc(spreadsheetId) + '/values/' + enc(range);
        return sendJson('GET', path, null);
    }

    /** Update cell values in one or more ranges. */
    public Map<String, Object> batchUpdateValues(String spreadsheetId, List<Map<String, Object>> data) {
        String path = '/v4/spreadsheets/' + enc(spreadsheetId) + '/values:batchUpdate';
        return sendJson(
            'POST',
            path,
            JSON.serialize(
                new Map<String, Object>{
                    'valueInputOption' => 'USER_ENTERED',
                    'data' => data
                }
            )
        );
    }

    /** Append rows after existing data. */
    public Map<String, Object> appendValues(String spreadsheetId, String range, List<List<Object>> values) {
        String path =
            '/v4/spreadsheets/' +
            enc(spreadsheetId) +
            '/values/' +
            enc(range) +
            ':append?valueInputOption=USER_ENTERED&insertDataOption=INSERT_ROWS';
        return sendJson('POST', path, JSON.serialize(new Map<String, Object>{ 'values' => values }));
    }

    /** Execute structural changes such as row deletion. */
    public Map<String, Object> batchUpdate(String spreadsheetId, List<Map<String, Object>> requests) {
        String path = '/v4/spreadsheets/' + enc(spreadsheetId) + ':batchUpdate';
        return sendJson('POST', path, JSON.serialize(new Map<String, Object>{ 'requests' => requests }));
    }

    /** Get spreadsheet metadata including sheet names and numeric IDs. */
    public Map<String, Object> getMetadata(String spreadsheetId) {
        String path = '/v4/spreadsheets/' + enc(spreadsheetId) + '?fields=sheets.properties';
        return sendJson('GET', path, null);
    }

    private Map<String, Object> sendJson(String method, String path, String body) {
        HttpRequest request = new HttpRequest();
        request.setMethod(method);
        request.setEndpoint('callout:' + namedCredential + normalizePath(path));
        request.setHeader('Accept', 'application/json');
        request.setHeader('Content-Type', 'application/json');
        request.setTimeout(DEFAULT_TIMEOUT_MS);
        if (body != null) {
            request.setBody(body);
        }

        HttpResponse response;
        CalloutException lastCalloutException;
        Integer attempt = 0;
        while (attempt <= MAX_RETRIES) {
            attempt++;
            try {
                response = new Http().send(request);
                lastCalloutException = null;
                if (!RETRYABLE_STATUS_CODES.contains(response.getStatusCode()) || attempt > MAX_RETRIES) {
                    break;
                }
            } catch (CalloutException e) {
                lastCalloutException = e;
                response = null;
                if (attempt > MAX_RETRIES) {
                    break;
                }
            }
        }

        if (response == null) {
            throw new GoogleSheetsClientException(
                'Google Sheets callout failed after ' +
                attempt +
                ' attempt(s): ' +
                (lastCalloutException == null ? 'No response received.' : lastCalloutException.getMessage())
            );
        }

        Integer statusCode = response.getStatusCode();
        if (statusCode < 200 || statusCode >= 300) {
            String responseBody = response.getBody();
            if (responseBody != null && responseBody.length() > 1000) {
                responseBody = responseBody.substring(0, 1000);
            }
            throw new GoogleSheetsClientException(
                'Google Sheets API returned HTTP ' +
                statusCode +
                (String.isBlank(response.getStatus()) ? '' : ' ' + response.getStatus()) +
                (String.isBlank(responseBody) ? '' : ': ' + responseBody)
            );
        }

        if (String.isBlank(response.getBody())) {
            return new Map<String, Object>();
        }
        try {
            return (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
        } catch (Exception e) {
            throw new GoogleSheetsClientException('Google Sheets API returned invalid JSON: ' + e.getMessage());
        }
    }

    private static String normalizePath(String path) {
        if (String.isBlank(path)) {
            return '';
        }
        return path.startsWith('/') ? path : '/' + path;
    }

    private static String enc(String value) {
        if (value == null) {
            throw new GoogleSheetsClientException('Google Sheets identifiers and ranges cannot be null.');
        }
        return EncodingUtil.urlEncode(value, 'UTF-8');
    }
}
