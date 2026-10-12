# HubSpot Extension

[Back to AppColab Grid Extensions](../../../README.md)

Display and manage HubSpot CRM records in Salesforce, including contacts, companies, deals, tickets, and email history.

## Setup guide

Follow the [HubSpot setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/hubspot-grid-integration) on appcolab.com for credential setup and Grid Definition configuration.

## Components

| Component | API name |
| --- | --- |
| Apex client | `HubSpotClient` |
| Data provider | `HubSpotGridDataProvider` |
| Named Credential | `HubSpot` |
| External Credential | `HubSpot` |
| Named principal | `ApiKey` |
| Permission set | `HubSpot_Integration` |

## Deploy and configure

1. Install [AppColab Grid](https://appexchange.salesforce.com/appxListingDetail?listingId=ed83d466-8f44-4f31-9261-b6fa9390119e) in the target Salesforce org.
2. From the repository root, deploy this extension:

```sh
sf project deploy start \
  --source-dir force-app/main/hubspot \
  --target-org YOUR_ORG_ALIAS
```

Replace the placeholder authentication headers in the External Credential with the token or API key described in the setup guide.

Assign the `HubSpot_Integration` permission set to users who need the extension. It grants access to the client, provider, and `HubSpot` → `ApiKey` External Credential principal. Use this permission set when the website guide refers to a shared integration permission set.

## Grid Definition

In the AppColab Grid app, create an active Grid Definition. Set **Data Provider Class** to `HubSpotGridDataProvider` and **Data Provider Configuration** to:

```json
{
  "objectType": "contacts"
}
```

Replace the placeholder IDs and names with values from your external system, then save and preview the grid.

Use `objectType` to select the HubSpot object. Optional `properties` and `columns` customize the returned fields and grid columns. `parentMatchField` and `hubspotMatchProperty` support matching data to a Salesforce parent record.

## Validate deployment

From the repository root, validate this extension and run its Apex tests against an org with AppColab Grid installed:

```sh
sf project deploy start \
  --dry-run \
  --source-dir force-app/main/hubspot \
  --target-org YOUR_ORG_ALIAS \
  --test-level RunSpecifiedTests \
  --tests HubSpotClientTest \
  --tests HubSpotGridDataProviderTest \
  --wait 30
```
