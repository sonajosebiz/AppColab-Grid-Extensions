# Airtable Extension

[Back to AppColab Grid Extensions](../../../README.md)

View, search, create, edit, delete, and export records from an Airtable base and table.

## Setup guide

Follow the [Airtable setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/airtable-grid-integration) on appcolab.com for credential setup and Grid Definition configuration.

## Components

| Component | API name |
| --- | --- |
| Apex client | `AirtableClient` |
| Data provider | `AirtableGridDataProvider` |
| Named Credential | `Airtable` |
| External Credential | `Airtable` |
| Named principal | `ApiKey` |
| Permission set | `Airtable_Integration` |

## Deploy and configure

1. Install [AppColab Grid](https://appexchange.salesforce.com/appxListingDetail?listingId=ed83d466-8f44-4f31-9261-b6fa9390119e) in the target Salesforce org.
2. From the repository root, deploy this extension:

```sh
sf project deploy start \
  --source-dir force-app/main/airtable \
  --target-org YOUR_ORG_ALIAS
```

Replace the placeholder authentication headers in the External Credential with the token or API key described in the setup guide.

Assign the `Airtable_Integration` permission set to users who need the extension. It grants access to the client, provider, and `Airtable` → `ApiKey` External Credential principal. Use this permission set when the website guide refers to a shared integration permission set.

## Grid Definition

In the AppColab Grid app, create an active Grid Definition. Set **Data Provider Class** to `AirtableGridDataProvider` and **Data Provider Configuration** to:

```json
{
  "baseId": "YOUR_BASE_ID",
  "tableIdOrName": "YOUR_TABLE_ID_OR_NAME"
}
```

Replace the placeholder IDs and names with values from your external system, then save and preview the grid.

Computed and other non-writable Airtable field types remain read only.

## Validate deployment

From the repository root, validate this extension and run its Apex tests against an org with AppColab Grid installed:

```sh
sf project deploy start \
  --dry-run \
  --source-dir force-app/main/airtable \
  --target-org YOUR_ORG_ALIAS \
  --test-level RunSpecifiedTests \
  --tests AirtableClientTest \
  --tests AirtableGridDataProviderTest \
  --wait 30
```
