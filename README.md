# AppColab Grid Extensions

Classes to extend your AppColab Grid to display data from external systems.

## Prerequisite

Install [AppColab Grid](https://appexchange.salesforce.com/appxListingDetail?listingId=ed83d466-8f44-4f31-9261-b6fa9390119e) in the target org. The extension classes work with the classes and objects available in the package.

## Google Sheets

Source: `force-app/main/google-sheets`

The extension allows you to integract with data in Google Sheet from your grids in Salesforce. 

It supports discovery of google sheet columns, search, add, edit, delete, CSV download, and optional filtering/auto-population by a Salesforce parent record. It expects `Google_Sheets` Named Credential.

Deploy the integration:

```sh
sf project deploy start \
  --source-dir force-app/main/google-sheets \
  --target-org YOUR_ORG_ALIAS
```

Validate with its tests:

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

For additional instructions to configure the extension follow the documentation in [AppColab Grid Guide](https://appcolab.com/guide/appcolab-grid/external-connections/google-sheets-grid-integration)
