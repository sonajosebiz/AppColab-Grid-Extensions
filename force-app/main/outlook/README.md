# Microsoft Outlook Extension

[Back to AppColab Grid Extensions](../../../README.md)

Display and search Outlook messages or calendar events through Microsoft Graph. The grid provider is read only.

## Setup guide

Follow the [General external-data setup guide](https://appcolab.com/guide/appcolab-grid/user-guide/displaying-data-from-external-systems) on appcolab.com for credential setup and Grid Definition configuration.

The website source currently has no dedicated Microsoft Outlook integration guide. The linked guide explains the shared AppColab Grid setup flow; use the extension-specific credential and configuration details below.

## Components

| Component | API name |
| --- | --- |
| Apex client | `OutlookClient` |
| Data provider | `OutlookGridDataProvider` |
| Named Credential | `Outlook` |
| External Credential | `Outlook` |
| Named principal | `ApiKey` |
| Permission set | `Outlook_Integration` |
| Auth Provider | `Microsoft_OAuth` |

## Deploy and configure

1. Install [AppColab Grid](https://appexchange.salesforce.com/appxListingDetail?listingId=ed83d466-8f44-4f31-9261-b6fa9390119e) in the target Salesforce org.
2. From the repository root, deploy this extension:

```sh
sf project deploy start \
  --source-dir force-app/main/outlook \
  --target-org YOUR_ORG_ALIAS
```

Configure `Microsoft_OAuth` with your Microsoft application client ID and secret and register its Salesforce callback URL with the application. The deployed Auth Provider uses these scopes:

```text
offline_access openid profile email https://graph.microsoft.com/Mail.Read https://graph.microsoft.com/Calendars.Read
```

Authenticate `Outlook` → `ApiKey` with the Microsoft account whose data the grid should access. Both Excel and Outlook include `Microsoft_OAuth`; if deploying both, configure that shared provider with the scopes needed by both extensions.

Assign the `Outlook_Integration` permission set to users who need the extension. It grants access to the client, provider, and `Outlook` → `ApiKey` External Credential principal. Use this permission set when the website guide refers to a shared integration permission set.

## Grid Definition

In the AppColab Grid app, create an active Grid Definition. Set **Data Provider Class** to `OutlookGridDataProvider` and **Data Provider Configuration** to:

```json
{
  "resource": "messages"
}
```

Replace the placeholder IDs and names with values from your external system, then save and preview the grid.

Use `{"resource":"events"}` for calendar events. Optional `filter` accepts an OData filter expression. On Salesforce record pages, `parentMatchField` defaults to `Email`. Server-side page size is capped at 50.

## Validate deployment

From the repository root, validate this extension and run its Apex tests against an org with AppColab Grid installed:

```sh
sf project deploy start \
  --dry-run \
  --source-dir force-app/main/outlook \
  --target-org YOUR_ORG_ALIAS \
  --test-level RunSpecifiedTests \
  --tests OutlookClientTest \
  --tests OutlookGridDataProviderTest \
  --wait 30
```
