<#
.SYNOPSIS
    Password Depot REST API Client Module for PowerShell (v2.0)

.DESCRIPTION
    Reusable PowerShell functions for interacting with the Password Depot
    Enterprise Server REST API v2.0. Used by the test suite and as a
    standalone client library.

.NOTES
    Compatible with PowerShell 5.1 and later.

    Connections. Server 20.0.0 and later keeps a connection open between
    requests and closes an idle one after 15 seconds without sending
    anything. These functions issue their calls back to back and never sit
    idle that long, so they are unaffected. A script of your own that SLEEPS
    between calls can meet that close on Windows PowerShell 5.1: a POST or
    PUT issued just as the server closes fails with "A connection that was
    expected to be kept alive was closed by the server." Add
    -DisableKeepAlive to those calls, or retry the request once. PowerShell 7
    retries such a failure by itself.

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

function Get-PDDatabaseCategories {
    <#
    .SYNOPSIS
        Lists the category names a database carries - the picker its entry and
        folder editors offer. Returns the envelope (.data, .total); .data is a
        sorted array of strings and always the whole list, so there is no
        offset and no limit on this route.

        Read-only: a category is created by saving an entry or a folder with
        it (New-PDEntry / Set-PDEntry / New-PDFolder / Set-PDFolder). The match
        ignores letter case, and nothing removes a name from the list.

        Server 20.0.0 and later. The route itself is the feature test - there
        is no capability object for it, and a server without the route answers
        404, as does a database you cannot reach.
    #>
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $DatabaseId
    )
    # Always the client path: categories live under /databases, in both scopes.
    return Invoke-PDRequest -Session $Session -Path "/databases/$DatabaseId/categories"
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
    <#
    .SYNOPSIS
        Deletes a folder and everything under it.

        -Mode permanent destroys it; -Mode recycle asks for the database's
        recycle bin, from where it can be restored. Without -Mode nothing is
        sent and the server's default applies, which on Server 20.0.0 and
        later is the recycle bin. The parameter is read by Server 20.0.0 and
        later; the 'recycle_bin' object on the database object (Get-PDDatabase)
        is how a client detects that.
    #>
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $DatabaseId,
        [Parameter(Mandatory)] [string] $FolderId,
        [ValidateSet("recycle", "permanent")] [string] $Mode
    )
    $qp = @{}
    if ($Mode) { $qp.mode = $Mode }
    Invoke-PDRequest -Session $Session -Path "/databases/$DatabaseId/folders/$FolderId" -Method DELETE -QueryParams $qp
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
    <#
    .SYNOPSIS
        Creates an entry. -Totp stores a one-time code (TOTP) with it:
        @{ secret = "<Base32 seed>"; algorithm = "SHA1"; digits = 6; period = 30 }.
        secret is required; the other members default to SHA1 / 6 / 30.
        The seed is never returned. Server 20.0.0 or later; older servers
        ignore the key.
    #>
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $DatabaseId,
        [Parameter(Mandatory)] [hashtable] $Fields,
        [string] $ParentId,
        [hashtable] $Totp
    )
    $qp = @{}
    if ($ParentId) { $qp.parent = $ParentId }

    $body = $Fields
    if ($Totp) {
        $body = $Fields.Clone()
        $body.totp = $Totp
    }

    return Invoke-PDRequest -Session $Session -Path "/databases/$DatabaseId/entries" -Method POST -Body $body -QueryParams $qp
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
    <#
    .SYNOPSIS
        Deletes an entry.

        -Mode permanent destroys it; -Mode recycle asks for the database's
        recycle bin, from where it can be restored. Without -Mode nothing is
        sent and the server's default applies, which on Server 20.0.0 and
        later is the recycle bin. The parameter is read by Server 20.0.0 and
        later; the 'recycle_bin' object on the database object (Get-PDDatabase)
        is how a client detects that.
    #>
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $DatabaseId,
        [Parameter(Mandatory)] [string] $EntryId,
        [ValidateSet("recycle", "permanent")] [string] $Mode
    )
    $qp = @{}
    if ($Mode) { $qp.mode = $Mode }
    Invoke-PDRequest -Session $Session -Path "/databases/$DatabaseId/entries/$EntryId" -Method DELETE -QueryParams $qp
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

# --- Recycle Bin ---
# Server 20.0.0 and later. Detect support with the 'recycle_bin' object on the
# database object (Get-PDDatabase); an older server answers 404 on these paths.

function Get-PDRecycleBin {
    <#
    .SYNOPSIS
        Lists the items in a database's recycle bin that the caller may see -
        its own deletions always, other people's only when the database's
        recycle_bin.can_manage is true. Returns the paginated envelope
        (.data, .total, .offset, .limit); each row is the compact entry or
        folder representation, with 'type' telling the two apart.
    #>
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $DatabaseId,
        [int] $Offset = 0,
        [int] $Limit = 100
    )
    return Invoke-PDRequest -Session $Session -Path "/databases/$DatabaseId/recyclebin" `
        -QueryParams @{ offset = $Offset; limit = $Limit }
}

function Restore-PDRecycleBinItem {
    <#
    .SYNOPSIS
        Puts one item back into the folder it was deleted from, or into the
        database root when that folder is gone. Needs the right to change the
        folder the item returns to. The 204 does not say where the item landed -
        reload the folder, or read the item, to find out.
    #>
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $DatabaseId,
        [Parameter(Mandatory)] [string] $ItemId
    )
    Invoke-PDRequest -Session $Session -Path "/databases/$DatabaseId/recyclebin/$ItemId/restore" -Method POST -Body "{}"
}

function Remove-PDRecycleBinItem {
    <#
    .SYNOPSIS
        Destroys one item in the recycle bin - a folder with everything that
        went into the bin with it. This cannot be undone.
    #>
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $DatabaseId,
        [Parameter(Mandatory)] [string] $ItemId
    )
    Invoke-PDRequest -Session $Session -Path "/databases/$DatabaseId/recyclebin/$ItemId" -Method DELETE
}

function Clear-PDRecycleBin {
    <#
    .SYNOPSIS
        Destroys every item in the database's recycle bin that the caller can
        see and may delete. An item it may not see, or may not delete, is left
        in the bin. This cannot be undone.
    #>
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $DatabaseId
    )
    Invoke-PDRequest -Session $Session -Path "/databases/$DatabaseId/recyclebin" -Method DELETE
}

# --- One-Time Code ---

function Get-PDEntryOneTimeCode {
    <#
    .SYNOPSIS
        Returns the entry's current one-time code (TOTP): code, digits, period,
        expires_in and algorithm. Requires a login session; long-lived API tokens
        are refused. Server 20.0.0 or later.
    #>
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
    return Invoke-PDRequest -Session $Session -Path "/databases/$DatabaseId/entries/$EntryId/otp" -Headers $headers
}

function Set-PDEntryOneTimeCode {
    <#
    .SYNOPSIS
        Sets, replaces or re-parameterises the entry's one-time code (TOTP)
        through PATCH .../entries/{id} with a "totp" object. With -Secret the
        seed is set or replaced and all four members are sent (the omitted ones
        as SHA1 / 6 / 30). Without -Secret only the members you pass change and
        the stored seed is kept. The seed is never returned. Long-lived API
        tokens may write seeds. Server 20.0.0 or later.
    .EXAMPLE
        Set-PDEntryOneTimeCode -Session $s -DatabaseId $db -EntryId $id -Secret "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
        Set-PDEntryOneTimeCode -Session $s -DatabaseId $db -EntryId $id -Digits 8
    #>
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $DatabaseId,
        [Parameter(Mandatory)] [string] $EntryId,
        [string] $Secret,
        [string] $Algorithm,
        [int] $Digits,
        [int] $Period,
        [string] $SecondPassword
    )
    $totp = @{}
    if ($Secret) {
        # When a seed is sent, send all four members (documented client obligation).
        $totp.secret = $Secret
        $totp.algorithm = if ($Algorithm) { $Algorithm } else { "SHA1" }
        $totp.digits = if ($Digits) { $Digits } else { 6 }
        $totp.period = if ($Period) { $Period } else { 30 }
    } else {
        if ($Algorithm) { $totp.algorithm = $Algorithm }
        if ($Digits) { $totp.digits = $Digits }
        if ($Period) { $totp.period = $Period }
    }
    if ($totp.Count -eq 0) {
        throw "Set-PDEntryOneTimeCode: pass -Secret, or at least one of -Algorithm, -Digits, -Period"
    }
    return Set-PDEntry -Session $Session -DatabaseId $DatabaseId -EntryId $EntryId -Fields @{ totp = $totp } -SecondPassword $SecondPassword
}

function Clear-PDEntryOneTimeCode {
    <#
    .SYNOPSIS
        Removes the entry's one-time code (TOTP) through PATCH .../entries/{id}
        with "totp": null. The seed cannot be read back first, and this API
        cannot restore it (it stays in the entry's history where the database
        keeps one). Server 20.0.0 or later.
    #>
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
    $json = '{"totp":null}'
    return Invoke-PDRequest -Session $Session -Path "/databases/$DatabaseId/entries/$EntryId" -Method PATCH -Body $json -Headers $headers
}

# --- Database Icons ---

function Get-PDDatabaseIcon {
    <#
    .SYNOPSIS
        Reads the icons stored in a database ("custom icons"). Without -Id or
        -Ids: the paginated list, without image data (id, name, version).
        -Ids with -IncludeData: up to 32 icons with their images in one call.
        -Id: one icon with its image; -OutFile also writes the decoded image
        to a file. The image is Base64 in 'data'; 'content_type' is image/png,
        or image/bmp for icons an older client stored. Detect support by the
        'icons' object on the database. Server 20.0.0 or later.
    .EXAMPLE
        (Get-PDDatabaseIcon -Session $s -DatabaseId $db).data | Format-Table id, name, version
        Get-PDDatabaseIcon -Session $s -DatabaseId $db -Ids "3","7" -IncludeData
        Get-PDDatabaseIcon -Session $s -DatabaseId $db -Id "3" -OutFile ".\example.com.png"
    #>
    [CmdletBinding(DefaultParameterSetName = "List")]
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $DatabaseId,
        [Parameter(Mandatory, ParameterSetName = "One")] [string] $Id,
        [Parameter(ParameterSetName = "One")] [string] $OutFile,
        [Parameter(Mandatory, ParameterSetName = "Batch")] [string[]] $Ids,
        [Parameter(ParameterSetName = "Batch")] [switch] $IncludeData,
        [Parameter(ParameterSetName = "List")] [int] $Offset = 0,
        [Parameter(ParameterSetName = "List")] [int] $Limit = 100
    )

    if ($PSCmdlet.ParameterSetName -eq "One") {
        if ($Id -notmatch '^[0-9]{1,6}$') { throw "Get-PDDatabaseIcon: -Id must be 1 to 6 decimal digits" }
        $icon = Invoke-PDRequest -Session $Session -Path "/databases/$DatabaseId/icons/$Id"
        if ($OutFile) {
            if ($icon.state -ne "ok" -or -not $icon.data) {
                throw "Get-PDDatabaseIcon: icon $Id has no usable image (state '$($icon.state)')"
            }
            $target = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
            [System.IO.File]::WriteAllBytes($target, [Convert]::FromBase64String($icon.data))
        }
        return $icon
    }

    if ($PSCmdlet.ParameterSetName -eq "Batch") {
        foreach ($one in $Ids) {
            if ($one -notmatch '^[0-9]{1,6}$') { throw "Get-PDDatabaseIcon: every id must be 1 to 6 decimal digits ('$one')" }
        }
        # The order matters for nothing, but keep the hashtable small and explicit.
        $qp = @{ ids = ($Ids -join ",") }
        if ($IncludeData) { $qp.include = "data" }
        return Invoke-PDRequest -Session $Session -Path "/databases/$DatabaseId/icons" -QueryParams $qp
    }

    return Invoke-PDRequest -Session $Session -Path "/databases/$DatabaseId/icons" -QueryParams @{ offset = $Offset; limit = $Limit }
}

function Add-PDDatabaseIcon {
    <#
    .SYNOPSIS
        Uploads an icon to a database: POST .../icons with {"name","data"}, the
        image as Base64 inside JSON. The server accepts PNG only, at most
        icons.max_side (64) pixels per side and icons.max_bytes (32768) bytes;
        both limits are read from the database's 'icons' object. -Resize turns
        any picture System.Drawing can read (PNG, JPEG, GIF, BMP, ICO) into
        what the Password Depot clients send: the picture scaled to fit a
        transparent 64x64 canvas, saved as PNG. Without -Resize the bytes must
        already be such a PNG. Returns id, name, version and created; USE THE
        RETURNED name for image_name - it may be "<name> (2)" when an icon of
        that name with a different image exists. The upload is database-wide,
        visible to every user of the database, and cannot be deleted over
        REST. Server 20.0.0 or later.
    .EXAMPLE
        $icon = Add-PDDatabaseIcon -Session $s -DatabaseId $db -Name "example.com" -Path ".\logo.jpg" -Resize
        Set-PDEntryIcon -Session $s -DatabaseId $db -EntryId $id -Name $icon.name
    #>
    [CmdletBinding(DefaultParameterSetName = "Path")]
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $DatabaseId,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory, ParameterSetName = "Path")] [string] $Path,
        [Parameter(Mandatory, ParameterSetName = "Bytes")] [byte[]] $Bytes,
        [switch] $Resize
    )

    # Capability first: a server without the 'icons' object has no such route,
    # and the contract forbids probing by upload.
    $db = Get-PDDatabase -Session $Session -DatabaseId $DatabaseId
    if ($null -eq $db.PSObject.Properties['icons']) {
        throw "Add-PDDatabaseIcon: this server has no database-icon support (older than 20.0.0)"
    }
    if (-not $db.icons.can_upload) {
        throw "Add-PDDatabaseIcon: icons.can_upload is false (mirror server, or the database has no icon slot left)"
    }
    $maxBytes = [int] $db.icons.max_bytes
    $maxSide = [int] $db.icons.max_side

    if ($PSCmdlet.ParameterSetName -eq "Path") {
        $source = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        $raw = [System.IO.File]::ReadAllBytes($source)
    } else {
        $raw = $Bytes
    }

    if ($Resize) {
        Add-Type -AssemblyName System.Drawing
        $side = [Math]::Min(64, $maxSide)   # 64x64 is the native size of a Password Depot icon
        $inStream = New-Object System.IO.MemoryStream(, $raw)
        $src = $null; $canvas = $null; $g = $null
        $outStream = New-Object System.IO.MemoryStream
        try {
            $src = [System.Drawing.Image]::FromStream($inStream)
            $canvas = New-Object System.Drawing.Bitmap($side, $side, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $g = [System.Drawing.Graphics]::FromImage($canvas)
            $g.Clear([System.Drawing.Color]::Transparent)
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

            # "contain": the whole picture, centred, aspect ratio kept
            $scale = [Math]::Min($side / $src.Width, $side / $src.Height)
            $w = [Math]::Max(1, [int] [Math]::Round($src.Width * $scale))
            $h = [Math]::Max(1, [int] [Math]::Round($src.Height * $scale))
            $x = [int] [Math]::Floor(($side - $w) / 2)
            $y = [int] [Math]::Floor(($side - $h) / 2)
            $g.DrawImage($src, (New-Object System.Drawing.Rectangle($x, $y, $w, $h)))

            $canvas.Save($outStream, [System.Drawing.Imaging.ImageFormat]::Png)
            $raw = $outStream.ToArray()
        }
        finally {
            if ($g) { $g.Dispose() }
            if ($canvas) { $canvas.Dispose() }
            if ($src) { $src.Dispose() }
            $inStream.Dispose()
            $outStream.Dispose()
        }
    } else {
        # Refuse locally what the server would refuse: not a PNG, or too many pixels.
        $sig = [byte[]] @(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
        $isPng = ($raw.Length -ge 24)
        for ($i = 0; $isPng -and $i -lt 8; $i++) { if ($raw[$i] -ne $sig[$i]) { $isPng = $false } }
        if (-not $isPng) { throw "Add-PDDatabaseIcon: the image is not a PNG; pass -Resize to convert it" }
        $pngW = ([int64] $raw[16] -shl 24) -bor ([int64] $raw[17] -shl 16) -bor ([int64] $raw[18] -shl 8) -bor [int64] $raw[19]
        $pngH = ([int64] $raw[20] -shl 24) -bor ([int64] $raw[21] -shl 16) -bor ([int64] $raw[22] -shl 8) -bor [int64] $raw[23]
        if ($pngW -gt $maxSide -or $pngH -gt $maxSide) {
            throw "Add-PDDatabaseIcon: the PNG is ${pngW}x${pngH}; the server accepts at most ${maxSide}x${maxSide}. Pass -Resize"
        }
    }

    # No step-down: the canvas is always 64x64. A PNG that is still too large is refused here.
    if ($raw.Length -gt $maxBytes) {
        throw "Add-PDDatabaseIcon: the PNG has $($raw.Length) bytes; the server accepts at most $maxBytes"
    }

    $body = @{ name = $Name; data = [Convert]::ToBase64String($raw) }
    return Invoke-PDRequest -Session $Session -Path "/databases/$DatabaseId/icons" -Method POST -Body $body
}

function Set-PDEntryIcon {
    <#
    .SYNOPSIS
        Selects an entry's icon through PATCH .../entries/{id}: -Name assigns
        the database icon of that name (as Add-PDDatabaseIcon or
        Get-PDDatabaseIcon returned it), -StandardIndex one of the standard
        icons 0 to 134, -Reset the standard icon of the entry's type. A name
        that is not an icon of this database answers 400 with error.code 4007
        and changes nothing. Returns the compact entry: 'database_icon' names
        the icon, 'icon' the standard icon to fall back on.
        Server 20.0.0 or later.
    .EXAMPLE
        Set-PDEntryIcon -Session $s -DatabaseId $db -EntryId $id -Name "example.com"
        Set-PDEntryIcon -Session $s -DatabaseId $db -EntryId $id -StandardIndex 12
        Set-PDEntryIcon -Session $s -DatabaseId $db -EntryId $id -Reset
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [PSCustomObject] $Session,
        [Parameter(Mandatory)] [string] $DatabaseId,
        [Parameter(Mandatory)] [string] $EntryId,
        [Parameter(Mandatory, ParameterSetName = "Name")] [string] $Name,
        [Parameter(Mandatory, ParameterSetName = "Standard")] [ValidateRange(0, 134)] [int] $StandardIndex,
        [Parameter(Mandatory, ParameterSetName = "Reset")] [switch] $Reset,
        [string] $SecondPassword
    )
    switch ($PSCmdlet.ParameterSetName) {
        "Name"     { $fields = @{ image_custom = $true; image_name = $Name } }
        "Standard" { $fields = @{ image_custom = $false; image_index = $StandardIndex } }
        default    { $fields = @{ image_custom = $false; image_index = -1 } }
    }
    return Set-PDEntry -Session $Session -DatabaseId $DatabaseId -EntryId $EntryId -Fields $fields -SecondPassword $SecondPassword
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
