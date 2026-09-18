#!/usr/bin/env bash
set -euo pipefail

target_org="${1:?Usage: ./scripts/validate-integrations.sh TARGET_ORG_ALIAS}"

validations=(
  "google-sheets:GoogleSheetsClientTest:GoogleSheetsGridDataProviderTest"
  "airtable:AirtableClientTest:AirtableGridDataProviderTest"
  "asana:AsanaClientTest:AsanaGridDataProviderTest"
  "gmail:GmailClientTest:GmailGridDataProviderTest"
  "google-analytics:GoogleAnalyticsClientTest:GoogleAnalyticsGridDataProviderTest"
  "hubspot:HubSpotClientTest:HubSpotGridDataProviderTest"
  "quickbooks:QuickBooksClientTest:QuickBooksGridDataProviderTest"
  "salesforce:SalesforceClientTest:SalesforceGridDataProviderTest"
  "shopify:ShopifyClientTest:ShopifyGridDataProviderTest"
  "stripe:StripeClientTest:StripeGridDataProviderTest"
  "supabase:SupabaseClientTest:SupabaseGridDataProviderTest"
  "trello:TrelloClientTest:TrelloGridDataProviderTest"
  "xero:XeroClientTest:XeroGridDataProviderTest"
)

for validation in "${validations[@]}"; do
  IFS=: read -r folder client_test provider_test <<< "${validation}"
  echo "Validating ${folder}"
  SF_DISABLE_LOG_FILE=true sf project deploy start \
    --dry-run \
    --source-dir "force-app/main/${folder}" \
    --target-org "${target_org}" \
    --test-level RunSpecifiedTests \
    --tests "${client_test}" \
    --tests "${provider_test}" \
    --wait 30
done
