@description('Location for Logic App')
param location string

@description('Resource name prefix')
param resourcePrefix string

@description('Environment name')
param environmentName string

@description('Storage account name')
param storageAccountName string

@description('Service Bus connection string')
param serviceBusConnectionString string

var logicAppName = '${toLower(resourcePrefix)}-logicapp'

resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      triggers: {
        When_messages_arrive_in_queue: {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'servicebus\'].connectionId'
              }
            }
            method: 'get'
            path: '/@{encodeURIComponent(\'inbound\')}/messages/head'
            queries: {
              'queueType': 'Main'
              'maxMessageCount': 1
            }
          }
          recurrence: {
            frequency: 'Second'
            interval: 10
          }
        }
      }
      actions: {
        Process_message: {
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'servicebus\'].connectionId'
              }
            }
            method: 'post'
            path: '/@{encodeURIComponent(\'inbound\')}/messages/@{encodeURIComponent(triggerBody()?[\'ContentData\'])}/complete'
            queries: {
              'lockToken': '@{triggerBody()?[\'ContentData\']}'
            }
          }
          runAfter: {}
        }
      }
      parameters: {
        '$connections': {
          value: {
            servicebus: {
              connectionId: '[resourceId(\'Microsoft.Web/connections\', \'${logicAppName}-servicebus\')]'
              connectionName: '${logicAppName}-servicebus'
              id: '[resourceId(\'Microsoft.Web/connections\', \'${logicAppName}-servicebus\')]'
            }
          }
        }
      }
    }
    parameters: {}
    state: 'Enabled'
  }
}

// Service Bus API Connection
resource serviceBusConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: '${logicAppName}-servicebus'
  location: location
  kind: 'V1'
  properties: {
    displayName: 'Service Bus Connection'
    api: {
      id: subscriptionResourceId('Microsoft.Web/locations', location, 'managedApis', 'servicebus')
    }
    parameterValues: {
      connectionString: serviceBusConnectionString
    }
  }
}

output logicAppName string = logicApp.name
output logicAppId string = logicApp.id

