@description('Location for the storage account')
param location string

@description('Resource name prefix')
param resourcePrefix string

@description('Environment name')
param environmentName string

// Storage account name (must be globally unique, lowercase, 3-24 chars)
var storageAccountName = '${toLower(resourcePrefix)}sa'

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    accessTier: 'Hot'
  }
}

// Container for landing zone
resource landingContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: 'landing'
  parent: storageAccount::blobServices
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'data-landing-zone'
      environment: environmentName
    }
  }
}

// Container for processed data
resource processedContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: 'processed'
  parent: storageAccount::blobServices
  properties: {
    publicAccess: 'None'
    metadata: {
      purpose: 'processed-data'
      environment: environmentName
    }
  }
}

output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output primaryEndpoints object = storageAccount.properties.primaryEndpoints

