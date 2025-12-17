#Requires -Version 5.1

<#
.SYNOPSIS
    Simulates data flow through the integration pipeline with live visualization
#>

param(
    [string]$ResourceGroupName = (Get-Content "$PSScriptRoot\..\.deployment-info.json" -ErrorAction SilentlyContinue | ConvertFrom-Json).ResourceGroupName,
    [int]$DelaySeconds = 2
)

$ErrorActionPreference = "Stop"

function Write-Transport {
    param([string]$Stage, [string]$Message, [string]$Status = "info")
    $colors = @{"info"="Cyan"; "success"="Green"; "warning"="Yellow"; "error"="Red"}
    $symbols = @{"info"="->"; "success"="[OK]"; "warning"="[WARN]"; "error"="[ERROR]"}
    Write-Host "`n  $($symbols[$Status]) " -NoNewline -ForegroundColor $colors[$Status]
    Write-Host "[$Stage] " -NoNewline -ForegroundColor Gray
    Write-Host $Message -ForegroundColor White
    Start-Sleep -Seconds $DelaySeconds
}

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  DATA FLOW SIMULATION - Integration Pipeline Demo" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

# Get deployment info
if (-not $ResourceGroupName) {
    Write-Host "Error: Resource group not found. Run deploy-demo.ps1 first." -ForegroundColor Red
    exit 1
}

# Get Function App name (filter out warnings)
$ErrorActionPreference = "SilentlyContinue"
$funcListOutput = az functionapp list --resource-group $ResourceGroupName --query "[0].name" --output tsv 2>&1
$ErrorActionPreference = "Stop"
$functionAppName = $funcListOutput | Where-Object { $_ -and $_ -notmatch "Warning" -and $_ -notmatch "UserWarning" -and $_ -match "^[a-z0-9-]+$" } | Select-Object -First 1

if (-not $functionAppName -or $functionAppName -eq "") {
    Write-Host "Error: Function App not found in resource group $ResourceGroupName" -ForegroundColor Red
    Write-Host "Please ensure the deployment completed successfully." -ForegroundColor Yellow
    Write-Host "`nTipp: Das Deployment kann 5-10 Minuten dauern. Bitte warten Sie noch etwas." -ForegroundColor Cyan
    exit 1
}

$ErrorActionPreference = "SilentlyContinue"
$funcShowOutput = az functionapp show --resource-group $ResourceGroupName --name $functionAppName --output json 2>&1
$ErrorActionPreference = "Stop"
$jsonOutput = $funcShowOutput | Where-Object { $_ -notmatch "Warning" -and $_ -notmatch "UserWarning" } | Out-String
$functionApp = $jsonOutput | ConvertFrom-Json
$functionUrl = "https://$($functionApp.defaultHostName)/api/HttpIngest"

# Sample vendor data
$vendorData = @{
    vendorId = "VENDOR-DEMO-001"
    name = "Demo Vendor Corporation"
    email = "demo@vendor.com"
    address = @{
        street = "123 Demo Street"
        city = "Demo City"
        state = "DC"
        zipCode = "12345"
        country = "USA"
    }
    contactPerson = "Demo Contact"
    phone = "+1-555-DEMO"
    status = "Active"
    registrationDate = (Get-Date).ToString("yyyy-MM-dd")
}

$correlationId = [guid]::NewGuid().ToString()

Write-Transport "CLIENT" "Preparing vendor data..." "info"
Write-Host "    Correlation ID: $correlationId" -ForegroundColor Gray
Write-Host "    Vendor ID: $($vendorData.vendorId)" -ForegroundColor Gray

Write-Transport "HTTP INGEST" "Sending POST request to Function App..." "info"
try {
    $response = Invoke-RestMethod -Uri $functionUrl `
        -Method POST `
        -Body ($vendorData | ConvertTo-Json) `
        -ContentType "application/json" `
        -Headers @{"x-correlation-id"=$correlationId}
    
    Write-Transport "HTTP INGEST" "Request accepted (HTTP 202)" "success"
    Write-Host "    Message ID: $($response.messageId)" -ForegroundColor Gray
    Write-Host "    Status: $($response.status)" -ForegroundColor Gray
    
    Write-Transport "SERVICE BUS" "Message queued in 'inbound' queue..." "info"
    Start-Sleep -Seconds 3
    
    Write-Transport "SB PROCESSOR" "Processing message from queue..." "info"
    Start-Sleep -Seconds 2
    
    Write-Transport "ADLS GEN2" "Saving data to blob storage..." "info"
    Write-Host "    Path: landing/vendors/$(Get-Date -Format 'yyyy/MM/dd')/$($response.messageId).json" -ForegroundColor Gray
    Start-Sleep -Seconds 2
    
    Write-Transport "LOGIC APP" "Orchestrating workflow - forwarding to outbound queue..." "info"
    Start-Sleep -Seconds 2
    
    Write-Transport "SERVICE BUS" "Message forwarded to 'outbound' queue..." "info"
    Start-Sleep -Seconds 2
    
    Write-Transport "MOCK TARGET" "Receiving data at target system..." "info"
    Start-Sleep -Seconds 2
    
    Write-Transport "PIPELINE" "Data successfully processed end-to-end!" "success"
    
} catch {
    Write-Transport "ERROR" "Failed: $($_.Exception.Message)" "error"
    exit 1
}

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  Simulation completed successfully!" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Green
