public with sharing class GmailClient {
    public class ClientException extends Exception {
    }
    public class HttpException extends Exception {
    }

    private static final String NAMED_CREDENTIAL = 'Gmail';
    private static final Set<Integer> RETRYABLE_STATUS_CODES = new Set<Integer>{ 408, 429, 500, 502, 503, 504 };

    public GmailClient() {
    }

    public Map<String, Object> sendEmail(String toAddress, String subject, String htmlBody) {
        String mime =
            'To: ' + toAddress + '\r\n' +
            'Subject: ' + subject + '\r\n' +
            'MIME-Version: 1.0\r\n' +
            'Content-Type: text/html; charset="UTF-8"\r\n' +
            '\r\n' +
            htmlBody;
        String payload = JSON.serialize(new Map<String, Object>{
            'raw' => base64UrlEncode(Blob.valueOf(mime))
        });
        HttpResponse res = post('/gmail/v1/users/me/messages/send', payload);
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    public Map<String, Object> getProfile() {
        HttpResponse res = get('/gmail/v1/users/me/profile');
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    public Map<String, Object> listMessages(String query, Integer maxResults) {
        Integer capped = (maxResults == null || maxResults <= 0) ? 10 : maxResults;
        String path = '/gmail/v1/users/me/messages?maxResults=' + capped;
        if (String.isNotBlank(query)) {
            path += '&q=' + EncodingUtil.urlEncode(query, 'UTF-8');
        }
        HttpResponse res = get(path);
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    public Map<String, Object> getMessage(String messageId) {
        HttpResponse res = get('/gmail/v1/users/me/messages/' + EncodingUtil.urlEncode(messageId, 'UTF-8'));
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    // Gmail requires base64url (RFC 4648 §5) without padding for the raw MIME message
    private static String base64UrlEncode(Blob input) {
        return EncodingUtil.base64Encode(input)
            .replace('+', '-')
            .replace('/', '_')
            .replaceAll('=+$', '');
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
                'Gmail API returned HTTP ' + response.getStatusCode() +
                (String.isBlank(response.getBody()) ? '' : ': ' + response.getBody())
            );
        }
        return response;
    }

    private void setHeader(HttpRequest request, String name, String value) {
        request.setHeader(name, value);
    }
}