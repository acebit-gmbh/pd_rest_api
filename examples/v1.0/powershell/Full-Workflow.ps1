<#
.SYNOPSIS
    Complete end-to-end workflow demonstrating all major REST API operations.

.DESCRIPTION
    This script demonstrates:
    - Login / Logout
    - Listing databases
    - Browsing entries
    - Creating a new entry
    - Searching for entries
    - Reading entry details

.EXAMPLE
    .\Full-Workflow.ps1 -Server "myserver" -Username "admin" -Password "pass"
#>

param(
    [Parameter(Mandatory)] [string] $Server,
    [Parameter(Mandatory)] [string] $Username,
    [Parameter(Mandatory)] [string] $Password,
    [int] $Port = 8714
)

$BaseUri = "https://${Server}:${Port}/v1.0"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Password Depot REST API - Full Workflow"     -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# ── 1. Login ──────────────────────────────────────────
Write-Host "`n[1/6] Logging in..." -ForegroundColor Yellow

$login = Invoke-RestMethod -Uri "$BaseUri/login" -Method POST `
    -Body (@{ user = $Username; pass = $Password } | ConvertTo-Json) `
    -ContentType "application/json"

$headers = @{
    access_token = $login.access_token
    client_id    = $login.client_id
}
Write-Host "  Logged in. Client ID: $($login.client_id)" -ForegroundColor Green

try {
    # ── 2. List Databases ─────────────────────────────
    Write-Host "`n[2/6] Listing databases..." -ForegroundColor Yellow

    $dbs = Invoke-RestMethod -Uri "$BaseUri/list" `
        -Headers $headers

    $dbs.databases | Format-Table name, fingerprint, rights -AutoSize

    if ($dbs.databases.Count -eq 0) {
        Write-Warning "No databases found. Exiting."
        return
    }

    $dbFp = $dbs.databases[0].fingerprint
    Write-Host "  Using: $($dbs.databases[0].name)" -ForegroundColor Green

    # ── 3. List Entries ───────────────────────────────
    Write-Host "`n[3/6] Listing entries in root folder..." -ForegroundColor Yellow

    $entries = Invoke-RestMethod -Uri "$BaseUri/list?db=$dbFp" `
        -Headers $headers

    if ($entries.entries -and $entries.entries.Count -gt 0) {
        $entries.entries | Format-Table name, login, url -AutoSize
    } else {
        Write-Host "  (No entries in root folder)"
    }

    # ── 4. Create Entry ──────────────────────────────
    Write-Host "[4/6] Creating a test entry..." -ForegroundColor Yellow

    $testEntry = @{
        name     = "API Workflow Test - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
        login    = "workflow_test"
        password = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 16 | ForEach-Object { [char]$_ })
        url      = "https://test.example.com"
    } | ConvertTo-Json

    $created = Invoke-RestMethod -Uri "$BaseUri/add?db=$dbFp" -Method PUT `
        -Headers $headers -Body $testEntry `
        -ContentType "application/json"

    Write-Host "  Entry created." -ForegroundColor Green

    # ── 5. Search ─────────────────────────────────────
    Write-Host "`n[5/6] Searching for 'workflow_test'..." -ForegroundColor Yellow

    $search = Invoke-RestMethod `
        -Uri "$BaseUri/search?db=$dbFp&query=workflow_test" `
        -Headers $headers

    if ($search.entries -and $search.entries.Count -gt 0) {
        Write-Host "  Found $($search.entries.Count) matching entries:" -ForegroundColor Green
        $search.entries | Format-Table name, login, url -AutoSize

        # ── Read first result ─────────────────────────
        Write-Host "[6/6] Reading entry details..." -ForegroundColor Yellow

        $detail = Invoke-RestMethod `
            -Uri "$BaseUri/read?db=$dbFp&entry=$($search.entries[0].fingerprint)" `
            -Headers $headers

        Write-Host "  Entry details:" -ForegroundColor Green
        $detail | ConvertTo-Json -Depth 5
    } else {
        Write-Host "  No entries found." -ForegroundColor Yellow
    }
}
finally {
    # ── Logout ────────────────────────────────────────
    Write-Host "`nLogging out..." -ForegroundColor Yellow
    Invoke-RestMethod -Uri "$BaseUri/logout" -Method POST `
        -Headers @{ client_id = $login.client_id }
    Write-Host "Done." -ForegroundColor Green
}
