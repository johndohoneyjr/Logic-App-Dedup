# Get Logic App webhook URL as post-deployment step
$ErrorActionPreference = "Stop"

$RESOURCE_GROUP = "rg-alert-dedup-v2"

# Get Logic App name dynamically
$LOGIC_APP_NAME = az logic workflow list --resource-group $RESOURCE_GROUP --query "[?contains(name, 'alertdedup')].name" -o tsv

if (-not $LOGIC_APP_NAME) {
    Write-Host "Error: No Logic App found in resource group $RESOURCE_GROUP" -ForegroundColor Red
    exit 1
}

Write-Host "Getting Logic App webhook URL..." -ForegroundColor Cyan
Write-Host "Logic App: $LOGIC_APP_NAME" -ForegroundColor Yellow

# Get required values
$SUBSCRIPTION_ID = az account show --query id -o tsv

# Get callback URL using Azure CLI REST command
$WEBHOOK_URL = az rest --method POST --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Logic/workflows/$LOGIC_APP_NAME/triggers/manual/listCallbackUrl?api-version=2016-06-01" --query "value" -o tsv

if (-not $WEBHOOK_URL -or $WEBHOOK_URL -eq "null") {
    Write-Host "Unable to retrieve URL - check Azure Portal" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Logic App Webhook URL:" -ForegroundColor Green
Write-Host "$WEBHOOK_URL" -ForegroundColor White
Write-Host ""
Write-Host "Save this URL for the next step: .\update-action-group.ps1" -ForegroundColor Cyan
Write-Host ""

# Save to file for next script
$WEBHOOK_URL | Out-File ".webhook-url.txt" -NoNewline
Write-Host "URL saved to .webhook-url.txt" -ForegroundColor Green
