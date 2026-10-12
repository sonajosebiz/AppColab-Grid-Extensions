# Trello Extension

[Back to AppColab Grid Extensions](../../../README.md)

Display, search, create, edit, delete, and export cards from a Trello board in Salesforce.

## Setup guide

Follow the [Trello setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/trello-grid-integration) on appcolab.com for credential setup and Grid Definition configuration.

## Components

| Component | API name |
| --- | --- |
| Apex client | `TrelloClient` |
| Data provider | `TrelloGridDataProvider` |
| Named Credential | `Trello` |
| External Credential | `Trello` |
| Named principal | `ApiKey` |
| Permission set | `Trello_Integration` |

## Deploy and configure

1. Install [AppColab Grid](https://appexchange.salesforce.com/appxListingDetail?listingId=ed83d466-8f44-4f31-9261-b6fa9390119e) in the target Salesforce org.
2. From the repository root, deploy this extension:

```sh
sf project deploy start \
  --source-dir force-app/main/trello \
  --target-org YOUR_ORG_ALIAS
```

Replace the placeholder authentication headers in the External Credential with the token or API key described in the setup guide.

Assign the `Trello_Integration` permission set to users who need the extension. It grants access to the client, provider, and `Trello` → `ApiKey` External Credential principal. Use this permission set when the website guide refers to a shared integration permission set.

## Grid Definition

In the AppColab Grid app, create an active Grid Definition. Set **Data Provider Class** to `TrelloGridDataProvider` and **Data Provider Configuration** to:

```json
{
  "boardId": "YOUR_BOARD_ID"
}
```

Replace the placeholder IDs and names with values from your external system, then save and preview the grid.

Use the Trello board ID for `boardId`. The provider resolves board lists to display list names alongside card details.

## Validate deployment

From the repository root, validate this extension and run its Apex tests against an org with AppColab Grid installed:

```sh
sf project deploy start \
  --dry-run \
  --source-dir force-app/main/trello \
  --target-org YOUR_ORG_ALIAS \
  --test-level RunSpecifiedTests \
  --tests TrelloClientTest \
  --tests TrelloGridDataProviderTest \
  --wait 30
```
