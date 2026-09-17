<#
.SYNOPSIS
    Searches for entries in a Password Depot database.

.EXAMPLE
    .\Search-Entries.ps1 -Server "myserver" -Username "admin" -Password "pass" -Query "example"

.EXAMPLE
    .\Search-Entries.ps1 -Server "myserver" -Username "admin" -Password "pass" -Query "admin" -DatabaseName "db_1.pswe"
#>

param(
    [Parameter(Mandatory)] [string] $Server,
    [Parameter(Mandatory)] [string] $Username,
    [Parameter(Mandatory)] [string] $Password,
    [Parameter(Mandatory)] [string] $Query,
    [int] $Port = 8714,
    [string] $DatabaseName
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
    # Get databases
    $dbs = Invoke-RestMethod -Uri "$BaseUri/list" `
        -Headers $headers

    # Select database
    if ($DatabaseName) {
        $db = $dbs.databases | Where-Object { $_.name -eq $DatabaseName }
        if (-not $db) {
            Write-Error "Database '$DatabaseName' not found."
            return
        }
    } else {
        $db = $dbs.databases[0]
        Write-Host "Using first database: $($db.name)" -ForegroundColor Yellow
    }

    # Search
    Write-Host "Searching for '$Query' in $($db.name)..." -ForegroundColor Cyan

    $results = Invoke-RestMethod `
        -Uri "$BaseUri/search?db=$($db.fingerprint)&query=$Query" `
        -Headers $headers

    if ($results.entries -and $results.entries.Count -gt 0) {
        Write-Host "Found $($results.entries.Count) entries:" -ForegroundColor Green
        $results.entries | Format-Table `
            @{Label="Name"; Expression={$_.name}},
            @{Label="Login"; Expression={$_.login}},
            @{Label="URL"; Expression={$_.url}},
            @{Label="Modified"; Expression={$_.date}} -AutoSize
    } else {
        Write-Host "No entries found." -ForegroundColor Yellow
    }
}
finally {
    Invoke-RestMethod -Uri "$BaseUri/logout" -Method POST `
        -Headers @{ client_id = $login.client_id }
}
