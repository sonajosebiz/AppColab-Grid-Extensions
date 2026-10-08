public with sharing class OutlookClient {
    public class ClientException extends Exception {}
    public class HttpException extends Exception {}

    private static final String NAMED_CREDENTIAL = 'Outlook';
    private static final Set<Integer> RETRYABLE_STATUS_CODES = new Set<Integer>{ 408, 429, 500, 502, 503, 504 };

    public OutlookClient() {}

    public Map<String, Object> listMessages(Integer top, Integer skip, String filter, String search) {
        Integer pageSize = (top == null || top <= 0) ? 20 : Math.min(top, 50);
        List<String> queryParams = new List<String>();
        queryParams.add('$top=' + pageSize);
        if (skip != null && skip > 0) {
            queryParams.add('$skip=' + skip);
        }
        queryParams.add('$select=' + EncodingUtil.urlEncode('id,subject,from,toRecipients,receivedDateTime,bodyPreview,isRead,hasAttachments,webLink', 'UTF-8'));

        // Microsoft Graph does not permit $orderby when $search is used
        if (String.isNotBlank(search)) {
            queryParams.add('$search=' + EncodingUtil.urlEncode('"' + search + '"', 'UTF-8'));
        } else {
            queryParams.add('$orderby=' + EncodingUtil.urlEncode('receivedDateTime desc', 'UTF-8'));
        }

        if (String.isNotBlank(filter)) {
            queryParams.add('$filter=' + EncodingUtil.urlEncode(filter, 'UTF-8'));
        }

        String path = '/v1.0/me/messages?' + String.join(queryParams, '&');
        HttpResponse res = get(path);
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    public Map<String, Object> getMessage(String messageId) {
        HttpResponse res = get('/v1.0/me/messages/' + EncodingUtil.urlEncode(messageId, 'UTF-8'));
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    public Map<String, Object> listEvents(Integer top, Integer skip, String filter) {
        Integer pageSize = (top == null || top <= 0) ? 20 : Math.min(top, 50);
        List<String> queryParams = new List<String>();
        queryParams.add('$top=' + pageSize);
        if (skip != null && skip > 0) {
            queryParams.add('$skip=' + skip);
        }
        queryParams.add('$select=' + EncodingUtil.urlEncode('id,subject,start,end,organizer,attendees,location,isAllDay,webLink', 'UTF-8'));
        queryParams.add('$orderby=' + EncodingUtil.urlEncode('start/dateTime asc', 'UTF-8'));

        if (String.isNotBlank(filter)) {
            queryParams.add('$filter=' + EncodingUtil.urlEncode(filter, 'UTF-8'));
        }

        String path = '/v1.0/me/events?' + String.join(queryParams, '&');
        HttpResponse res = get(path);
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    public Map<String, Object> sendMail(String toAddress, String subject, String htmlContent) {
        Map<String, Object> emailAddress = new Map<String, Object>{ 'address' => toAddress };
        Map<String, Object> recipient = new Map<String, Object>{ 'emailAddress' => emailAddress };
        Map<String, Object> body = new Map<String, Object>{
            'contentType' => 'HTML',
            'content' => htmlContent
        };
        Map<String, Object> message = new Map<String, Object>{
            'subject' => subject,
            'body' => body,
            'toRecipients' => new List<Object>{ recipient }
        };
        Map<String, Object> payload = new Map<String, Object>{
            'message' => message,
            'saveToSentItems' => true
        };

        HttpResponse res = post('/v1.0/me/sendMail', JSON.serialize(payload));
        if (String.isNotBlank(res.getBody())) {
            return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        }
        return new Map<String, Object>{ 'status' => 'SENT' };
    }

    public Map<String, Object> getProfile() {
        HttpResponse res = get('/v1.0/me');
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    private HttpResponse get(String path) {
        return send(newRequest('GET', path, null));
    }

    private HttpResponse post(String path, String body) {
        return send(newRequest('POST', path, body));
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
                'Outlook API returned HTTP ' + response.getStatusCode() +
                (String.isBlank(response.getBody()) ? '' : ': ' + response.getBody())
            );
        }
        return response;
    }
}
