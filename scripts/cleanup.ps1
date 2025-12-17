#Requires -Version 5.1

<#
.SYNOPSIS
    Cleans up all Azure resources created by the demo
#>

param(
    [string]$ResourceGroupName = (Get-Content "$PSScriptRoot\..\.deployment-info.json" -ErrorAction SilentlyContinue | ConvertFrom-Json).ResourceGroupName
)

if (-not $ResourceGroupName) {
    Write-Host "Error: Resource group not found. Specify -ResourceGroupName or run deploy-demo.ps1 first." -ForegroundColor Red
    exit 1
}

Write-Host "`nCleaning up resource group: $ResourceGroupName" -ForegroundColor Yellow
$confirm = Read-Host "Are you sure you want to delete all resources? (yes/no)"

if ($confirm -eq "yes") {
    az group delete --name $ResourceGroupName --yes --no-wait
    Write-Host "Resource group deletion initiated." -ForegroundColor Green
    
    # Remove deployment info file
    Remove-Item "$PSScriptRoot\..\.deployment-info.json" -ErrorAction SilentlyContinue
    
    Write-Host "Cleanup completed." -ForegroundColor Green
} else {
    Write-Host "Cleanup cancelled." -ForegroundColor Yellow
}

