#Requires -Version 5.1

<#
.SYNOPSIS
    Starts Azurite (Azure Storage Emulator) for local development
#>

Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Starting Azurite Storage Emulator" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════════════`n" -ForegroundColor Cyan

# Check if Azurite is installed
$azuriteCmd = Get-Command azurite -ErrorAction SilentlyContinue
if (-not $azuriteCmd) {
    Write-Host "Azurite not found. Installing..." -ForegroundColor Yellow
    try {
        npm install -g azurite
        Write-Host "Azurite installed successfully!" -ForegroundColor Green
    } catch {
        Write-Host "Error installing Azurite: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Please install manually: npm install -g azurite" -ForegroundColor Yellow
        exit 1
    }
}

# Check if Azurite is already running
$azuriteProcess = Get-Process -Name Azurite -ErrorAction SilentlyContinue
if ($azuriteProcess) {
    Write-Host "Azurite is already running (PID: $($azuriteProcess.Id))" -ForegroundColor Green
    Write-Host "Blob Service: http://127.0.0.1:10000" -ForegroundColor Gray
    Write-Host "Queue Service: http://127.0.0.1:10001" -ForegroundColor Gray
    Write-Host "Table Service: http://127.0.0.1:10002" -ForegroundColor Gray
    exit 0
}

Write-Host "Starting Azurite..." -ForegroundColor Cyan
Write-Host "Blob Service will be available at: http://127.0.0.1:10000" -ForegroundColor Gray
Write-Host "Queue Service will be available at: http://127.0.0.1:10001" -ForegroundColor Gray
Write-Host "Table Service will be available at: http://127.0.0.1:10002" -ForegroundColor Gray
Write-Host "`nPress Ctrl+C to stop Azurite`n" -ForegroundColor Yellow

# Start Azurite
azurite


