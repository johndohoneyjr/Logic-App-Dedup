# Test Azure Alert Deduplication Solution
$ErrorActionPreference = "Stop"

$RESOURCE_GROUP = "rg-alert-dedup-v2"

Write-Host "Testing Azure Alert Deduplication Solution..." -ForegroundColor Cyan

# Get Logic App webhook URL from saved file or retrieve it
if (Test-Path ".webhook-url.txt") {
    $WEBHOOK_URL = (Get-Content ".webhook-url.txt" -Raw).Trim()
    Write-Host "Using cached webhook URL from .webhook-url.txt" -ForegroundColor Yellow
} else {
    Write-Host "Retrieving Logic App webhook URL..." -ForegroundColor Yellow
    
    $LOGIC_APP_NAME = az logic workflow list --resource-group $RESOURCE_GROUP --query "[?contains(name, 'alertdedup-v2')].name" -o tsv
    $SUBSCRIPTION_ID = az account show --query id -o tsv
    
    $WEBHOOK_URL = az rest --method POST --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Logic/workflows/$LOGIC_APP_NAME/triggers/manual/listCallbackUrl?api-version=2016-06-01" --query "value" -o tsv
    
    $WEBHOOK_URL | Out-File ".webhook-url.txt" -NoNewline
}

# Get App Service URL for dashboard
$APP_SERVICE_NAME = az webapp list --resource-group $RESOURCE_GROUP --query "[?contains(name, 'mockservicenow-v2')].name" -o tsv
$APP_SERVICE_URL = "https://$APP_SERVICE_NAME.azurewebsites.net"

Write-Host "Testing setup:" -ForegroundColor Green
Write-Host "   Logic App: $($WEBHOOK_URL.Split('/')[-3])" -ForegroundColor White
Write-Host "   Webhook URL: $($WEBHOOK_URL.Substring(0, [Math]::Min(50, $WEBHOOK_URL.Length)))..." -ForegroundColor White
Write-Host "   Mock ServiceNow: $APP_SERVICE_URL" -ForegroundColor White

# Clear any existing tickets
Write-Host ""
Write-Host "Clearing existing tickets..." -ForegroundColor Yellow

try {
    $clearResponse = Invoke-RestMethod -Uri "$APP_SERVICE_URL/api/test/tickets" -Method Delete
    Write-Host "Cleared: $($clearResponse.message)" -ForegroundColor Green
} catch {
    Write-Host "Tickets cleared" -ForegroundColor Green
}

# Generate test alert payload
$CURRENT_TIME = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
$ALERT_ID = "alert-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"

$TEST_ALERT_PAYLOAD = @{
    schemaId = "azureMonitorCommonAlertSchema"
    data = @{
        essentials = @{
            alertId = $ALERT_ID
            alertRule = "CDN-Availability-Alert"
            severity = "Sev2"
            signalType = "Metric"
            monitorCondition = "Fired"
            description = "CDN endpoint availability has dropped below threshold"
            firedDateTime = $CURRENT_TIME
            resolvedDateTime = $null
            monitoringService = "Platform"
            alertTargetIDs = @(
                "/subscriptions/12345/resourceGroups/cdn-rg/providers/Microsoft.Cdn/profiles/mycdnprofile/endpoints/endpoint1"
            )
        }
        alertContext = @{
            condition = @{
                windowSize = "PT5M"
                allOf = @(
                    @{
                        metricName = "Percentage"
                        metricNamespace = "Microsoft.Cdn/profiles/endpoints"
                        operator = "LessThan"
                        thresholds = @(
                            @{
                                operator = "LessThan"
                                value = 95.0
                            }
                        )
                        timeAggregation = "Average"
                        dimensions = @(
                            @{
                                name = "Endpoint"
                                value = "endpoint1.azureedge.net"
                            }
                        )
                        metricValue = 87.5
                    }
                )
            }
        }
    }
} | ConvertTo-Json -Depth 10

Write-Host ""
Write-Host "Test 1: Sending first alert (should create ticket)..." -ForegroundColor Cyan

try {
    $response1 = Invoke-RestMethod -Uri $WEBHOOK_URL -Method Post -Body $TEST_ALERT_PAYLOAD -ContentType "application/json"
    Write-Host "Response 1 (HTTP 200):" -ForegroundColor Green
    $response1 | ConvertTo-Json -Depth 5 | Write-Host
    
    $DEDUP_KEY1 = $response1.deduplicationKey
} catch {
    Write-Host "Response 1 (HTTP Error):" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    $DEDUP_KEY1 = "unknown"
}

Write-Host ""
Write-Host "Waiting 2 seconds..." -ForegroundColor Yellow
Start-Sleep -Seconds 2

Write-Host ""
Write-Host "Test 2: Sending duplicate alert (should be suppressed)..." -ForegroundColor Cyan

# Generate second alert with different ID but same rule
$ALERT_ID2 = "alert-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())-duplicate"
$TEST_ALERT_PAYLOAD2 = $TEST_ALERT_PAYLOAD -replace $ALERT_ID, $ALERT_ID2

try {
    $response2 = Invoke-RestMethod -Uri $WEBHOOK_URL -Method Post -Body $TEST_ALERT_PAYLOAD2 -ContentType "application/json"
    Write-Host "Response 2 (HTTP 200):" -ForegroundColor Green
    $response2 | ConvertTo-Json -Depth 5 | Write-Host
    
    $DEDUP_KEY2 = $response2.deduplicationKey
} catch {
    Write-Host "Response 2 (HTTP Error):" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    $DEDUP_KEY2 = "unknown"
}

Write-Host ""
Write-Host "Test Results Analysis:" -ForegroundColor Green
Write-Host "   Deduplication Key 1: $DEDUP_KEY1" -ForegroundColor White
Write-Host "   Deduplication Key 2: $DEDUP_KEY2" -ForegroundColor White

if ($DEDUP_KEY1 -eq $DEDUP_KEY2) {
    Write-Host "   Keys match - deduplication working correctly!" -ForegroundColor Green
} else {
    Write-Host "   Keys don't match - deduplication may not be working" -ForegroundColor Red
}

# Check ticket creation
Write-Host ""
Write-Host "Checking ServiceNow tickets created..." -ForegroundColor Yellow

try {
    $ticketsResponse = Invoke-RestMethod -Uri "$APP_SERVICE_URL/api/test/tickets"
    $TICKET_COUNT = $ticketsResponse.count
} catch {
    $TICKET_COUNT = 0
}

Write-Host "ServiceNow Tickets Created: $TICKET_COUNT" -ForegroundColor Green

if ($TICKET_COUNT -eq 1) {
    Write-Host "   Perfect! Only 1 ticket created (deduplication successful)" -ForegroundColor Green
    if ($ticketsResponse.tickets -and $ticketsResponse.tickets.Count -gt 0) {
        $ticket = $ticketsResponse.tickets[0]
        Write-Host "   Ticket: $($ticket.number) - $($ticket.short_description) (Created: $($ticket.created_on))" -ForegroundColor White
    }
} elseif ($TICKET_COUNT -eq 0) {
    Write-Host "   No tickets created - check ServiceNow API connection" -ForegroundColor Yellow
} else {
    Write-Host "   Multiple tickets created ($TICKET_COUNT) - deduplication failed" -ForegroundColor Red
}

Write-Host ""
Write-Host "Test 3: Sending different alert rule (should create new ticket)..." -ForegroundColor Cyan

# Test with different alert rule to ensure it creates a new ticket
$DIFFERENT_ALERT_PAYLOAD = $TEST_ALERT_PAYLOAD -replace "CDN-Availability-Alert", "CDN-Performance-Alert"

try {
    $response3 = Invoke-RestMethod -Uri $WEBHOOK_URL -Method Post -Body $DIFFERENT_ALERT_PAYLOAD -ContentType "application/json"
    Write-Host "Response 3 (HTTP 200):" -ForegroundColor Green
    $response3 | ConvertTo-Json -Depth 5 | Write-Host
} catch {
    Write-Host "Response 3 (HTTP Error):" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}

# Final ticket count
Start-Sleep -Seconds 2

try {
    $finalTickets = Invoke-RestMethod -Uri "$APP_SERVICE_URL/api/test/tickets"
    $FINAL_COUNT = $finalTickets.count
} catch {
    $FINAL_COUNT = 0
}

Write-Host ""
Write-Host "Final Results:" -ForegroundColor Green
Write-Host "   Total Tickets Created: $FINAL_COUNT" -ForegroundColor White
Write-Host "   Expected: 2 tickets (1 for CDN-Availability-Alert, 1 for CDN-Performance-Alert)" -ForegroundColor White

if ($FINAL_COUNT -eq 2) {
    Write-Host "   Perfect! Deduplication working correctly!" -ForegroundColor Green
} else {
    Write-Host "   Unexpected ticket count - review Logic App runs in Azure Portal" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "1. View Mock ServiceNow Dashboard: $APP_SERVICE_URL" -ForegroundColor White
Write-Host "2. View Logic App Runs: https://portal.azure.com (search for alertdedup-v2)" -ForegroundColor White
Write-Host "3. Query deduplication table: .\query-deduplication-table.ps1" -ForegroundColor White
Write-Host "4. Test different scenarios using the Mock ServiceNow dashboard" -ForegroundColor White

Write-Host ""
Write-Host "Test Scenarios Available:" -ForegroundColor Cyan
Write-Host "   - Visit $APP_SERVICE_URL to access test controls" -ForegroundColor White
Write-Host "   - Simulate ServiceNow failures, slow responses, etc." -ForegroundColor White
Write-Host "   - View all created tickets and their details" -ForegroundColor White
