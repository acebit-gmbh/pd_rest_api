<#
.SYNOPSIS
    Password Depot REST API Client Module for PowerShell (v2.0)

.DESCRIPTION
    Reusable PowerShell functions for interacting with the Password Depot
    Enterprise Server REST API v2.0. Used by the test suite and as a
    standalone client library.

.NOTES
    Compatible with PowerShell 5.1 and later.

.EXAMPLE
    . .\PD-RestClient-v2.ps1
    $session = Connect-PDServer -Server "myserver" -Username "admin" -Password "pass" -Scope "admin"
    $dbs = Get-PDDatabases -Session $session
    $children = Get-PDChildren -Session $session -DatabaseId $dbs[0].id
    Disconnect-PDServer -Session $session
#>

# --- Helper ---

function Invoke-PDRequest {
    <#
    .SYNOPSIS
        Sends an authenticated request to the PD REST API v2.0.
        Returns the parsed response body, or $null for 204 No Content.
    #>
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $Path,
        [string] $Method = "GET",
        [object] $Body,
        [hashtable] $Headers = @{},
        [hashtable] $QueryParams = @{}
    )

    $uri = "$($Session.BaseUri)$Path"

    # Append query params
    if ($QueryParams.Count -gt 0) {
        $qs = ($QueryParams.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "&"
        $uri += "?$qs"
    }

    $allHeaders = @{ Authorization = "Bearer $($Session.Token)" }
    foreach ($k in $Headers.Keys) { $allHeaders[$k] = $Headers[$k] }

    $params = @{
        Uri         = $uri
        Method      = $Method
        Headers     = $allHeaders
        ContentType = "application/json"
    }

    if ($Body) {
        if ($Body -is [string]) {
            $params.Body = $Body
        } else {
            $params.Body = $Body | ConvertTo-Json -Depth 10
        }
    }

    $response = Invoke-WebRequest @params -UseBasicParsing

    if ($response.StatusCode -eq 204) { return $null }
    return $response.Content | ConvertFrom-Json
}

# --- Authentication ---

function Connect-PDServer {
    <#
    .SYNOPSIS
        Authenticates with the Password Depot Server v2.0 and returns a session object.
    #>
    param(
        [Parameter(Mandatory)] [string] $Server,
        [Parameter(Mandatory)] [string] $Username,
        [Parameter(Mandatory)] [string] $Password,
        [int] $Port = 8714,
        [string] $Scope = "client",
        [string] $TfaCode
    )

    $baseUri = "https://${Server}:${Port}/v2.0"
    $body = @{ user = $Username; pass = $Password; scope = $Scope }

    if ($TfaCode) {
        $body.tfacode = $TfaCode
    }

    try {
        $response = Invoke-RestMethod -Uri "$baseUri/auth/login" -Method POST `
            -Body ($body | ConvertTo-Json) -ContentType "application/json"
    }
    catch {
        # Transport-level failures (SSL handshake, DNS, TCP) have no HTTP body to parse.
        # Only HTTP error responses carry $_.ErrorDetails.Message with JSON.
        $errorBody = $null
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            try { $errorBody = $_.ErrorDetails.Message | ConvertFrom-Json } catch {}
        }

        if (-not $errorBody) {
            # Non-HTTP failure (TLS, network...). Surface the real reason.
            throw "Login to $baseUri failed: $($_.Exception.Message)"
        }

        $code = $errorBody.error.code

        if ($code -eq 460) {
            $tfaInput = Read-Host "Enter your 2FA code"
            $body.tfacode = $tfaInput
            $response = Invoke-RestMethod -Uri "$baseUri/auth/login" -Method POST `
                -Body ($body | ConvertTo-Json) -ContentType "application/json"
        }
        elseif ($code -eq 459) {
            Write-Warning "2FA setup required. QR code URL: $($errorBody.error.message)"
            return $null
        }
        else {
            throw "Login failed ($code): $($errorBody.error.message)"
        }
    }

    return [PSCustomObject]@{
        BaseUri = $baseUri
        Token   = $response.access_token
        Server  = $Server
        Port    = $Port
        Scope   = $Scope
    }
}

function Disconnect-PDServer {
    param([Parameter(Mandatory)] [PSCustomObject] $Session)
    try {
        Invoke-PDRequest -Session $Session -Path "/auth/logout" -Method POST | Out-Null
    } catch {}
}

# --- Databases ---

function Get-PDDatabases {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [int] $Offset = 0,
        [int] $Limit = 100
    )
    if ($Session.Scope -eq "admin") {
        return Invoke-PDRequest -Session $Session -Path "/admin/databases" -QueryParams @{ offset = $Offset; limit = $Limit }
    } else {
        return Invoke-PDRequest -Session $Session -Path "/databases" -QueryParams @{ offset = $Offset; limit = $Limit }
    }
}

function Get-PDDatabase {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $DatabaseId
    )
    if ($Session.Scope -eq "admin") {
        return Invoke-PDRequest -Session $Session -Path "/admin/databases/$DatabaseId"
    } else {
        return Invoke-PDRequest -Session $Session -Path "/databases/$DatabaseId"
    }
}

# --- Folders ---

function Get-PDChildren {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $DatabaseId,
        [string] $FolderId,
        [int] $Offset = 0,
        [int] $Limit = 100
    )
    if ($FolderId) {
        $path = "/databases/$DatabaseId/folders/$FolderId/children"
    } else {
        $path = "/databases/$DatabaseId/children"
    }
    return Invoke-PDRequest -Session $Session -Path $path -QueryParams @{ offset = $Offset; limit = $Limit }
}

function Get-PDFolder {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $DatabaseId,
        [Parameter(Mandatory)] [string] $FolderId,
        [string] $SecondPassword
    )
    $headers = @{}
    if ($SecondPassword) {
        $headers["X-Second-Password"] = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($SecondPassword))
    }
    return Invoke-PDRequest -Session $Session -Path "/databases/$DatabaseId/folders/$FolderId" -Headers $headers
}

function New-PDFolder {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $DatabaseId,
        [Parameter(Mandatory)] [string] $Name,
        [string] $ParentId,
        [string] $Importance = "normal",
        [string] $Category,
        [string] $Tags,
        [string] $Comments
    )
    $body = @{ name = $Name; importance = $Importance }
    if ($Category) { $body.category = $Category }
    if ($Tags) { $body.tags = $Tags }
    if ($Comments) { $body.comments = $Comments }

    $qp = @{}
    if ($ParentId) { $qp.parent = $ParentId }

    return Invoke-PDRequest -Session $Session -Path "/databases/$DatabaseId/folders" -Method POST -Body $body -QueryParams $qp
}

function Set-PDFolder {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $DatabaseId,
        [Parameter(Mandatory)] [string] $FolderId,
        [Parameter(Mandatory)] [hashtable] $Fields
    )
    return Invoke-PDRequest -Session $Session -Path "/databases/$DatabaseId/folders/$FolderId" -Method PATCH -Body $Fields
}

function Remove-PDFolder {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $DatabaseId,
        [Parameter(Mandatory)] [string] $FolderId
    )
    Invoke-PDRequest -Session $Session -Path "/databases/$DatabaseId/folders/$FolderId" -Method DELETE
}

function Move-PDFolder {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $DatabaseId,
        [Parameter(Mandatory)] [string] $FolderId,
        [string] $TargetId  # $null or empty = move to root
    )
    if ($TargetId) {
        $json = "{`"target`":`"$TargetId`"}"
    } else {
        $json = '{"target":null}'
    }
    return Invoke-PDRequest -Session $Session -Path "/databases/$DatabaseId/folders/$FolderId/move" -Method POST -Body $json
}

# --- Entries ---

function Get-PDEntry {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $DatabaseId,
        [Parameter(Mandatory)] [string] $EntryId,
        [string] $SecondPassword
    )
    $headers = @{}
    if ($SecondPassword) {
        $headers["X-Second-Password"] = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($SecondPassword))
    }
    return Invoke-PDRequest -Session $Session -Path "/databases/$DatabaseId/entries/$EntryId" -Headers $headers
}

function New-PDEntry {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $DatabaseId,
        [Parameter(Mandatory)] [hashtable] $Fields,
        [string] $ParentId
    )
    $qp = @{}
    if ($ParentId) { $qp.parent = $ParentId }

    return Invoke-PDRequest -Session $Session -Path "/databases/$DatabaseId/entries" -Method POST -Body $Fields -QueryParams $qp
}

function Set-PDEntry {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $DatabaseId,
        [Parameter(Mandatory)] [string] $EntryId,
        [Parameter(Mandatory)] [hashtable] $Fields,
        [string] $SecondPassword
    )
    $headers = @{}
    if ($SecondPassword) {
        $headers["X-Second-Password"] = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($SecondPassword))
    }
    return Invoke-PDRequest -Session $Session -Path "/databases/$DatabaseId/entries/$EntryId" -Method PATCH -Body $Fields -Headers $headers
}

function Remove-PDEntry {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $DatabaseId,
        [Parameter(Mandatory)] [string] $EntryId
    )
    Invoke-PDRequest -Session $Session -Path "/databases/$DatabaseId/entries/$EntryId" -Method DELETE
}

function Move-PDEntry {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $DatabaseId,
        [Parameter(Mandatory)] [string] $EntryId,
        [string] $TargetId  # $null or empty = move to root
    )
    if ($TargetId) {
        $json = "{`"target`":`"$TargetId`"}"
    } else {
        $json = '{"target":null}'
    }
    return Invoke-PDRequest -Session $Session -Path "/databases/$DatabaseId/entries/$EntryId/move" -Method POST -Body $json
}

# --- Document Content ---

function Set-PDDocumentContent {
    <#
    .SYNOPSIS
        Uploads binary content to a document entry.
    #>
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $DatabaseId,
        [Parameter(Mandatory)] [string] $EntryId,
        [Parameter(Mandatory)] [byte[]] $Content,
        [Parameter(Mandatory)] [string] $ContentType,
        [string] $FileName
    )
    $uri = "$($Session.BaseUri)/databases/$DatabaseId/entries/$EntryId/content"
    $headers = @{ Authorization = "Bearer $($Session.Token)" }
    if ($FileName) {
        $headers["Content-Disposition"] = "attachment; filename=`"$FileName`""
    }
    $response = Invoke-WebRequest -Uri $uri -Method PUT -Headers $headers `
        -ContentType $ContentType -Body $Content -UseBasicParsing
    if ($response.StatusCode -eq 204) { return $null }
    return $response.Content | ConvertFrom-Json
}

function Get-PDDocumentContent {
    <#
    .SYNOPSIS
        Downloads binary content of a document entry.
        Returns a hashtable with Content (byte[]), ContentType, and FileName.
    #>
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $DatabaseId,
        [Parameter(Mandatory)] [string] $EntryId
    )
    $uri = "$($Session.BaseUri)/databases/$DatabaseId/entries/$EntryId/content"
    $headers = @{ Authorization = "Bearer $($Session.Token)" }
    $response = Invoke-WebRequest -Uri $uri -Method GET -Headers $headers -UseBasicParsing

    # Extract filename from Content-Disposition header
    $fileName = ""
    $cd = $response.Headers["Content-Disposition"]
    if ($cd -match 'filename="?([^"]+)"?') {
        $fileName = $Matches[1]
    }

    # RawContentStream always returns bytes regardless of content type
    $ms = New-Object System.IO.MemoryStream
    $response.RawContentStream.CopyTo($ms)
    $bytes = $ms.ToArray()
    $ms.Dispose()

    return @{
        Content     = $bytes
        ContentType = $response.Headers["Content-Type"]
        FileName    = $fileName
        Size        = $bytes.Length
    }
}

# --- Search ---

function Search-PDEntries {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $DatabaseId,
        [Parameter(Mandatory)] [string] $Query,
        [int] $Offset = 0,
        [int] $Limit = 100
    )
    return Invoke-PDRequest -Session $Session -Path "/databases/$DatabaseId/search" -QueryParams @{ q = $Query; offset = $Offset; limit = $Limit }
}

# --- Users (client scope: read-only) ---

function Get-PDUsers {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [int] $Offset = 0,
        [int] $Limit = 100
    )
    if ($Session.Scope -eq "admin") {
        return Invoke-PDRequest -Session $Session -Path "/admin/users" -QueryParams @{ offset = $Offset; limit = $Limit }
    } else {
        return Invoke-PDRequest -Session $Session -Path "/users" -QueryParams @{ offset = $Offset; limit = $Limit }
    }
}

function Get-PDUser {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $UserId
    )
    if ($Session.Scope -eq "admin") {
        return Invoke-PDRequest -Session $Session -Path "/admin/users/$UserId"
    } else {
        return Invoke-PDRequest -Session $Session -Path "/users/$UserId"
    }
}

# --- Groups (client scope: read-only) ---

function Get-PDGroups {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [int] $Offset = 0,
        [int] $Limit = 100
    )
    if ($Session.Scope -eq "admin") {
        return Invoke-PDRequest -Session $Session -Path "/admin/groups" -QueryParams @{ offset = $Offset; limit = $Limit }
    } else {
        return Invoke-PDRequest -Session $Session -Path "/groups" -QueryParams @{ offset = $Offset; limit = $Limit }
    }
}

# --- Admin: Users CRUD ---

function New-PDUser {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [hashtable] $Fields
    )
    return Invoke-PDRequest -Session $Session -Path "/admin/users" -Method POST -Body $Fields
}

function Set-PDUser {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $UserId,
        [Parameter(Mandatory)] [hashtable] $Fields
    )
    return Invoke-PDRequest -Session $Session -Path "/admin/users/$UserId" -Method PATCH -Body $Fields
}

function Remove-PDUser {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $UserId
    )
    Invoke-PDRequest -Session $Session -Path "/admin/users/$UserId" -Method DELETE
}

# --- Admin: Groups CRUD ---

function New-PDGroup {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [hashtable] $Fields
    )
    return Invoke-PDRequest -Session $Session -Path "/admin/groups" -Method POST -Body $Fields
}

function Set-PDGroup {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $GroupId,
        [Parameter(Mandatory)] [hashtable] $Fields
    )
    return Invoke-PDRequest -Session $Session -Path "/admin/groups/$GroupId" -Method PATCH -Body $Fields
}

function Remove-PDGroup {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $GroupId
    )
    Invoke-PDRequest -Session $Session -Path "/admin/groups/$GroupId" -Method DELETE
}

# --- Admin: Alerts CRUD ---

function Get-PDAlerts {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [int] $Offset = 0,
        [int] $Limit = 100
    )
    return Invoke-PDRequest -Session $Session -Path "/admin/alerts" -QueryParams @{ offset = $Offset; limit = $Limit }
}

function Get-PDAlert {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $AlertId
    )
    return Invoke-PDRequest -Session $Session -Path "/admin/alerts/$AlertId"
}

function New-PDAlert {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [hashtable] $Fields
    )
    return Invoke-PDRequest -Session $Session -Path "/admin/alerts" -Method POST -Body $Fields
}

function Set-PDAlert {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $AlertId,
        [Parameter(Mandatory)] [hashtable] $Fields
    )
    return Invoke-PDRequest -Session $Session -Path "/admin/alerts/$AlertId" -Method PATCH -Body $Fields
}

function Remove-PDAlert {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $AlertId
    )
    Invoke-PDRequest -Session $Session -Path "/admin/alerts/$AlertId" -Method DELETE
}

# --- Admin: Permissions CRUD ---

function Get-PDPermissions {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $DatabaseId,
        [int] $Offset = 0,
        [int] $Limit = 100
    )
    return Invoke-PDRequest -Session $Session -Path "/admin/databases/$DatabaseId/permissions" -QueryParams @{ offset = $Offset; limit = $Limit }
}

function Get-PDPermission {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $DatabaseId,
        [Parameter(Mandatory)] [string] $PermissionId
    )
    return Invoke-PDRequest -Session $Session -Path "/admin/databases/$DatabaseId/permissions/$PermissionId"
}

function New-PDPermission {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $DatabaseId,
        [Parameter(Mandatory)] [hashtable] $Fields
    )
    return Invoke-PDRequest -Session $Session -Path "/admin/databases/$DatabaseId/permissions" -Method POST -Body $Fields
}

function Set-PDPermission {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $DatabaseId,
        [Parameter(Mandatory)] [string] $PermissionId,
        [Parameter(Mandatory)] [hashtable] $Fields
    )
    return Invoke-PDRequest -Session $Session -Path "/admin/databases/$DatabaseId/permissions/$PermissionId" -Method PATCH -Body $Fields
}

function Remove-PDPermission {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $DatabaseId,
        [Parameter(Mandatory)] [string] $PermissionId
    )
    Invoke-PDRequest -Session $Session -Path "/admin/databases/$DatabaseId/permissions/$PermissionId" -Method DELETE
}

# --- Secrets (Shared Links) ---

function Get-PDSecrets {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [int] $Offset = 0,
        [int] $Limit = 100
    )
    if ($Session.Scope -eq "admin") {
        return Invoke-PDRequest -Session $Session -Path "/admin/secrets" -QueryParams @{ offset = $Offset; limit = $Limit }
    } else {
        return Invoke-PDRequest -Session $Session -Path "/secrets" -QueryParams @{ offset = $Offset; limit = $Limit }
    }
}

function Get-PDSecret {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $SecretId
    )
    if ($Session.Scope -eq "admin") {
        return Invoke-PDRequest -Session $Session -Path "/admin/secrets/$SecretId"
    } else {
        return Invoke-PDRequest -Session $Session -Path "/secrets/$SecretId"
    }
}

function New-PDSecret {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [hashtable] $Fields
    )
    $path = if ($Session.Scope -eq "admin") { "/admin/secrets" } else { "/secrets" }
    return Invoke-PDRequest -Session $Session -Path $path -Method POST -Body $Fields
}

function Set-PDSecret {
    <# Admin scope only #>
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $SecretId,
        [Parameter(Mandatory)] [hashtable] $Fields
    )
    return Invoke-PDRequest -Session $Session -Path "/admin/secrets/$SecretId" -Method PATCH -Body $Fields
}

function Remove-PDSecret {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $SecretId
    )
    if ($Session.Scope -eq "admin") {
        Invoke-PDRequest -Session $Session -Path "/admin/secrets/$SecretId" -Method DELETE
    } else {
        Invoke-PDRequest -Session $Session -Path "/secrets/$SecretId" -Method DELETE
    }
}

function Approve-PDSecret {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $SecretId,
        [int] $ExtendMinutes = 0
    )
    $path = if ($Session.Scope -eq "admin") { "/admin/secrets/$SecretId/approve" } else { "/secrets/$SecretId/approve" }
    $body = @{}
    if ($ExtendMinutes -gt 0) { $body.extends = $ExtendMinutes }
    return Invoke-PDRequest -Session $Session -Path $path -Method POST -Body $body
}

function Deny-PDSecret {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $SecretId
    )
    $path = if ($Session.Scope -eq "admin") { "/admin/secrets/$SecretId/reject" } else { "/secrets/$SecretId/reject" }
    return Invoke-PDRequest -Session $Session -Path $path -Method POST -Body @{}
}

function Revoke-PDSecret {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $SecretId
    )
    $path = if ($Session.Scope -eq "admin") { "/admin/secrets/$SecretId/revoke" } else { "/secrets/$SecretId/revoke" }
    return Invoke-PDRequest -Session $Session -Path $path -Method POST -Body @{}
}

# --- Me (current user profile) ---

function Get-PDMe {
    param([Parameter(Mandatory)] [PSCustomObject] $Session)
    return Invoke-PDRequest -Session $Session -Path "/me"
}

function Set-PDMyProfile {
    <#
    .SYNOPSIS
        Update the caller's own profile. Allowed fields: display_name, department, phone.
    .DESCRIPTION
        Only the fields passed as parameters are sent in the PATCH body.
        Username, roles, groups, auth-mode, 2FA settings, and password cannot
        be changed via this endpoint. Use /me/password for password changes.
    #>
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [string] $DisplayName,
        [string] $Department,
        [string] $Phone
    )
    $body = @{}
    if ($PSBoundParameters.ContainsKey('DisplayName')) { $body.display_name = $DisplayName }
    if ($PSBoundParameters.ContainsKey('Department'))  { $body.department   = $Department }
    if ($PSBoundParameters.ContainsKey('Phone'))       { $body.phone        = $Phone }
    return Invoke-PDRequest -Session $Session -Path "/me" -Method PATCH -Body $body
}

# --- Passkeys / WebAuthn credentials ---

function Get-PDPasskeys {
    <# List own passkeys (or any user's, in admin scope) #>
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [string] $UserId  # if provided, uses /admin/users/{id}/passkeys (admin scope only)
    )
    if ($UserId) {
        return Invoke-PDRequest -Session $Session -Path "/admin/users/$UserId/passkeys"
    } else {
        return Invoke-PDRequest -Session $Session -Path "/me/passkeys"
    }
}

function Rename-PDPasskey {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $PasskeyId,
        [Parameter(Mandatory)] [string] $NewName
    )
    return Invoke-PDRequest -Session $Session -Path "/me/passkeys/$PasskeyId" -Method PATCH -Body @{ name = $NewName }
}

function Remove-PDPasskey {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $PasskeyId,
        [string] $UserId  # if provided, uses /admin/users/{id}/passkeys/{id} (admin)
    )
    if ($UserId) {
        Invoke-PDRequest -Session $Session -Path "/admin/users/$UserId/passkeys/$PasskeyId" -Method DELETE
    } else {
        Invoke-PDRequest -Session $Session -Path "/me/passkeys/$PasskeyId" -Method DELETE
    }
}

# Begin/complete are exposed for completeness, but cannot be tested without a real authenticator
function Start-PDPasskeyRegistration {
    param([Parameter(Mandatory)] [PSCustomObject] $Session)
    return Invoke-PDRequest -Session $Session -Path "/me/passkeys/begin" -Method POST -Body @{}
}

function Complete-PDPasskeyRegistration {
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [hashtable] $AuthenticatorResponse  # session_id + WebAuthn fields + optional name
    )
    return Invoke-PDRequest -Session $Session -Path "/me/passkeys/complete" -Method POST -Body $AuthenticatorResponse
}
