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
| Excel | `force-app/main/excel` | `ExcelGridDataProvider` | `Excel` |
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

### Microsoft Excel

Source: `force-app/main/excel`. The extension supports column discovery, search, refresh, add, edit, delete, CSV download, and filtering/auto-population by a Salesforce parent record. It uses the same self-contained client, provider, test support, modern credential metadata, and permission-set structure as the Salesforce and Stripe extensions.

Deploy or validate independently:

```sh
sf project deploy start --source-dir force-app/main/excel --target-org YOUR_ORG_ALIAS

sf project deploy start \
  --dry-run \
  --source-dir force-app/main/excel \
  --target-org YOUR_ORG_ALIAS \
  --test-level RunSpecifiedTests \
  --tests ExcelClientTest \
  --tests ExcelGridDataProviderTest \
  --wait 30
```

After deployment:

1. Register a web application in Microsoft Entra ID with delegated Microsoft Graph `Files.ReadWrite` permission. Use a work or school account with access to an `.xlsx` workbook in OneDrive for Business. The provider uses `/me/drive`; personal Microsoft accounts and application-only authentication are unsupported by the [used-range API](https://learn.microsoft.com/en-us/graph/api/worksheet-usedrange?view=graph-rest-1.0).
2. In Salesforce's `Excel_Microsoft_OAuth` Auth Provider, replace the placeholder Consumer Key and Consumer Secret with the application's client ID and secret. Register the Salesforce OAuth Callback URL as a Web redirect URI in Entra ID. The supplied scopes include `openid profile email offline_access https://graph.microsoft.com/Files.ReadWrite`. For a single-tenant application, replace `organizations` in both OAuth endpoint URLs with your tenant ID.
3. Authenticate the `Excel_User` named principal in the `Excel_Graph` External Credential. The `Excel` Named Credential points to `https://graph.microsoft.com` and uses this dedicated credential; it does not depend on the sample repo's Outlook credential or integration custom metadata.
4. Assign `Excel_Integration` to grid users and select `ExcelGridDataProvider` as the grid's data provider.

Configure by OneDrive item ID:

```json
{"workbookId":"YOUR_DRIVE_ITEM_ID","sheetName":"Sheet1","headerRow":1}
```

Or use an unencoded file path relative to the authenticated user's OneDrive root:

```json
{"filePath":"/Documents/Sales.xlsx","sheetName":"Sales","headerRow":3}
```

`sheetName` defaults to `Sheet1`; `headerRow` defaults to worksheet row 1 and is an absolute, one-based worksheet row number. The provider respects the used range's row and column offsets. Blank headers receive `ColumnN` names, duplicate names receive numeric suffixes, and an Excel header named `Id` becomes `Id_2` to preserve the grid's row identifier. Completely blank data rows are skipped. Initialize the header row before adding data to an empty worksheet.

To show rows related to a Salesforce record and populate the match column on new rows:

```json
{"workbookId":"YOUR_DRIVE_ITEM_ID","sheetName":"Sheet1","parentMatchColumn":"ContactEmail","parentMatchField":"Email","autoPopulateParent":true}
```

`parentMatchField` defaults to `Id`; ID matching accepts Salesforce's 15- and 18-character forms. Other values are trimmed and matched exactly. A blank parent field shows no rows and prevents automatic population. The parent field is queried in user mode. When automatic population is enabled on a record page, the match column is read-only.

The extension advertises client-side pagination. It reads the worksheet's used range and applies parent filtering and search before the grid's record limit; the default limit is 1,000 and the maximum is 50,000. Large worksheets still incur the full Graph response and Apex heap cost. Partial edits preserve omitted cells, including formulas, using [Graph's null-cell semantics](https://learn.microsoft.com/en-us/graph/api/range-update?view=graph-rest-1.0). Adds are written in one contiguous range. Deletes shift cells upward within the grid's column range, bottom-up, and ignore duplicate row IDs. Read and range-update callouts retry once on transient failures; range deletion is never replayed automatically because it shifts rows.

Grid IDs are worksheet row numbers. Refresh after deletion or outside edits that move rows. Multiple writes are not transactional; if a later callout fails, earlier workbook changes remain. Deployment tests mock Graph responses; testing live workbook access requires completing OAuth setup.

### Stripe grids on a Salesforce record

Set `parentMatchColumn` to the Stripe column and `parentMatchField` to a field on the Salesforce record containing the match value. When the grid is on a Contact, these configurations show that Contact's payments:

```json
{"resource":"charges","parentMatchColumn":"customer","parentMatchField":"Stripe_Customer_Id__c"}
```

```json
{"resource":"charges","parentMatchColumn":"customer_email","parentMatchField":"Email"}
```

`charges.customer_email` uses the charge's billing email, falling back to its receipt email. For `payment_intents`, use `customer` for the Stripe customer ID or `receipt_email` for email matching. Invoices expose `customer` and `customer_email`. A record with an empty match field shows no rows. If `parentMatchField` is omitted, it defaults to the Salesforce record ID. Email matches ignore case; Stripe IDs match exactly. The Stripe record limit applies after matching. Customer ID matches use Stripe's customer filter; email matches scan Stripe pages and can reach Salesforce's callout limit on large accounts.

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
