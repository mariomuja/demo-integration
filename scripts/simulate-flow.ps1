#Requires -Version 5.1

<#
.SYNOPSIS
    Simulates data flow through the integration pipeline with detailed step-by-step visualization
#>

param(
    [string]$ResourceGroupName = (Get-Content "$PSScriptRoot\..\.deployment-info.json" -ErrorAction SilentlyContinue | ConvertFrom-Json).ResourceGroupName,
    [int]$DelaySeconds = 5
)

$ErrorActionPreference = "Continue"

# Installation helper functions
function Install-AzureCLI {
    Write-Host "`n    Installing Azure CLI..." -ForegroundColor Cyan
    
    # Try winget first (Windows 10/11)
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetCmd) {
        Write-Host "      Using winget to install Azure CLI..." -ForegroundColor DarkGray
        try {
            $process = Start-Process -FilePath "winget" -ArgumentList "install", "Microsoft.AzureCLI", "--silent", "--accept-package-agreements", "--accept-source-agreements" -Wait -PassThru -NoNewWindow
            if ($process.ExitCode -eq 0) {
                Write-Host "      [OK] Azure CLI installation completed" -ForegroundColor Green
                # Refresh PATH
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
                return $true
            }
        } catch {
            Write-Host "      [WARN] winget installation failed, trying alternative..." -ForegroundColor Yellow
        }
    }
    
    # Fallback: Download and install MSI
    Write-Host "      Downloading Azure CLI installer..." -ForegroundColor DarkGray
    $installerPath = "$env:TEMP\AzureCLI.msi"
    try {
        Invoke-WebRequest -Uri "https://aka.ms/installazurecliwindows" -OutFile $installerPath -UseBasicParsing
        Write-Host "      Running installer (this may take a few minutes)..." -ForegroundColor DarkGray
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i", "`"$installerPath`"", "/quiet", "/norestart" -Wait -PassThru
        if ($process.ExitCode -eq 0 -or $process.ExitCode -eq 3010) {
            Write-Host "      [OK] Azure CLI installation completed" -ForegroundColor Green
            Remove-Item $installerPath -ErrorAction SilentlyContinue
            # Refresh PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            return $true
        } else {
            Write-Host "      [ERROR] Installation failed with exit code $($process.ExitCode)" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "      [ERROR] Failed to download/install Azure CLI: $_" -ForegroundColor Red
        return $false
    }
}

function Install-NodeJS {
    Write-Host "`n    Installing Node.js..." -ForegroundColor Cyan
    
    # Try winget first
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetCmd) {
        Write-Host "      Using winget to install Node.js..." -ForegroundColor DarkGray
        try {
            $process = Start-Process -FilePath "winget" -ArgumentList "install", "OpenJS.NodeJS.LTS", "--silent", "--accept-package-agreements", "--accept-source-agreements" -Wait -PassThru -NoNewWindow
            if ($process.ExitCode -eq 0) {
                Write-Host "      [OK] Node.js installation completed" -ForegroundColor Green
                # Refresh PATH
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
                Start-Sleep -Seconds 2
                return $true
            }
        } catch {
            Write-Host "      [WARN] winget installation failed" -ForegroundColor Yellow
        }
    }
    
    Write-Host "      [INFO] Please install Node.js manually from: https://nodejs.org/" -ForegroundColor Yellow
    Write-Host "      After installation, restart PowerShell and run this script again." -ForegroundColor Yellow
    return $false
}

function Install-AzureFunctionsCoreTools {
    Write-Host "`n    Installing Azure Functions Core Tools..." -ForegroundColor Cyan
    
    # Check if npm is available
    $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $npmCmd) {
        Write-Host "      [ERROR] npm is required but not found. Please install Node.js first." -ForegroundColor Red
        return $false
    }
    
    Write-Host "      Installing via npm (this may take a few minutes)..." -ForegroundColor DarkGray
    try {
        $process = Start-Process -FilePath "npm" -ArgumentList "install", "-g", "azure-functions-core-tools@4", "--unsafe-perm", "true" -Wait -PassThru -NoNewWindow
        if ($process.ExitCode -eq 0) {
            Write-Host "      [OK] Azure Functions Core Tools installation completed" -ForegroundColor Green
            # Refresh PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            return $true
        } else {
            Write-Host "      [ERROR] Installation failed with exit code $($process.ExitCode)" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "      [ERROR] Failed to install: $_" -ForegroundColor Red
        return $false
    }
}

function Install-Azurite {
    Write-Host "`n    Installing Azurite..." -ForegroundColor Cyan
    
    # Check if npm is available
    $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $npmCmd) {
        Write-Host "      [ERROR] npm is required but not found. Please install Node.js first." -ForegroundColor Red
        return $false
    }
    
    Write-Host "      Installing via npm..." -ForegroundColor DarkGray
    try {
        $process = Start-Process -FilePath "npm" -ArgumentList "install", "-g", "azurite" -Wait -PassThru -NoNewWindow
        if ($process.ExitCode -eq 0) {
            Write-Host "      [OK] Azurite installation completed" -ForegroundColor Green
            # Refresh PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
            return $true
        } else {
            Write-Host "      [ERROR] Installation failed with exit code $($process.ExitCode)" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "      [ERROR] Failed to install: $_" -ForegroundColor Red
        return $false
    }
}

# Check for required tools with interactive installation
function Test-RequiredTools {
    Write-Host "`n=================================================================================" -ForegroundColor Cyan
    Write-Host "                    Checking Required Tools and Dependencies" -ForegroundColor White
    Write-Host "=================================================================================" -ForegroundColor Cyan
    Write-Host ""
    
    $allToolsAvailable = $true
    
    # Check PowerShell version
    Write-Host "  Checking PowerShell..." -ForegroundColor Cyan
    $psVersion = $PSVersionTable.PSVersion
    if ($psVersion.Major -ge 5) {
        Write-Host "    [OK] PowerShell $($psVersion.Major).$($psVersion.Minor) - OK" -ForegroundColor Green
    } else {
        Write-Host "    [ERROR] PowerShell version too old (requires 5.1+)" -ForegroundColor Red
        Write-Host "      Please upgrade PowerShell manually. This cannot be automated." -ForegroundColor Yellow
        $allToolsAvailable = $false
    }
    Start-Sleep -Milliseconds 300
    
    # Check Azure CLI
    Write-Host "  Checking Azure CLI..." -ForegroundColor Cyan
    $azCmd = Get-Command az -ErrorAction SilentlyContinue
    if ($azCmd) {
        try {
            $azVersion = az version --output json 2>$null | ConvertFrom-Json
            Write-Host "    [OK] Azure CLI installed" -ForegroundColor Green
            Write-Host "      Version: $($azVersion.'azure-cli')" -ForegroundColor DarkGray
            Write-Host "      Note: Required for Azure deployments" -ForegroundColor DarkGray
        } catch {
            Write-Host "    [OK] Azure CLI installed (version check failed)" -ForegroundColor Green
        }
    } else {
        Write-Host "    [WARN] Azure CLI not found" -ForegroundColor Yellow
        Write-Host "      Note: Optional for local testing, required for Azure deployments" -ForegroundColor DarkGray
        $response = Read-Host "      Install Azure CLI now? (Y/N)"
        if ($response -eq 'Y' -or $response -eq 'y') {
            if (Install-AzureCLI) {
                # Verify installation
                Start-Sleep -Seconds 2
                $azCmd = Get-Command az -ErrorAction SilentlyContinue
                if ($azCmd) {
                    Write-Host "    [OK] Azure CLI successfully installed and verified" -ForegroundColor Green
                } else {
                    Write-Host "    [WARN] Azure CLI installed but not yet available in PATH" -ForegroundColor Yellow
                    Write-Host "      Please restart PowerShell and run this script again." -ForegroundColor Yellow
                }
            }
        } else {
            Write-Host "      Skipping Azure CLI installation" -ForegroundColor DarkGray
        }
    }
    Start-Sleep -Milliseconds 300
    
    # Check Node.js/npm (needed for Functions Core Tools and Azurite)
    Write-Host "  Checking Node.js/npm..." -ForegroundColor Cyan
    $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
    if ($npmCmd) {
        try {
            $nodeVersion = node --version 2>&1
            Write-Host "    [OK] Node.js installed" -ForegroundColor Green
            Write-Host "      Version: $nodeVersion" -ForegroundColor DarkGray
            Write-Host "      Note: Required for Azure Functions Core Tools and Azurite" -ForegroundColor DarkGray
        } catch {
            Write-Host "    [OK] Node.js/npm installed" -ForegroundColor Green
        }
    } else {
        Write-Host "    [WARN] Node.js/npm not found" -ForegroundColor Yellow
        Write-Host "      Note: Required for Azure Functions Core Tools and Azurite" -ForegroundColor DarkGray
        $response = Read-Host "      Install Node.js now? (Y/N)"
        if ($response -eq 'Y' -or $response -eq 'y') {
            if (Install-NodeJS) {
                # Verify installation
                Start-Sleep -Seconds 3
                $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
                if ($npmCmd) {
                    Write-Host "    [OK] Node.js successfully installed and verified" -ForegroundColor Green
                } else {
                    Write-Host "    [WARN] Node.js installed but not yet available in PATH" -ForegroundColor Yellow
                    Write-Host "      Please restart PowerShell and run this script again." -ForegroundColor Yellow
                }
            }
        } else {
            Write-Host "      Skipping Node.js installation" -ForegroundColor DarkGray
        }
    }
    Start-Sleep -Milliseconds 300
    
    # Check Azure Functions Core Tools
    Write-Host "  Checking Azure Functions Core Tools..." -ForegroundColor Cyan
    $funcCmd = Get-Command func -ErrorAction SilentlyContinue
    if ($funcCmd) {
        try {
            $funcVersion = func --version 2>&1 | Select-String -Pattern "\d+\.\d+\.\d+" | Select-Object -First 1
            Write-Host "    [OK] Azure Functions Core Tools installed" -ForegroundColor Green
            Write-Host "      Version: $funcVersion" -ForegroundColor DarkGray
            Write-Host "      Note: Required for local Function development" -ForegroundColor DarkGray
        } catch {
            Write-Host "    [OK] Azure Functions Core Tools installed" -ForegroundColor Green
        }
    } else {
        Write-Host "    [WARN] Azure Functions Core Tools not found" -ForegroundColor Yellow
        Write-Host "      Note: Optional for mock mode, required for local Function testing" -ForegroundColor DarkGray
        $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
        if ($npmCmd) {
            $response = Read-Host "      Install Azure Functions Core Tools now? (Y/N)"
            if ($response -eq 'Y' -or $response -eq 'y') {
                if (Install-AzureFunctionsCoreTools) {
                    # Verify installation
                    Start-Sleep -Seconds 2
                    $funcCmd = Get-Command func -ErrorAction SilentlyContinue
                    if ($funcCmd) {
                        Write-Host "    [OK] Azure Functions Core Tools successfully installed and verified" -ForegroundColor Green
                    } else {
                        Write-Host "    [WARN] Installed but not yet available in PATH" -ForegroundColor Yellow
                        Write-Host "      Please restart PowerShell and run this script again." -ForegroundColor Yellow
                    }
                }
            } else {
                Write-Host "      Skipping Azure Functions Core Tools installation" -ForegroundColor DarkGray
            }
        } else {
            Write-Host "      npm not available - cannot install automatically" -ForegroundColor DarkGray
            Write-Host "      Install Node.js first, then run this script again" -ForegroundColor DarkGray
        }
    }
    Start-Sleep -Milliseconds 300
    
    # Check Azurite (optional)
    Write-Host "  Checking Azurite Storage Emulator..." -ForegroundColor Cyan
    $azuriteCmd = Get-Command azurite -ErrorAction SilentlyContinue
    if ($azuriteCmd) {
        Write-Host "    [OK] Azurite installed" -ForegroundColor Green
        Write-Host "      Note: Optional - provides local blob storage emulation" -ForegroundColor DarkGray
    } else {
        Write-Host "    [WARN] Azurite not found" -ForegroundColor Yellow
        Write-Host "      Note: Optional - provides local blob storage emulation" -ForegroundColor DarkGray
        $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
        if ($npmCmd) {
            $response = Read-Host "      Install Azurite now? (Y/N)"
            if ($response -eq 'Y' -or $response -eq 'y') {
                if (Install-Azurite) {
                    # Verify installation
                    Start-Sleep -Seconds 2
                    $azuriteCmd = Get-Command azurite -ErrorAction SilentlyContinue
                    if ($azuriteCmd) {
                        Write-Host "    [OK] Azurite successfully installed and verified" -ForegroundColor Green
                    } else {
                        Write-Host "    [WARN] Installed but not yet available in PATH" -ForegroundColor Yellow
                        Write-Host "      Please restart PowerShell and run this script again." -ForegroundColor Yellow
                    }
                }
            } else {
                Write-Host "      Skipping Azurite installation" -ForegroundColor DarkGray
            }
        } else {
            Write-Host "      npm not available - cannot install automatically" -ForegroundColor DarkGray
            Write-Host "      Install Node.js first, then run this script again" -ForegroundColor DarkGray
        }
    }
    Start-Sleep -Milliseconds 300
    
    Write-Host ""
    Write-Host "  [OK] Tool check completed!" -ForegroundColor Green
    Write-Host "    The script will run in mock mode if Functions are not available." -ForegroundColor DarkGray
    Write-Host ""
    return $true
}

function Write-Step {
    param([string]$Message, [int]$StepNumber, [int]$TotalSteps, [string]$Color = "Cyan")
    Write-Host "`n" -NoNewline
    Write-Host "+-----------------------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "| " -NoNewline -ForegroundColor DarkGray
    Write-Host "STEP $StepNumber/$TotalSteps" -NoNewline -ForegroundColor $Color
    $spaces = 65 - "STEP $StepNumber/$TotalSteps".Length - $Message.Length
    if ($spaces -gt 0) {
        Write-Host (" " * $spaces) -NoNewline
    }
    Write-Host $Message -NoNewline -ForegroundColor White
    Write-Host " |" -ForegroundColor DarkGray
    Write-Host "+-----------------------------------------------------------------------------+" -ForegroundColor DarkGray
    Start-Sleep -Seconds 2
}

function Write-Detail {
    param([string]$Label, [string]$Value, [string]$Indent = "    ")
    Write-Host "$Indent- " -NoNewline -ForegroundColor DarkGray
    Write-Host "$Label" -NoNewline -ForegroundColor Gray
    Write-Host ": " -NoNewline
    Write-Host $Value -ForegroundColor Yellow
    Start-Sleep -Milliseconds 500
}

function Write-Transport {
    param([string]$Stage, [string]$Message, [string]$Status = "info", [hashtable]$Details = $null)
    $colors = @{"info"="Cyan"; "success"="Green"; "warning"="Yellow"; "error"="Red"}
    $symbols = @{"info"="->"; "success"="[OK]"; "warning"="[WARN]"; "error"="[ERROR]"}
    Write-Host "`n  $($symbols[$Status]) " -NoNewline -ForegroundColor $colors[$Status]
    Write-Host "[$Stage] " -NoNewline -ForegroundColor Gray
    Write-Host $Message -ForegroundColor White
    if ($Details) {
        foreach ($key in $Details.Keys) {
            Write-Detail $key $Details[$key] "      "
        }
    }
    Start-Sleep -Seconds $DelaySeconds
}

# Main execution
Write-Host "`n=================================================================================" -ForegroundColor Cyan
Write-Host "                    DATA FLOW SIMULATION - Integration Pipeline Demo" -ForegroundColor White
Write-Host "=================================================================================" -ForegroundColor Cyan

# Check tools first
$toolsOK = Test-RequiredTools

# Get deployment info with error handling
Write-Step "Initializing pipeline connection..." 1 8
if (-not $ResourceGroupName) {
    Write-Host "  [WARN] " -NoNewline -ForegroundColor Yellow
    Write-Host "Resource group not found. Using local mode..." -ForegroundColor Yellow
    $functionUrl = "http://localhost:7071/api/HttpIngest"
    Write-Detail "Mode" "Local Development"
    Write-Detail "Function URL" $functionUrl
} else {
    Write-Detail "Mode" "Azure Cloud"
    Write-Detail "Resource Group" $ResourceGroupName
$ErrorActionPreference = "SilentlyContinue"
    try {
$funcListOutput = az functionapp list --resource-group $ResourceGroupName --query "[0].name" --output tsv 2>&1
$functionAppName = $funcListOutput | Where-Object { $_ -and $_ -notmatch "Warning" -and $_ -notmatch "UserWarning" -and $_ -match "^[a-z0-9-]+$" } | Select-Object -First 1

if (-not $functionAppName -or $functionAppName -eq "") {
            Write-Host "  [WARN] " -NoNewline -ForegroundColor Yellow
            Write-Host "Function App not found. Using local mode..." -ForegroundColor Yellow
            $functionUrl = "http://localhost:7071/api/HttpIngest"
            Write-Detail "Mode" "Local Development (Fallback)"
        } else {
$funcShowOutput = az functionapp show --resource-group $ResourceGroupName --name $functionAppName --output json 2>&1
$jsonOutput = $funcShowOutput | Where-Object { $_ -notmatch "Warning" -and $_ -notmatch "UserWarning" } | Out-String
$functionApp = $jsonOutput | ConvertFrom-Json
$functionUrl = "https://$($functionApp.defaultHostName)/api/HttpIngest"
            Write-Detail "Function App" $functionAppName
            Write-Detail "Hostname" $functionApp.defaultHostName
        }
    } catch {
        Write-Host "  [WARN] " -NoNewline -ForegroundColor Yellow
        Write-Host "Could not get Azure Function App. Using local mode..." -ForegroundColor Yellow
        $functionUrl = "http://localhost:7071/api/HttpIngest"
        Write-Detail "Mode" "Local Development (Fallback)"
    }
    $ErrorActionPreference = "Continue"
}

# Sample vendor data
Write-Step "Preparing vendor data payload..." 2 8
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
$messageId = [guid]::NewGuid().ToString()

Write-Detail "Vendor ID" $vendorData.vendorId
Write-Detail "Vendor Name" $vendorData.name
Write-Detail "Email" $vendorData.email
Write-Detail "Correlation ID" $correlationId
Write-Detail "Message ID" $messageId
Write-Detail "Timestamp" (Get-Date).ToUniversalTime().ToString("o")
Write-Detail "Payload Size" "$(($vendorData | ConvertTo-Json).Length) bytes"

# Step 3: HTTP Ingest
Write-Step "Sending HTTP POST request to Function App..." 3 8
Write-Detail "Endpoint" $functionUrl
Write-Detail "Method" "POST"
Write-Detail "Content-Type" "application/json"
Write-Detail "Header" "x-correlation-id: $correlationId"

$maxRetries = 3
$retryCount = 0
$success = $false

while ($retryCount -lt $maxRetries -and -not $success) {
    $retryCount++
    
    try {
        if ($retryCount -gt 1) {
            Write-Host "  [WARN] " -NoNewline -ForegroundColor Yellow
            Write-Host "Retry attempt $retryCount of $maxRetries..." -ForegroundColor Yellow
            Start-Sleep -Seconds 3
        }
        
        # Try to call the function, but fall back to mock mode if unavailable
        try {
            Write-Host "  -> " -NoNewline -ForegroundColor Cyan
            Write-Host "Sending HTTP request..." -ForegroundColor White
            Start-Sleep -Seconds 2
            
    $response = Invoke-RestMethod -Uri $functionUrl `
        -Method POST `
                -Body ($vendorData | ConvertTo-Json -Depth 10) `
        -ContentType "application/json" `
                -Headers @{"x-correlation-id"=$correlationId} `
                -TimeoutSec 10 `
                -ErrorAction Stop
            
            Write-Host "  [OK] " -NoNewline -ForegroundColor Green
            Write-Host "HTTP 202 Accepted" -ForegroundColor Green
            Write-Detail "Response Status" "Accepted"
            Write-Detail "Response Message ID" $response.messageId
            Write-Detail "Response Correlation ID" $response.correlationId
            $messageId = $response.messageId
        } catch {
            # Mock mode - simulate successful response
            Write-Host "  [WARN] " -NoNewline -ForegroundColor Yellow
            Write-Host "Functions not available - running in mock mode..." -ForegroundColor Yellow
            $response = @{
                messageId = $messageId
                correlationId = $correlationId
                status = "accepted"
                message = "Data received and queued for processing (mock mode)"
            }
            Write-Detail "Mode" "Mock (Functions Runtime not available)"
            Write-Detail "Simulated Message ID" $messageId
        }
        
        $success = $true
        
        # Step 4: Service Bus Queue
        Write-Step "Message queued in Service Bus 'inbound' queue..." 4 8
        Write-Detail "Queue Name" "inbound"
        Write-Detail "Message Format" "JSON"
        Write-Detail "Message Structure" "id, correlationId, timestamp, source, data"
        Write-Detail "Queue Type" "Service Bus Standard Queue"
        Write-Detail "TTL" "24 hours"
        Write-Detail "Dead Letter" "Enabled"
    Start-Sleep -Seconds 3
    
        # Step 5: Service Bus Processor
        Write-Step "Service Bus Processor triggered - processing message..." 5 8
        Write-Detail "Trigger Type" "Service Bus Queue Trigger"
        Write-Detail "Function" "SbProcessor"
        Write-Detail "Processing Action" "Parse JSON, extract data, add metadata"
        Write-Detail "Processor Metadata" "receivedAt, processedAt, processor name"
        Start-Sleep -Seconds 3
        
        # Step 6: Blob Storage
        Write-Step "Saving processed data to Azure Data Lake Storage Gen2..." 6 8
        $blobPath = "landing/vendors/$(Get-Date -Format 'yyyy/MM/dd')/$messageId.json"
        Write-Detail "Storage Account" "Azure Storage Account"
        Write-Detail "Container" "landing"
        Write-Detail "Blob Path" $blobPath
        Write-Detail "File Format" "JSON"
        Write-Detail "Content" "Vendor data with processing metadata"
        Write-Detail "Access Level" "Private"
        Start-Sleep -Seconds 3
        
        # Step 7: Logic App
        Write-Step "Logic App workflow triggered - orchestrating data flow..." 7 8
        Write-Detail "Workflow" "Process and forward message"
        Write-Detail "Trigger" "Service Bus Queue (inbound)"
        Write-Detail "Actions" "Parse message -> Forward to outbound -> Complete message"
        Write-Detail "Target Queue" "outbound"
        Write-Detail "Orchestration" "Managed by Azure Logic Apps"
        Start-Sleep -Seconds 3
        
        # Step 8: Final Delivery
        Write-Step "Message delivered to target system..." 8 8
        Write-Detail "Target System" "Mock Target Function"
        Write-Detail "Delivery Status" "Success"
        Write-Detail "End-to-End Time" "~$($DelaySeconds * 8) seconds"
        Write-Detail "Data Integrity" "Maintained (Correlation ID preserved)"
        
        Write-Transport "PIPELINE" "Data successfully processed end-to-end!" "success" @{
            "Total Steps" = "8"
            "Message Traced" = "Yes"
            "Correlation ID" = $correlationId
            "Message ID" = $messageId
        }
    
} catch {
        $errorMessage = $_.Exception.Message
        
        if ($retryCount -lt $maxRetries) {
            Write-Host "  [WARN] " -NoNewline -ForegroundColor Yellow
            Write-Host "Error on attempt $retryCount : $errorMessage" -ForegroundColor Yellow
            Write-Host "  -> " -NoNewline -ForegroundColor Cyan
            Write-Host "Will retry..." -ForegroundColor Cyan
        } else {
            Write-Transport "ERROR" "Failed after $maxRetries attempts: $errorMessage" "error" @{
                "Last Error" = $errorMessage
                "Attempts" = $maxRetries
            }
            
            if ($_.Exception.Response) {
                try {
                    $stream = $_.Exception.Response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($stream)
                    $responseBody = $reader.ReadToEnd()
                    Write-Detail "Error Response" $responseBody
                } catch {
                    Write-Detail "Error Response" "Could not read"
                }
            }
            
            Write-Host "`n  Troubleshooting:" -ForegroundColor Yellow
            Write-Host "    • Check if Functions are running: func start --port 7071" -ForegroundColor Cyan
            Write-Host "    • Or deploy to Azure: .\scripts\deploy-demo.ps1" -ForegroundColor Cyan
            Write-Host ""
            
            throw
        }
    }
}

Write-Host "`n=================================================================================" -ForegroundColor Green
Write-Host "                         Simulation completed successfully!" -ForegroundColor White
Write-Host "=================================================================================" -ForegroundColor Green
Write-Host ""
