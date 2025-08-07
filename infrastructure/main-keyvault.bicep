@description('The environment name (dev, staging, prod)')
param environmentName string = 'dev'

@description('The location for all resources')
param location string = resourceGroup().location

@description('The resource token for unique naming')
param resourceToken string = uniqueString(resourceGroup().id)

// Variables
var storageAccountName = 'alertdedup${resourceToken}'
var logicAppName = 'alertdedup-logicapp-${environmentName}'
var appServicePlanName = 'asp-mockservicenow-${environmentName}'
var appServiceName = 'mockservicenow-${resourceToken}'
var actionGroupName = 'ag-cdn-alerts-${environmentName}'
var keyVaultName = 'kv-${take(resourceToken, 18)}'
var managedIdentityName = 'mi-alertdedup-${environmentName}'

// User-assigned managed identity for Logic App
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
  tags: {
    'azd-env-name': environmentName
  }
}

// Storage Account for deduplication tracking
resource storageAccount 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageAccountName
  location: location
  tags: {
    'azd-env-name': environmentName
  }
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

// Table service for deduplication records
resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2022-09-01' = {
  parent: storageAccount
  name: 'default'
  properties: {}
}

// Deduplication table
resource deduplicationTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2022-09-01' = {
  parent: tableService
  name: 'AlertDeduplication'
}

// Key Vault for storing secrets
resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: keyVaultName
  location: location
  tags: {
    'azd-env-name': environmentName
  }
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenant().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
  }
}

// Store storage account key in Key Vault
resource storageKeySecret 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  parent: keyVault
  name: 'storage-account-key'
  properties: {
    value: storageAccount.listKeys().keys[0].value
  }
}

// Grant Key Vault Secrets User role to managed identity
resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, managedIdentity.id, 'Key Vault Secrets User')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// App Service Plan for Mock ServiceNow API
resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: appServicePlanName
  location: location
  tags: {
    'azd-env-name': environmentName
  }
  sku: {
    name: 'B1'
    tier: 'Basic'
  }
  properties: {
    reserved: false
  }
}

// App Service for Mock ServiceNow API
resource appService 'Microsoft.Web/sites@2022-09-01' = {
  name: appServiceName
  location: location
  tags: {
    'azd-env-name': environmentName
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      appSettings: [
        {
          name: 'NODE_ENV'
          value: 'production'
        }
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'false'
        }
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
      ]
      cors: {
        allowedOrigins: ['*']
        supportCredentials: false
      }
      nodeVersion: '~18'
    }
  }
}

// Logic App with complete secure workflow for ServiceNow integration
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  tags: {
    'azd-env-name': environmentName
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        storageAccountName: {
          type: 'String'
        }
        keyVaultUri: {
          type: 'String'
        }
        mockServiceNowUrl: {
          type: 'String'
        }
        managedIdentityClientId: {
          type: 'String'
        }
        managedIdentityResourceId: {
          type: 'String'
        }
        storageEndpointSuffix: {
          type: 'String'
        }
      }
      triggers: {
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              properties: {
                schemaId: {
                  type: 'string'
                }
                data: {
                  type: 'object'
                  properties: {
                    essentials: {
                      type: 'object'
                      properties: {
                        alertId: {
                          type: 'string'
                        }
                        alertRule: {
                          type: 'string'
                        }
                        severity: {
                          type: 'string'
                        }
                        description: {
                          type: 'string'
                        }
                        firedDateTime: {
                          type: 'string'
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
      actions: {
        Immediate_Response: {
          runAfter: {}
          type: 'Response'
          inputs: {
            statusCode: 202
            body: {
              message: 'Alert received and processing started'
              alertId: '@{triggerBody()?[\'data\']?[\'essentials\']?[\'alertId\']}'
              alertRule: '@{triggerBody()?[\'data\']?[\'essentials\']?[\'alertRule\']}'
              deduplicationKey: '@{triggerBody()?[\'data\']?[\'essentials\']?[\'alertRule\']}-@{formatDateTime(utcNow(), \'yyyy-MM-dd-HH\')}'
              timestamp: '@{utcNow()}'
              status: 'processing'
            }
          }
        }
        Get_Storage_Key_From_KeyVault: {
          runAfter: {
            Immediate_Response: [
              'Succeeded'
            ]
          }
          type: 'Http'
          inputs: {
            uri: '@{parameters(\'keyVaultUri\')}secrets/storage-account-key?api-version=7.3'
            method: 'GET'
            authentication: {
              type: 'ManagedServiceIdentity'
              identity: '@{parameters(\'managedIdentityResourceId\')}'
            }
          }
        }
        Initialize_Deduplication_Key: {
          runAfter: {
            Get_Storage_Key_From_KeyVault: [
              'Succeeded'
            ]
          }
          type: 'InitializeVariable'
          inputs: {
            variables: [
              {
                name: 'DeduplicationKey'
                type: 'String'
                value: '@{triggerBody()?[\'data\']?[\'essentials\']?[\'alertRule\']}-@{formatDateTime(utcNow(), \'yyyy-MM-dd-HH\')}'
              }
            ]
          }
        }
        Check_Deduplication_Table: {
          runAfter: {
            Initialize_Deduplication_Key: [
              'Succeeded'
            ]
          }
          type: 'Http'
          inputs: {
            uri: 'https://@{parameters(\'storageAccountName\')}.table.@{parameters(\'storageEndpointSuffix\')}/AlertDeduplication(PartitionKey=\'@{variables(\'DeduplicationKey\')}\',RowKey=\'@{variables(\'DeduplicationKey\')}\')'
            method: 'GET'
            headers: {
              Accept: 'application/json;odata=nometadata'
              'x-ms-date': '@{formatDateTime(utcNow(), \'ddd, dd MMM yyyy HH:mm:ss\')} GMT'
              'x-ms-version': '2019-07-07'
              Authorization: 'SharedKey @{parameters(\'storageAccountName\')}:@{base64(hmacSha256(concat(\'GET\', char(10), char(10), char(10), char(10), \'application/json;odata=nometadata\', char(10), char(10), char(10), char(10), char(10), char(10), formatDateTime(utcNow(), \'ddd, dd MMM yyyy HH:mm:ss\'), \' GMT\', char(10), \'/\', parameters(\'storageAccountName\'), \'/AlertDeduplication(PartitionKey=\'\'\', encodeUriComponent(variables(\'DeduplicationKey\')), \'\'\',RowKey=\'\'\', encodeUriComponent(variables(\'DeduplicationKey\')), \'\'\')\'), base64(outputs(\'Get_Storage_Key_From_KeyVault\')?[\'body\']?[\'value\'])))}'
            }
          }
        }
        Check_If_Duplicate: {
          runAfter: {
            Check_Deduplication_Table: [
              'Succeeded'
              'Failed'
            ]
          }
          type: 'If'
          expression: {
            and: [
              {
                equals: [
                  '@outputs(\'Check_Deduplication_Table\')[\'statusCode\']'
                  200
                ]
              }
            ]
          }
          actions: {
            Log_Duplicate_Suppressed: {
              type: 'Compose'
              inputs: {
                message: 'Duplicate alert suppressed'
                deduplicationKey: '@{variables(\'DeduplicationKey\')}'
                timestamp: '@{utcNow()}'
              }
            }
          }
          else: {
            actions: {
              Store_Deduplication_Record: {
                type: 'Http'
                inputs: {
                  uri: 'https://@{parameters(\'storageAccountName\')}.table.@{parameters(\'storageEndpointSuffix\')}/AlertDeduplication'
                  method: 'POST'
                  headers: {
                    Accept: 'application/json;odata=nometadata'
                    'Content-Type': 'application/json'
                    'x-ms-date': '@{formatDateTime(utcNow(), \'ddd, dd MMM yyyy HH:mm:ss\')} GMT'
                    'x-ms-version': '2019-07-07'
                    Authorization: 'SharedKey @{parameters(\'storageAccountName\')}:@{base64(hmacSha256(concat(\'POST\', char(10), char(10), char(10), \'application/json\', char(10), \'application/json;odata=nometadata\', char(10), char(10), char(10), char(10), char(10), char(10), formatDateTime(utcNow(), \'ddd, dd MMM yyyy HH:mm:ss\'), \' GMT\', char(10), \'/\', parameters(\'storageAccountName\'), \'/AlertDeduplication\'), base64(outputs(\'Get_Storage_Key_From_KeyVault\')?[\'body\']?[\'value\'])))}'
                  }
                  body: {
                    PartitionKey: '@{variables(\'DeduplicationKey\')}'
                    RowKey: '@{variables(\'DeduplicationKey\')}'
                    AlertRule: '@{triggerBody()?[\'data\']?[\'essentials\']?[\'alertRule\']}'
                    AlertId: '@{triggerBody()?[\'data\']?[\'essentials\']?[\'alertId\']}'
                    ProcessedDateTime: '@{utcNow()}'
                    Severity: '@{triggerBody()?[\'data\']?[\'essentials\']?[\'severity\']}'
                  }
                }
              }
              Create_ServiceNow_Ticket: {
                runAfter: {
                  Store_Deduplication_Record: [
                    'Succeeded'
                  ]
                }
                type: 'Http'
                inputs: {
                  uri: '@{parameters(\'mockServiceNowUrl\')}/api/now/table/incident'
                  method: 'POST'
                  headers: {
                    Accept: 'application/json'
                    'Content-Type': 'application/json'
                    Authorization: 'Basic QVpVUkVfSU5TSUdIVDpII1hkW3UxbikmaztDc3A/T2ZZIzA5OV8+QE07UjlbcSFSamJXUCs5'
                  }
                  body: {
                    caller_id: 'e8600d0e1bb4ea10523aca67624bcb4b'
                    assignment_group: '12503dd987754e502421ff78cebb35bd'
                    short_description: 'DEDUPLICATED CDN Alert: @{triggerBody()?[\'data\']?[\'essentials\']?[\'alertRule\']}'
                    description: '@{triggerBody()?[\'data\']?[\'essentials\']?[\'description\']} - Deduplication Key: @{variables(\'DeduplicationKey\')} - Processed at: @{utcNow()}'
                    impact: '2'
                    urgency: '2'
                  }
                  retryPolicy: {
                    type: 'exponential'
                    count: 3
                    interval: 'PT10S'
                    maximumInterval: 'PT1M'
                  }
                }
              }
              Handle_ServiceNow_Response: {
                runAfter: {
                  Create_ServiceNow_Ticket: [
                    'Succeeded'
                    'Failed'
                  ]
                }
                type: 'If'
                expression: {
                  and: [
                    {
                      greater: [
                        '@outputs(\'Create_ServiceNow_Ticket\')[\'statusCode\']'
                        199
                      ]
                    }
                    {
                      less: [
                        '@outputs(\'Create_ServiceNow_Ticket\')[\'statusCode\']'
                        300
                      ]
                    }
                  ]
                }
                actions: {
                  Log_Success: {
                    type: 'Compose'
                    inputs: {
                      message: 'ServiceNow ticket created successfully'
                      ticketNumber: '@{outputs(\'Create_ServiceNow_Ticket\')?[\'body\']?[\'result\']?[\'number\']}'
                      deduplicationKey: '@{variables(\'DeduplicationKey\')}'
                      timestamp: '@{utcNow()}'
                    }
                  }
                }
                else: {
                  actions: {
                    Log_Failure: {
                      type: 'Compose'
                      inputs: {
                        message: 'Failed to create ServiceNow ticket'
                        error: '@{outputs(\'Create_ServiceNow_Ticket\')}'
                        deduplicationKey: '@{variables(\'DeduplicationKey\')}'
                        timestamp: '@{utcNow()}'
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
      outputs: {}
    }
    parameters: {
      storageAccountName: {
        value: storageAccount.name
      }
      keyVaultUri: {
        value: keyVault.properties.vaultUri
      }
      mockServiceNowUrl: {
        value: 'https://${appService.properties.defaultHostName}'
      }
      managedIdentityClientId: {
        value: managedIdentity.properties.clientId
      }
      managedIdentityResourceId: {
        value: managedIdentity.id
      }
      storageEndpointSuffix: {
        value: environment().suffixes.storage
      }
    }
  }
  dependsOn: [
    keyVaultRoleAssignment
  ]
}

// Action Group for CDN Alerts (will be updated with Logic App URL after deployment)
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'Global'
  tags: {
    'azd-env-name': environmentName
  }
  properties: {
    groupShortName: 'CDNAlerts'
    enabled: true
    emailReceivers: []
    smsReceivers: []
    webhookReceivers: []
    itsmReceivers: []
    azureAppPushReceivers: []
    automationRunbookReceivers: []
    voiceReceivers: []
    logicAppReceivers: []
    azureFunctionReceivers: []
    armRoleReceivers: []
  }
}

// Outputs
output storageAccountName string = storageAccount.name
output logicAppName string = logicApp.name
output appServiceName string = appService.name
output appServiceUrl string = 'https://${appService.properties.defaultHostName}'
output actionGroupName string = actionGroup.name
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output managedIdentityName string = managedIdentity.name
output managedIdentityClientId string = managedIdentity.properties.clientId
output managedIdentityResourceId string = managedIdentity.id
output resourceGroupName string = resourceGroup().name
output subscriptionId string = subscription().subscriptionId
