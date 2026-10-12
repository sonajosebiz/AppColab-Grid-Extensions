# Google Sheets Extension

[Back to AppColab Grid Extensions](../../../README.md)

View, search, add, edit, delete, and export Google Sheets rows in Salesforce, with column discovery and optional filtering and auto-population by a Salesforce parent record.

## Setup guide

Follow the [Google Sheets setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/google-sheets-grid-integration) on appcolab.com for credential setup and Grid Definition configuration.

## Components

| Component | API name |
| --- | --- |
| Apex client | `GoogleSheetsClient` |
| Data provider | `GoogleSheetsGridDataProvider` |
| Named Credential | `Google_Sheets` |
| External Credential | `Google_APIs` |
| Named principal | `Google_User` |
| Permission set | `Google_Sheets_Integration` |
| Auth Provider | `Google_OAuth` |

## Deploy and configure

1. Install [AppColab Grid](https://appexchange.salesforce.com/appxListingDetail?listingId=ed83d466-8f44-4f31-9261-b6fa9390119e) in the target Salesforce org.
2. From the repository root, deploy this extension:

```sh
sf project deploy start \
  --source-dir force-app/main/google-sheets \
  --target-org YOUR_ORG_ALIAS
```

Configure `Google_OAuth` with your application client ID, client secret, callback URL, and required scopes, then authenticate `Google_APIs` → `Google_User` as described in the setup guide.

Assign the `Google_Sheets_Integration` permission set to users who need the extension. It grants access to the client, provider, and `Google_APIs` → `Google_User` External Credential principal. Use this permission set when the website guide refers to a shared integration permission set.

## Grid Definition

In the AppColab Grid app, create an active Grid Definition. Set **Data Provider Class** to `GoogleSheetsGridDataProvider` and **Data Provider Configuration** to:

```json
{
  "spreadsheetId": "YOUR_SPREADSHEET_ID",
  "sheetName": "Sheet1",
  "headerRow": 1
}
```

Replace the placeholder IDs and names with values from your external system, then save and preview the grid.

For a grid on a Salesforce record, add `parentMatchColumn` with the sheet header to match and `parentMatchField` with the Salesforce field holding that value (defaults to `Id`). Set `autoPopulateParent` to `true` to fill that sheet column when adding rows.

## Validate deployment

From the repository root, validate this extension and run its Apex tests against an org with AppColab Grid installed:

```sh
sf project deploy start \
  --dry-run \
  --source-dir force-app/main/google-sheets \
  --target-org YOUR_ORG_ALIAS \
  --test-level RunSpecifiedTests \
  --tests GoogleSheetsClientTest \
  --tests GoogleSheetsGridDataProviderTest \
  --wait 30
```
