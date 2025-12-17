@description('Location for Function App')
param location string

@description('Resource name prefix')
param resourcePrefix string

@description('Environment name')
param environmentName string

@description('Storage account name')
param storageAccountName string

@description('Service Bus namespace name')
param serviceBusNamespace string

@description('Application Insights instrumentation key')
param appInsightsInstrumentationKey string

var functionAppName = '${toLower(resourcePrefix)}-func'
var appServicePlanName = '${functionAppName}-plan'

// App Service Plan (Consumption)
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  kind: 'functionapp'
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    reserved: true
  }
}

// Storage account reference
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

// Function App
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
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
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsightsInstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: 'InstrumentationKey=${appInsightsInstrumentationKey}'
        }
        {
          name: 'ServiceBusConnection__fullyQualifiedNamespace'
          value: '${serviceBusNamespace}.servicebus.windows.net'
        }
        {
          name: 'WEBSITE_ENABLE_SYNC_UPDATE_SITE'
          value: 'true'
        }
        {
          name: 'AzureWebJobsFeatureFlags'
          value: 'EnableWorkerIndexing'
        }
      ]
      linuxFxVersion: 'POWERSHELL|7.4'
      http20Enabled: true
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
    }
    httpsOnly: true
  }
}

// Role assignment: Storage Blob Data Contributor
resource storageBlobContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, 'StorageBlobDataContributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role assignment: Service Bus Data Receiver
resource serviceBusDataReceiver 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, 'ServiceBusDataReceiver')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Role assignment: Service Bus Data Sender
resource serviceBusDataSender 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, 'ServiceBusDataSender')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output functionAppName string = functionApp.name
output functionAppHostName string = functionApp.properties.defaultHostName
output functionAppId string = functionApp.id
output managedIdentityPrincipalId string = functionApp.identity.principalId

