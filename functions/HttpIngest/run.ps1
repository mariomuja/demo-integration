using namespace System.Net

param($Request, $TriggerMetadata, $outputMessage)

# Log incoming request
Write-Host "HttpIngest: Received request at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "HttpIngest: Request body length: $($Request.Body.Length) bytes"

try {
    # Parse request body
    $body = $Request.Body | ConvertFrom-Json
    
    # Add metadata
    $message = @{
        id = [guid]::NewGuid().ToString()
        timestamp = (Get-Date).ToUniversalTime().ToString("o")
        source = "HttpIngest"
        data = $body
        correlationId = if ($Request.Headers.'x-correlation-id') { $Request.Headers.'x-correlation-id' } else { [guid]::NewGuid().ToString() }
    }
    
    # Convert to JSON
    $messageJson = $message | ConvertTo-Json -Depth 10 -Compress
    
    # Send to Service Bus
    Push-OutputBinding -Name outputMessage -Value $messageJson
    
    Write-Host "HttpIngest: Message sent to Service Bus queue 'inbound'"
    Write-Host "HttpIngest: Message ID: $($message.id)"
    Write-Host "HttpIngest: Correlation ID: $($message.correlationId)"
    
    # Return success response
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Accepted
        Body = @{
            messageId = $message.id
            correlationId = $message.correlationId
            status = "accepted"
            message = "Data received and queued for processing"
        } | ConvertTo-Json
        ContentType = "application/json"
    })
    
} catch {
    Write-Error "HttpIngest: Error processing request - $($_.Exception.Message)"
    Write-Error $_.ScriptStackTrace
    
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body = @{
            error = $_.Exception.Message
            status = "error"
        } | ConvertTo-Json
        ContentType = "application/json"
    })
}

