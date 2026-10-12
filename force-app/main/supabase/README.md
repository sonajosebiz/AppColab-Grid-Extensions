# Supabase Extension

[Back to AppColab Grid Extensions](../../../README.md)

View, search, create, edit, delete, and export rows from a Supabase PostgreSQL table in Salesforce.

## Setup guide

Follow the [Supabase setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/supabase-grid-integration) on appcolab.com for credential setup and Grid Definition configuration.

## Components

| Component | API name |
| --- | --- |
| Apex client | `SupabaseClient` |
| Data provider | `SupabaseGridDataProvider` |
| Named Credential | `Supabase` |
| External Credential | `Supabase` |
| Named principal | `ApiKey` |
| Permission set | `Supabase_Integration` |

## Deploy and configure

1. Install [AppColab Grid](https://appexchange.salesforce.com/appxListingDetail?listingId=ed83d466-8f44-4f31-9261-b6fa9390119e) in the target Salesforce org.
2. From the repository root, deploy this extension:

```sh
sf project deploy start \
  --source-dir force-app/main/supabase \
  --target-org YOUR_ORG_ALIAS
```

Replace the placeholder authentication headers in the External Credential with the token or API key described in the setup guide. Set the Named Credential URL to your Supabase project.

Assign the `Supabase_Integration` permission set to users who need the extension. It grants access to the client, provider, and `Supabase` → `ApiKey` External Credential principal. Use this permission set when the website guide refers to a shared integration permission set.

## Grid Definition

In the AppColab Grid app, create an active Grid Definition. Set **Data Provider Class** to `SupabaseGridDataProvider` and **Data Provider Configuration** to:

```json
{
  "tableName": "contacts"
}
```

Replace the placeholder IDs and names with values from your external system, then save and preview the grid.

`table` is also accepted as an alias for `tableName`. Optional `idColumn` defaults to `id`; use `select` or `selectFields` to select columns and `order` or `orderBy` to sort records.

## Validate deployment

From the repository root, validate this extension and run its Apex tests against an org with AppColab Grid installed:

```sh
sf project deploy start \
  --dry-run \
  --source-dir force-app/main/supabase \
  --target-org YOUR_ORG_ALIAS \
  --test-level RunSpecifiedTests \
  --tests SupabaseClientTest \
  --tests SupabaseGridDataProviderTest \
  --wait 30
```
