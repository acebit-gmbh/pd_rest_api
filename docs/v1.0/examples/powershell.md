# PowerShell Examples

Complete PowerShell examples for all Password Depot REST API v1.0 endpoints.

!!! info "Prerequisites"
    - **PowerShell 5.1 or later**
    - Replace `YOUR_SERVER` with your Password Depot Server address

## Setup

### Define Base Variables

```powershell
$Server = "YOUR_SERVER"
$Port = 8714
$BaseUri = "https://${Server}:${Port}/v1.0"
```

### Self-Signed Certificate Workaround

If your server uses a self-signed certificate, add this at the beginning of your script to skip certificate validation:

```powershell
# Skip certificate validation for self-signed certificates
if (-not ([System.Management.Automation.PSTypeName]'TrustAllCerts').Type) {
    Add-Type @"
        using System.Net;
        using System.Security.Cryptography.X509Certificates;
        public class TrustAllCerts : ICertificatePolicy {
            public bool CheckValidationResult(
                ServicePoint sp, X509Certificate cert,
                WebRequest req, int problem) { return true; }
        }
"@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCerts
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
}
```

## Authentication

!!! warning "Legacy Servers (prior to v18.0.0)"
    The examples below pass login credentials as a JSON request body, which requires **v18.0.0 or later**. For older servers, credentials (`user`, `pass`, `tfacode`) must be passed as custom HTTP headers instead. See the [API Reference: Authentication](../api-reference/authentication.md) for legacy examples.

### Login

```powershell
$loginBody = @{
    user = "admin"
    pass = "my_password"
} | ConvertTo-Json

$login = Invoke-RestMethod -Uri "$BaseUri/login" `
    -Method POST `
    -Body $loginBody `
    -ContentType "application/json"

# Store headers for subsequent requests
$headers = @{
    access_token = $login.access_token
    client_id    = $login.client_id
}

Write-Host "Logged in successfully."
Write-Host "Client ID: $($login.client_id)"
```

### Login with 2FA

```powershell
$loginBody = @{
    user    = "admin"
    pass    = "my_password"
    tfacode = "123456"
} | ConvertTo-Json

$login = Invoke-RestMethod -Uri "$BaseUri/login" `
    -Method POST `
    -Body $loginBody `
    -ContentType "application/json"
```

### Logout

```powershell
Invoke-RestMethod -Uri "$BaseUri/logout" `
    -Method POST `
    -Headers @{ client_id = $login.client_id }

Write-Host "Logged out."
```

## Databases

### List All Databases

```powershell
$result = Invoke-RestMethod -Uri "$BaseUri/list" `
    -Headers $headers

# Display as table
$result.databases | Format-Table name, fingerprint, date, rights

# Access specific database
$db = $result.databases[0]
Write-Host "First database: $($db.name) ($($db.fingerprint))"
```

### Display Password Policy

```powershell
$result = Invoke-RestMethod -Uri "$BaseUri/list" `
    -Headers $headers

Write-Host "Password Policy:"
Write-Host "  Enforced:      $($result.policyforce -eq '1')"
Write-Host "  Min Length:    $($result.policyminlength)"
Write-Host "  Min Groups:   $($result.policymingroups)"
```

## Entries

### List Entries in Root Folder

```powershell
$dbFingerprint = $result.databases[0].fingerprint

$entries = Invoke-RestMethod `
    -Uri "$BaseUri/list?db=$dbFingerprint" `
    -Headers $headers

Write-Host "Folder: $($entries.name)"
$entries.entries | Format-Table name, login, url, fingerprint
```

### List Entries in a Specific Folder

```powershell
$folderFingerprint = "your-folder-fingerprint"

$folderEntries = Invoke-RestMethod `
    -Uri "$BaseUri/list?db=$dbFingerprint&folder=$folderFingerprint" `
    -Headers $headers

$folderEntries.entries | Format-Table name, login, url
```

### Read Entry Details

```powershell
$entryFingerprint = $entries.entries[0].fingerprint

$detail = Invoke-RestMethod `
    -Uri "$BaseUri/read?db=$dbFingerprint&entry=$entryFingerprint" `
    -Headers $headers

# Display all fields
$detail | ConvertTo-Json -Depth 5

# Access specific fields
Write-Host "Name:     $($detail.name)"
Write-Host "Login:    $($detail.login)"
Write-Host "URL:      $($detail.url)"
Write-Host "Password: $($detail.password)"
```

### Create a New Entry

```powershell
$newEntry = @{
    name     = "My New Entry"
    login    = "user@example.com"
    password = "secure_password_123"
    url      = "https://example.com"
} | ConvertTo-Json

# Add to root folder
$created = Invoke-RestMethod `
    -Uri "$BaseUri/add?db=$dbFingerprint" `
    -Method PUT `
    -Headers $headers `
    -Body $newEntry `
    -ContentType "application/json"

Write-Host "Created entry: $($created.name)"

# Add to specific folder
$created = Invoke-RestMethod `
    -Uri "$BaseUri/add?db=$dbFingerprint&parent=$folderFingerprint" `
    -Method PUT `
    -Headers $headers `
    -Body $newEntry `
    -ContentType "application/json"
```

### Modify an Entry

```powershell
$updates = @{
    name     = "Updated Entry Name"
    login    = "new_user@example.com"
    password = "new_password_456"
} | ConvertTo-Json

Invoke-RestMethod `
    -Uri "$BaseUri/modify?db=$dbFingerprint&entry=$entryFingerprint" `
    -Method POST `
    -Headers $headers `
    -Body $updates `
    -ContentType "application/json"

Write-Host "Entry updated."
```

## Search

### Search Entire Database

```powershell
$searchTerm = "example"

$results = Invoke-RestMethod `
    -Uri "$BaseUri/search?db=$dbFingerprint&query=$searchTerm" `
    -Headers $headers

Write-Host "Found $($results.entries.Count) entries:"
$results.entries | Format-Table name, login, url
```

### Search Within a Folder

```powershell
$results = Invoke-RestMethod `
    -Uri "$BaseUri/search?db=$dbFingerprint&query=$searchTerm&parent=$folderFingerprint" `
    -Headers $headers

$results.entries | Format-Table name, login, url
```

## Delete

### Delete Entries

```powershell
$deleteBody = @{
    reason  = "Credentials rotated"
    entries = @(
        "entry-uuid-1",
        "entry-uuid-2"
    )
} | ConvertTo-Json

Invoke-RestMethod `
    -Uri "$BaseUri/delete?db=$dbFingerprint" `
    -Method DELETE `
    -Headers $headers `
    -Body $deleteBody `
    -ContentType "application/json"

Write-Host "Entries deleted."
```

## Move

### Move Entries to Another Folder

```powershell
$moveBody = @{
    target  = "target-folder-fingerprint"
    entries = @(
        "entry-uuid-1",
        "entry-uuid-2"
    )
} | ConvertTo-Json

Invoke-RestMethod `
    -Uri "$BaseUri/move?db=$dbFingerprint" `
    -Method POST `
    -Headers $headers `
    -Body $moveBody `
    -ContentType "application/json"

Write-Host "Entries moved."
```

## Complete Workflow Script

A full end-to-end PowerShell script:

```powershell
param(
    [Parameter(Mandatory)] [string] $Server,
    [Parameter(Mandatory)] [string] $Username,
    [Parameter(Mandatory)] [string] $Password,
    [int] $Port = 8714
)

$BaseUri = "https://${Server}:${Port}/v1.0"

Write-Host "=== Password Depot REST API - PowerShell Workflow ===" -ForegroundColor Cyan

# 1. Login
Write-Host "`n--- Logging in..." -ForegroundColor Yellow
$loginBody = @{ user = $Username; pass = $Password } | ConvertTo-Json
$login = Invoke-RestMethod -Uri "$BaseUri/login" -Method POST `
    -Body $loginBody -ContentType "application/json"

$headers = @{
    access_token = $login.access_token
    client_id    = $login.client_id
}
Write-Host "Logged in. Client ID: $($login.client_id)"

try {
    # 2. List databases
    Write-Host "`n--- Databases:" -ForegroundColor Yellow
    $dbs = Invoke-RestMethod -Uri "$BaseUri/list" -Headers $headers
    $dbs.databases | Format-Table name, fingerprint, rights

    # 3. List entries in first database
    $dbFp = $dbs.databases[0].fingerprint
    Write-Host "--- Entries in '$($dbs.databases[0].name)':" -ForegroundColor Yellow
    $entries = Invoke-RestMethod -Uri "$BaseUri/list?db=$dbFp" `
        -Headers $headers
    $entries.entries | Format-Table name, login, url

    # 4. Create a new entry
    Write-Host "--- Creating new entry..." -ForegroundColor Yellow
    $newEntry = @{
        name     = "Test Entry from PowerShell"
        login    = "psuser"
        password = "ps_test_123"
        url      = "https://test.example.com"
    } | ConvertTo-Json

    $created = Invoke-RestMethod -Uri "$BaseUri/add?db=$dbFp" -Method PUT `
        -Headers $headers -Body $newEntry -ContentType "application/json"
    Write-Host "Created entry successfully."

    # 5. Search
    Write-Host "`n--- Searching for 'psuser'..." -ForegroundColor Yellow
    $search = Invoke-RestMethod `
        -Uri "$BaseUri/search?db=$dbFp&query=psuser" `
        -Headers $headers
    $search.entries | Format-Table name, login, url

} finally {
    # 6. Always logout
    Write-Host "`n--- Logging out..." -ForegroundColor Yellow
    Invoke-RestMethod -Uri "$BaseUri/logout" -Method POST `
        -Headers @{ client_id = $login.client_id }
    Write-Host "Done."
}
```

**Usage:**
```powershell
.\workflow.ps1 -Server "your-server" -Username "admin" -Password "my_password"
```

## Standalone Scripts

Ready-to-use PowerShell scripts are available in the [`examples/powershell/`](https://github.com/acebit-gmbh/pd_rest_api/tree/main/examples/v1.0/powershell) directory:

!!! tip "Dot-Source the Client Module"
    `PD-RestClient.ps1` must be **dot-sourced** to load its functions into your session:
    ```powershell
    . .\PD-RestClient.ps1
    $session = Connect-PDServer -Server "myserver" -Username "admin" -Password "pass"
    ```
    Running it without the dot (`. `) will not make the functions available.

| Script | Description |
|--------|-------------|
| `PD-RestClient.ps1` | Reusable PowerShell module (dot-source to load) |
| `Login-Example.ps1` | Authentication example |
| `List-Databases.ps1` | List all databases |
| `Search-Entries.ps1` | Search for entries |
| `Full-Workflow.ps1` | Complete end-to-end workflow |
