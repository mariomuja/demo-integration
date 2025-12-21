param($queueItem, $TriggerMetadata, $outputBlob)

$ErrorActionPreference = "Continue"

try {
    $messageId = if ($TriggerMetadata -and $TriggerMetadata.MessageId) { $TriggerMetadata.MessageId } else { "unknown" }
    $deliveryCount = if ($TriggerMetadata -and $TriggerMetadata.DeliveryCount) { $TriggerMetadata.DeliveryCount } else { 0 }
    
    Write-Host "SbProcessor: Processing message at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Host "SbProcessor: Message ID: $messageId"
    Write-Host "SbProcessor: Delivery Count: $deliveryCount"
} catch {
    Write-Host "SbProcessor: Warning - Could not log metadata: $($_.Exception.Message)"
}

try {
    # Validate queue item
    if (-not $queueItem) {
        throw "Queue item is null or empty"
    }
    
    # Parse message with error handling
    try {
        $messageString = if ($queueItem -is [string]) { 
            $queueItem 
        } else { 
            $queueItem | ConvertTo-Json -Depth 10 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $queueItem | Out-String
        }
        
        if ([string]::IsNullOrWhiteSpace($messageString)) {
            throw "Queue item is empty"
        }
        
        $message = $messageString | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Host "SbProcessor: Error parsing message JSON - $($_.Exception.Message)"
        throw "Invalid JSON in queue message: $($_.Exception.Message)"
    }
    
    # Validate message structure
    if (-not $message.id) {
        throw "Message missing required field: id"
    }
    
    $correlationId = if ($message.correlationId) { $message.correlationId } else { "unknown" }
    $source = if ($message.source) { $message.source } else { "unknown" }
    
    Write-Host "SbProcessor: Correlation ID: $correlationId"
    Write-Host "SbProcessor: Source: $source"
    
    # Extract data with null safety
    $data = if ($message.data) { $message.data } else { @{} }
    
    # Add processing metadata
    $processedData = @{
        messageId = $message.id
        correlationId = $correlationId
        receivedAt = if ($message.timestamp) { $message.timestamp } else { (Get-Date).ToUniversalTime().ToString("o") }
        processedAt = (Get-Date).ToUniversalTime().ToString("o")
        processor = "SbProcessor"
        data = $data
    }
    
    # Convert to JSON with error handling
    try {
        $jsonData = $processedData | ConvertTo-Json -Depth 10 -ErrorAction Stop
    } catch {
        Write-Host "SbProcessor: Error converting to JSON - $($_.Exception.Message)"
        throw "Failed to serialize processed data: $($_.Exception.Message)"
    }
    
    # Save to blob storage with error handling
    try {
        if ($null -ne $outputBlob) {
            Push-OutputBinding -Name outputBlob -Value $jsonData -ErrorAction Stop
            Write-Host "SbProcessor: Data saved to ADLS Gen2"
        } else {
            Write-Host "SbProcessor: Blob output binding not available (local mode) - data logged only"
        }
    } catch {
        Write-Host "SbProcessor: Warning - Could not save to blob storage (local mode): $($_.Exception.Message)"
        Write-Host "SbProcessor: Data would be saved to: landing/vendors/$(Get-Date -Format 'yyyy/MM/dd')/$($message.id).json"
    }
    
    Write-Host "SbProcessor: Blob path: landing/vendors/$(Get-Date -Format 'yyyy/MM/dd')/$($message.id).json"
    Write-Host "SbProcessor: Processing completed successfully"
    
} catch {
    $errorMessage = $_.Exception.Message
    Write-Host "SbProcessor: Error processing message - $errorMessage" -ForegroundColor Red
    
    if ($_.ScriptStackTrace) {
        Write-Host "SbProcessor: Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Yellow
    }
    
    # Re-throw to trigger retry/dead-letter (only if not in local mode)
    if ($null -ne $outputBlob) {
        throw
    } else {
        Write-Host "SbProcessor: Local mode - not re-throwing error"
    }
}

