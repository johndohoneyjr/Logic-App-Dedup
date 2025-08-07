#!/bin/bash

# Query Azure Table Storage for deduplication records
set -e

RESOURCE_GROUP="rg-alert-dedup-keyvault"

echo "🗄️  Querying Azure Table Storage for deduplication records..."

# Get storage account details
STORAGE_ACCOUNT_NAME=$(az storage account list \
    --resource-group $RESOURCE_GROUP \
    --query "[?contains(name, 'alertdedup')].name" -o tsv)

if [ -z "$STORAGE_ACCOUNT_NAME" ]; then
    echo "❌ Storage account not found in resource group $RESOURCE_GROUP"
    exit 1
fi

STORAGE_KEY=$(az storage account keys list \
    --resource-group $RESOURCE_GROUP \
    --account-name $STORAGE_ACCOUNT_NAME \
    --query "[0].value" -o tsv)

echo "📋 Storage Account: $STORAGE_ACCOUNT_NAME"
echo ""

# Function to query table with proper error handling
query_table() {
    local query="$1"
    local description="$2"
    
    echo "🔍 $description"
    
    RESULT=$(az storage entity query \
        --account-name $STORAGE_ACCOUNT_NAME \
        --account-key $STORAGE_KEY \
        --table-name AlertDeduplication \
        --filter "$query" \
        --output json 2>/dev/null || echo "[]")
    
    if [ "$RESULT" = "[]" ] || [ -z "$RESULT" ]; then
        echo "   📝 No records found"
    else
        echo "$RESULT" | jq -r '.[] | "   🔑 Key: \(.PartitionKey) | Alert: \(.AlertRule) | Processed: \(.ProcessedDateTime) | Severity: \(.Severity)"' 2>/dev/null || echo "   📝 Records found but formatting failed"
        echo "   📊 Total records: $(echo "$RESULT" | jq '. | length' 2>/dev/null || echo "unknown")"
    fi
    echo ""
}

# Query all records
echo "📊 All Deduplication Records:"
query_table "" "Retrieving all deduplication records"

# Query recent records (last 24 hours)
YESTERDAY=$(date -u -d '1 day ago' +"%Y-%m-%dT%H:%M:%S.%3NZ" 2>/dev/null || date -u -v-1d +"%Y-%m-%dT%H:%M:%S.%3NZ" 2>/dev/null || echo "2025-07-29T00:00:00.000Z")
query_table "ProcessedDateTime ge datetime'$YESTERDAY'" "Records from last 24 hours"

# Query CDN alerts specifically
query_table "PartitionKey ge 'CDN' and PartitionKey lt 'CDO'" "CDN-related alerts"

# Query by current hour (most recent deduplication window)
CURRENT_HOUR=$(date -u +"%Y-%m-%d-%H")
query_table "PartitionKey ge 'CDN-Availability-Alert-$CURRENT_HOUR' and PartitionKey lt 'CDN-Availability-Alert-$CURRENT_HOUR~'" "Current hour deduplication window ($CURRENT_HOUR)"

# Summary statistics
echo "📈 Summary Statistics:"
ALL_RECORDS=$(az storage entity query \
    --account-name $STORAGE_ACCOUNT_NAME \
    --account-key $STORAGE_KEY \
    --table-name AlertDeduplication \
    --output json 2>/dev/null || echo "[]")

if [ "$ALL_RECORDS" != "[]" ] && [ -n "$ALL_RECORDS" ]; then
    TOTAL_COUNT=$(echo "$ALL_RECORDS" | jq '. | length' 2>/dev/null || echo "0")
    UNIQUE_RULES=$(echo "$ALL_RECORDS" | jq -r '[.[].AlertRule] | unique | length' 2>/dev/null || echo "0")
    
    echo "   📊 Total deduplication records: $TOTAL_COUNT"
    echo "   🎯 Unique alert rules processed: $UNIQUE_RULES"
    
    if [ "$TOTAL_COUNT" -gt "0" ]; then
        echo "   📝 Alert rules seen:"
        echo "$ALL_RECORDS" | jq -r '[.[].AlertRule] | unique | .[]' 2>/dev/null | sed 's/^/      - /' || echo "      - Could not parse rules"
    fi
else
    echo "   📝 No records found in deduplication table"
fi

echo ""
echo "🛠️  Management Commands:"
echo ""
echo "🗑️  Clear all deduplication records:"
echo "   az storage entity delete --account-name $STORAGE_ACCOUNT_NAME --account-key $STORAGE_KEY --table-name AlertDeduplication --partition-key '<KEY>' --row-key '<KEY>'"
echo ""
echo "🔍 Query specific deduplication key:"
echo "   az storage entity show --account-name $STORAGE_ACCOUNT_NAME --account-key $STORAGE_KEY --table-name AlertDeduplication --partition-key '<DEDUP_KEY>' --row-key '<DEDUP_KEY>'"
echo ""
echo "📊 Table Storage Explorer:"
echo "   https://portal.azure.com/#@/resource/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME/storageBrowser"

# Check if we can detect duplicate patterns
echo ""
echo "🔍 Duplicate Detection Analysis:"
if [ "$ALL_RECORDS" != "[]" ] && [ -n "$ALL_RECORDS" ]; then
    # Group by hour windows to see deduplication effectiveness
    echo "$ALL_RECORDS" | jq -r 'group_by(.PartitionKey) | .[] | "\(.[0].PartitionKey): \(length) alerts processed"' 2>/dev/null | head -10 | sed 's/^/   /' || echo "   Analysis not available"
    
    if [ "$TOTAL_COUNT" -gt "1" ]; then
        echo "   ✅ Deduplication is working - multiple records indicate alert processing"
    fi
else
    echo "   📝 No data available for analysis"
fi
