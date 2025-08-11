# Clear Deduplication Table Script
# This script clears all records from the Azure Table Storage deduplication table
# Use this for testing purposes when you want to run fresh tests

Write-Host "Clearing Azure Table Storage deduplication records..." -ForegroundColor Yellow

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
    $storageAccount = az keyvault secret show --vault-name $keyVaultName --name "storage-account-name" --query "value" --output tsv
    $accountKey = az keyvault secret show --vault-name $keyVaultName --name "storage-account-key" --query "value" --output tsv
    $tableName = az keyvault secret show --vault-name $keyVaultName --name "storage-table-name" --query "value" --output tsv
    
    if ([string]::IsNullOrEmpty($storageAccount) -or [string]::IsNullOrEmpty($accountKey) -or [string]::IsNullOrEmpty($tableName)) {
        throw "Failed to retrieve storage credentials from Key Vault"
    }
    
    Write-Host "Storage credentials retrieved successfully" -ForegroundColor Green
}
catch {
    Write-Error "Failed to retrieve credentials from Key Vault: $_"
    Write-Host "Make sure you have access to the Key Vault and the secrets exist." -ForegroundColor Yellow
    exit 1
}

try {
    # Query all records
    Write-Host "Querying existing records..."
    $records = az storage entity query --account-name $storageAccount --account-key $accountKey --table-name $tableName --output json | ConvertFrom-Json
    
    if ($records.items.Count -eq 0) {
        Write-Host "No records found to delete." -ForegroundColor Green
        return
    }
    
    Write-Host "Found $($records.items.Count) records to delete..." -ForegroundColor Yellow
    
    # Delete each record
    $deletedCount = 0
    foreach ($record in $records.items) {
        try {
            az storage entity delete --account-name $storageAccount --account-key $accountKey --table-name $tableName --partition-key $record.PartitionKey --row-key $record.RowKey --if-match '*' --output none
            $deletedCount++
            Write-Host "." -NoNewline -ForegroundColor Green
        }
        catch {
            Write-Host "X" -NoNewline -ForegroundColor Red
        }
    }
    
    Write-Host ""
    Write-Host "Successfully deleted $deletedCount out of $($records.items.Count) records." -ForegroundColor Green
    
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "Deduplication table cleared. You can now run fresh tests." -ForegroundColor Cyan
