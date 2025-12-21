using namespace System.Net

param($Request, $TriggerMetadata, $outputMessage)

$ErrorActionPreference = "Continue"

# Log incoming request
try {
    $bodyLength = if ($Request.Body) { $Request.Body.Length } else { 0 }
    Write-Host "HttpIngest: Received request at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Host "HttpIngest: Request body length: $bodyLength bytes"
} catch {
    Write-Host "HttpIngest: Warning - Could not log request details: $($_.Exception.Message)"
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
        Write-Host "HttpIngest: Error parsing JSON - $($_.Exception.Message)"
        throw "Invalid JSON in request body: $($_.Exception.Message)"
    }
    
    # Get correlation ID from headers (with null safety)
    $correlationId = [guid]::NewGuid().ToString()
    try {
        if ($Request.Headers -and $Request.Headers.'x-correlation-id') {
            $headerCorrelationId = $Request.Headers.'x-correlation-id'
            if (-not [string]::IsNullOrWhiteSpace($headerCorrelationId)) {
                $correlationId = $headerCorrelationId
            }
        }
    } catch {
        Write-Host "HttpIngest: Warning - Could not read correlation ID header, using generated ID"
    }
    
    # Add metadata
    $message = @{
        id = [guid]::NewGuid().ToString()
        timestamp = (Get-Date).ToUniversalTime().ToString("o")
        source = "HttpIngest"
        data = $body
        correlationId = $correlationId
    }
    
    # Convert to JSON with error handling
    try {
        $messageJson = $message | ConvertTo-Json -Depth 10 -Compress -ErrorAction Stop
    } catch {
        Write-Host "HttpIngest: Error converting message to JSON - $($_.Exception.Message)"
        throw "Failed to serialize message: $($_.Exception.Message)"
    }
    
    # Send to Service Bus (with error handling for local development)
    $serviceBusAvailable = $false
    try {
        if ($null -ne $outputMessage) {
            Push-OutputBinding -Name outputMessage -Value $messageJson -ErrorAction Stop
            Write-Host "HttpIngest: Message sent to Service Bus queue 'inbound'"
            $serviceBusAvailable = $true
        } else {
            Write-Host "HttpIngest: Service Bus output binding not available (local mode)"
        }
    } catch {
        Write-Host "HttpIngest: Service Bus not available (local mode) - message logged only"
        Write-Host "HttpIngest: Message would be sent to queue 'inbound': $($messageJson.Substring(0, [Math]::Min(200, $messageJson.Length)))..."
    }
    
    Write-Host "HttpIngest: Message ID: $($message.id)"
    Write-Host "HttpIngest: Correlation ID: $($message.correlationId)"
    
    # Build response message
    $responseMessage = if ($serviceBusAvailable) {
        "Data received and queued for processing"
    } else {
        "Data received and processed (local mode - Service Bus mocked)"
    }
    
    # Return success response with error handling
    try {
        $responseBody = @{
            messageId = $message.id
            correlationId = $message.correlationId
            status = "accepted"
            message = $responseMessage
        } | ConvertTo-Json -ErrorAction Stop
        
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::Accepted
            Body = $responseBody
            ContentType = "application/json"
        })
    } catch {
        Write-Host "HttpIngest: Error creating response - $($_.Exception.Message)"
        # Fallback response
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::Accepted
            Body = '{"status":"accepted","messageId":"' + $message.id + '"}'
            ContentType = "application/json"
        })
    }
    
} catch {
    $errorMessage = $_.Exception.Message
    Write-Host "HttpIngest: Error processing request - $errorMessage" -ForegroundColor Red
    
    if ($_.ScriptStackTrace) {
        Write-Host "HttpIngest: Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Yellow
    }
    
    # Return error response with error handling
    try {
        $errorResponseBody = @{
            error = $errorMessage
            status = "error"
            timestamp = (Get-Date).ToUniversalTime().ToString("o")
        } | ConvertTo-Json -ErrorAction Stop
        
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body = $errorResponseBody
            ContentType = "application/json"
        })
    } catch {
        Write-Host "HttpIngest: Critical error - Could not create error response: $($_.Exception.Message)" -ForegroundColor Red
        # Last resort - simple error response
        try {
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body = '{"error":"Internal server error","status":"error"}'
                ContentType = "application/json"
            })
        } catch {
            Write-Host "HttpIngest: Fatal error - Could not send any response" -ForegroundColor Red
        }
    }
}

