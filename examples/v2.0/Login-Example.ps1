<#
.SYNOPSIS
    Demonstrates login and logout with the Password Depot REST API.

.EXAMPLE
    .\Login-Example.ps1 -Server "myserver" -Username "admin" -Password "admin"
#>


param(
    [Parameter(Mandatory)] [string] $Server,
    [Parameter(Mandatory)] [string] $Username,
    [Parameter(Mandatory)] [string] $Password,
    [int] $Port = 8714
)

$BaseUri = "https://${Server}:${Port}/v2.0/auth"

# Login
Write-Host "Logging in to $Server..." -ForegroundColor Cyan

$loginBody = @{
    user = $Username
    pass = $Password
} | ConvertTo-Json

$login = Invoke-RestMethod -Uri "$BaseUri/login" -Method POST `
    -Body $loginBody -ContentType "application/json"

Write-Host "Login successful!" -ForegroundColor Green
Write-Host "  Access Token: $($login.access_token.Substring(0, 20))..."

# Logout
# Write-Host "`nLogging out..." -ForegroundColor Cyan

#Invoke-RestMethod -Uri "$BaseUri/logout" -Method POST `
#   -Headers @{ client_id = $login.client_id } 

#Write-Host "Logged out." -ForegroundColor Green
