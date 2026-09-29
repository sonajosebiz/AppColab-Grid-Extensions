@IsTest
public class QuickBooksTestSupport {
    public class SingleResponseMock implements HttpCalloutMock {
        public Integer statusCode = 200;
        public String status = 'OK';
        public String body = '{}';
        public String lastEndpoint;
        public String lastMethod;
        public String lastBody;
        public Map<String, String> capturedHeaders = new Map<String, String>();
        public Integer callCount = 0;

        public HttpResponse respond(HttpRequest request) {
            callCount++;
            lastEndpoint = request.getEndpoint();
            lastMethod = request.getMethod();
            lastBody = request.getBody();
            for (String header : new List<String>{
                'Authorization', 'Content-Type', 'Accept', 'Prefer', 'xero-tenant-id'
            }) {
                String value = request.getHeader(header);
                if (value != null) capturedHeaders.put(header, value);
            }
            return makeResponse(statusCode, body, status);
        }
    }

    public class RoutingMock implements HttpCalloutMock {
        public Map<String, HttpResponse> byEndpointContains = new Map<String, HttpResponse>();
        public List<String> endpointLog = new List<String>();

        public HttpResponse respond(HttpRequest request) {
            endpointLog.add(request.getEndpoint());
            String bestMatch;
            for (String candidate : byEndpointContains.keySet()) {
                if (request.getEndpoint().contains(candidate) &&
                    (bestMatch == null || candidate.length() > bestMatch.length())) {
                    bestMatch = candidate;
                }
            }
            if (bestMatch == null) return makeResponse(404, '{"error":"No test route matched."}', 'Not Found');
            HttpResponse configured = byEndpointContains.get(bestMatch);
            if (EncodingUtil.urlDecode(request.getEndpoint(), 'UTF-8').toLowerCase().contains('select count(*)')) {
                Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(configured.getBody());
                Map<String, Object> qr = (Map<String, Object>) body.get('QueryResponse');
                Integer size = 0;
                if (qr != null) {
                    for (Object value : qr.values()) {
                        if (value instanceof List<Object>) size = ((List<Object>) value).size();
                    }
                }
                return makeResponse(200, '{"QueryResponse":{"totalCount":' + size + '}}');
            }
            return configured;
        }
    }

    public static HttpResponse makeResponse(Integer statusCode, String body) {
        return makeResponse(statusCode, body, 'Test');
    }

    private static HttpResponse makeResponse(Integer statusCode, String body, String status) {
        HttpResponse response = new HttpResponse();
        response.setStatusCode(statusCode);
        response.setStatus(status);
        response.setBody(body == null ? '' : body);
        return response;
    }
}
