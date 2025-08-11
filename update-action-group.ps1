# Update Action Group with Logic App webhook URL
$ErrorActionPreference = "Stop"

$RESOURCE_GROUP = "rg-alert-dedup-v2"

Write-Host "Updating Action Group with Logic App webhook URL..." -ForegroundColor Cyan

# Get webhook URL from saved file or retrieve it
if (Test-Path ".webhook-url.txt") {
    $WEBHOOK_URL = (Get-Content ".webhook-url.txt" -Raw).Trim()
    Write-Host "Using cached webhook URL from .webhook-url.txt" -ForegroundColor Yellow
} else {
    Write-Host "Retrieving Logic App webhook URL..." -ForegroundColor Yellow
    
    $LOGIC_APP_NAME = az logic workflow list --resource-group $RESOURCE_GROUP --query "[?contains(name, 'alertdedup')].name" -o tsv
    $SUBSCRIPTION_ID = az account show --query id -o tsv
    
    $WEBHOOK_URL = az rest --method POST --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Logic/workflows/$LOGIC_APP_NAME/triggers/manual/listCallbackUrl?api-version=2016-06-01" --query "value" -o tsv
    
    $WEBHOOK_URL | Out-File ".webhook-url.txt" -NoNewline
}

# Get Action Group name
$ACTION_GROUP_NAME = az monitor action-group list --resource-group $RESOURCE_GROUP --query "[?contains(name, 'ag-cdn-alerts')].name" -o tsv

Write-Host "Action Group: $ACTION_GROUP_NAME" -ForegroundColor Green
Write-Host "Webhook URL: $($WEBHOOK_URL.Substring(0, [Math]::Min(50, $WEBHOOK_URL.Length)))..." -ForegroundColor White

# Update Action Group with webhook
Write-Host "Adding webhook to Action Group..." -ForegroundColor Yellow

az monitor action-group update --resource-group $RESOURCE_GROUP --name $ACTION_GROUP_NAME --add-action webhook LogicAppWebhook $WEBHOOK_URL

Write-Host "Action Group updated successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Action Group '$ACTION_GROUP_NAME' now includes:" -ForegroundColor Green
Write-Host "   Logic App webhook for alert deduplication" -ForegroundColor White
Write-Host ""
Write-Host "Test the integration:" -ForegroundColor Cyan
Write-Host "   .\test-azure-solution.ps1" -ForegroundColor White
