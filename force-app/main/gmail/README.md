# Gmail Extension

[Back to AppColab Grid Extensions](../../../README.md)

Display and search Gmail messages and inspect thread histories in Salesforce. The grid provider is read only.

## Setup guide

Follow the [Gmail setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/gmail-grid-integration) on appcolab.com for credential setup and Grid Definition configuration.

## Components

| Component | API name |
| --- | --- |
| Apex client | `GmailClient` |
| Data provider | `GmailGridDataProvider` |
| Named Credential | `Gmail` |
| External Credential | `Gmail_Google_APIs` |
| Named principal | `Google_User` |
| Permission set | `Gmail_Integration` |
| Auth Provider | `Gmail_Google_OAuth` |

## Deploy and configure

1. Install [AppColab Grid](https://appexchange.salesforce.com/appxListingDetail?listingId=ed83d466-8f44-4f31-9261-b6fa9390119e) in the target Salesforce org.
2. From the repository root, deploy this extension:

```sh
sf project deploy start \
  --source-dir force-app/main/gmail \
  --target-org YOUR_ORG_ALIAS
```

Configure `Gmail_Google_OAuth` with your application client ID, client secret, callback URL, and required scopes, then authenticate `Gmail_Google_APIs` → `Google_User` as described in the setup guide.

Assign the `Gmail_Integration` permission set to users who need the extension. It grants access to the client, provider, and `Gmail_Google_APIs` → `Google_User` External Credential principal. Use this permission set when the website guide refers to a shared integration permission set.

## Grid Definition

In the AppColab Grid app, create an active Grid Definition. Set **Data Provider Class** to `GmailGridDataProvider` and **Data Provider Configuration** to:

```json
{
  "query": "is:inbox",
  "maxResults": 25
}
```

Replace the placeholder IDs and names with values from your external system, then save and preview the grid.

`query` accepts a Gmail search expression. Optional `maxResults` further limits the requested page size. The provider fetches at most 25 messages per request to limit message-detail callouts.

## Validate deployment

From the repository root, validate this extension and run its Apex tests against an org with AppColab Grid installed:

```sh
sf project deploy start \
  --dry-run \
  --source-dir force-app/main/gmail \
  --target-org YOUR_ORG_ALIAS \
  --test-level RunSpecifiedTests \
  --tests GmailClientTest \
  --tests GmailGridDataProviderTest \
  --wait 30
```
