# Stripe Extension

[Back to AppColab Grid Extensions](../../../README.md)

Display, search, and export Stripe records in Salesforce. Mutation support depends on the selected resource.

## Setup guide

Follow the [Stripe setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/stripe-grid-integration) on appcolab.com for credential setup and Grid Definition configuration.

## Components

| Component | API name |
| --- | --- |
| Apex client | `StripeClient` |
| Data provider | `StripeGridDataProvider` |
| Named Credential | `Stripe` |
| External Credential | `Stripe` |
| Named principal | `ApiKey` |
| Permission set | `Stripe_Integration` |

## Deploy and configure

1. Install [AppColab Grid](https://appexchange.salesforce.com/appxListingDetail?listingId=ed83d466-8f44-4f31-9261-b6fa9390119e) in the target Salesforce org.
2. From the repository root, deploy this extension:

```sh
sf project deploy start \
  --source-dir force-app/main/stripe \
  --target-org YOUR_ORG_ALIAS
```

Replace the placeholder authentication headers in the External Credential with the token or API key described in the setup guide.

Assign the `Stripe_Integration` permission set to users who need the extension. It grants access to the client, provider, and `Stripe` → `ApiKey` External Credential principal. Use this permission set when the website guide refers to a shared integration permission set.

## Grid Definition

In the AppColab Grid app, create an active Grid Definition. Set **Data Provider Class** to `StripeGridDataProvider` and **Data Provider Configuration** to:

```json
{
  "resource": "customers"
}
```

Replace the placeholder IDs and names with values from your external system, then save and preview the grid.

## Stripe grids on a Salesforce record

Set the grid's Data Provider Configuration to one of `customers`, `invoices`, `subscriptions`, `charges`, `payment_intents`, `refunds`, `disputes`, `payouts`, `products`, `prices`, or `balance_transactions`. The six resources from `refunds` onward are read only.

To show charges on a Salesforce record, store the Stripe customer ID (such as `cus_123`) on that record. Set `parentMatchColumn` to `customer` and `parentMatchField` to the Salesforce field holding that ID. For example, a Contact grid uses:

```json
{"resource":"charges","parentMatchColumn":"customer","parentMatchField":"Stripe_Customer_Id__c"}
```

```json
{"resource":"charges","parentMatchColumn":"customer_email","parentMatchField":"Email"}
```

The second configuration matches charges by the Contact's email. `charges.customer_email` uses the charge's billing email, falling back to its receipt email. For `payment_intents`, use `customer` for the Stripe customer ID or `receipt_email` for email matching. Invoices expose `customer` and `customer_email`. Refunds and disputes can match `charge` or `payment_intent`; prices can match `product`. A record with an empty match field shows no rows. If `parentMatchField` is omitted, it defaults to the Salesforce record ID. Email matches ignore case; Stripe IDs match exactly. The Stripe record limit applies after matching. Customer ID matches use Stripe's customer filter; email matches scan Stripe pages and can reach Salesforce's callout limit on large accounts.

## Validate deployment

From the repository root, validate this extension and run its Apex tests against an org with AppColab Grid installed:

```sh
sf project deploy start \
  --dry-run \
  --source-dir force-app/main/stripe \
  --target-org YOUR_ORG_ALIAS \
  --test-level RunSpecifiedTests \
  --tests StripeClientTest \
  --tests StripeGridDataProviderTest \
  --wait 30
```
