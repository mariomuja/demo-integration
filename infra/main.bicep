targetScope = 'resourceGroup'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment name (dev, test, prod)')
param environmentName string = 'dev'

@description('Project name prefix')
param projectName string = 'demo-integration'

@description('Application Insights instrumentation key')
param appInsightsInstrumentationKey string = ''

// Generate unique suffix
var uniqueSuffix = uniqueString(resourceGroup().id, subscription().id)
var resourcePrefix = '${projectName}-${environmentName}-${uniqueSuffix}'

// Storage Account
module storageAccount 'modules/storage.bicep' = {
  name: 'storageDeployment'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    environmentName: environmentName
  }
}

// Service Bus
module serviceBus 'modules/servicebus.bicep' = {
  name: 'serviceBusDeployment'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    environmentName: environmentName
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${resourcePrefix}-insights'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: ''
  }
}

// Functions App
module functionsApp 'modules/functions.bicep' = {
  name: 'functionsDeployment'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    environmentName: environmentName
    storageAccountName: storageAccount.outputs.storageAccountName
    serviceBusNamespace: serviceBus.outputs.namespaceName
    appInsightsInstrumentationKey: appInsights.properties.InstrumentationKey
  }
}

// API Management
module apim 'modules/apim.bicep' = {
  name: 'apimDeployment'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    environmentName: environmentName
    functionAppName: functionsApp.outputs.functionAppName
    functionAppHostName: functionsApp.outputs.functionAppHostName
  }
}

// Logic App
module logicApp 'modules/logicapp.bicep' = {
  name: 'logicAppDeployment'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    environmentName: environmentName
    storageAccountName: storageAccount.outputs.storageAccountName
    serviceBusConnectionString: serviceBus.outputs.connectionString
  }
}

// Outputs
output resourceGroupName string = resourceGroup().name
output storageAccountName string = storageAccount.outputs.storageAccountName
output functionAppName string = functionsApp.outputs.functionAppName
output functionAppHostName string = functionsApp.outputs.functionAppHostName
output apimServiceName string = apim.outputs.apimServiceName
output apimGatewayUrl string = apim.outputs.gatewayUrl
output serviceBusNamespace string = serviceBus.outputs.namespaceName
output logicAppName string = logicApp.outputs.logicAppName
output appInsightsName string = appInsights.name
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey

