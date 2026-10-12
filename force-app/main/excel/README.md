# Microsoft Excel Extension

[Back to AppColab Grid Extensions](../../../README.md)

View, search, add, edit, delete, and export worksheet rows from a OneDrive workbook through Microsoft Graph.

## Setup guide

Follow the [General external-data setup guide](https://appcolab.com/guide/appcolab-grid/user-guide/displaying-data-from-external-systems) on appcolab.com for credential setup and Grid Definition configuration.

The website source currently has no dedicated Microsoft Excel integration guide. The linked guide explains the shared AppColab Grid setup flow; use the extension-specific credential and configuration details below.

## Components

| Component | API name |
| --- | --- |
| Apex client | `ExcelClient` |
| Data provider | `ExcelGridDataProvider` |
| Named Credential | `Excel` |
| External Credential | `Excel` |
| Named principal | `ApiKey` |
| Permission set | `Excel_Integration` |
| Auth Provider | `Microsoft_OAuth` |

## Deploy and configure

1. Install [AppColab Grid](https://appexchange.salesforce.com/appxListingDetail?listingId=ed83d466-8f44-4f31-9261-b6fa9390119e) in the target Salesforce org.
2. From the repository root, deploy this extension:

```sh
sf project deploy start \
  --source-dir force-app/main/excel \
  --target-org YOUR_ORG_ALIAS
```

Configure `Microsoft_OAuth` with your Microsoft application client ID and secret and register its Salesforce callback URL with the application. The deployed Auth Provider uses these scopes:

```text
offline_access openid profile email https://graph.microsoft.com/Files.ReadWrite
```

Authenticate `Excel` → `ApiKey` with the Microsoft account whose data the grid should access. Both Excel and Outlook include `Microsoft_OAuth`; if deploying both, configure that shared provider with the scopes needed by both extensions.

Assign the `Excel_Integration` permission set to users who need the extension. It grants access to the client, provider, and `Excel` → `ApiKey` External Credential principal. Use this permission set when the website guide refers to a shared integration permission set.

## Grid Definition

In the AppColab Grid app, create an active Grid Definition. Set **Data Provider Class** to `ExcelGridDataProvider` and **Data Provider Configuration** to:

```json
{
  "workbookId": "YOUR_ONEDRIVE_ITEM_ID",
  "sheetName": "Sheet1",
  "headerRow": 1
}
```

Replace the placeholder IDs and names with values from your external system, then save and preview the grid.

You can use `filePath` instead of `workbookId`, for example `{"filePath":"/Documents/Sales.xlsx","sheetName":"Sheet1"}`. The provider defaults to `Sheet1` and header row 1. Optional `parentMatchColumn`, `parentMatchField`, and `autoPopulateParent` support grids on Salesforce records.

## Validate deployment

From the repository root, validate this extension and run its Apex tests against an org with AppColab Grid installed:

```sh
sf project deploy start \
  --dry-run \
  --source-dir force-app/main/excel \
  --target-org YOUR_ORG_ALIAS \
  --test-level RunSpecifiedTests \
  --tests ExcelClientTest \
  --tests ExcelGridDataProviderTest \
  --wait 30
```
