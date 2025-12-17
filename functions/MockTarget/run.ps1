using namespace System.Net

param($Request, $TriggerMetadata, $Response)

Write-Host "MockTarget: Data received at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

try {
    $body = $Request.Body | ConvertFrom-Json
    
    Write-Host "MockTarget: Processing vendor data"
    Write-Host "MockTarget: Message ID: $($body.messageId)"
    Write-Host "MockTarget: Correlation ID: $($body.correlationId)"
    
    # Simulate target system processing
    $result = @{
        status = "success"
        messageId = $body.messageId
        correlationId = $body.correlationId
        receivedAt = (Get-Date).ToUniversalTime().ToString("o")
        targetSystem = "MockTarget"
        processedRecords = if ($body.data.vendorId) { 1 } else { 0 }
        message = "Data successfully received and processed by target system"
    }
    
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body = $result | ConvertTo-Json
        ContentType = "application/json"
    })
    
    Write-Host "MockTarget: Processing completed successfully"
    
} catch {
    Write-Error "MockTarget: Error - $($_.Exception.Message)"
    
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::InternalServerError
        Body = @{
            status = "error"
            error = $_.Exception.Message
        } | ConvertTo-Json
        ContentType = "application/json"
    })
}

