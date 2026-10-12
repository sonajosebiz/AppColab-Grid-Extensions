# AppColab Grid Extensions

Classes to extend your AppColab Grid to display data from external systems.

## Prerequisite

Install [AppColab Grid](https://appexchange.salesforce.com/appxListingDetail?listingId=ed83d466-8f44-4f31-9261-b6fa9390119e) in the target org. The extension classes work with the classes and objects available in the package.

## Google Sheets

Source: `force-app/main/google-sheets` · [Extension README](force-app/main/google-sheets/README.md)

The extension allows you to interact with data in Google Sheets from your grids in Salesforce.

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

## QuickBooks

Set the grid's Data Provider Configuration to the QuickBooks company ID and entity. The provider supports invoices, customers, payments, items, bills, vendors, estimates, sales receipts, credit memos, purchase orders, accounts, deposits, journal entries, and purchases. Singular and plural resource names are accepted.

```json
{"realmId":"YOUR_COMPANY_ID","resource":"invoices","parentMatchColumn":"CustomerRef","parentMatchField":"QuickBooks_Customer_Id__c"}
```

`parentMatchColumn` is a filterable QuickBooks field. When the grid opens on a Salesforce record, the provider reads `parentMatchField` from that record and adds an equality predicate to both the count and page queries. If `parentMatchField` is omitted, the Salesforce record ID is used. An empty parent field shows no rows. Use the QuickBooks ID stored in Salesforce when matching a reference such as `CustomerRef` or `VendorRef`. The optional `where` or `whereClause` value is combined with the parent predicate using `AND`.

Server pagination queries only the requested page, with a maximum page size of 1,000. Search scans QuickBooks pages up to the configured record limit so its total count and page offsets reflect all matches. The default record limit is 1,000 and the maximum is 10,000. The integration is read only.

## Integrations

Every integration is self-contained and can be deployed independently. Its client owns Named Credential callouts, JSON or form headers, a 60-second timeout, transient-error retry, and HTTP error handling. No integration depends on the unpackaged `APIClient`, integration custom metadata, logging classes, or test utilities from another repository.

| Integration | Extension README | Source folder | Data provider | Named Credential | Website setup guide |
| --- | --- | --- | --- | --- | --- |
| Airtable | [README](force-app/main/airtable/README.md) | `force-app/main/airtable` | `AirtableGridDataProvider` | `Airtable` | [Setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/airtable-grid-integration) |
| Asana | [README](force-app/main/asana/README.md) | `force-app/main/asana` | `AsanaGridDataProvider` | `Asana` | [Setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/asana-grid-integration) |
| Microsoft Excel | [README](force-app/main/excel/README.md) | `force-app/main/excel` | `ExcelGridDataProvider` | `Excel` | [General setup guide](https://appcolab.com/guide/appcolab-grid/user-guide/displaying-data-from-external-systems) |
| Gmail | [README](force-app/main/gmail/README.md) | `force-app/main/gmail` | `GmailGridDataProvider` | `Gmail` | [Setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/gmail-grid-integration) |
| Google Analytics | [README](force-app/main/google-analytics/README.md) | `force-app/main/google-analytics` | `GoogleAnalyticsGridDataProvider` | `Google_Analytics` | [Setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/google-analytics-grid-integration) |
| Google Sheets | [README](force-app/main/google-sheets/README.md) | `force-app/main/google-sheets` | `GoogleSheetsGridDataProvider` | `Google_Sheets` | [Setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/google-sheets-grid-integration) |
| HubSpot | [README](force-app/main/hubspot/README.md) | `force-app/main/hubspot` | `HubSpotGridDataProvider` | `HubSpot` | [Setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/hubspot-grid-integration) |
| Microsoft Outlook | [README](force-app/main/outlook/README.md) | `force-app/main/outlook` | `OutlookGridDataProvider` | `Outlook` | [General setup guide](https://appcolab.com/guide/appcolab-grid/user-guide/displaying-data-from-external-systems) |
| QuickBooks | [README](force-app/main/quickbooks/README.md) | `force-app/main/quickbooks` | `QuickBooksGridDataProvider` | `QuickBooks` | [Setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/quickbooks-grid-integration) |
| Salesforce cross-org | [README](force-app/main/salesforce/README.md) | `force-app/main/salesforce` | `SalesforceGridDataProvider` | `Salesforce_Org` | [Setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/salesforce-cross-org-grid-integration) |
| Shopify | [README](force-app/main/shopify/README.md) | `force-app/main/shopify` | `ShopifyGridDataProvider` | `Shopify` | [Setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/shopify-grid-integration) |
| Stripe | [README](force-app/main/stripe/README.md) | `force-app/main/stripe` | `StripeGridDataProvider` | `Stripe` | [Setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/stripe-grid-integration) |
| Supabase | [README](force-app/main/supabase/README.md) | `force-app/main/supabase` | `SupabaseGridDataProvider` | `Supabase` | [Setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/supabase-grid-integration) |
| Trello | [README](force-app/main/trello/README.md) | `force-app/main/trello` | `TrelloGridDataProvider` | `Trello` | [Setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/trello-grid-integration) |
| Xero | [README](force-app/main/xero/README.md) | `force-app/main/xero` | `XeroGridDataProvider` | `Xero` | [Setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/xero-grid-integration) |

Excel and Outlook link to the general external-data setup guide because the website source has no dedicated guide for those extensions.

### Stripe grids on a Salesforce record

Set the grid's Data Provider Configuration to one of `customers`, `invoices`, `subscriptions`, `charges`, `payment_intents`, `refunds`, `disputes`, `payouts`, `products`, `prices`, or `balance_transactions`. The six resources from `refunds` onward are read only.

To show charges on a Salesforce record, store the Stripe customer ID (such as `cus_123`) on that record. Set `parentMatchColumn` to `customer` and `parentMatchField` to the Salesforce field holding that ID. For example, a Contact grid uses:

```json
{"resource":"charges","parentMatchColumn":"customer","parentMatchField":"Stripe_Customer_Id__c"}
```

```json
{"resource":"charges","parentMatchColumn":"customer_email","parentMatchField":"Email"}
```

The second configuration matches charges by the Contact's email. `charges.customer_email` uses the charge's billing email, falling back to its receipt email. For `payment_intents`, use `customer` for the Stripe customer ID or `receipt_email` for email matching. Invoices expose `customer` and `customer_email`. Refunds and disputes can match `charge` or `payment_intent`; prices can match `product`. A record with an empty match field shows no rows. If `parentMatchField` is omitted, it defaults to the Salesforce record ID. Email matches ignore case; Stripe IDs match exactly. The Stripe record limit applies after matching. Customer ID matches use Stripe's customer filter; email matches scan Stripe pages and can reach Salesforce's callout limit on large accounts.

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
