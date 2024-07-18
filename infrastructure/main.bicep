@description('The Azure Region to deploy the resources into. Default: resourceGroup().location')
param location string = resourceGroup().location

@description('Switch to enable/disable Diagnostic Settings for the Azure resources. Default: false')
param diagnosticSettingsEnabled bool = false

@description('A unique string to add as a suffix to all resources. Default: substring(uniqueString(resourceGroup().id), 0, 5)')
param uniqueSuffix string = substring(uniqueString(resourceGroup().id), 0, 5)

@description('Log Analytics Workspace name. Default: log-mcserverops-$<uniqueSuffix>')
param logAnalyticsWorkspaceName string = 'log-mcserverops-${uniqueSuffix}'

@description('Application Insights name. Default: appi-mcserverops-$<uniqueSuffix>')
param appInsightsName string = 'appi-mcserverops-${uniqueSuffix}'

@description('Storage Account name. Default: stmcserverops$<uniqueSuffix>')
param storageAccountName string = 'stmcserverops${uniqueSuffix}'

@description('Storage Account File Share name: Default: mcserverops')
param storageAccountFileShareName string = 'mcserverops'

@description('Storage Account File Share quota in GB. Default: 5120')
param storageAccountFileShareQuota int = 5120

@allowed([
  'Cool'
  'Hot'
  'TransactionOptimized'
])
@description('Storage Account File Share access tier. Deafult: TransactionOptimized')
param storageAccountFileShareAccessTier string

@description('App Service Plan name. Default: asp-mcserverops-$<uniqueSuffix>')
param appServicePlanName string = 'asp-mcserverops-${uniqueSuffix}'

@description('Function App name. Default: func-mcserverops-$<uniqueSuffix>')
param functionAppName string = 'func-mcserverops-${uniqueSuffix}'

@description('Container Instance name. Default: ci-mcserverops-$<uniqueSuffix>')
param conatinerInstanceName string = 'ci-mcserverops-${uniqueSuffix}'

@description('Docker container image/url. Default: itzg/minecraft-server')
param conatinerInstanceImage string = 'itzg/minecraft-server'

@minValue(1)
@description('Container Instance CPU Count. Default: 2')
param containerInstanceCpu int = 2

@minValue(3)
@description('Container Instance Memory in GB. Default: 5')
param containerInstanceMemory int = 5

@allowed([
  'VANILLA'
  'FORGE'
  'FTBA'
])
@description('Minecraft Server type. Default: VANILLA')
param minecraftServerType string = 'VANILLA'

@description('Event Grid System Topic name. Default: evgst-mcserverops-$<uniqueSuffix>')
param eventGridSystemTopicName string = 'evgst-mcserverops-${uniqueSuffix}'

@description('Event Grid Subscription name. Default: evgs-mcserverops-$<uniqueSuffix>')
param eventGridSubscriptionName string = 'evgs-mcserverops-${uniqueSuffix}'

@secure()
@description('Event Grid Subscription Authorization Principal ID.')
param eventGridSubscriptionAuthorizationPrincipalId string

@description('Existing DNS Zone Subscription ID. Default: subscription().id')
param dnsZoneSubscriptionId string = subscription().id

@description('Existing DNS Zone Resource Group name. Default: resourceGroup().name')
param dnsZoneResourceGroupName string = resourceGroup().name

@description('Existing DNS Zone name (should match domain name)')
param dnsZoneName string

@description('Key Vault name. Default: kv-mcserverops-$<uniqueSuffix>')
param keyVaultName string = 'kv-mcserverops-${uniqueSuffix}'

@secure()
@description('Twilio Subscription phone number in format "+18888888888".')
param twilioPhoneNumber string

@secure()
@description('Twilio Subscription ID (SID).')
param twilioSid string

@secure()
@description('Twilio Subscription Token.')
param twilioToken string

@secure()
@description('Minecraft Server RCON Password.')
param minecraftServerRconPassword string


// Resource Group Lock
resource rgLock 'Microsoft.Authorization/locks@2016-09-01' = {
  scope: resourceGroup()
  name: 'DoNotDelete'
  properties: {
    level: 'CanNotDelete'
    notes: 'This lock prevents the accidental deletion of resources'
  }
}

// RBAC Role definitions
@description('Built-in Key Vault Secrets User role. See https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#key-vault-secrets-user')
resource keyVaultSecretsUserRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: '4633458b-17de-408a-b874-0445c86b69e6'
}

// DNS Zone Role assignment
module funcMIDnsRole 'dns.bicep' = {
  name: 'DNSZoneRoleAssignment'
  scope: resourceGroup(dnsZoneSubscriptionId, dnsZoneResourceGroupName)
  params: {
    dnsZoneName: dnsZoneName
    functionAppId: func.id
    functionAppPrincipalId: func.identity.principalId
    uniqueSuffix: uniqueSuffix
  }
}

@description('Allows Function App Managed Identity to use Key Vault Secrets')
resource funcMIVaultRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(func.id, kv.id, keyVaultSecretsUserRole.id)
  scope: kv
  properties: {
    roleDefinitionId: keyVaultSecretsUserRole.id
    principalId: func.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Log Analytics Workspace
resource log 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }
}

// Application Insights
resource appi 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: log.id
  }
  // Link Application Insights instance to Function App
  tags: {
    'hidden-link:${resourceId('Microsoft.Web/sites', functionAppName)}': 'Resource'
  }
}

// Storage Account
resource st 'Microsoft.Storage/storageAccounts@2022-05-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    allowBlobPublicAccess: false
  }

}

resource stFile 'Microsoft.Storage/storageAccounts/fileServices@2023-05-01' = {
  name: 'default'
  parent: st
}

resource stFileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' = {
  name: storageAccountFileShareName
  parent: stFile
  properties: {
    accessTier: storageAccountFileShareAccessTier
    enabledProtocols: 'SMB'
    shareQuota: storageAccountFileShareQuota
  }
}

// App Service Plan
resource asp 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  kind: 'linux'
  properties: {
    reserved: true
  }
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
}

// Function App
resource func 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    httpsOnly: true
    reserved: true
    serverFarmId: asp.id
    keyVaultReferenceIdentity: 'SystemAssigned'
    siteConfig: {
      linuxFxVersion: 'POWERSHELL|7.4'
      appSettings: [
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appi.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appi.properties.ConnectionString
        }
        {
          name: 'AzureWebJobsStorage'
          value: '@Microsoft.KeyVault(VaultName=${kv.name};SecretName=StorageAccount-ConnectionString)'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'powershell'
        }
        {
          name: 'KEY_VAULT_NAME'
          value: kv.name
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: 'https://github.com/RylandDeGregory/SpotifyExporter/blob/master/src.zip?raw=true'
        }
      ]
      alwaysOn: false
    }
  }
}

// Key Vault
resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    publicNetworkAccess: 'Enabled'
    softDeleteRetentionInDays: 30
    tenantId: tenant().tenantId
  }
}

resource kvSecretStorageCS 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'StorageAccount-ConnectionString'
  parent: kv
  properties: {
    value: 'DefaultEndpointsProtocol=https;AccountName=${st.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${st.listKeys().keys[0].value}'
  }
}

resource kvSecretTwilioPhoneNumber 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'Twilio-PhoneNumber'
  parent: kv
  properties: {
    value: twilioPhoneNumber
  }
}

resource kvSecretTwilioSid 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'Twilio-SID'
  parent: kv
  properties: {
    value: twilioSid
  }
}

resource kvSecretTwilioToken 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'Twilio-Token'
  parent: kv
  properties: {
    value: twilioToken
  }
}

// Container Instance
resource ci 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: conatinerInstanceName
  location: location
  properties: {
    containers: [
      {
        name: 'minecraft'
        properties: {
          environmentVariables: [
            {
              name: 'ALLOW_NETHER'
              value: 'TRUE'
            }
            {
              name: 'ENABLE_RCON'
              value: 'TRUE'
            }
            {
              name: 'EULA'
              value: 'TRUE'
            }
            {
              name: 'MEMORY'
              value: '${containerInstanceMemory - 1}G'
            }
            {
              name: 'RCON_PASSWORD'
              value: minecraftServerRconPassword
            }
            {
              name: 'TYPE'
              value: minecraftServerType != 'VANILLA' ? minecraftServerType : null
            }
          ]
          image: conatinerInstanceImage
          ports: [
            {
              port: 25565
              protocol: 'TCP'
            }
            {
              port: 25575
              protocol: 'TCP'
            }
          ]
          resources: {
            requests: {
              cpu: containerInstanceCpu
              memoryInGB: containerInstanceMemory
            }
            limits: {
              cpu: containerInstanceCpu
              memoryInGB: containerInstanceMemory
            }
          }
          volumeMounts: [
            {
              name: 'minecraft'
              mountPath: '/data'
            }
          ]
        }
      }
    ]
    ipAddress: {
      ports: [
        {
          port: 25565
          protocol: 'TCP'
        }
        {
          port: 25575
          protocol: 'TCP'
        }
      ]
      type: 'Public'
    }
    osType: 'Linux'
    restartPolicy: 'Always'
    sku: 'Standard'
    volumes: [
      {
        name: 'minecraft'
        azureFile: {
          shareName: conatinerInstanceName
          storageAccountName: storageAccountName
          readOnly: false
        }
      }
    ]
  }
}

resource evgst 'Microsoft.EventGrid/systemTopics@2022-06-15' = {
  name: eventGridSystemTopicName
  location: location
  properties: {
    source: resourceGroup().id
    topicType: 'Microsoft.Resources.ResourceGroups'
  }
}

resource evgs 'Microsoft.EventGrid/systemTopics/eventSubscriptions@2022-06-15' = {
  name: eventGridSubscriptionName
  parent: evgst
  properties: {
    destination: {
      endpointType: 'AzureFunction'
      properties: {
        resourceId: '${func.id}/functions/UpdateDNS'
        maxEventsPerBatch: 1
        preferredBatchSizeInKilobytes: 64
      }
    }
    filter: {
      includedEventTypes: [
        'Microsoft.Resources.ResourceActionSuccess'
      ]
      enableAdvancedFilteringOnArrays: true
      advancedFilters: [
        {
          key: 'data.operationName'
          operatorType: 'StringBeginsWith'
          values: [
            'Microsoft.ContainerInstance/containerGroups/start/action'
          ]
        }
        {
          key: 'data.resourceUri'
          operatorType: 'StringContains'
          values: [
            conatinerInstanceName
          ]
        }
        {
          key: 'data.authorization.evidence.principalId'
          operatorType: 'StringNotBeginsWith'
          values: [
            eventGridSubscriptionAuthorizationPrincipalId
          ]
        }
      ]
    }
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 30
      eventTimeToLiveInMinutes: 1440
    }
  }
}
