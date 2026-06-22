<#
.SYNOPSIS
    Lists all databases available to the authenticated user.

.EXAMPLE
    .\List-Databases.ps1 -Server "myserver" -Username "admin" -Password "admin"
#>

param(
    [Parameter(Mandatory)] [string] $Server,
    [Parameter(Mandatory)] [string] $Username,
    [Parameter(Mandatory)] [string] $Password,
    [int] $Port = 8714
)

$BaseUri = "https://${Server}:${Port}/v1.0"

# Login
$login = Invoke-RestMethod -Uri "$BaseUri/login" -Method POST `
    -Body (@{ user = $Username; pass = $Password } | ConvertTo-Json) `
    -ContentType "application/json" 
	
$headers = @{
    access_token = $login.access_token
    client_id    = $login.client_id
}

try {
    # List databases
    $result = Invoke-RestMethod -Uri "$BaseUri/list" `
        -Headers $headers 

    Write-Host "Available Databases:" -ForegroundColor Cyan
    Write-Host "====================" -ForegroundColor Cyan
    $result.databases | Format-Table `
        @{Label="Name"; Expression={$_.name}},
        @{Label="Fingerprint"; Expression={$_.fingerprint}},
        @{Label="Last Modified"; Expression={$_.date}},
        @{Label="Rights"; Expression={$_.rights}} -AutoSize

    Write-Host "Password Policy:" -ForegroundColor Cyan
    Write-Host "  Enforced:    $(if ($result.policyforce -eq '1') {'Yes'} else {'No'})"
    Write-Host "  Min Length:  $($result.policyminlength)"
    Write-Host "  Min Groups:  $($result.policymingroups)"
}
finally {
    # Logout
    Invoke-RestMethod -Uri "$BaseUri/logout" -Method POST `
        -Headers @{ client_id = $login.client_id } 
}
