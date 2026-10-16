public with sharing class GitHubClient {
    public class ClientException extends Exception {}
    public class HttpException extends Exception {}

    private static final String NAMED_CREDENTIAL = 'GitHub';
    private static final Set<Integer> RETRYABLE_STATUS_CODES = new Set<Integer>{ 408, 429, 500, 502, 503, 504 };

    public GitHubClient() {}

    /**
     * List issues for a repository.
     * GET /repos/{owner}/{repo}/issues
     */
    public List<Object> listIssues(
        String owner,
        String repo,
        String state,
        Integer page,
        Integer perPage
    ) {
        validateOwnerRepo(owner, repo);
        String path = '/repos/' + enc(owner) + '/' + enc(repo) + '/issues';
        List<String> queryParams = new List<String>();
        if (String.isNotBlank(state)) {
            queryParams.add('state=' + enc(state));
        } else {
            queryParams.add('state=all');
        }
        if (page != null && page > 0) {
            queryParams.add('page=' + page);
        }
        if (perPage != null && perPage > 0) {
            queryParams.add('per_page=' + Math.min(perPage, 100));
        }
        if (!queryParams.isEmpty()) {
            path += '?' + String.join(queryParams, '&');
        }

        HttpResponse res = get(path);
        return (List<Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Get a specific issue by number.
     * GET /repos/{owner}/{repo}/issues/{issue_number}
     */
    public Map<String, Object> getIssue(String owner, String repo, Integer issueNumber) {
        validateOwnerRepo(owner, repo);
        if (issueNumber == null || issueNumber <= 0) {
            throw new ClientException('issueNumber is required');
        }
        String path = '/repos/' + enc(owner) + '/' + enc(repo) + '/issues/' + issueNumber;
        HttpResponse res = get(path);
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Create an issue in a repository.
     * POST /repos/{owner}/{repo}/issues
     */
    public Map<String, Object> createIssue(String owner, String repo, Map<String, Object> payload) {
        validateOwnerRepo(owner, repo);
        if (payload == null || !payload.containsKey('title') || String.isBlank(String.valueOf(payload.get('title')))) {
            throw new ClientException('Issue title is required');
        }
        String path = '/repos/' + enc(owner) + '/' + enc(repo) + '/issues';
        HttpResponse res = post(path, JSON.serialize(payload));
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Update an issue by number.
     * PATCH /repos/{owner}/{repo}/issues/{issue_number}
     */
    public Map<String, Object> updateIssue(String owner, String repo, Integer issueNumber, Map<String, Object> payload) {
        validateOwnerRepo(owner, repo);
        if (issueNumber == null || issueNumber <= 0) {
            throw new ClientException('issueNumber is required');
        }
        String path = '/repos/' + enc(owner) + '/' + enc(repo) + '/issues/' + issueNumber;
        HttpResponse res = patch(path, JSON.serialize(payload));
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    // "?"?"? Internal HTTP Helpers "?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?

    private static void validateOwnerRepo(String owner, String repo) {
        if (String.isBlank(owner)) {
            throw new ClientException('Repository owner is required');
        }
        if (String.isBlank(repo)) {
            throw new ClientException('Repository name is required');
        }
    }

    private static String enc(String value) {
        if (String.isBlank(value)) return '';
        return EncodingUtil.urlEncode(value, 'UTF-8').replace('+', '%20');
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

        if (String.isBlank(request.getHeader('Accept'))) {
            request.setHeader('Accept', 'application/vnd.github+json');
        }
        if (String.isBlank(request.getHeader('X-GitHub-Api-Version'))) {
            request.setHeader('X-GitHub-Api-Version', '2022-11-28');
        }
        if (String.isBlank(request.getHeader('User-Agent'))) {
            request.setHeader('User-Agent', 'AppColab-Grid');
        }
        if (String.isBlank(request.getHeader('Content-Type')) && request.getMethod() != 'GET' && request.getMethod() != 'DELETE') {
            request.setHeader('Content-Type', 'application/json');
        }

        HttpResponse response;
        Integer attempts = 0;
        while (attempts < 3) {
            attempts++;
            response = new Http().send(request);
            if (!RETRYABLE_STATUS_CODES.contains(response.getStatusCode()) || attempts >= 3) {
                break;
            }
        }

        if (response.getStatusCode() >= 400) {
            throw new HttpException(
                'GitHub API call failed [' + response.getStatusCode() + ' ' + response.getStatus() + ']: ' + response.getBody()
            );
        }
        return response;
    }
}