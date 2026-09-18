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

## Other integrations

Every integration is self-contained and can be deployed independently. Its client owns Named Credential callouts, JSON or form headers, a 60-second timeout, transient-error retry, and HTTP error handling. No integration depends on the unpackaged `APIClient`, integration custom metadata, logging classes, or test utilities from another repository.

| Integration | Source folder | Data provider | Named Credential |
| --- | --- | --- | --- |
| Airtable | `force-app/main/airtable` | `AirtableGridDataProvider` | `Airtable` |
| Asana | `force-app/main/asana` | `AsanaGridDataProvider` | `Asana` |
| Gmail | `force-app/main/gmail` | `GmailGridDataProvider` | `Gmail` |
| Google Analytics | `force-app/main/google-analytics` | `GoogleAnalyticsGridDataProvider` | `Google_Analytics` |
| HubSpot | `force-app/main/hubspot` | `HubSpotGridDataProvider` | `HubSpot` |
| QuickBooks | `force-app/main/quickbooks` | `QuickBooksGridDataProvider` | `QuickBooks` |
| Salesforce cross-org | `force-app/main/salesforce` | `SalesforceGridDataProvider` | `Salesforce_Org` |
| Shopify | `force-app/main/shopify` | `ShopifyGridDataProvider` | `Shopify` |
| Stripe | `force-app/main/stripe` | `StripeGridDataProvider` | `Stripe` |
| Supabase | `force-app/main/supabase` | `SupabaseGridDataProvider` | `Supabase` |
| Trello | `force-app/main/trello` | `TrelloGridDataProvider` | `Trello` |
| Xero | `force-app/main/xero` | `XeroGridDataProvider` | `Xero` |

Deploy one integration by passing its source folder:

```sh
sf project deploy start \
  --source-dir force-app/main/airtable \
  --target-org YOUR_ORG_ALIAS
```

Run all test-only deployment validations:

```sh
./scripts/validate-integrations.sh YOUR_ORG_ALIAS
```

Credential metadata contains placeholders only. After deployment, configure the integration's External Credential or Auth Provider, authenticate its named principal where OAuth is used, and assign the integration-specific permission set to users.
