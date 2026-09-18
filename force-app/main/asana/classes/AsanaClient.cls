public with sharing class AsanaClient {
    public class ClientException extends Exception {
    }
    public class HttpException extends Exception {
    }

    private static final String NAMED_CREDENTIAL = 'Asana';
    private static final Set<Integer> RETRYABLE_STATUS_CODES = new Set<Integer>{ 408, 429, 500, 502, 503, 504 };


    private static final String TASK_OPT_FIELDS =
        'gid,name,completed,due_on,due_at,assignee.name,assignee.email,notes,created_at,modified_at,permalink_url,memberships.section.name,tags.name';

    public AsanaClient() {
    }

    /**
     * Fetch tasks from a specific Asana project.
     * GET /api/1.0/projects/{projectGid}/tasks
     */
    public Map<String, Object> getProjectTasks(String projectGid, Integer limitCount, String offsetToken) {
        validateGid('projectGid', projectGid);
        String path = '/api/1.0/projects/' + enc(projectGid) + '/tasks?opt_fields=' + TASK_OPT_FIELDS;
        path = appendPaginationParams(path, limitCount, offsetToken);
        HttpResponse res = get(path);
        return deserialize(res);
    }

    /**
     * Fetch tasks from a specific section within a project.
     * GET /api/1.0/sections/{sectionGid}/tasks
     */
    public Map<String, Object> getSectionTasks(String sectionGid, Integer limitCount, String offsetToken) {
        validateGid('sectionGid', sectionGid);
        String path = '/api/1.0/sections/' + enc(sectionGid) + '/tasks?opt_fields=' + TASK_OPT_FIELDS;
        path = appendPaginationParams(path, limitCount, offsetToken);
        HttpResponse res = get(path);
        return deserialize(res);
    }

    /**
     * Fetch tasks from a user's task list (My Tasks).
     * GET /api/1.0/user_task_lists/{userTaskListGid}/tasks
     */
    public Map<String, Object> getUserTasks(String userTaskListGid, Integer limitCount, String offsetToken) {
        validateGid('userTaskListGid', userTaskListGid);
        String path = '/api/1.0/user_task_lists/' + enc(userTaskListGid) + '/tasks?opt_fields=' + TASK_OPT_FIELDS;
        path = appendPaginationParams(path, limitCount, offsetToken);
        HttpResponse res = get(path);
        return deserialize(res);
    }

    /**
     * Fetch sections in a project (columns on a board).
     * GET /api/1.0/projects/{projectGid}/sections
     */
    public Map<String, Object> getProjectSections(String projectGid) {
        validateGid('projectGid', projectGid);
        String path = '/api/1.0/projects/' + enc(projectGid) + '/sections?opt_fields=gid,name';
        HttpResponse res = get(path);
        return deserialize(res);
    }

    /**
     * Fetch all projects in a workspace.
     * GET /api/1.0/workspaces/{workspaceGid}/projects
     */
    public Map<String, Object> getProjects(String workspaceGid) {
        validateGid('workspaceGid', workspaceGid);
        String path = '/api/1.0/workspaces/' + enc(workspaceGid) +
            '/projects?opt_fields=gid,name,color,created_at,archived,permalink_url';
        HttpResponse res = get(path);
        return deserialize(res);
    }

    /**
     * Fetch all workspaces accessible to the authenticated user.
     * GET /api/1.0/workspaces
     */
    public Map<String, Object> getWorkspaces() {
        String path = '/api/1.0/workspaces?opt_fields=gid,name';
        HttpResponse res = get(path);
        return deserialize(res);
    }

    /**
     * Fetch full details for a single task.
     * GET /api/1.0/tasks/{taskGid}
     */
    public Map<String, Object> getTask(String taskGid) {
        validateGid('taskGid', taskGid);
        String path = '/api/1.0/tasks/' + enc(taskGid) + '?opt_fields=' + TASK_OPT_FIELDS;
        HttpResponse res = get(path);
        return deserialize(res);
    }

    /**
     * Create a new task in Asana.
     * POST /api/1.0/tasks
     */
    public Map<String, Object> createTask(Map<String, Object> data) {
        String path = '/api/1.0/tasks';
        String body = JSON.serialize(new Map<String, Object>{ 'data' => data });
        HttpResponse res = post(path, body);
        return deserialize(res);
    }

    /**
     * Update an existing task in Asana.
     * PUT /api/1.0/tasks/{taskGid}
     */
    public Map<String, Object> updateTask(String taskGid, Map<String, Object> data) {
        validateGid('taskGid', taskGid);
        String path = '/api/1.0/tasks/' + enc(taskGid);
        String body = JSON.serialize(new Map<String, Object>{ 'data' => data });
        HttpResponse res = put(path, body);
        return deserialize(res);
    }

    /**
     * Delete a task from Asana.
     * DELETE /api/1.0/tasks/{taskGid}
     */
    public Map<String, Object> deleteTask(String taskGid) {
        validateGid('taskGid', taskGid);
        String path = '/api/1.0/tasks/' + enc(taskGid);
        HttpResponse res = del(path);
        return deserialize(res);
    }

    // ─── Helpers ──────────────────────────────────────────────────────

    private static String appendPaginationParams(String path, Integer limitCount, String offsetToken) {
        if (limitCount != null && limitCount > 0) {
            path += '&limit=' + Math.min(limitCount, 100);
        }
        if (String.isNotBlank(offsetToken)) {
            path += '&offset=' + enc(offsetToken);
        }
        return path;
    }

    private static Map<String, Object> deserialize(HttpResponse res) {
        String body = res.getBody();
        if (String.isBlank(body)) {
            return new Map<String, Object>();
        }
        return (Map<String, Object>) JSON.deserializeUntyped(body);
    }

    private static void validateGid(String paramName, String gid) {
        if (String.isBlank(gid)) {
            throw new ClientException(paramName + ' is required.');
        }
    }

    private static String enc(String value) {
        return value == null ? '' : EncodingUtil.urlEncode(value, 'UTF-8');
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
                'Asana API returned HTTP ' + response.getStatusCode() +
                (String.isBlank(response.getBody()) ? '' : ': ' + response.getBody())
            );
        }
        return response;
    }

    private void setHeader(HttpRequest request, String name, String value) {
        request.setHeader(name, value);
    }
}
