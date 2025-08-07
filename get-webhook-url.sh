#!/bin/bash

# Get Logic App webhook URL as post-deployment step
set -e

RESOURCE_GROUP="rg-alert-dedup-keyvault"

# Get Logic App name dynamically
LOGIC_APP_NAME=$(az logic workflow list \
    --resource-group $RESOURCE_GROUP \
    --query "[?contains(name, 'alertdedup')].name" -o tsv)

if [ -z "$LOGIC_APP_NAME" ]; then
    echo "❌ Error: No Logic App found in resource group $RESOURCE_GROUP"
    exit 1
fi

echo "🔗 Getting Logic App webhook URL..."
echo "⚡ Logic App: $LOGIC_APP_NAME"

# Get required values
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
ACCESS_TOKEN=$(az account get-access-token --query accessToken -o tsv)

# Get callback URL
WEBHOOK_URL=$(curl -s -X POST \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -H "Content-Length: 0" \
    "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Logic/workflows/$LOGIC_APP_NAME/triggers/manual/listCallbackUrl?api-version=2016-06-01" | jq -r '.value // "Unable to retrieve URL - check Azure Portal"')

echo ""
echo "✅ Logic App Webhook URL:"
echo "$WEBHOOK_URL"
echo ""
echo "📋 Save this URL for the next step: ./update-action-group.sh"
echo ""

# Save to file for next script
echo "$WEBHOOK_URL" > .webhook-url.txt
echo "💾 URL saved to .webhook-url.txt"
