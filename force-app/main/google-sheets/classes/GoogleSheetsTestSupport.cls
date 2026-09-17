@IsTest
public class GoogleSheetsTestSupport {
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
            for (String header : new List<String>{ 'Accept', 'Content-Type' }) {
                String value = request.getHeader(header);
                if (value != null) {
                    capturedHeaders.put(header, value);
                }
            }
            return makeResponse(statusCode, body, status);
        }
    }

    public class SequenceMock implements HttpCalloutMock {
        public List<Integer> statusCodes = new List<Integer>();
        public String body = '{}';
        public Integer callCount = 0;

        public HttpResponse respond(HttpRequest request) {
            Integer index = Math.min(callCount, statusCodes.size() - 1);
            Integer statusCode = statusCodes[index];
            callCount++;
            return makeResponse(statusCode, body, 'Test');
        }
    }

    public class RoutingMock implements HttpCalloutMock {
        public Map<String, HttpResponse> byEndpointContains = new Map<String, HttpResponse>();
        public List<String> endpointLog = new List<String>();

        public HttpResponse respond(HttpRequest request) {
            endpointLog.add(request.getEndpoint());
            String bestMatch;
            for (String candidate : byEndpointContains.keySet()) {
                if (
                    request.getEndpoint().contains(candidate) &&
                    (bestMatch == null || candidate.length() > bestMatch.length())
                ) {
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
}
