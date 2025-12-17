param($queueItem, $TriggerMetadata, $outputBlob)

Write-Host "SbProcessor: Processing message at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "SbProcessor: Message ID: $($TriggerMetadata.MessageId)"
Write-Host "SbProcessor: Delivery Count: $($TriggerMetadata.DeliveryCount)"

try {
    # Parse message
    $message = $queueItem | ConvertFrom-Json
    
    Write-Host "SbProcessor: Correlation ID: $($message.correlationId)"
    Write-Host "SbProcessor: Source: $($message.source)"
    
    # Extract data
    $data = $message.data
    
    # Add processing metadata
    $processedData = @{
        messageId = $message.id
        correlationId = $message.correlationId
        receivedAt = $message.timestamp
        processedAt = (Get-Date).ToUniversalTime().ToString("o")
        processor = "SbProcessor"
        data = $data
    }
    
    # Convert to JSON
    $jsonData = $processedData | ConvertTo-Json -Depth 10
    
    # Save to blob storage
    Push-OutputBinding -Name outputBlob -Value $jsonData
    
    Write-Host "SbProcessor: Data saved to ADLS Gen2"
    Write-Host "SbProcessor: Blob path: landing/vendors/$(Get-Date -Format 'yyyy/MM/dd')/$($message.id).json"
    Write-Host "SbProcessor: Processing completed successfully"
    
} catch {
    Write-Error "SbProcessor: Error processing message - $($_.Exception.Message)"
    Write-Error $_.ScriptStackTrace
    
    # Re-throw to trigger retry/dead-letter
    throw
}

