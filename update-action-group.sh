#!/bin/bash

# Update Action Group with Logic App webhook URL
set -e

RESOURCE_GROUP="rg-alert-dedup-keyvault"

echo "📢 Updating Action Group with Logic App webhook URL..."

# Get webhook URL from saved file or retrieve it
if [ -f ".webhook-url.txt" ]; then
    WEBHOOK_URL=$(cat .webhook-url.txt)
    echo "📁 Using cached webhook URL from .webhook-url.txt"
else
    echo "🔗 Retrieving Logic App webhook URL..."
    LOGIC_APP_NAME=$(az logic workflow list \
        --resource-group $RESOURCE_GROUP \
        --query "[?contains(name, 'alertdedup')].name" -o tsv)

    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    WEBHOOK_URL=$(az rest --method POST \
      --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Logic/workflows/$LOGIC_APP_NAME/triggers/manual/listCallbackUrl?api-version=2016-06-01" \
      --query "value" -o tsv)
    
    echo "$WEBHOOK_URL" > .webhook-url.txt
fi

# Get Action Group name
ACTION_GROUP_NAME=$(az monitor action-group list \
    --resource-group $RESOURCE_GROUP \
    --query "[?contains(name, 'ag-cdn-alerts')].name" -o tsv)

echo "📢 Action Group: $ACTION_GROUP_NAME"
echo "🔗 Webhook URL: ${WEBHOOK_URL:0:50}..."

# Update Action Group with webhook
az monitor action-group update \
  --resource-group $RESOURCE_GROUP \
  --name $ACTION_GROUP_NAME \
  --add-action webhook LogicAppWebhook "$WEBHOOK_URL"

echo "✅ Action Group updated successfully!"
echo ""
echo "📢 Action Group '$ACTION_GROUP_NAME' now includes:"
echo "   🔗 Logic App webhook for alert deduplication"
echo ""
echo "🧪 Test the integration:"
echo "   ./test-azure-solution.sh"