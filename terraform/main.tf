terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Variables
variable "location" {
  description = "Location for all resources"
  type        = string
  default     = "Central US"
}

variable "environment_name" {
  description = "Environment name (dev, test, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name prefix"
  type        = string
  default     = "demo-integration"
}

# Generate unique suffix
resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  unique_suffix = random_id.suffix.hex
  resource_prefix = "${var.project_name}-${var.environment_name}-${local.unique_suffix}"
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "rg-${local.resource_prefix}"
  location = var.location

  tags = {
    Environment = var.environment_name
    Project     = var.project_name
  }
}

# Storage Account
resource "azurerm_storage_account" "main" {
  name                     = "demo${substr(local.unique_suffix, 0, 18)}sa"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  access_tier                     = "Hot"

  tags = {
    Environment = var.environment_name
    Project     = var.project_name
  }
}

# Storage Containers
resource "azurerm_storage_container" "landing" {
  name                  = "landing"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"

  metadata = {
    purpose     = "data-landing-zone"
    environment = var.environment_name
  }
}

resource "azurerm_storage_container" "processed" {
  name                  = "processed"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"

  metadata = {
    purpose     = "processed-data"
    environment = var.environment_name
  }
}

# Service Bus Namespace
resource "azurerm_servicebus_namespace" "main" {
  name                = "demo${substr(local.unique_suffix, 0, 20)}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"

  minimum_tls_version = "1.2"

  tags = {
    Environment = var.environment_name
    Project     = var.project_name
  }
}

# Service Bus Queues
resource "azurerm_servicebus_queue" "inbound" {
  name         = "inbound"
  namespace_id = azurerm_servicebus_namespace.main.id

  max_size_in_megabytes                = 1024
  default_message_ttl                  = "PT24H"
  lock_duration                        = "PT30S"
  dead_lettering_on_message_expiration = true
  batched_operations_enabled            = true
}

resource "azurerm_servicebus_queue" "outbound" {
  name         = "outbound"
  namespace_id = azurerm_servicebus_namespace.main.id

  max_size_in_megabytes                = 1024
  default_message_ttl                  = "PT24H"
  lock_duration                        = "PT30S"
  dead_lettering_on_message_expiration = true
  batched_operations_enabled            = true
}

# Service Bus Authorization Rule (for connection string)
# Use data source to reference the default RootManageSharedAccessKey that Azure creates automatically
data "azurerm_servicebus_namespace_authorization_rule" "root" {
  name         = "RootManageSharedAccessKey"
  namespace_id = azurerm_servicebus_namespace.main.id
}

# Log Analytics Workspace
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${lower(local.resource_prefix)}-law"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = {
    Environment = var.environment_name
    Project     = var.project_name
  }
}

# Application Insights (linked to Log Analytics Workspace)
resource "azurerm_application_insights" "main" {
  name                = "${local.resource_prefix}-insights"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.main.id

  tags = {
    Environment = var.environment_name
    Project     = var.project_name
  }
}

# App Service Plan (Consumption)
resource "azurerm_service_plan" "functions" {
  name                = "${lower(local.resource_prefix)}-func-plan"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = "Y1"

  tags = {
    Environment = var.environment_name
    Project     = var.project_name
  }
}

# Function App
resource "azurerm_linux_function_app" "main" {
  name                = "${lower(local.resource_prefix)}-func"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.functions.id

  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key

  identity {
    type = "SystemAssigned"
  }

  app_settings = {
    "AzureWebJobsStorage"                        = azurerm_storage_account.main.primary_connection_string
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING"   = azurerm_storage_account.main.primary_connection_string
    "WEBSITE_CONTENTSHARE"                        = lower("${local.resource_prefix}-func")
    "FUNCTIONS_EXTENSION_VERSION"                 = "~4"
    "FUNCTIONS_WORKER_RUNTIME"                    = "powershell"
    "APPINSIGHTS_INSTRUMENTATIONKEY"              = azurerm_application_insights.main.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING"      = azurerm_application_insights.main.connection_string
    "ServiceBusConnection__fullyQualifiedNamespace" = "${azurerm_servicebus_namespace.main.name}.servicebus.windows.net"
    "WEBSITE_ENABLE_SYNC_UPDATE_SITE"            = "true"
    "AzureWebJobsFeatureFlags"                   = "EnableWorkerIndexing"
  }

  site_config {
    application_insights_key               = azurerm_application_insights.main.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.main.connection_string
    http2_enabled                          = true
    ftps_state                             = "Disabled"
    always_on                              = false
  }

  tags = {
    Environment = var.environment_name
    Project     = var.project_name
  }
}

# Role Assignment: Storage Blob Data Contributor
resource "azurerm_role_assignment" "function_storage_blob" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Role Assignment: Service Bus Data Receiver
resource "azurerm_role_assignment" "function_sb_receiver" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Azure Service Bus Data Receiver"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Role Assignment: Service Bus Data Sender
resource "azurerm_role_assignment" "function_sb_sender" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Azure Service Bus Data Sender"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# API Management
resource "azurerm_api_management" "main" {
  name                = "${lower(local.resource_prefix)}-apim"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  publisher_name      = "Demo Integration"
  publisher_email     = "demo@example.com"

  sku_name = "Consumption_0"

  identity {
    type = "SystemAssigned"
  }

  tags = {
    Environment = var.environment_name
    Project     = var.project_name
  }
}

# API Management API
resource "azurerm_api_management_api" "vendor_ingest" {
  name                = "vendor-ingest"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  revision            = "1"
  display_name        = "Vendor Ingest API"
  path                = "vendor-ingest"
  protocols           = ["https"]
  service_url         = "https://${azurerm_linux_function_app.main.default_hostname}"
}

# API Management Backend
resource "azurerm_api_management_backend" "function_app" {
  name                = "function-app-backend"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.main.name
  protocol            = "http"
  url                 = "https://${azurerm_linux_function_app.main.default_hostname}"
  description         = "Azure Function App Backend"
}

# API Management Operation
resource "azurerm_api_management_api_operation" "post_vendors" {
  operation_id        = "post-vendors"
  api_name            = azurerm_api_management_api.vendor_ingest.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name
  display_name        = "Post Vendors"
  method              = "POST"
  url_template        = "/vendors"
}

# API Management Policy
resource "azurerm_api_management_api_policy" "vendor_ingest" {
  api_name            = azurerm_api_management_api.vendor_ingest.name
  api_management_name = azurerm_api_management.main.name
  resource_group_name = azurerm_resource_group.main.name

  xml_content = <<XML
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
XML
}

# Get current subscription
data "azurerm_client_config" "current" {}

# Service Bus Connection for Logic App (must be created before Logic App)
resource "azurerm_api_connection" "servicebus" {
  name                = "${lower(local.resource_prefix)}-logicapp-servicebus"
  resource_group_name = azurerm_resource_group.main.name
  managed_api_id      = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.main.location}/managedApis/servicebus"
  display_name        = "Service Bus Connection"

  parameter_values = {
    connectionString = data.azurerm_servicebus_namespace_authorization_rule.root.primary_connection_string
  }
}

# Logic App
resource "azurerm_logic_app_workflow" "main" {
  name                = "${lower(local.resource_prefix)}-logicapp"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  identity {
    type = "SystemAssigned"
  }


  tags = {
    Environment = var.environment_name
    Project     = var.project_name
  }

  depends_on = [azurerm_api_connection.servicebus]
}

# Diagnostic Settings for Logic App - sends Run History to Log Analytics Workspace
resource "azurerm_monitor_diagnostic_setting" "logic_app" {
  name                       = "${lower(local.resource_prefix)}-logicapp-diag"
  target_resource_id         = azurerm_logic_app_workflow.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "WorkflowRuntime"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Note: Logic App workflow definition should be configured via Azure Portal or CLI after creation
# The Logic App resource is created here, but the workflow definition needs to be set separately

# Outputs
output "resource_group_name" {
  value       = azurerm_resource_group.main.name
  description = "Name of the resource group"
}

output "storage_account_name" {
  value       = azurerm_storage_account.main.name
  description = "Name of the storage account"
}

output "function_app_name" {
  value       = azurerm_linux_function_app.main.name
  description = "Name of the Function App"
}

output "function_app_hostname" {
  value       = azurerm_linux_function_app.main.default_hostname
  description = "Hostname of the Function App"
}

output "apim_service_name" {
  value       = azurerm_api_management.main.name
  description = "Name of the API Management service"
}

output "apim_gateway_url" {
  value       = "https://${azurerm_api_management.main.name}.azure-api.net"
  description = "Gateway URL of the API Management service"
}

output "service_bus_namespace" {
  value       = azurerm_servicebus_namespace.main.name
  description = "Name of the Service Bus namespace"
}

output "logic_app_name" {
  value       = azurerm_logic_app_workflow.main.name
  description = "Name of the Logic App"
}

output "app_insights_name" {
  value       = azurerm_application_insights.main.name
  description = "Name of the Application Insights instance"
}

output "app_insights_instrumentation_key" {
  value       = azurerm_application_insights.main.instrumentation_key
  description = "Instrumentation key for Application Insights"
  sensitive   = true
}

output "log_analytics_workspace_id" {
  value       = azurerm_log_analytics_workspace.main.id
  description = "ID of the Log Analytics Workspace"
}

output "log_analytics_workspace_name" {
  value       = azurerm_log_analytics_workspace.main.name
  description = "Name of the Log Analytics Workspace"
}

