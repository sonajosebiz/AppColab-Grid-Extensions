# Asana Extension

[Back to AppColab Grid Extensions](../../../README.md)

Display and manage Asana tasks in Salesforce, with search, pagination, inline updates, and CSV export.

## Setup guide

Follow the [Asana setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/asana-grid-integration) on appcolab.com for credential setup and Grid Definition configuration.

## Components

| Component | API name |
| --- | --- |
| Apex client | `AsanaClient` |
| Data provider | `AsanaGridDataProvider` |
| Named Credential | `Asana` |
| External Credential | `Asana` |
| Named principal | `ApiKey` |
| Permission set | `Asana_Integration` |

## Deploy and configure

1. Install [AppColab Grid](https://appexchange.salesforce.com/appxListingDetail?listingId=ed83d466-8f44-4f31-9261-b6fa9390119e) in the target Salesforce org.
2. From the repository root, deploy this extension:

```sh
sf project deploy start \
  --source-dir force-app/main/asana \
  --target-org YOUR_ORG_ALIAS
```

Replace the placeholder authentication headers in the External Credential with the token or API key described in the setup guide.

Assign the `Asana_Integration` permission set to users who need the extension. It grants access to the client, provider, and `Asana` → `ApiKey` External Credential principal. Use this permission set when the website guide refers to a shared integration permission set.

## Grid Definition

In the AppColab Grid app, create an active Grid Definition. Set **Data Provider Class** to `AsanaGridDataProvider` and **Data Provider Configuration** to:

```json
{
  "projectId": "YOUR_PROJECT_ID"
}
```

Replace the placeholder IDs and names with values from your external system, then save and preview the grid.

Tasks are the default resource. Use `projectId`, `sectionId`, or `userTaskListId` to select a task list. To display projects, set `resource` to `projects` and supply `workspaceId`.

## Validate deployment

From the repository root, validate this extension and run its Apex tests against an org with AppColab Grid installed:

```sh
sf project deploy start \
  --dry-run \
  --source-dir force-app/main/asana \
  --target-org YOUR_ORG_ALIAS \
  --test-level RunSpecifiedTests \
  --tests AsanaClientTest \
  --tests AsanaGridDataProviderTest \
  --wait 30
```
