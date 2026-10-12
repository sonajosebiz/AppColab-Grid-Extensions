# Shopify Extension

[Back to AppColab Grid Extensions](../../../README.md)

Display Shopify products, orders, and customers in Salesforce. Products and customers support add, edit, and delete; orders are read only.

## Setup guide

Follow the [Shopify setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/shopify-grid-integration) on appcolab.com for credential setup and Grid Definition configuration.

## Components

| Component | API name |
| --- | --- |
| Apex client | `ShopifyClient` |
| Data provider | `ShopifyGridDataProvider` |
| Named Credential | `Shopify` |
| External Credential | `Shopify` |
| Named principal | `ApiKey` |
| Permission set | `Shopify_Integration` |

## Deploy and configure

1. Install [AppColab Grid](https://appexchange.salesforce.com/appxListingDetail?listingId=ed83d466-8f44-4f31-9261-b6fa9390119e) in the target Salesforce org.
2. From the repository root, deploy this extension:

```sh
sf project deploy start \
  --source-dir force-app/main/shopify \
  --target-org YOUR_ORG_ALIAS
```

Replace the placeholder authentication headers in the External Credential with the token or API key described in the setup guide. Set the Named Credential URL to your Shopify store.

Assign the `Shopify_Integration` permission set to users who need the extension. It grants access to the client, provider, and `Shopify` → `ApiKey` External Credential principal. Use this permission set when the website guide refers to a shared integration permission set.

## Grid Definition

In the AppColab Grid app, create an active Grid Definition. Set **Data Provider Class** to `ShopifyGridDataProvider` and **Data Provider Configuration** to:

```json
{
  "resource": "products"
}
```

Replace the placeholder IDs and names with values from your external system, then save and preview the grid.

Set `resource` to `products`, `customers`, or `orders`.

## Validate deployment

From the repository root, validate this extension and run its Apex tests against an org with AppColab Grid installed:

```sh
sf project deploy start \
  --dry-run \
  --source-dir force-app/main/shopify \
  --target-org YOUR_ORG_ALIAS \
  --test-level RunSpecifiedTests \
  --tests ShopifyClientTest \
  --tests ShopifyGridDataProviderTest \
  --wait 30
```
