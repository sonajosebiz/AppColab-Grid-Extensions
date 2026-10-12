# QuickBooks Extension

[Back to AppColab Grid Extensions](../../../README.md)

Display, search, and export QuickBooks Online accounting records in Salesforce. The provider is read only.

## Setup guide

Follow the [QuickBooks setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/quickbooks-grid-integration) on appcolab.com for credential setup and Grid Definition configuration.

## Components

| Component | API name |
| --- | --- |
| Apex client | `QuickBooksClient` |
| Data provider | `QuickBooksGridDataProvider` |
| Named Credential | `QuickBooks` |
| External Credential | `QuickBooks` |
| Named principal | `ApiKey` |
| Permission set | `QuickBooks_Integration` |

## Deploy and configure

1. Install [AppColab Grid](https://appexchange.salesforce.com/appxListingDetail?listingId=ed83d466-8f44-4f31-9261-b6fa9390119e) in the target Salesforce org.
2. From the repository root, deploy this extension:

```sh
sf project deploy start \
  --source-dir force-app/main/quickbooks \
  --target-org YOUR_ORG_ALIAS
```

The supplied External Credential uses Custom authentication with an `Authorization` header containing `Bearer YOUR_QUICKBOOKS_BEARER_TOKEN`. Replace the placeholder with a valid QuickBooks access token. The website guide describes obtaining OAuth credentials; this folder does not include a QuickBooks Auth Provider or automatic token refresh.

Assign the `QuickBooks_Integration` permission set to users who need the extension. It grants access to the client, provider, and `QuickBooks` → `ApiKey` External Credential principal. Use this permission set when the website guide refers to a shared integration permission set.

## Grid Definition

In the AppColab Grid app, create an active Grid Definition. Set **Data Provider Class** to `QuickBooksGridDataProvider` and **Data Provider Configuration** to:

```json
{
  "realmId": "YOUR_COMPANY_ID",
  "resource": "invoices"
}
```

Replace the placeholder IDs and names with values from your external system, then save and preview the grid.

## Supported resources and parent-record filtering

Set the grid's Data Provider Configuration to the QuickBooks company ID and entity. The provider supports invoices, customers, payments, items, bills, vendors, estimates, sales receipts, credit memos, purchase orders, accounts, deposits, journal entries, and purchases. Singular and plural resource names are accepted.

```json
{"realmId":"YOUR_COMPANY_ID","resource":"invoices","parentMatchColumn":"CustomerRef","parentMatchField":"QuickBooks_Customer_Id__c"}
```

`parentMatchColumn` is a filterable QuickBooks field. When the grid opens on a Salesforce record, the provider reads `parentMatchField` from that record and adds an equality predicate to both the count and page queries. If `parentMatchField` is omitted, the Salesforce record ID is used. An empty parent field shows no rows. Use the QuickBooks ID stored in Salesforce when matching a reference such as `CustomerRef` or `VendorRef`. The optional `where` or `whereClause` value is combined with the parent predicate using `AND`.

Server pagination queries only the requested page, with a maximum page size of 1,000. Search scans QuickBooks pages up to the configured record limit so its total count and page offsets reflect all matches. The default record limit is 1,000 and the maximum is 10,000. The integration is read only.

## Validate deployment

From the repository root, validate this extension and run its Apex tests against an org with AppColab Grid installed:

```sh
sf project deploy start \
  --dry-run \
  --source-dir force-app/main/quickbooks \
  --target-org YOUR_ORG_ALIAS \
  --test-level RunSpecifiedTests \
  --tests QuickBooksClientTest \
  --tests QuickBooksGridDataProviderTest \
  --wait 30
```
