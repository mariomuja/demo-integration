# Logic App Workflow

This folder contains the Logic App workflow definition for the demo integration.

## Workflow Overview

The Logic App processes messages from the Service Bus `inbound` queue and forwards them to the `outbound` queue.

### Workflow Steps

1. **Trigger**: When messages arrive in the `inbound` Service Bus queue
   - Polls every 10 seconds
   - Retrieves 1 message at a time

2. **Parse Message**: Parses the JSON message content
   - Extracts: id, correlationId, timestamp, source, data

3. **Send to Outbound Queue**: Forwards the parsed message to the `outbound` queue

4. **Complete Message**: Marks the original message as completed in the `inbound` queue

## Deployment

The Logic App resource is created via Terraform (`terraform/main.tf`), but the workflow definition (`workflow.json`) needs to be deployed separately using:

```powershell
# After Terraform deployment, update the Logic App workflow
az logicapp workflow update `
  --resource-group <resource-group-name> `
  --name <logic-app-name> `
  --definition logicapp/workflow.json
```

Or via Azure Portal:
1. Navigate to the Logic App resource
2. Go to "Logic app designer"
3. Import the `workflow.json` file

## Parameters

The workflow requires a Service Bus connection parameter (`$connections`) which is automatically configured when the Logic App is created with the Service Bus API connection.

