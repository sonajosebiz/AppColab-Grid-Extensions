@IsTest
public class ExcelTestSupport {
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
            return bestMatch == null
                ? makeResponse(404, '{"error":"No test route matched."}', 'Not Found')
                : byEndpointContains.get(bestMatch);
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
    public class RecordingMock implements HttpCalloutMock {
        public String usedRangeBody;
        public List<HttpRequest> requests = new List<HttpRequest>();
        public Integer failWriteStatus;

        public RecordingMock(String body) {
            usedRangeBody = body;
        }

        public HttpResponse respond(HttpRequest request) {
            requests.add(request);
            System.assert(request.getEndpoint().startsWith('callout:Excel/'), request.getEndpoint());
            System.assertEquals('application/json', request.getHeader('Accept'));
            if (request.getMethod() == 'GET') return makeResponse(200, usedRangeBody);
            System.assertEquals('application/json', request.getHeader('Content-Type'));
            if (failWriteStatus != null) return makeResponse(failWriteStatus, '{"error":"write failed"}');
            return request.getMethod() == 'POST' ? makeResponse(204, '') : makeResponse(200, '{}');
        }
    }

    public class RetryMock implements HttpCalloutMock {
        public Integer callCount = 0;
        public Boolean throwCallout = false;
        public HttpResponse respond(HttpRequest request) {
            callCount++;
            if (throwCallout) throw new CalloutException('Simulated timeout');
            return callCount == 1 ? makeResponse(503, '{"error":"unavailable"}') : makeResponse(200, '{}');
        }
    }
}
