#Requires -Version 5.1

<#
.SYNOPSIS
    Deploys the complete Azure Integration Demo infrastructure
    
.DESCRIPTION
    Deploys all Azure resources using Bicep templates. Uses Managed Identities
    throughout - no secrets required.
    
.EXAMPLE
    .\scripts\deploy-demo.ps1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "rg-demo-integration-$(Get-Date -Format 'yyyyMMdd-HHmmss')",
    
    [Parameter(Mandatory = $false)]
    [string]$Location = "West Europe",
    
    [Parameter(Mandatory = $false)]
    [string]$EnvironmentName = "dev"
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] " -NoNewline -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor White
}

function Write-Success {
    param([string]$Message)
    Write-Host "  [OK] " -NoNewline -ForegroundColor Green
    Write-Host $Message -ForegroundColor Gray
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "  [ERROR] " -NoNewline -ForegroundColor Red
    Write-Host $Message -ForegroundColor Yellow
}

# Check prerequisites
Write-Step "Checking prerequisites..."

try {
    $azContext = az account show 2>$null | ConvertFrom-Json
    if (-not $azContext) {
        throw "Not logged in"
    }
    Write-Success "Azure CLI authenticated (Subscription: $($azContext.name))"
} catch {
    Write-Error-Custom "Please login: az login"
    exit 1
}

# Check Bicep (ignore warnings)
$ErrorActionPreference = "SilentlyContinue"
az bicep version | Out-Null
$bicepAvailable = $LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq $null
$ErrorActionPreference = "Stop"
if ($bicepAvailable) {
    Write-Success "Bicep CLI available"
} else {
    Write-Error-Custom "Install Bicep: az bicep install"
    exit 1
}

# Create resource group
Write-Step "Creating resource group: $ResourceGroupName"

$rg = az group create `
    --name $ResourceGroupName `
    --location $Location `
    --output json 2>$null | ConvertFrom-Json

if (-not $rg) {
    Write-Error-Custom "Failed to create resource group"
    exit 1
}
Write-Success "Resource group created"

# Deploy infrastructure
Write-Step "Deploying infrastructure with Bicep..."

$deploymentName = "demo-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$deploymentPath = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) "infra") "main.bicep"

az deployment group create `
    --resource-group $ResourceGroupName `
    --name $deploymentName `
    --template-file $deploymentPath `
    --parameters environmentName=$EnvironmentName `
    --output json | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Error-Custom "Infrastructure deployment failed"
    exit 1
}
Write-Success "Infrastructure deployed"

# Get outputs
Write-Step "Retrieving deployment outputs..."

$outputs = az deployment group show `
    --resource-group $ResourceGroupName `
    --name $deploymentName `
    --query "properties.outputs" `
    --output json | ConvertFrom-Json

$functionAppName = $outputs.functionAppName.value
$storageAccountName = $outputs.storageAccountName.value
$apimServiceName = $outputs.apimServiceName.value

Write-Success "Function App: $functionAppName"
Write-Success "Storage Account: $storageAccountName"
Write-Success "API Management: $apimServiceName"

# Deploy functions
Write-Step "Deploying Azure Functions..."

$functionsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "functions"
$tempZip = New-TemporaryFile
Remove-Item $tempZip -Force
$tempZip = "$tempZip.zip"

Compress-Archive -Path "$functionsPath\*" -DestinationPath $tempZip -Force

Write-Host "  -> Waiting for Function App to be ready..." -ForegroundColor Gray
Start-Sleep -Seconds 30

az functionapp deployment source config-zip `
    --resource-group $ResourceGroupName `
    --name $functionAppName `
    --src $tempZip | Out-Null

Remove-Item $tempZip -Force

if ($LASTEXITCODE -eq 0) {
    Write-Success "Functions deployed"
} else {
    Write-Error-Custom "Function deployment failed"
    exit 1
}

# Wait for functions to initialize
Write-Step "Waiting for functions to initialize..."
Start-Sleep -Seconds 20

# Save deployment info
$deploymentInfo = @{
    ResourceGroupName = $ResourceGroupName
    FunctionAppName = $functionAppName
    StorageAccountName = $storageAccountName
    ApimServiceName = $apimServiceName
    DeploymentName = $deploymentName
}

$infoPath = Join-Path (Split-Path $PSScriptRoot -Parent) ".deployment-info.json"
$deploymentInfo | ConvertTo-Json | Set-Content $infoPath

Write-Step "Deployment completed successfully!"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Run: .\scripts\simulate-flow.ps1" -ForegroundColor Cyan
Write-Host "  2. Or specify resource group: .\scripts\simulate-flow.ps1 -ResourceGroupName $ResourceGroupName" -ForegroundColor Cyan
Write-Host ""
