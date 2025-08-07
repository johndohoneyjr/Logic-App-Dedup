#!/bin/bash

# Test Azure Alert Deduplication Solution
set -e

RESOURCE_GROUP="rg-alert-dedup-keyvault"

echo "🧪 Testing Azure Alert Deduplication Solution..."

# Get Logic App webhook URL from saved file or retrieve it
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

# Get App Service URL for dashboard
APP_SERVICE_NAME=$(az webapp list \
    --resource-group $RESOURCE_GROUP \
    --query "[?contains(name, 'mockservicenow')].name" -o tsv)

APP_SERVICE_URL="https://${APP_SERVICE_NAME}.azurewebsites.net"

echo "📊 Testing setup:"
echo "   ⚡ Logic App: $(basename $WEBHOOK_URL | cut -d'?' -f1)"
echo "   🔗 Webhook URL: ${WEBHOOK_URL:0:50}..."
echo "   🌐 Mock ServiceNow: $APP_SERVICE_URL"

# Clear any existing tickets
echo ""
echo "🧹 Clearing existing tickets..."
curl -s -X DELETE "$APP_SERVICE_URL/api/test/tickets" | jq '.message' || echo "Tickets cleared"

# Generate test alert payload
CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
ALERT_ID="alert-$(date +%s)"

TEST_ALERT_PAYLOAD=$(cat << EOF
{
  "schemaId": "azureMonitorCommonAlertSchema",
  "data": {
    "essentials": {
      "alertId": "$ALERT_ID",
      "alertRule": "CDN-Availability-Alert",
      "severity": "Sev2",
      "signalType": "Metric",
      "monitorCondition": "Fired",
      "description": "CDN endpoint availability has dropped below threshold",
      "firedDateTime": "$CURRENT_TIME",
      "resolvedDateTime": null,
      "monitoringService": "Platform",
      "alertTargetIDs": [
        "/subscriptions/12345/resourceGroups/cdn-rg/providers/Microsoft.Cdn/profiles/mycdnprofile/endpoints/endpoint1"
      ]
    },
    "alertContext": {
      "condition": {
        "windowSize": "PT5M",
        "allOf": [
          {
            "metricName": "Percentage",
            "metricNamespace": "Microsoft.Cdn/profiles/endpoints",
            "operator": "LessThan",
            "thresholds": [
              {
                "operator": "LessThan",
                "value": 95.0
              }
            ],
            "timeAggregation": "Average",
            "dimensions": [
              {
                "name": "Endpoint",
                "value": "endpoint1.azureedge.net"
              }
            ],
            "metricValue": 87.5
          }
        ]
      }
    }
  }
}
EOF
)

echo ""
echo "🚀 Test 1: Sending first alert (should create ticket)..."
RESPONSE1=$(curl -s -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "$TEST_ALERT_PAYLOAD" \
  -w "\nHTTP_CODE:%{http_code}")

HTTP_CODE1=$(echo "$RESPONSE1" | grep "HTTP_CODE:" | cut -d: -f2)
RESPONSE_BODY1=$(echo "$RESPONSE1" | sed '/HTTP_CODE:/d')

echo "📥 Response 1 (HTTP $HTTP_CODE1):"
echo "$RESPONSE_BODY1" | jq . 2>/dev/null || echo "$RESPONSE_BODY1"

# Extract deduplication key from first response
DEDUP_KEY1=$(echo "$RESPONSE_BODY1" | jq -r '.deduplicationKey' 2>/dev/null || echo "unknown")

echo ""
echo "⏱️  Waiting 2 seconds..."
sleep 2

echo ""
echo "🚀 Test 2: Sending duplicate alert (should be suppressed)..."
# Generate second alert with different ID but same rule (within same hour)
ALERT_ID2="alert-$(date +%s)-duplicate"
TEST_ALERT_PAYLOAD2=$(echo "$TEST_ALERT_PAYLOAD" | sed "s/$ALERT_ID/$ALERT_ID2/g")

RESPONSE2=$(curl -s -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "$TEST_ALERT_PAYLOAD2" \
  -w "\nHTTP_CODE:%{http_code}")

HTTP_CODE2=$(echo "$RESPONSE2" | grep "HTTP_CODE:" | cut -d: -f2)
RESPONSE_BODY2=$(echo "$RESPONSE2" | sed '/HTTP_CODE:/d')

echo "📥 Response 2 (HTTP $HTTP_CODE2):"
echo "$RESPONSE_BODY2" | jq . 2>/dev/null || echo "$RESPONSE_BODY2"

# Extract deduplication key from second response
DEDUP_KEY2=$(echo "$RESPONSE_BODY2" | jq -r '.deduplicationKey' 2>/dev/null || echo "unknown")

echo ""
echo "📊 Test Results Analysis:"
echo "   🔑 Deduplication Key 1: $DEDUP_KEY1"
echo "   🔑 Deduplication Key 2: $DEDUP_KEY2"

if [ "$DEDUP_KEY1" = "$DEDUP_KEY2" ]; then
    echo "   ✅ Keys match - deduplication working correctly!"
else
    echo "   ❌ Keys don't match - deduplication may not be working"
fi

# Check ticket creation
echo ""
echo "🎫 Checking ServiceNow tickets created..."
TICKETS_RESPONSE=$(curl -s "$APP_SERVICE_URL/api/test/tickets")
TICKET_COUNT=$(echo "$TICKETS_RESPONSE" | jq '.count' 2>/dev/null || echo "0")

echo "📊 ServiceNow Tickets Created: $TICKET_COUNT"

if [ "$TICKET_COUNT" = "1" ]; then
    echo "   ✅ Perfect! Only 1 ticket created (deduplication successful)"
    echo "$TICKETS_RESPONSE" | jq '.tickets[0] | {number, short_description, created_on}' 2>/dev/null || echo "Ticket details not available"
elif [ "$TICKET_COUNT" = "0" ]; then
    echo "   ⚠️  No tickets created - check ServiceNow API connection"
else
    echo "   ❌ Multiple tickets created ($TICKET_COUNT) - deduplication failed"
fi

echo ""
echo "🧪 Test 3: Sending different alert rule (should create new ticket)..."
# Test with different alert rule to ensure it creates a new ticket
DIFFERENT_ALERT_PAYLOAD=$(echo "$TEST_ALERT_PAYLOAD" | sed 's/CDN-Availability-Alert/CDN-Performance-Alert/g')

RESPONSE3=$(curl -s -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "$DIFFERENT_ALERT_PAYLOAD" \
  -w "\nHTTP_CODE:%{http_code}")

HTTP_CODE3=$(echo "$RESPONSE3" | grep "HTTP_CODE:" | cut -d: -f2)
RESPONSE_BODY3=$(echo "$RESPONSE3" | sed '/HTTP_CODE:/d')

echo "📥 Response 3 (HTTP $HTTP_CODE3):"
echo "$RESPONSE_BODY3" | jq . 2>/dev/null || echo "$RESPONSE_BODY3"

# Final ticket count
sleep 2
FINAL_TICKETS=$(curl -s "$APP_SERVICE_URL/api/test/tickets")
FINAL_COUNT=$(echo "$FINAL_TICKETS" | jq '.count' 2>/dev/null || echo "0")

echo ""
echo "📊 Final Results:"
echo "   🎫 Total Tickets Created: $FINAL_COUNT"
echo "   🎯 Expected: 2 tickets (1 for CDN-Availability-Alert, 1 for CDN-Performance-Alert)"

if [ "$FINAL_COUNT" = "2" ]; then
    echo "   ✅ Perfect! Deduplication working correctly!"
else
    echo "   ⚠️  Unexpected ticket count - review Logic App runs in Azure Portal"
fi

echo ""
echo "🔍 Next Steps:"
echo "1. 📊 View Mock ServiceNow Dashboard: $APP_SERVICE_URL"
echo "2. ⚡ View Logic App Runs: https://portal.azure.com (search for $LOGIC_APP_NAME)"
echo "3. 🗄️  Query deduplication table: ./query-deduplication-table.sh"
echo "4. 🧪 Test different scenarios using the Mock ServiceNow dashboard"

echo ""
echo "🎭 Test Scenarios Available:"
echo "   - Visit $APP_SERVICE_URL to access test controls"
echo "   - Simulate ServiceNow failures, slow responses, etc."
echo "   - View all created tickets and their details"
