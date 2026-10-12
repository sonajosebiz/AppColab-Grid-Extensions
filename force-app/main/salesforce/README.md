# Salesforce cross-org Extension

[Back to AppColab Grid Extensions](../../../README.md)

Query, search, create, edit, delete, and export records from another Salesforce org.

## Setup guide

Follow the [Salesforce cross-org setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/salesforce-cross-org-grid-integration) on appcolab.com for credential setup and Grid Definition configuration.

## Components

| Component | API name |
| --- | --- |
| Apex client | `SalesforceClient` |
| Data provider | `SalesforceGridDataProvider` |
| Named Credential | `Salesforce_Org` |
| External Credential | `Salesforce_Org` |
| Named principal | `ApiKey` |
| Permission set | `Salesforce_Integration` |

## Deploy and configure

1. Install [AppColab Grid](https://appexchange.salesforce.com/appxListingDetail?listingId=ed83d466-8f44-4f31-9261-b6fa9390119e) in the target Salesforce org.
2. From the repository root, deploy this extension:

```sh
sf project deploy start \
  --source-dir force-app/main/salesforce \
  --target-org YOUR_ORG_ALIAS
```

Configure the Named Credential URL for the target Salesforce org and the External Credential for OAuth client credentials. Set the client ID and secret from the target org application and configure its execution user as described in the setup guide.

Assign the `Salesforce_Integration` permission set to users who need the extension. It grants access to the client, provider, and `Salesforce_Org` → `ApiKey` External Credential principal. Use this permission set when the website guide refers to a shared integration permission set.

## Grid Definition

In the AppColab Grid app, create an active Grid Definition. Set **Data Provider Class** to `SalesforceGridDataProvider` and **Data Provider Configuration** to:

```json
{
  "sObject": "Opportunity",
  "fields": "Id, Name, StageName, Amount, CloseDate, Type"
}
```

Replace the placeholder IDs and names with values from your external system, then save and preview the grid.

Use `sObject` for the remote object API name and `fields` for the requested fields. Optional `where`, `orderBy`, `parentMatchColumn`, `parentMatchField`, and `autoPopulateParent` control queries and parent-record matching.

## Validate deployment

From the repository root, validate this extension and run its Apex tests against an org with AppColab Grid installed:

```sh
sf project deploy start \
  --dry-run \
  --source-dir force-app/main/salesforce \
  --target-org YOUR_ORG_ALIAS \
  --test-level RunSpecifiedTests \
  --tests SalesforceClientTest \
  --tests SalesforceGridDataProviderTest \
  --wait 30
```
