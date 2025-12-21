using namespace System.Net

param($Request, $TriggerMetadata, $Response)

$ErrorActionPreference = "Continue"

try {
    Write-Host "MockTarget: Data received at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
} catch {
    Write-Host "MockTarget: Warning - Could not log receive time"
}

try {
    # Validate request body
    if (-not $Request -or -not $Request.Body) {
        throw "Request body is missing or empty"
    }
    
    # Parse request body with error handling
    try {
        $bodyString = if ($Request.Body -is [string]) { 
            $Request.Body 
        } else { 
            $Request.Body | Out-String 
        }
        
        if ([string]::IsNullOrWhiteSpace($bodyString)) {
            throw "Request body is empty"
        }
        
        $body = $bodyString | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Host "MockTarget: Error parsing JSON - $($_.Exception.Message)"
        throw "Invalid JSON in request body: $($_.Exception.Message)"
    }
    
    # Extract fields with null safety
    $messageId = if ($body.messageId) { $body.messageId } else { "unknown" }
    $correlationId = if ($body.correlationId) { $body.correlationId } else { "unknown" }
    
    Write-Host "MockTarget: Processing vendor data"
    Write-Host "MockTarget: Message ID: $messageId"
    Write-Host "MockTarget: Correlation ID: $correlationId"
    
    # Simulate target system processing
    $processedRecords = 0
    try {
        if ($body.data -and $body.data.vendorId) {
            $processedRecords = 1
        }
    } catch {
        Write-Host "MockTarget: Warning - Could not determine processed records count"
    }
    
    $result = @{
        status = "success"
        messageId = $messageId
        correlationId = $correlationId
        receivedAt = (Get-Date).ToUniversalTime().ToString("o")
        targetSystem = "MockTarget"
        processedRecords = $processedRecords
        message = "Data successfully received and processed by target system"
    }
    
    # Return response with error handling
    try {
        $responseBody = $result | ConvertTo-Json -ErrorAction Stop
        
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body = $responseBody
            ContentType = "application/json"
        })
        
        Write-Host "MockTarget: Processing completed successfully"
    } catch {
        Write-Host "MockTarget: Error creating response - $($_.Exception.Message)" -ForegroundColor Red
        # Fallback response
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body = '{"status":"success","targetSystem":"MockTarget","message":"Processing completed"}'
            ContentType = "application/json"
        })
    }
    
} catch {
    $errorMessage = $_.Exception.Message
    Write-Host "MockTarget: Error - $errorMessage" -ForegroundColor Red
    
    if ($_.ScriptStackTrace) {
        Write-Host "MockTarget: Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Yellow
    }
    
    # Return error response with error handling
    try {
        $errorResponseBody = @{
            status = "error"
            error = $errorMessage
            targetSystem = "MockTarget"
            timestamp = (Get-Date).ToUniversalTime().ToString("o")
        } | ConvertTo-Json -ErrorAction Stop
        
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body = $errorResponseBody
            ContentType = "application/json"
        })
    } catch {
        Write-Host "MockTarget: Critical error - Could not create error response: $($_.Exception.Message)" -ForegroundColor Red
        # Last resort error response
        try {
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body = '{"status":"error","error":"Internal server error","targetSystem":"MockTarget"}'
                ContentType = "application/json"
            })
        } catch {
            Write-Host "MockTarget: Fatal error - Could not send any response" -ForegroundColor Red
        }
    }
}

