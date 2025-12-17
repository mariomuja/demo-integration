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

# Clean up old demo resource groups (only those belonging to this repo)
Write-Step "Cleaning up old demo resource groups..."

$ErrorActionPreference = "SilentlyContinue"
# Only find resource groups that match the exact pattern for this demo-integration repo
$oldRgs = az group list --query "[?starts_with(name, 'rg-demo-integration-')].{Name:name, Location:location}" --output json 2>$null | ConvertFrom-Json
$ErrorActionPreference = "Stop"

if ($oldRgs -and $oldRgs.Count -gt 0) {
    Write-Host "  Found $($oldRgs.Count) old resource group(s) belonging to demo-integration" -ForegroundColor Gray
    foreach ($oldRg in $oldRgs) {
        if ($oldRg.Name -ne $ResourceGroupName) {
            Write-Host "  -> Deleting: $($oldRg.Name)..." -ForegroundColor Gray -NoNewline
            az group delete --name $oldRg.Name --yes --no-wait 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host " Done" -ForegroundColor Green
            } else {
                Write-Host " Failed" -ForegroundColor Yellow
            }
        }
    }
    Write-Success "Old demo-integration resource groups cleanup initiated"
} else {
    Write-Success "No old resource groups found"
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
$logicAppName = $outputs.logicAppName.value

Write-Success "Function App: $functionAppName"
Write-Success "Storage Account: $storageAccountName"
Write-Success "API Management: $apimServiceName"
Write-Success "Logic App: $logicAppName"

# Deploy functions
Write-Step "Deploying Azure Functions..."

$functionsPath = Join-Path (Split-Path $PSScriptRoot -Parent) "functions"

# Check if func CLI is available
$funcCheck = func --version 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Error-Custom "Azure Functions Core Tools not found. Install with: npm install -g azure-functions-core-tools@4"
    exit 1
}

# Wait for Function App to be ready (check instead of fixed sleep)
Write-Host "  -> Waiting for Function App to be ready..." -ForegroundColor Gray
$maxRetries = 12
$retryCount = 0
$functionAppReady = $false

while (-not $functionAppReady -and $retryCount -lt $maxRetries) {
    $ErrorActionPreference = "SilentlyContinue"
    $appState = az functionapp show --resource-group $ResourceGroupName --name $functionAppName --query "state" --output tsv 2>&1 | Where-Object { $_ -and $_ -notmatch "Warning" }
    $ErrorActionPreference = "Stop"
    
    if ($appState -eq "Running") {
        $functionAppReady = $true
        Write-Host "    Function App is ready!" -ForegroundColor Green
    } else {
        $retryCount++
        Write-Host "    Waiting... ($retryCount/$maxRetries)" -ForegroundColor Gray
        Start-Sleep -Seconds 5
    }
}

if (-not $functionAppReady) {
    Write-Error-Custom "Function App did not become ready in time"
    exit 1
}

# Deploy using func with --no-selfcontained to avoid large files
Push-Location $functionsPath
try {
    Write-Host "  -> Deploying functions (ZIP size: ~5 KB)..." -ForegroundColor Gray
    func azure functionapp publish $functionAppName --no-selfcontained --force
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Functions deployed"
    } else {
        Write-Error-Custom "Function deployment failed"
        exit 1
    }
} finally {
    Pop-Location
}

# Quick check that functions are available (no long wait needed for small ZIP)
Write-Step "Verifying functions are available..."
Start-Sleep -Seconds 5

# Save deployment info
$deploymentInfo = @{
    ResourceGroupName = $ResourceGroupName
    FunctionAppName = $functionAppName
    StorageAccountName = $storageAccountName
    ApimServiceName = $apimServiceName
    LogicAppName = $logicAppName
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
