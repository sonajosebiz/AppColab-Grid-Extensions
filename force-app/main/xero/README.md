# Xero Extension

[Back to AppColab Grid Extensions](../../../README.md)

Display, search, and export Xero accounting records in Salesforce. The provider is read only.

## Setup guide

Follow the [Xero setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/xero-grid-integration) on appcolab.com for credential setup and Grid Definition configuration.

## Components

| Component | API name |
| --- | --- |
| Apex client | `XeroClient` |
| Data provider | `XeroGridDataProvider` |
| Named Credential | `Xero` |
| External Credential | `Xero` |
| Named principal | `ApiKey` |
| Permission set | `Xero_Integration` |
| Auth Provider | `Xero_OAuth` |

## Deploy and configure

1. Install [AppColab Grid](https://appexchange.salesforce.com/appxListingDetail?listingId=ed83d466-8f44-4f31-9261-b6fa9390119e) in the target Salesforce org.
2. From the repository root, deploy this extension:

```sh
sf project deploy start \
  --source-dir force-app/main/xero \
  --target-org YOUR_ORG_ALIAS
```

Configure `Xero_OAuth` with your application client ID, client secret, callback URL, and required scopes, then authenticate `Xero` → `ApiKey` as described in the setup guide.

Assign the `Xero_Integration` permission set to users who need the extension. It grants access to the client, provider, and `Xero` → `ApiKey` External Credential principal. Use this permission set when the website guide refers to a shared integration permission set.

## Grid Definition

In the AppColab Grid app, create an active Grid Definition. Set **Data Provider Class** to `XeroGridDataProvider` and **Data Provider Configuration** to:

```json
{
  "tenantId": "YOUR_XERO_TENANT_ID",
  "resource": "invoices"
}
```

Replace the placeholder IDs and names with values from your external system, then save and preview the grid.

Use the tenant ID of the connected Xero organization. Other resources include `contacts`, `accounts`, `bills`, and `payments`. Optional `where` adds a Xero query filter.

## Validate deployment

From the repository root, validate this extension and run its Apex tests against an org with AppColab Grid installed:

```sh
sf project deploy start \
  --dry-run \
  --source-dir force-app/main/xero \
  --target-org YOUR_ORG_ALIAS \
  --test-level RunSpecifiedTests \
  --tests XeroClientTest \
  --tests XeroGridDataProviderTest \
  --wait 30
```
