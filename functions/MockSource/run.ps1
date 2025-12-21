using namespace System.Net

param($Request, $TriggerMetadata, $Response)

$ErrorActionPreference = "Continue"

try {
    Write-Host "MockSource: Request received at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
} catch {
    Write-Host "MockSource: Warning - Could not log request time"
}

try {
    # Generate sample vendor data
    $vendors = @(
        @{
            vendorId = "VENDOR-001"
            name = "Acme Corporation"
            email = "contact@acme.com"
            address = @{
                street = "123 Business St"
                city = "New York"
                state = "NY"
                zipCode = "10001"
                country = "USA"
            }
            contactPerson = "John Doe"
            phone = "+1-555-0101"
            status = "Active"
            registrationDate = "2024-01-15"
        },
        @{
            vendorId = "VENDOR-002"
            name = "Tech Solutions Inc"
            email = "info@techsolutions.com"
            address = @{
                street = "456 Innovation Ave"
                city = "San Francisco"
                state = "CA"
                zipCode = "94102"
                country = "USA"
            }
            contactPerson = "Jane Smith"
            phone = "+1-555-0102"
            status = "Active"
            registrationDate = "2024-02-20"
        },
        @{
            vendorId = "VENDOR-003"
            name = "Global Supplies Ltd"
            email = "sales@globalsupplies.com"
            address = @{
                street = "789 Trade Blvd"
                city = "London"
                state = ""
                zipCode = "SW1A 1AA"
                country = "UK"
            }
            contactPerson = "Robert Brown"
            phone = "+44-20-5555-0103"
            status = "Pending"
            registrationDate = "2024-03-10"
        }
    )
    
    # Build response body with error handling
    try {
        $responseBody = @{
            vendors = $vendors
            count = $vendors.Count
            timestamp = (Get-Date).ToUniversalTime().ToString("o")
            source = "MockSource"
        } | ConvertTo-Json -Depth 10 -ErrorAction Stop
        
        # Return vendor data
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body = $responseBody
            ContentType = "application/json"
        })
    } catch {
        Write-Host "MockSource: Error creating response - $($_.Exception.Message)" -ForegroundColor Red
        # Fallback response
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body = '{"vendors":[],"count":0,"source":"MockSource","error":"Failed to serialize response"}'
            ContentType = "application/json"
        })
    }
    
} catch {
    Write-Host "MockSource: Error processing request - $($_.Exception.Message)" -ForegroundColor Red
    
    try {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body = @{
                error = $_.Exception.Message
                status = "error"
                source = "MockSource"
            } | ConvertTo-Json
            ContentType = "application/json"
        })
    } catch {
        Write-Host "MockSource: Critical error - Could not send error response" -ForegroundColor Red
    }
}

