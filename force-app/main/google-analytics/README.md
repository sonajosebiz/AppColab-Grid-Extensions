# Google Analytics Extension

[Back to AppColab Grid Extensions](../../../README.md)

Display, search, and export Google Analytics 4 reports in Salesforce. The provider is read only.

## Setup guide

Follow the [Google Analytics setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/google-analytics-grid-integration) on appcolab.com for credential setup and Grid Definition configuration.

## Components

| Component | API name |
| --- | --- |
| Apex client | `GoogleAnalyticsClient` |
| Data provider | `GoogleAnalyticsGridDataProvider` |
| Named Credential | `Google_Analytics` |
| External Credential | `Google_Analytics_APIs` |
| Named principal | `Google_User` |
| Permission set | `GoogleAnalytics_Integration` |
| Auth Provider | `Google_Analytics_OAuth` |

## Deploy and configure

1. Install [AppColab Grid](https://appexchange.salesforce.com/appxListingDetail?listingId=ed83d466-8f44-4f31-9261-b6fa9390119e) in the target Salesforce org.
2. From the repository root, deploy this extension:

```sh
sf project deploy start \
  --source-dir force-app/main/google-analytics \
  --target-org YOUR_ORG_ALIAS
```

Configure `Google_Analytics_OAuth` with your application client ID, client secret, callback URL, and required scopes, then authenticate `Google_Analytics_APIs` → `Google_User` as described in the setup guide.

Assign the `GoogleAnalytics_Integration` permission set to users who need the extension. It grants access to the client, provider, and `Google_Analytics_APIs` → `Google_User` External Credential principal. Use this permission set when the website guide refers to a shared integration permission set.

## Grid Definition

In the AppColab Grid app, create an active Grid Definition. Set **Data Provider Class** to `GoogleAnalyticsGridDataProvider` and **Data Provider Configuration** to:

```json
{
  "propertyId": "YOUR_GA4_PROPERTY_ID",
  "reportType": "top_pages",
  "dateRange": "last_30_days",
  "limit": 100
}
```

Replace the placeholder IDs and names with values from your external system, then save and preview the grid.

Reports include `top_pages`, `traffic_sources`, `geo`, and `user_activity` (also accepted as `events` or `timeline`). `limit` defaults to 100 and is capped at 1,000.

## Validate deployment

From the repository root, validate this extension and run its Apex tests against an org with AppColab Grid installed:

```sh
sf project deploy start \
  --dry-run \
  --source-dir force-app/main/google-analytics \
  --target-org YOUR_ORG_ALIAS \
  --test-level RunSpecifiedTests \
  --tests GoogleAnalyticsClientTest \
  --tests GoogleAnalyticsGridDataProviderTest \
  --wait 30
```
