@description('Location for Service Bus')
param location string

@description('Resource name prefix')
param resourcePrefix string

@description('Environment name')
param environmentName string

// Service Bus namespace name (max 50 chars, alphanumeric and hyphens only, cannot end with '-sb')
// Generate shorter name to ensure it fits
var uniqueId = uniqueString(resourceGroup().id, subscription().id)
var baseName = 'demo${substring(uniqueId, 0, min(20, length(uniqueId)))}'
var namespaceName = toLower(baseName)

resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: namespaceName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {
    minimumTlsVersion: '1.2'
  }
}

// Inbound queue
resource inboundQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: 'inbound'
  properties: {
    maxSizeInMegabytes: 1024
    defaultMessageTimeToLive: 'PT24H'
    lockDuration: 'PT30S'
    requiresDuplicateDetection: false
    deadLetteringOnMessageExpiration: true
    enableBatchedOperations: true
  }
}

// Outbound queue (for processed messages)
resource outboundQueue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: 'outbound'
  properties: {
    maxSizeInMegabytes: 1024
    defaultMessageTimeToLive: 'PT24H'
    lockDuration: 'PT30S'
    requiresDuplicateDetection: false
    deadLetteringOnMessageExpiration: true
    enableBatchedOperations: true
  }
}

output namespaceName string = serviceBusNamespace.name
output namespaceId string = serviceBusNamespace.id
output inboundQueueName string = inboundQueue.name
output outboundQueueName string = outboundQueue.name
output connectionString string = 'Endpoint=sb://${serviceBusNamespace.name}.servicebus.windows.net/;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=${listKeys(serviceBusNamespace.id, serviceBusNamespace.apiVersion).primaryKey}'

