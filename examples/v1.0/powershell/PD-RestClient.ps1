<#
.SYNOPSIS
    Password Depot REST API Client Module for PowerShell

.DESCRIPTION
    Reusable PowerShell functions for interacting with the Password Depot
    Enterprise Server REST API v1.0.

.NOTES
    Compatible with PowerShell 5.1 and later.

.EXAMPLE
    . .\PD-RestClient.ps1
    $session = Connect-PDServer -Server "myserver" -Username "admin" -Password "pass"
    $dbs = Get-PDDatabases -Session $session
    $entries = Get-PDEntries -Session $session -Database $dbs[0].fingerprint
    Disconnect-PDServer -Session $session
#>

function Connect-PDServer {
    <#
    .SYNOPSIS
        Authenticates with the Password Depot Server and returns a session object.
    .PARAMETER Server
        Hostname or IP address of the Password Depot Server.
    .PARAMETER Username
        Username for authentication.
    .PARAMETER Password
        Password for authentication.
    .PARAMETER Port
        REST service port (default: 8714).
    .PARAMETER TfaCode
        Optional 6-digit two-factor authentication code.
    #>
    param(
        [Parameter(Mandatory)] [string] $Server,
        [Parameter(Mandatory)] [string] $Username,
        [Parameter(Mandatory)] [string] $Password,
        [int] $Port = 8714,
        [string] $TfaCode
    )

    $baseUri = "https://${Server}:${Port}/v1.0"
    $body = @{ user = $Username; pass = $Password }

    if ($TfaCode) {
        $body.tfacode = $TfaCode
    }

    try {
        $response = Invoke-RestMethod -Uri "$baseUri/login" -Method POST `
            -Body ($body | ConvertTo-Json) `
            -ContentType "application/json"
    }
    catch {
        $errorBody = $_.ErrorDetails.Message | ConvertFrom-Json

        switch ($errorBody.code) {
            "459" {
                Write-Warning "2FA setup required. QR code URL: $($errorBody.error)"
                $qrPath = Join-Path $PWD "qr_code.png"
                Invoke-WebRequest -Uri $errorBody.error -OutFile $qrPath
                Write-Host "QR code saved to: $qrPath"
                Write-Host "Scan with your authenticator app, then re-run with -TfaCode parameter."
                return $null
            }
            "460" {
                $code = Read-Host "Enter your 2FA code"
                $body.tfacode = $code
                $response = Invoke-RestMethod -Uri "$baseUri/login" -Method POST `
                    -Body ($body | ConvertTo-Json) `
                    -ContentType "application/json"
            }
            default {
                throw "Login failed: $($errorBody.error)"
            }
        }
    }

    return [PSCustomObject]@{
        BaseUri      = $baseUri
        AccessToken  = $response.access_token
        ClientId     = $response.client_id
        Headers      = @{
            access_token = $response.access_token
            client_id    = $response.client_id
        }
        Server       = $Server
        Port         = $Port
        Username     = $Username
        ConnectedAt  = Get-Date
    }
}

function Disconnect-PDServer {
    <#
    .SYNOPSIS
        Logs out from the Password Depot Server.
    #>
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session
    )

    Invoke-RestMethod -Uri "$($Session.BaseUri)/logout" -Method POST `
        -Headers @{ client_id = $Session.ClientId }

    Write-Host "Disconnected from $($Session.Server)."
}

function Get-PDDatabases {
    <#
    .SYNOPSIS
        Lists all databases available to the authenticated user.
    #>
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session
    )

    $result = Invoke-RestMethod -Uri "$($Session.BaseUri)/list" `
        -Headers $Session.Headers

    return $result.databases
}

function Get-PDEntries {
    <#
    .SYNOPSIS
        Lists entries in a database folder.
    .PARAMETER Database
        Database fingerprint (UUID).
    .PARAMETER Folder
        Optional folder fingerprint. If omitted, lists root folder.
    #>
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $Database,
        [string] $Folder
    )

    $uri = "$($Session.BaseUri)/list?db=$Database"
    if ($Folder) {
        $uri += "&folder=$Folder"
    }

    $result = Invoke-RestMethod -Uri $uri `
        -Headers $Session.Headers

    return $result
}

function Read-PDEntry {
    <#
    .SYNOPSIS
        Reads all attributes of a specific entry.
    #>
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $Database,
        [Parameter(Mandatory)] [string] $Entry
    )

    $result = Invoke-RestMethod `
        -Uri "$($Session.BaseUri)/read?db=$Database&entry=$Entry" `
        -Headers $Session.Headers

    return $result
}

function New-PDEntry {
    <#
    .SYNOPSIS
        Creates a new entry in the database.
    .PARAMETER EntryData
        Hashtable with entry attributes (name, login, password, url, etc.).
    .PARAMETER Parent
        Optional parent folder fingerprint. Defaults to root folder.
    #>
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $Database,
        [Parameter(Mandatory)] [hashtable] $EntryData,
        [string] $Parent
    )

    $uri = "$($Session.BaseUri)/add?db=$Database"
    if ($Parent) {
        $uri += "&parent=$Parent"
    }

    $result = Invoke-RestMethod -Uri $uri -Method PUT `
        -Headers $Session.Headers `
        -Body ($EntryData | ConvertTo-Json -Depth 10) `
        -ContentType "application/json"

    return $result
}

function Set-PDEntry {
    <#
    .SYNOPSIS
        Modifies an existing entry.
    .PARAMETER Updates
        Hashtable with attributes to update.
    #>
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $Database,
        [Parameter(Mandatory)] [string] $Entry,
        [Parameter(Mandatory)] [hashtable] $Updates
    )

    Invoke-RestMethod `
        -Uri "$($Session.BaseUri)/modify?db=$Database&entry=$Entry" `
        -Method POST `
        -Headers $Session.Headers `
        -Body ($Updates | ConvertTo-Json -Depth 10) `
        -ContentType "application/json"
}

function Remove-PDEntries {
    <#
    .SYNOPSIS
        Deletes one or more entries.
    .PARAMETER Entries
        Array of entry fingerprints to delete.
    .PARAMETER Reason
        Optional reason for deletion.
    #>
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $Database,
        [Parameter(Mandatory)] [string[]] $Entries,
        [string] $Reason = ""
    )

    $body = @{
        reason  = $Reason
        entries = $Entries
    } | ConvertTo-Json

    Invoke-RestMethod `
        -Uri "$($Session.BaseUri)/delete?db=$Database" `
        -Method DELETE `
        -Headers $Session.Headers `
        -Body $body `
        -ContentType "application/json"
}

function Move-PDEntries {
    <#
    .SYNOPSIS
        Moves entries to a target folder.
    .PARAMETER TargetFolder
        Target folder fingerprint.
    .PARAMETER Entries
        Array of entry fingerprints to move.
    #>
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $Database,
        [Parameter(Mandatory)] [string] $TargetFolder,
        [Parameter(Mandatory)] [string[]] $Entries
    )

    $body = @{
        target  = $TargetFolder
        entries = $Entries
    } | ConvertTo-Json

    Invoke-RestMethod `
        -Uri "$($Session.BaseUri)/move?db=$Database" `
        -Method POST `
        -Headers $Session.Headers `
        -Body $body `
        -ContentType "application/json"
}

function Search-PDEntries {
    <#
    .SYNOPSIS
        Searches for entries matching a query.
    .PARAMETER Parent
        Optional parent folder to restrict search scope.
    #>
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $Database,
        [Parameter(Mandatory)] [string] $Query,
        [string] $Parent
    )

    $uri = "$($Session.BaseUri)/search?db=$Database&query=$Query"
    if ($Parent) {
        $uri += "&parent=$Parent"
    }

    $result = Invoke-RestMethod -Uri $uri `
        -Headers $Session.Headers

    return $result
}

# Verify that the script was dot-sourced (functions available in caller's scope)
if ($MyInvocation.InvocationName -eq '.' -or $MyInvocation.Line -match '^\.\s') {
    Write-Host "Password Depot REST Client module loaded." -ForegroundColor Green
    Write-Host "Available commands: Connect-PDServer, Disconnect-PDServer, Get-PDDatabases,"
    Write-Host "  Get-PDEntries, Read-PDEntry, New-PDEntry, Set-PDEntry,"
    Write-Host "  Remove-PDEntries, Move-PDEntries, Search-PDEntries"
} else {
    Write-Warning "This script must be dot-sourced to make its functions available:"
    Write-Warning "    . .\PD-RestClient.ps1"
    Write-Warning "Then use: Connect-PDServer -Server 'myserver' -Username 'admin' -Password 'pass'"
}
