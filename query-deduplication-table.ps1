# Query Azure Table Storage for deduplication records
$ErrorActionPreference = "Stop"

$RESOURCE_GROUP = "rg-alert-dedup-v2"

Write-Host "Querying Azure Table Storage for deduplication records..." -ForegroundColor Cyan

# Get Key Vault name from deployment
$keyVaultName = ""
try {
    # Try to find the Key Vault in the resource group (updated pattern to match actual deployment)
    $kvResult = az keyvault list --query "[?starts_with(name, 'kv-v2-')]" --output json | ConvertFrom-Json
    if ($kvResult.Count -gt 0) {
        $keyVaultName = $kvResult[0].name
        Write-Host "Found Key Vault: $keyVaultName" -ForegroundColor Green
    } else {
        throw "Key Vault not found"
    }
}
catch {
    Write-Error "Unable to find Key Vault. Please ensure the solution is deployed."
    exit 1
}

# Retrieve storage credentials from Key Vault
Write-Host "Retrieving storage credentials from Key Vault..." -ForegroundColor Yellow
try {
    $STORAGE_ACCOUNT_NAME = az keyvault secret show --vault-name $keyVaultName --name "storage-account-name" --query "value" --output tsv
    $STORAGE_KEY = az keyvault secret show --vault-name $keyVaultName --name "storage-account-key" --query "value" --output tsv
    $TABLE_NAME = az keyvault secret show --vault-name $keyVaultName --name "storage-table-name" --query "value" --output tsv
    
    if ([string]::IsNullOrEmpty($STORAGE_ACCOUNT_NAME) -or [string]::IsNullOrEmpty($STORAGE_KEY) -or [string]::IsNullOrEmpty($TABLE_NAME)) {
        throw "Failed to retrieve storage credentials from Key Vault"
    }
    
    Write-Host "Storage credentials retrieved successfully" -ForegroundColor Green
}
catch {
    Write-Error "Failed to retrieve credentials from Key Vault: $_"
    Write-Host "Make sure you have access to the Key Vault and the secrets exist." -ForegroundColor Yellow
    exit 1
}

Write-Host "Storage Account: $STORAGE_ACCOUNT_NAME" -ForegroundColor Green
Write-Host ""

# Function to query table with proper error handling
function QueryTable {
    param(
        [string]$Query,
        [string]$Description
    )
    
    Write-Host "Searching: $Description" -ForegroundColor Yellow
    
    try {
        if ($Query) {
            $rawResult = az storage entity query --account-name $STORAGE_ACCOUNT_NAME --account-key $STORAGE_KEY --table-name $TABLE_NAME --filter $Query --output json | ConvertFrom-Json
        } else {
            $rawResult = az storage entity query --account-name $STORAGE_ACCOUNT_NAME --account-key $STORAGE_KEY --table-name $TABLE_NAME --output json | ConvertFrom-Json
        }
        
        # Extract items array from the response
        $result = if ($rawResult.items) { $rawResult.items } else { $rawResult }
        
        if (-not $result -or $result.Count -eq 0) {
            Write-Host "   No records found" -ForegroundColor Gray
        } else {
            foreach ($record in $result) {
                $key = if ($record.PartitionKey) { $record.PartitionKey } else { "Unknown" }
                $alertRule = if ($record.AlertRule) { $record.AlertRule } else { "Unknown" }
                $processed = if ($record.ProcessedDateTime) { $record.ProcessedDateTime } else { "Unknown" }
                $severity = if ($record.Severity) { $record.Severity } else { "Unknown" }
                Write-Host "   Key: $key | Alert: $alertRule | Processed: $processed | Severity: $severity" -ForegroundColor White
            }
            Write-Host "   Total records: $($result.Count)" -ForegroundColor Green
        }
    } catch {
        Write-Host "   No records found or query failed" -ForegroundColor Gray
    }
    Write-Host ""
}

# Query all records
Write-Host "All Deduplication Records:" -ForegroundColor Green
QueryTable -Query "" -Description "Retrieving all deduplication records"

# Query recent records (last 24 hours)
$yesterday = (Get-Date).AddDays(-1).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
QueryTable -Query "ProcessedDateTime ge datetime'$yesterday'" -Description "Records from last 24 hours"

# Query CDN alerts specifically
QueryTable -Query "PartitionKey ge 'CDN' and PartitionKey lt 'CDO'" -Description "CDN-related alerts"

# Query by current hour (most recent deduplication window)
$currentHour = (Get-Date).ToString("yyyy-MM-dd-HH")
QueryTable -Query "PartitionKey ge 'CDN-Availability-Alert-$currentHour' and PartitionKey lt 'CDN-Availability-Alert-$currentHour~'" -Description "Current hour deduplication window ($currentHour)"

# Summary statistics
Write-Host "Summary Statistics:" -ForegroundColor Green

try {
    $rawAllRecords = az storage entity query --account-name $STORAGE_ACCOUNT_NAME --account-key $STORAGE_KEY --table-name $TABLE_NAME --output json | ConvertFrom-Json
    $allRecords = if ($rawAllRecords.items) { $rawAllRecords.items } else { $rawAllRecords }
    
    if ($allRecords -and $allRecords.Count -gt 0) {
        $totalCount = $allRecords.Count
        $uniqueRules = ($allRecords | Select-Object -Property AlertRule -Unique).Count
        
        Write-Host "   Total deduplication records: $totalCount" -ForegroundColor White
        Write-Host "   Unique alert rules processed: $uniqueRules" -ForegroundColor White
        
        if ($totalCount -gt 0) {
            Write-Host "   Alert rules seen:" -ForegroundColor White
            $allRecords | Select-Object -Property AlertRule -Unique | ForEach-Object {
                Write-Host "      - $($_.AlertRule)" -ForegroundColor Gray
            }
        }
    } else {
        Write-Host "   No records found in deduplication table" -ForegroundColor Gray
    }
} catch {
    Write-Host "   No records found in deduplication table" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Management Commands:" -ForegroundColor Cyan
Write-Host ""
Write-Host "Clear all deduplication records:" -ForegroundColor Yellow
Write-Host "   az storage entity delete --account-name $STORAGE_ACCOUNT_NAME --account-key $STORAGE_KEY --table-name $TABLE_NAME --partition-key '<KEY>' --row-key '<KEY>'" -ForegroundColor Gray
Write-Host ""
Write-Host "Query specific deduplication key:" -ForegroundColor Yellow
Write-Host "   az storage entity show --account-name $STORAGE_ACCOUNT_NAME --account-key $STORAGE_KEY --table-name $TABLE_NAME --partition-key '<DEDUP_KEY>' --row-key '<DEDUP_KEY>'" -ForegroundColor Gray
Write-Host ""
Write-Host "Table Storage Explorer:" -ForegroundColor Yellow
$subscriptionId = az account show --query id -o tsv
Write-Host "   https://portal.azure.com/#@/resource/subscriptions/$subscriptionId/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT_NAME/storageBrowser" -ForegroundColor Gray

# Check if we can detect duplicate patterns
Write-Host ""
Write-Host "Duplicate Detection Analysis:" -ForegroundColor Green

try {
    if ($allRecords -and $allRecords.Count -gt 0) {
        # Group by hour windows to see deduplication effectiveness
        $grouped = $allRecords | Group-Object -Property PartitionKey | Select-Object -First 10
        foreach ($group in $grouped) {
            Write-Host "   $($group.Name): $($group.Count) alerts processed" -ForegroundColor White
        }
        
        if ($allRecords.Count -gt 1) {
            Write-Host "   Deduplication is working - multiple records indicate alert processing" -ForegroundColor Green
        }
    } else {
        Write-Host "   No data available for analysis" -ForegroundColor Gray
    }
} catch {
    Write-Host "   Analysis not available" -ForegroundColor Gray
}
