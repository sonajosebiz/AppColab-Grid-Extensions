# AppColab Grid Extensions

Bring data from your spreadsheets, CRM, accounting tools, and other systems directly into Salesforce with AppColab Grid.

**Get up and running with the systems under 30 mins**, provided AppColab Grid is installed and your external account credentials ready 😊. Each extension includes ready-to-deploy code and setup instructions to help you get your first grid running.

## Get started

1. Install [AppColab Grid](https://appexchange.salesforce.com/appxListingDetail?listingId=ed83d466-8f44-4f31-9261-b6fa9390119e) in your Salesforce org.
2. Choose a system below. Open its extension README for deployment instructions and its setup guide for the configuration walkthrough.
3. Deploy the extension, connect your account, grant users access, and create your Grid Definition. Save and preview to see your data in Salesforce.

## Choose your integration

Deploy only the extensions you need. Each README includes credential details, a configuration example, and validation commands.

| Integration | Extension README | Website setup guide |
| --- | --- | --- |
| Airtable | [README](force-app/main/airtable/README.md) | [Setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/airtable-grid-integration) |
| Asana | [README](force-app/main/asana/README.md) | [Setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/asana-grid-integration) |
| Microsoft Excel | [README](force-app/main/excel/README.md) | [General setup guide](https://appcolab.com/guide/appcolab-grid/user-guide/displaying-data-from-external-systems) |
| Gmail | [README](force-app/main/gmail/README.md) | [Setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/gmail-grid-integration) |
| Google Analytics | [README](force-app/main/google-analytics/README.md) | [Setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/google-analytics-grid-integration) |
| Google Sheets | [README](force-app/main/google-sheets/README.md) | [Setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/google-sheets-grid-integration) |
| HubSpot | [README](force-app/main/hubspot/README.md) | [Setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/hubspot-grid-integration) |
| Microsoft Outlook | [README](force-app/main/outlook/README.md) | [General setup guide](https://appcolab.com/guide/appcolab-grid/user-guide/displaying-data-from-external-systems) |
| QuickBooks | [README](force-app/main/quickbooks/README.md) | [Setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/quickbooks-grid-integration) |
| Salesforce cross-org | [README](force-app/main/salesforce/README.md) | [Setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/salesforce-cross-org-grid-integration) |
| Shopify | [README](force-app/main/shopify/README.md) | [Setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/shopify-grid-integration) |
| Stripe | [README](force-app/main/stripe/README.md) | [Setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/stripe-grid-integration) |
| Supabase | [README](force-app/main/supabase/README.md) | [Setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/supabase-grid-integration) |
| Trello | [README](force-app/main/trello/README.md) | [Setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/trello-grid-integration) |
| Xero | [README](force-app/main/xero/README.md) | [Setup guide](https://appcolab.com/guide/appcolab-grid/external-connections/xero-grid-integration) |

Excel and Outlook use the general external-data setup guide. Their extension READMEs include the Microsoft-specific configuration details.

<details>
<summary>For developers: validate all extensions</summary>

From the repository root, run the test-only deployment validations against an org with AppColab Grid installed:

```sh
./scripts/validate-integrations.sh YOUR_ORG_ALIAS
```

Each integration is self-contained and can be deployed independently. Its client handles Named Credential callouts, JSON or form headers, a 60-second timeout, transient-error retry, and HTTP errors. No integration depends on the unpackaged `APIClient`, integration custom metadata, logging classes, or test utilities from another repository.

Credential metadata contains placeholders. Configure the extension's External Credential or Auth Provider, authenticate its named principal where OAuth is used, and assign its permission set as described in the extension README.

</details>
