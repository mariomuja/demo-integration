@description('Location for API Management')
param location string

@description('Resource name prefix')
param resourcePrefix string

@description('Environment name')
param environmentName string

@description('Function App name')
param functionAppName string

@description('Function App hostname')
param functionAppHostName string

var apimServiceName = '${toLower(resourcePrefix)}-apim'

resource apimService 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: apimServiceName
  location: location
  sku: {
    name: 'Consumption'
    capacity: 0
  }
  properties: {
    publisherName: 'Demo Integration'
    publisherEmail: 'demo@example.com'
    notificationSenderEmail: 'apimgmt-noreply@mail.windowsazure.com'
    publicNetworkAccess: 'Enabled'
    virtualNetworkType: 'None'
    disableGateway: false
    apiVersionConstraint: {}
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// API
resource api 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apimService
  name: 'vendor-ingest'
  properties: {
    displayName: 'Vendor Ingest API'
    description: 'API for ingesting vendor data'
    serviceUrl: 'https://${functionAppHostName}'
    path: 'vendor-ingest'
    protocols: [
      'https'
    ]
    subscriptionRequired: false
    format: 'openapi+json'
    value: '''
      openapi: 3.0.0
      info:
        title: Vendor Ingest API
        version: 1.0.0
      paths:
        /vendors:
          post:
            summary: Ingest vendor data
            operationId: ingestVendor
            responses:
              '200':
                description: Success
              '400':
                description: Bad Request
    '''
  }
}

// Operation: POST /vendors
resource postVendorsOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: api
  name: 'post-vendors'
  properties: {
    displayName: 'Post Vendors'
    method: 'POST'
    urlTemplate: '/vendors'
  }
}

// Backend: Function App
resource functionBackend 'Microsoft.ApiManagement/service/backends@2023-05-01-preview' = {
  parent: apimService
  name: 'function-app-backend'
  properties: {
    url: 'https://${functionAppHostName}'
    protocol: 'http'
    description: 'Azure Function App Backend'
  }
}

// Policy: Forward to backend
resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: api
  name: 'policy'
  properties: {
    format: 'xml'
    value: '''
      <policies>
        <inbound>
          <base />
          <set-backend-service backend-id="function-app-backend" />
          <rewrite-uri template="/api/HttpIngest" />
        </inbound>
        <backend>
          <base />
        </backend>
        <outbound>
          <base />
        </outbound>
        <on-error>
          <base />
        </on-error>
      </policies>
    '''
  }
}

output apimServiceName string = apimService.name
output gatewayUrl string = 'https://${apimService.name}.azure-api.net'
output apiId string = api.id

