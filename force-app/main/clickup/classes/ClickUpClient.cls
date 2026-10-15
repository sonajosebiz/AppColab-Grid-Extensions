public with sharing class ClickUpClient {
    public class ClientException extends Exception {}
    public class HttpException extends Exception {}

    private static final String NAMED_CREDENTIAL = 'ClickUp';
    private static final Set<Integer> RETRYABLE_STATUS_CODES = new Set<Integer>{ 408, 429, 500, 502, 503, 504 };

    public ClickUpClient() {}

    /**
     * Retrieve list metadata, including available statuses.
     * GET /api/v2/list/{list_id}
     */
    public Map<String, Object> getList(String listId) {
        if (String.isBlank(listId)) {
            throw new ClientException('listId is required');
        }
        String path = '/api/v2/list/' + enc(listId);
        HttpResponse res = get(path);
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Retrieve tasks in a list.
     * GET /api/v2/list/{list_id}/task
     */
    public Map<String, Object> getTasks(
        String listId,
        Integer page,
        Boolean includeSubtasks,
        Boolean includeClosed
    ) {
        if (String.isBlank(listId)) {
            throw new ClientException('listId is required');
        }
        String path = '/api/v2/list/' + enc(listId) + '/task';
        List<String> queryParams = new List<String>();
        if (page != null && page >= 0) {
            queryParams.add('page=' + page);
        }
        if (includeSubtasks == true) {
            queryParams.add('subtasks=true');
        }
        if (includeClosed != null) {
            queryParams.add('include_closed=' + (includeClosed ? 'true' : 'false'));
        }
        if (!queryParams.isEmpty()) {
            path += '?' + String.join(queryParams, '&');
        }
        HttpResponse res = get(path);
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Retrieve a specific task by ID.
     * GET /api/v2/task/{task_id}
     */
    public Map<String, Object> getTask(String taskId) {
        if (String.isBlank(taskId)) {
            throw new ClientException('taskId is required');
        }
        String path = '/api/v2/task/' + enc(taskId);
        HttpResponse res = get(path);
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Create a task in a list.
     * POST /api/v2/list/{list_id}/task
     */
    public Map<String, Object> createTask(String listId, Map<String, Object> taskPayload) {
        if (String.isBlank(listId)) {
            throw new ClientException('listId is required');
        }
        String path = '/api/v2/list/' + enc(listId) + '/task';
        HttpResponse res = post(path, JSON.serialize(taskPayload));
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Update an existing task by ID.
     * PUT /api/v2/task/{task_id}
     */
    public Map<String, Object> updateTask(String taskId, Map<String, Object> taskPayload) {
        if (String.isBlank(taskId)) {
            throw new ClientException('taskId is required');
        }
        String path = '/api/v2/task/' + enc(taskId);
        HttpResponse res = put(path, JSON.serialize(taskPayload));
        return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    }

    /**
     * Delete a task by ID.
     * DELETE /api/v2/task/{task_id}
     */
    public void deleteTask(String taskId) {
        if (String.isBlank(taskId)) {
            throw new ClientException('taskId is required');
        }
        String path = '/api/v2/task/' + enc(taskId);
        del(path);
    }

    // "?"?"? Internal HTTP Helpers "?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?"?

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

    private HttpResponse put(String path, String body) {
        return send(newRequest('PUT', path, body));
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
        if (String.isBlank(request.getHeader('Content-Type')) && request.getMethod() != 'GET' && request.getMethod() != 'DELETE') {
            request.setHeader('Content-Type', 'application/json');
        }
        if (String.isBlank(request.getHeader('Accept'))) {
            request.setHeader('Accept', 'application/json');
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
                'ClickUp API call failed [' + response.getStatusCode() + ' ' + response.getStatus() + ']: ' + response.getBody()
            );
        }
        return response;
    }
}