#Requires -Version 5.1

<#
.SYNOPSIS
    Starts Azure Functions locally for testing
#>

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Starting Azure Functions Locally" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

# Check if func is installed
$funcCmd = Get-Command func -ErrorAction SilentlyContinue
if (-not $funcCmd) {
    Write-Host "Error: Azure Functions Core Tools not found!" -ForegroundColor Red
    Write-Host "Install from: https://aka.ms/installazurefunctionstools" -ForegroundColor Yellow
    exit 1
}

Write-Host "Azure Functions Core Tools found: $(func --version)" -ForegroundColor Green
Write-Host ""

# Change to functions directory
Push-Location (Join-Path $PSScriptRoot "..\functions")

try {
    Write-Host "Starting Functions runtime on port 7071..." -ForegroundColor Cyan
    Write-Host "Press Ctrl+C to stop`n" -ForegroundColor Yellow
    
    # Start functions
    func start --port 7071
} finally {
    Pop-Location
}


