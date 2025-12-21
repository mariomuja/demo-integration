#Requires -Version 5.1

<#
.SYNOPSIS
    Tests the Azure Functions locally
#>

$ErrorActionPreference = "Stop"

function Write-Transport {
    param([string]$Stage, [string]$Message, [string]$Status = "info")
    $colors = @{"info"="Cyan"; "success"="Green"; "warning"="Yellow"; "error"="Red"}
    $symbols = @{"info"="->"; "success"="[OK]"; "warning"="[WARN]"; "error"="[ERROR]"}
    Write-Host "`n  $($symbols[$Status]) " -NoNewline -ForegroundColor $colors[$Status]
    Write-Host "[$Stage] " -NoNewline -ForegroundColor Gray
    Write-Host $Message -ForegroundColor White
}

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  LOCAL FUNCTION TEST - Integration Pipeline Demo" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

# Check if Functions are running
$functionUrl = "http://localhost:7071/api/HttpIngest"
Write-Transport "CHECK" "Checking if Functions are running on localhost:7071..." "info"

try {
    $testResponse = Invoke-WebRequest -Uri "http://localhost:7071" -Method GET -TimeoutSec 2 -ErrorAction SilentlyContinue
    Write-Transport "CHECK" "Functions runtime is running" "success"
} catch {
    Write-Transport "CHECK" "Functions runtime not running. Starting..." "warning"
    Write-Host "  Please run: cd functions; func start" -ForegroundColor Yellow
    Write-Host "  Or wait a few seconds if Functions are still starting..." -ForegroundColor Yellow
    exit 1
}

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
Write-Host "    Function URL: $functionUrl" -ForegroundColor Gray

Write-Transport "HTTP INGEST" "Sending POST request to local Function..." "info"
try {
    $response = Invoke-RestMethod -Uri $functionUrl `
        -Method POST `
        -Body ($vendorData | ConvertTo-Json -Depth 10) `
        -ContentType "application/json" `
        -Headers @{"x-correlation-id"=$correlationId}
    
    Write-Transport "HTTP INGEST" "Request accepted (HTTP 202)" "success"
    Write-Host "    Message ID: $($response.messageId)" -ForegroundColor Gray
    Write-Host "    Correlation ID: $($response.correlationId)" -ForegroundColor Gray
    Write-Host "    Status: $($response.status)" -ForegroundColor Gray
    Write-Host "    Message: $($response.message)" -ForegroundColor Gray
    
    Write-Transport "LOCAL TEST" "Function executed successfully!" "success"
    
} catch {
    $errorMessage = $_.Exception.Message
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $responseBody = $reader.ReadToEnd()
        Write-Transport "ERROR" "HTTP Error: $errorMessage" "error"
        Write-Host "    Response: $responseBody" -ForegroundColor Red
    } else {
        Write-Transport "ERROR" "Failed: $errorMessage" "error"
    }
    exit 1
}

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  Local test completed successfully!" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Green
Write-Host "Note: Service Bus bindings require Azure resources for full end-to-end testing." -ForegroundColor Yellow
Write-Host "      For complete testing, deploy to Azure and use simulate-flow.ps1" -ForegroundColor Yellow
Write-Host ""


