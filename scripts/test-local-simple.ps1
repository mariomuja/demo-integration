#Requires -Version 5.1

<#
.SYNOPSIS
    Simple local test of the HttpIngest function logic
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
Write-Host "  LOCAL FUNCTION LOGIC TEST" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

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

Write-Transport "TEST" "Testing HttpIngest function logic..." "info"
Write-Host "    Correlation ID: $correlationId" -ForegroundColor Gray
Write-Host "    Vendor ID: $($vendorData.vendorId)" -ForegroundColor Gray

# Simulate the function logic
try {
    Write-Transport "PARSE" "Parsing request body..." "info"
    $body = $vendorData | ConvertTo-Json -Depth 10
    
    Write-Transport "METADATA" "Adding metadata..." "info"
    $message = @{
        id = [guid]::NewGuid().ToString()
        timestamp = (Get-Date).ToUniversalTime().ToString("o")
        source = "HttpIngest"
        data = $vendorData
        correlationId = $correlationId
    }
    
    Write-Transport "JSON" "Converting to JSON..." "info"
    $messageJson = $message | ConvertTo-Json -Depth 10 -Compress
    
    Write-Transport "RESULT" "Function logic executed successfully!" "success"
    Write-Host "    Message ID: $($message.id)" -ForegroundColor Gray
    Write-Host "    Correlation ID: $($message.correlationId)" -ForegroundColor Gray
    Write-Host "    Timestamp: $($message.timestamp)" -ForegroundColor Gray
    Write-Host "    Source: $($message.source)" -ForegroundColor Gray
    Write-Host "`n    Message JSON (first 200 chars):" -ForegroundColor Gray
    Write-Host "    $($messageJson.Substring(0, [Math]::Min(200, $messageJson.Length)))..." -ForegroundColor DarkGray
    
    Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "  Local logic test completed successfully!" -ForegroundColor White
    Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Green
    
    Write-Host "Note: For full end-to-end testing with Service Bus:" -ForegroundColor Yellow
    Write-Host "  1. Deploy to Azure: .\scripts\deploy-demo.ps1" -ForegroundColor Cyan
    Write-Host "  2. Run simulation: .\scripts\simulate-flow.ps1" -ForegroundColor Cyan
    Write-Host ""
    
} catch {
    Write-Transport "ERROR" "Failed: $($_.Exception.Message)" "error"
    Write-Host "    Stack: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
}


