<#
.SYNOPSIS
    Comprehensive integration test suite for Password Depot REST API v2.0.

.DESCRIPTION
    Tests the full API lifecycle: authentication, databases, folders, entries,
    search, users, groups, alerts, permissions, and /me endpoint.

    Requires an admin account on a running PD Enterprise Server with at least
    one database accessible by the test user.

.PARAMETER Server
    Hostname of the Password Depot Server.
.PARAMETER Username
    Admin username for testing.
.PARAMETER Password
    Password for the admin user.
.PARAMETER Port
    REST API port (default: 8714).
.PARAMETER DatabaseId
    UUID of an existing database to use for folder/entry tests.
    If omitted, the first available database is used.

.EXAMPLE
    .\Run-Tests.ps1 -Server "your-server" -Username "admin" -Password "<admin-password>"
    .\Run-Tests.ps1 -Server "your-server" -Username "admin" -Password "<admin-password>" -DatabaseId "00000000-0000-0000-0000-000000000000"
	.\Run-Tests.ps1 -Server "your-server" -Username "test_api" -Password "<password>"
#>

param(
    [Parameter(Mandatory)] [string] $Server,
    [Parameter(Mandatory)] [string] $Username,
    [Parameter(Mandatory)] [string] $Password,
    [int] $Port = 8714,
    [string] $DatabaseId,
    [string] $ApiToken
)

# Load modules
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptDir\Test-Framework.ps1"
. "$scriptDir\PD-RestClient-v2.ps1"

# Suppress SSL cert warnings for self-signed certs
if (-not ([System.Management.Automation.PSTypeName]'TrustAllCertsPolicy').Type) {
    Add-Type @"
        using System.Net;
        using System.Security.Cryptography.X509Certificates;
        public class TrustAllCertsPolicy : ICertificatePolicy {
            public bool CheckValidationResult(ServicePoint srvPoint, X509Certificate certificate,
                WebRequest request, int certificateProblem) { return true; }
        }
"@
}
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
# Enable TLS 1.2 AND 1.3 (the server may be configured for TLS 1.3-only after hardening).
# Tls13 enum value is 12288; symbolic name requires .NET 4.8+ so we fall back to the literal.
$tls13 = [enum]::ToObject([System.Net.SecurityProtocolType], 12288)
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor $tls13

$totalFailures = 0

# ============================================================
#  1. AUTHENTICATION
# ============================================================

Start-TestSuite "Authentication"

$adminSession = $null
$clientSession = $null

# 1.1 Admin login
Start-Test "Admin login"
try {
    $adminSession = Connect-PDServer -Server $Server -Username $Username -Password $Password -Port $Port -Scope "admin"
    if (Assert-NotNull $adminSession.Token "access_token") { Pass-Test }
} catch { Fail-Test $_.Exception.Message }

# 1.2 Client login
Start-Test "Client login"
try {
    $clientSession = Connect-PDServer -Server $Server -Username $Username -Password $Password -Port $Port -Scope "client"
    if (Assert-NotNull $clientSession.Token "access_token") { Pass-Test }
} catch { Fail-Test $_.Exception.Message }

# 1.3 Invalid credentials
Start-Test "Invalid credentials -> 401"
if (Assert-HttpError -ExpectedCode 401 -Action {
    Invoke-RestMethod -Uri "https://${Server}:${Port}/v2.0/auth/login" -Method POST `
        -Body '{"user":"nonexistent","pass":"wrong"}' -ContentType "application/json"
}) { Pass-Test "401 as expected" }

# 1.4 Client scope cannot access admin endpoints
Start-Test "Client scope -> admin endpoint -> 403"
if (Assert-HttpError -ExpectedCode 403 -Action {
    Invoke-PDRequest -Session $clientSession -Path "/admin/users"
}) { Pass-Test "403 as expected" }

# 1.5 /me endpoint
Start-Test "GET /me"
try {
    $me = Get-PDMe -Session $clientSession
    if ((Assert-NotNull $me.id "id") -and (Assert-NotNull $me.name "name")) { Pass-Test "$($me.name)" }
} catch { Fail-Test $_.Exception.Message }

# 1.5.1 B12: PATCH /me happy path - display_name, department, phone
Start-Test "PATCH /me updates allowed fields"
try {
    $orig = Get-PDMe -Session $clientSession
    $newDisplay = "B12 Test $(Get-Random)"
    $newDept    = "QA-$(Get-Random)"
    $newPhone   = "+1-555-$(Get-Random -Min 1000 -Max 9999)"
    $updated = Set-PDMyProfile -Session $clientSession -DisplayName $newDisplay -Department $newDept -Phone $newPhone
    $ok = ($updated.display_name -eq $newDisplay) -and ($updated.department -eq $newDept) -and ($updated.phone -eq $newPhone)
    if ($ok) {
        # Restore original values
        Set-PDMyProfile -Session $clientSession -DisplayName $orig.display_name -Department $orig.department -Phone $orig.phone | Out-Null
        Pass-Test "display_name, department, phone updated and restored"
    } else {
        Fail-Test "Got display_name='$($updated.display_name)', department='$($updated.department)', phone='$($updated.phone)'"
    }
} catch { Fail-Test $_.Exception.Message }

# 1.5.2 B12: PATCH /me with disallowed field -> 400
$disallowedCases = @(
    @{ field = 'name';            body = @{ name = "hijacked" } },
    @{ field = 'email';           body = @{ email = "x@y.z" } },
    @{ field = 'roles';           body = @{ roles = @("super_admin") } },
    @{ field = 'member_of';       body = @{ member_of = @() } },
    @{ field = 'auth_modes';      body = @{ auth_modes = @("standard") } },
    @{ field = 'two_factor_mode'; body = @{ two_factor_mode = "disabled" } },
    @{ field = 'disabled';        body = @{ disabled = $true } },
    @{ field = 'password';        body = @{ password = "x" } },
    @{ field = 'new_password';    body = @{ new_password = "x" } }
)
$allRejected = $true
foreach ($c in $disallowedCases) {
    if (-not (Assert-HttpError -ExpectedCode 400 -Action {
        Invoke-PDRequest -Session $clientSession -Path "/me" -Method PATCH -Body $c.body
    })) {
        $allRejected = $false
        Start-Test "PATCH /me { $($c.field): ... } -> 400"
        Fail-Test "Expected 400 for field '$($c.field)'"
        break
    }
}
if ($allRejected) {
    Start-Test "PATCH /me rejects disallowed fields -> 400"
    Pass-Test "$($disallowedCases.Count) disallowed fields rejected"
}

# 1.5.3 B12: empty PATCH body is accepted
Start-Test "PATCH /me with {} -> 200"
try {
    $me2 = Invoke-PDRequest -Session $clientSession -Path "/me" -Method PATCH -Body @{}
    if ($me2.name -eq $clientSession.Username -or $me2.id) { Pass-Test "empty patch returns current profile" }
    else { Fail-Test "Unexpected response: $($me2 | ConvertTo-Json -Compress)" }
} catch { Fail-Test $_.Exception.Message }

# 1.5b B1: /me/unknown-subpath must 404, not silently return /me profile
Start-Test "GET /me/foobar -> 404"
if (Assert-HttpError -ExpectedCode 404 -Action {
    Invoke-PDRequest -Session $clientSession -Path "/me/foobar"
}) { Pass-Test "404 as expected" }

# 1.5bc C13: trailing segments on known sub-paths must 404, not silently execute
# the action. These specifically guard against the "DELETE /admin/users/{id}/tfa
# silently deletes the user" class of bug across the v2.0 routing.
$c13Cases = @(
    @{ method = 'POST';   path = "/me/password/extra";                 why = '/me/password trailing' },
    @{ method = 'GET';    path = "/me/passkeys/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/extra"; why = '/me/passkeys/{id} trailing' },
    @{ method = 'POST';   path = "/auth/webauthn/begin/extra";         why = '/auth/webauthn/begin trailing' },
    @{ method = 'GET';    path = "/users/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/extra"; why = '/users/{id} trailing' },
    @{ method = 'GET';    path = "/groups/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/extra"; why = '/groups/{id} trailing' }
)
$allRejected = $true
foreach ($c in $c13Cases) {
    if (-not (Assert-HttpError -ExpectedCode 404 -Action {
        Invoke-PDRequest -Session $clientSession -Path $c.path -Method $c.method
    })) {
        $allRejected = $false
        Start-Test "C13: $($c.why) -> 404"
        Fail-Test "Expected 404 for $($c.method) $($c.path)"
        break
    }
}
if ($allRejected) {
    Start-Test "C13 client-scope trailing segments -> 404"
    Pass-Test "$($c13Cases.Count) trailing-segment cases rejected"
}

# 1.5b2 B9: v2.0 path segments are case-sensitive
Start-Test "GET /ME (uppercase) -> 404"
if (Assert-HttpError -ExpectedCode 404 -Action {
    Invoke-PDRequest -Session $clientSession -Path "/ME"
}) { Pass-Test "404 as expected" }

# 1.5c B4/B5: OPTIONS (CORS preflight) returns 204 with proper headers and no body
Start-Test "OPTIONS preflight: 204 + clean CORS headers"
try {
    $resp = Invoke-WebRequest -Uri "https://${Server}:${Port}/v2.0/databases" -Method OPTIONS `
        -UseBasicParsing -Headers @{ Origin = "https://any.example.com"; 'Access-Control-Request-Method' = 'GET' }

    # Note: `access_token` and `client_id` ARE expected in Allow-Headers --
    # they are needed by the v1.0 API for backward compatibility and must
    # remain advertised through CORS.
    $checks = @(
        @{ name = 'status is 204'; pass = ($resp.StatusCode -eq 204) }
        @{ name = 'body is empty'; pass = ([string]::IsNullOrEmpty($resp.Content) -or $resp.Content.Length -eq 0) }
        @{ name = 'Allow-Origin is *'; pass = ($resp.Headers['Access-Control-Allow-Origin'] -eq '*') }
        @{ name = 'no Allow-Credentials header'; pass = (-not $resp.Headers.ContainsKey('Access-Control-Allow-Credentials')) }
        @{ name = 'Allow-Methods includes OPTIONS'; pass = ($resp.Headers['Access-Control-Allow-Methods'] -match 'OPTIONS') }
        @{ name = 'Allow-Headers includes Authorization'; pass = ($resp.Headers['Access-Control-Allow-Headers'] -match 'Authorization') }
        @{ name = 'Max-Age is present'; pass = ($resp.Headers.ContainsKey('Access-Control-Max-Age')) }
    )
    $failed = $checks | Where-Object { -not $_.pass }
    if ($failed.Count -eq 0) {
        Pass-Test "all $($checks.Count) CORS checks passed"
    } else {
        $failedNames = ($failed | ForEach-Object { $_.name }) -join '; '
        Fail-Test "CORS checks failed: $failedNames"
    }
} catch { Fail-Test $_.Exception.Message }

# 1.6 Invalid token
Start-Test "Invalid token -> 401"
$fakeSession = [PSCustomObject]@{ BaseUri = "https://${Server}:${Port}/v2.0"; Token = "invalid.token.here" }
if (Assert-HttpError -ExpectedCode 401 -Action {
    Invoke-PDRequest -Session $fakeSession -Path "/databases"
}) { Pass-Test "401 as expected" }

# 1.6.1 B20: malformed JSON on /auth/login -> 400 (not 401). The fix also
# excludes these from the IP-lockout counter, but that can only be verified
# from a non-loopback peer; covered manually.
#
# Note on test bodies: Delphi's TJSONObject.Parse is lenient about some
# technically-dubious input. Numeric overflow literals like `{"a":1e99999}`
# parse as valid JSON (the number is read as Infinity / a very large
# double) and never reach the 400 path. We only test bodies that are
# structurally unparseable by any standard JSON grammar.
Start-Test "Malformed JSON on /auth/login -> 400"
$loginUri = "https://${Server}:${Port}/v2.0/auth/login"
$deepNested = '{' + ('"a":{' * 600) + '"x":1' + ('}' * 601)  # B18: exceeds Delphi's 512-nesting cap
$badBodies = @(
    '{not even json',                         # missing closing brace + bareword key
    '{"a":}',                                 # colon with no value
    '{"a":"b",,}',                            # trailing comma between members
    $deepNested                               # B18: deep nesting, must not leak parser path/offset
)
# B18: leaky tokens from the raw Delphi JSON parser message
$leakTokens = @('Path ''', 'line 1', 'position ', 'offset ', 'nesting level')
$allPassed = $true
foreach ($body in $badBodies) {
    $label = if ($body.Length -gt 40) { $body.Substring(0, 40) + '...' } else { $body }
    $code = 0
    $respBody = $null
    try {
        Invoke-RestMethod -Uri $loginUri -Method POST -Body $body -ContentType "application/json" | Out-Null
        $allPassed = $false
        Fail-Test "Expected 400 for body: $label"
        break
    } catch {
        if ($_.Exception.Response) { $code = [int] $_.Exception.Response.StatusCode }
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $respBody = $_.ErrorDetails.Message }
    }
    if ($code -ne 400) {
        $allPassed = $false
        Fail-Test "Got $code (expected 400) for body: $label"
        break
    }
    if ($respBody) {
        foreach ($t in $leakTokens) {
            if ($respBody -match [regex]::Escape($t)) {
                $allPassed = $false
                Fail-Test "Response leaks parser token '$t' for body: $label"
                break
            }
        }
        if (-not $allPassed) { break }
    }
}
if ($allPassed) { Pass-Test "All $($badBodies.Count) malformed bodies -> 400 without parser-internal leaks" }

# 1.6.2 R3: /auth/webauthn/begin must not leak per-user state. Whether the
# username is unknown, disabled, WebAuthn-not-enabled, or has no passkeys --
# the response message must be identical so an unauthenticated caller cannot
# enumerate users or auth state. Skipped silently if WebAuthn is disabled
# server-side (/begin returns 400 in that case).
Start-Test "R3: WebAuthn begin returns generic error for all user states"
try {
    $waUri = "https://${Server}:${Port}/v2.0/auth/webauthn/begin"
    $probes = @(
        'zz_does_not_exist_{0}' -f (Get-Random),
        'yy_also_unknown_{0}'   -f (Get-Random),
        'xx_some_other_{0}'     -f (Get-Random)
    )
    $messages = @()
    $statusCodes = @()
    $webauthnDisabled = $false
    foreach ($u in $probes) {
        try {
            Invoke-RestMethod -Uri $waUri -Method POST -ContentType 'application/json' `
                -Body (@{ user = $u; scope = 'client' } | ConvertTo-Json) | Out-Null
            $statusCodes += 200
            $messages += '(ok)'
        } catch {
            $code = if ($_.Exception.Response) { [int] $_.Exception.Response.StatusCode } else { 0 }
            $statusCodes += $code
            $msg = if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                try { (ConvertFrom-Json $_.ErrorDetails.Message).error.message } catch { $_.ErrorDetails.Message }
            } else { $_.Exception.Message }
            $messages += $msg
            if ($code -eq 400) { $webauthnDisabled = $true }
        }
    }
    if ($webauthnDisabled) {
        Skip-Test "Server has WebAuthn disabled (enable in Server Manager to run this test)"
    } else {
        $leakyTokens = @('not found', 'No passkeys', 'not activated', 'disabled', 'auth method')
        $distinct = $messages | Select-Object -Unique
        $leaks = @()
        foreach ($m in $messages) {
            foreach ($t in $leakyTokens) {
                if ($m -match [regex]::Escape($t)) { $leaks += $t; break }
            }
        }
        if ($distinct.Count -ne 1) {
            Fail-Test "Messages differ across probes: $($distinct -join ' | ')"
        } elseif ($leaks.Count -gt 0) {
            Fail-Test "Leaky wording in response: $($leaks -join ', '). Got: $($distinct[0])"
        } elseif ($statusCodes | Where-Object { $_ -ne 401 }) {
            Fail-Test "Expected 401 for all probes, got: $($statusCodes -join ', ')"
        } else {
            Pass-Test "3 probes -> same generic 401 message ('$($distinct[0])')"
        }
    }
} catch { Fail-Test $_.Exception.Message }

# 1.7 Client logout
Start-Test "Client logout"
try {
    Disconnect-PDServer -Session $clientSession
    Pass-Test
} catch { Fail-Test $_.Exception.Message }

$totalFailures += Write-TestSummary

# ============================================================
#  2. DATABASES
# ============================================================

Start-TestSuite "Databases"

$testDbId = $DatabaseId

# 2.1 List databases (admin)
Start-Test "List databases (admin)"
try {
    $dbs = Get-PDDatabases -Session $adminSession
    if (Assert-NotNull $dbs.data "data") {
        if (-not $testDbId -and $dbs.data.Count -gt 0) {
            $testDbId = $dbs.data[0].id
        }
        Pass-Test "$($dbs.total) database(s)"
    }
} catch { Fail-Test $_.Exception.Message }

# 2.2 Get database detail
Start-Test "Get database detail (admin)"
if ($testDbId) {
    try {
        $db = Get-PDDatabase -Session $adminSession -DatabaseId $testDbId
        if ((Assert-NotNull $db.id "id") -and (Assert-NotNull $db.name "name")) { Pass-Test "$($db.name)" }
    } catch { Fail-Test $_.Exception.Message }
} else { Skip-Test "No database available" }

# 2.3 Get non-existent database -> 404
Start-Test "Get non-existent database -> 404"
if (Assert-HttpError -ExpectedCode 404 -Action {
    Get-PDDatabase -Session $adminSession -DatabaseId "00000000-0000-0000-0000-000000000000"
}) { Pass-Test "404 as expected" }

# 2.4 Reject path-traversal names on create -> 400
$pathTraversalNames = @(
    '../../evil-traversal',          # unix-style
    '..\..\evil-traversal',          # windows-style
    'foo/bar',                       # slash mid-name
    'foo\bar',                       # backslash mid-name
    'C:\pwn',                        # drive letter
    'CON',                           # reserved device name
    'nul.dbp',                       # reserved name + ext
    '.leadingdot',                   # leading dot
    'trailingdot.',                  # trailing dot
    '  spaces  ',                    # leading/trailing whitespace
    "bad`twith`ttab",                # control character (tab)
    'weird*file',                    # wildcard
    '..dotsonly..',                  # `..` sequence
    '\\evil-host\share\payload',     # UNC path (SMB call-home)
    '//evil-host/share/payload',     # UNC path (forward-slash variant)
    "claude-null$([char]0)suffix",   # C4: NULL byte truncation (must not bypass .dbp suffix)
    "before$([char]10)after",        # LF control char
    "before$([char]13)after"         # CR control char
)
foreach ($badName in $pathTraversalNames) {
    Start-Test "Reject traversal name: '$badName'"
    if (Assert-HttpError -ExpectedCode 400 -Action {
        Invoke-PDRequest -Session $adminSession -Path "/admin/databases" -Method POST -Body @{ name = $badName }
    }) { Pass-Test "400 as expected" }
}

# 2.5 Error responses must not leak internal paths (C2 fix)
# If we ever 500, the client must get a generic message, not an OS path.
$leakIndicators = @('Program Files', 'Data\DB', 'Password Depot Server', '_database.pswd', '.dbp\')
Start-Test "No path leak on error (C:/Windows/... repro)"
$responseBody = $null
try {
    Invoke-PDRequest -Session $adminSession -Path "/admin/databases" -Method POST -Body @{ name = "C:/Windows/System32/claude-evil" }
} catch {
    # either response type is fine (400 expected after C1 fix, but 500 would be a regression)
    try { $responseBody = $_.ErrorDetails.Message } catch { $responseBody = $_.Exception.Message }
}
$leaked = $false
foreach ($indicator in $leakIndicators) {
    if ($responseBody -and $responseBody -like "*$indicator*") {
        $leaked = $true
        Fail-Test "Response leaked '$indicator': $responseBody"
        break
    }
}
if (-not $leaked) { Pass-Test "no internal paths in error response" }

# 2.6 C-Zusatzbefund: name with embedded dot must NOT be truncated at the dot.
# Before the fix, ChangeFileExt treated the last dot as an extension boundary,
# so "Q4.2024" would be stored as folder "Q4.dbp". Now EnsureFileExt preserves
# the full name.
Start-Test "Embedded dot in DB name is preserved (no truncation)"
$dotName = "Q4.2024"
$createdDbId = $null
try {
    $created = Invoke-PDRequest -Session $adminSession -Path "/admin/databases" -Method POST -Body @{ name = $dotName }
    $createdDbId = $created.id
    $detail = Get-PDDatabase -Session $adminSession -DatabaseId $createdDbId
    # The round-tripped name should preserve the dot and end with .pswe.
    if ((Assert-True ($detail.name.StartsWith("Q4.2024")) "name starts with 'Q4.2024'") -and
        (Assert-True ($detail.name.EndsWith(".pswe")) "name ends with '.pswe'")) {
        Pass-Test "stored name='$($detail.name)'"
    }
} catch { Fail-Test $_.Exception.Message }
# Clean up
if ($createdDbId) {
    try { Invoke-PDRequest -Session $adminSession -Path "/admin/databases/$createdDbId" -Method DELETE } catch {}
}

$totalFailures += Write-TestSummary

# ============================================================
#  3. FOLDERS
# ============================================================

Start-TestSuite "Folders"

$testFolderId = $null
$testSubFolderId = $null

if (-not $testDbId) {
    Start-Test "All folder tests"
    Skip-Test "No database available"
} else {
    # 3.1 List root children
    Start-Test "List root children"
    try {
        $root = Get-PDChildren -Session $adminSession -DatabaseId $testDbId
        if (Assert-NotNull $root "response") { Pass-Test "$($root.total) item(s) at root" }
    } catch { Fail-Test $_.Exception.Message }

    # 3.2 Create folder at root
    Start-Test "Create folder at root"
    try {
        $ts = Get-Date -Format "yyyyMMdd_HHmmss"
        $folder = New-PDFolder -Session $adminSession -DatabaseId $testDbId -Name "Test_$ts" -Importance "high" -Category "Testing" -Tags "api,test"
        if ((Assert-NotNull $folder.id "id") -and (Assert-Equal "folder" $folder.type "type")) {
            $testFolderId = $folder.id
            Pass-Test "id=$testFolderId"
        }
    } catch { Fail-Test $_.Exception.Message }

    # 3.3 Create sub-folder
    Start-Test "Create sub-folder"
    if ($testFolderId) {
        try {
            $sub = New-PDFolder -Session $adminSession -DatabaseId $testDbId -Name "SubFolder_$ts" -ParentId $testFolderId
            if (Assert-NotNull $sub.id "id") {
                $testSubFolderId = $sub.id
                Pass-Test "id=$testSubFolderId"
            }
        } catch { Fail-Test $_.Exception.Message }
    } else { Skip-Test "Parent folder not created" }

    # 3.4 Get folder detail (full representation with path)
    Start-Test "Get folder detail (full repr + path)"
    if ($testSubFolderId) {
        try {
            $detail = Get-PDFolder -Session $adminSession -DatabaseId $testDbId -FolderId $testSubFolderId
            if ((Assert-NotNull $detail.id "id") -and (Assert-NotNull $detail.path "path") -and (Assert-NotNull $detail.author "author")) {
                Pass-Test "path depth=$($detail.path.Count)"
            }
        } catch { Fail-Test $_.Exception.Message }
    } else { Skip-Test "Sub-folder not created" }

    # 3.5 List children of folder
    Start-Test "List children of test folder"
    if ($testFolderId) {
        try {
            $ch = Get-PDChildren -Session $adminSession -DatabaseId $testDbId -FolderId $testFolderId
            if (Assert-NotNull $ch "response") { Pass-Test "$($ch.total) child(ren), path depth=$($ch.path.Count)" }
        } catch { Fail-Test $_.Exception.Message }
    } else { Skip-Test "Folder not created" }

    # 3.6 Update folder
    Start-Test "Update folder name"
    if ($testFolderId) {
        try {
            $upd = Set-PDFolder -Session $adminSession -DatabaseId $testDbId -FolderId $testFolderId -Fields @{ name = "Renamed_$ts"; importance = "low" }
            if (Assert-Equal "Renamed_$ts" $upd.name "name") { Pass-Test }
        } catch { Fail-Test $_.Exception.Message }
    } else { Skip-Test "Folder not created" }

    # 3.7 Move sub-folder to root
    Start-Test "Move sub-folder to root"
    if ($testSubFolderId) {
        try {
            $moved = Move-PDFolder -Session $adminSession -DatabaseId $testDbId -FolderId $testSubFolderId -TargetId $null
            if (Assert-NotNull $moved.id "id") { Pass-Test }
        } catch { Fail-Test $_.Exception.Message }
    } else { Skip-Test "Sub-folder not created" }
}

$totalFailures += Write-TestSummary

# ============================================================
#  4. ENTRIES
# ============================================================

Start-TestSuite "Entries"

$testEntryId = $null

if (-not $testDbId) {
    Start-Test "All entry tests"
    Skip-Test "No database available"
} else {
    # 4.1 Create password entry
    Start-Test "Create password entry"
    try {
        $ts = Get-Date -Format "yyyyMMdd_HHmmss"
        $entry = New-PDEntry -Session $adminSession -DatabaseId $testDbId -ParentId $testFolderId -Fields @{
            type = "password"
            name = "TestEntry_$ts"
            login = "testuser"
            pass = "S3cureP@ss!"
            url = "https://example.com"
            comments = "Created by API test"
        }
        if ((Assert-NotNull $entry.id "id") -and (Assert-Equal "password" $entry.type "type")) {
            $testEntryId = $entry.id
            Pass-Test "id=$testEntryId"
        }
    } catch { Fail-Test $_.Exception.Message }

    # 4.2 Get entry detail (full representation with path and password)
    Start-Test "Get entry detail (full repr + path)"
    if ($testEntryId) {
        try {
            $detail = Get-PDEntry -Session $adminSession -DatabaseId $testDbId -EntryId $testEntryId
            $ok = (Assert-NotNull $detail.pass "pass") -and
                  (Assert-Equal "S3cureP@ss!" $detail.pass "password value") -and
                  (Assert-NotNull $detail.path "path") -and
                  (Assert-NotNull $detail.comments "comments")
            if ($ok) { Pass-Test "pass=***, path depth=$($detail.path.Count)" }
        } catch { Fail-Test $_.Exception.Message }
    } else { Skip-Test "Entry not created" }

    # 4.3 Update entry
    Start-Test "Update entry"
    if ($testEntryId) {
        try {
            $upd = Set-PDEntry -Session $adminSession -DatabaseId $testDbId -EntryId $testEntryId -Fields @{
                name = "Updated_$ts"
                login = "newuser"
            }
            if (Assert-Equal "Updated_$ts" $upd.name "name") { Pass-Test }
        } catch { Fail-Test $_.Exception.Message }
    } else { Skip-Test "Entry not created" }

    # 4.4 Create credit card entry
    Start-Test "Create credit_card entry"
    try {
        $cc = New-PDEntry -Session $adminSession -DatabaseId $testDbId -Fields @{
            type = "credit_card"
            name = "TestCard_$ts"
            credit_card = @{
                card = "visa"
                holder = "Test User"
                number = "4111 1111 1111 1111"
                valid_thru = "12/2030"
                cvv = "123"
            }
        }
        if (Assert-Equal "credit_card" $cc.type "type") { Pass-Test "id=$($cc.id)" }
        # Clean up
        Remove-PDEntry -Session $adminSession -DatabaseId $testDbId -EntryId $cc.id
    } catch { Fail-Test $_.Exception.Message }

    # 4.5 Create information entry
    Start-Test "Create information entry"
    try {
        $info = New-PDEntry -Session $adminSession -DatabaseId $testDbId -Fields @{
            type = "information"
            name = "TestInfo_$ts"
            information = @{ text = "Some secret notes" }
        }
        if (Assert-Equal "information" $info.type "type") { Pass-Test "id=$($info.id)" }
        Remove-PDEntry -Session $adminSession -DatabaseId $testDbId -EntryId $info.id
    } catch { Fail-Test $_.Exception.Message }

    # 4.6 Move entry to root
    Start-Test "Move entry to root"
    if ($testEntryId) {
        try {
            $moved = Move-PDEntry -Session $adminSession -DatabaseId $testDbId -EntryId $testEntryId -TargetId $null
            if (Assert-NotNull $moved.id "id") { Pass-Test }
        } catch { Fail-Test $_.Exception.Message }
    } else { Skip-Test "Entry not created" }

    # 4.7 Search
    Start-Test "Search for test entry"
    if ($testEntryId) {
        try {
            $results = Search-PDEntries -Session $adminSession -DatabaseId $testDbId -Query "Updated_$ts"
            if (Assert-GreaterThan $results.total 0 "total") { Pass-Test "$($results.total) result(s)" }
        } catch { Fail-Test $_.Exception.Message }
    } else { Skip-Test "Entry not created" }

    # 4.8 Get non-existent entry -> 404
    Start-Test "Get non-existent entry -> 404"
    if (Assert-HttpError -ExpectedCode 404 -Action {
        Get-PDEntry -Session $adminSession -DatabaseId $testDbId -EntryId "00000000-0000-0000-0000-000000000000"
    }) { Pass-Test "404 as expected" }

    # 4.9 Invalid entry type -> 400 (previously silently defaulted to password)
    Start-Test "Invalid entry type -> 400"
    if (Assert-HttpError -ExpectedCode 400 -Action {
        New-PDEntry -Session $adminSession -DatabaseId $testDbId -Fields @{
            type = "quantum_flux_capacitor"
            name = "BadType_$ts"
        }
    }) { Pass-Test "400 as expected" }
}

$totalFailures += Write-TestSummary

# ============================================================
#  4b. DOCUMENT ENTRIES (upload / download content)
# ============================================================

Start-TestSuite "Document Entries"

$testDocEntryId = $null

if (-not $testDbId) {
    Start-Test "All document tests"
    Skip-Test "No database available"
} else {
    # 4b.1 Create document entry
    Start-Test "Create document entry"
    try {
        $doc = New-PDEntry -Session $adminSession -DatabaseId $testDbId -Fields @{
            type = "document"
            name = "TestDocument_$ts"
        }
        if ((Assert-NotNull $doc.id "id") -and (Assert-Equal "document" $doc.type "type")) {
            $testDocEntryId = $doc.id
            Pass-Test "id=$testDocEntryId"
        }
    } catch { Fail-Test $_.Exception.Message }

    # 4b.2 Upload text content
    Start-Test "Upload text content"
    if ($testDocEntryId) {
        try {
            $textContent = "Hello from the API test suite! Timestamp: $ts"
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($textContent)
            $result = Set-PDDocumentContent -Session $adminSession -DatabaseId $testDbId `
                -EntryId $testDocEntryId -Content $bytes -ContentType "text/plain" -FileName "test.txt"
            Pass-Test "$($bytes.Length) bytes uploaded"
        } catch { Fail-Test $_.Exception.Message }
    } else { Skip-Test "Document entry not created" }

    # 4b.3 Download and verify text content
    Start-Test "Download and verify text content"
    if ($testDocEntryId) {
        try {
            $dl = Get-PDDocumentContent -Session $adminSession -DatabaseId $testDbId -EntryId $testDocEntryId
            $dlText = [System.Text.Encoding]::UTF8.GetString($dl.Content)
            if ((Assert-Equal $textContent $dlText "content matches") -and
                (Assert-Equal "test.txt" $dl.FileName "filename")) {
                Pass-Test "$($dl.Size) bytes, file=$($dl.FileName)"
            }
        } catch { Fail-Test $_.Exception.Message }
    } else { Skip-Test "Document entry not created" }

    # 4b.4 Upload binary content (replace previous)
    Start-Test "Upload binary content (PDF-like)"
    if ($testDocEntryId) {
        try {
            # Create a small fake binary payload
            $binaryContent = [byte[]]@(0x25, 0x50, 0x44, 0x46, 0x2D)  # "%PDF-" magic bytes
            $binaryContent += [byte[]](1..200 | ForEach-Object { [byte]($_ % 256) })  # 200 bytes of data
            $result = Set-PDDocumentContent -Session $adminSession -DatabaseId $testDbId `
                -EntryId $testDocEntryId -Content $binaryContent -ContentType "application/pdf" -FileName "report.pdf"
            Pass-Test "$($binaryContent.Length) bytes uploaded"
        } catch { Fail-Test $_.Exception.Message }
    } else { Skip-Test "Document entry not created" }

    # 4b.5 Download and verify binary content
    Start-Test "Download and verify binary content"
    if ($testDocEntryId) {
        try {
            $dl = Get-PDDocumentContent -Session $adminSession -DatabaseId $testDbId -EntryId $testDocEntryId
            $ok = (Assert-Equal $binaryContent.Length $dl.Size "size matches") -and
                  (Assert-Equal "report.pdf" $dl.FileName "filename")
            # Verify first bytes match (PDF magic)
            if ($ok) {
                $dlBytes = [byte[]]$dl.Content
                $ok = (Assert-Equal 0x25 $dlBytes[0] "byte[0]=%") -and
                      (Assert-Equal 0x50 $dlBytes[1] "byte[1]=P") -and
                      (Assert-Equal 0x44 $dlBytes[2] "byte[2]=D")
            }
            if ($ok) { Pass-Test "$($dl.Size) bytes, magic=PDF" }
        } catch { Fail-Test $_.Exception.Message }
    } else { Skip-Test "Document entry not created" }

    # 4b.6 Get entry detail to verify document metadata
    Start-Test "Verify document metadata in entry detail"
    if ($testDocEntryId) {
        try {
            $detail = Get-PDEntry -Session $adminSession -DatabaseId $testDbId -EntryId $testDocEntryId
            if ((Assert-Equal "document" $detail.type "type") -and
                (Assert-Equal "report.pdf" $detail.document.name "document.name") -and
                (Assert-GreaterThan $detail.document.size 0 "document.size")) {
                Pass-Test "name=$($detail.document.name), size=$($detail.document.size)"
            }
        } catch { Fail-Test $_.Exception.Message }
    } else { Skip-Test "Document entry not created" }

    # 4b.6.5 R2: filename with a bare double-quote must not break the response
    # Content-Disposition header. The server's SanitizeContentDispositionFilename
    # *strips* `"`, `\`, `/`, and CR/LF/NUL/controls (none of which are valid
    # in a Windows filename anyway), so the outbound header stays single-line
    # and unambiguously quoted. CR/LF cannot be exercised here: PowerShell's
    # HttpClient / System.Net WebRequest reject header values containing CR
    # or LF at send time, so a crafted upload never reaches the server. The
    # quote case is the one that is reachable end-to-end.
    Start-Test "R2: filename with double-quote stripped on download"
    if ($testDocEntryId) {
        try {
            $evilName = 'sa"b.txt'   # literal double-quote in the middle of the name
            $txt = "r2-test-$ts"
            $payload = [System.Text.Encoding]::UTF8.GetBytes($txt)
            Set-PDDocumentContent -Session $adminSession -DatabaseId $testDbId `
                -EntryId $testDocEntryId -Content $payload -ContentType "text/plain" -FileName $evilName | Out-Null

            # Pull the raw header via Invoke-WebRequest so we can inspect it
            $uri = "https://${Server}:${Port}/v2.0/databases/$testDbId/entries/$testDocEntryId/content"
            $resp = Invoke-WebRequest -Uri $uri -Headers @{ Authorization = "Bearer $($adminSession.Token)" } -UseBasicParsing
            $cd = $resp.Headers['Content-Disposition']

            # Strip the outer `filename="..."` wrapper so we can inspect the name itself
            $inner = ''
            if ($cd -match 'filename="([^"]*)"') { $inner = $matches[1] }

            $checks = @(
                @{ name = 'no CR in Content-Disposition'; pass = ($cd -notmatch "`r") }
                @{ name = 'no LF in Content-Disposition'; pass = ($cd -notmatch "`n") }
                @{ name = 'no bare quote inside filename'; pass = ($inner -notmatch '"') }
                @{ name = 'filename prefix preserved';    pass = ($inner -match '^sa') }
            )
            $failed = $checks | Where-Object { -not $_.pass }
            if ($failed.Count -eq 0) {
                Pass-Test "all $($checks.Count) header-injection guards held (filename=`"$inner`")"
            } else {
                $names = ($failed | ForEach-Object { $_.name }) -join '; '
                Fail-Test "R2 checks failed: $names. Got: $cd"
            }
        } catch { Fail-Test $_.Exception.Message }
    } else { Skip-Test "Document entry not created" }

    # 4b.7 Upload content to non-document entry -> 400
    Start-Test "Upload content to password entry -> 400"
    if ($testEntryId) {
        $dummyBytes = [byte[]](1..10)
        if (Assert-HttpError -ExpectedCode 400 -Action {
            Set-PDDocumentContent -Session $adminSession -DatabaseId $testDbId `
                -EntryId $testEntryId -Content $dummyBytes -ContentType "text/plain" -FileName "bad.txt"
        }) { Pass-Test "400 as expected" }
    } else { Skip-Test "No password entry available" }

    # 4b.8 Download content from entry with no content -> 404
    Start-Test "Download from empty document -> 404"
    try {
        $emptyDoc = New-PDEntry -Session $adminSession -DatabaseId $testDbId -Fields @{
            type = "document"
            name = "EmptyDoc_$ts"
        }
        if (Assert-HttpError -ExpectedCode 404 -Action {
            Get-PDDocumentContent -Session $adminSession -DatabaseId $testDbId -EntryId $emptyDoc.id
        }) { Pass-Test "404 as expected" }
        # Clean up
        Remove-PDEntry -Session $adminSession -DatabaseId $testDbId -EntryId $emptyDoc.id
    } catch { Fail-Test $_.Exception.Message }

    # 4b.9 C6: oversized JSON body (>1MB) to a JSON endpoint -> 413
    Start-Test "Oversized JSON body -> 413"
    try {
        # 2 MB junk "display_name" value -- JSON default limit is 1 MB.
        # The server must reject based on Content-Length BEFORE reading body.
        $bigJunk = 'A' * (2 * 1024 * 1024)
        if (Assert-HttpError -ExpectedCode 413 -Action {
            Invoke-PDRequest -Session $adminSession -Path "/admin/users" -Method POST -Body @{
                name = "huge_$ts"
                new_password = "T3stP@ss!"
                display_name = $bigJunk
            }
        }) { Pass-Test "413 as expected" }
    } catch { Fail-Test $_.Exception.Message }

    # 4b.10 C6: oversized upload (>64 MB) to content endpoint -> 413
    # The server must reject Content-Length > 64 MB BEFORE reading body.
    # We use a 65 MB body to cross the limit by the smallest amount.
    Start-Test "Oversized content upload -> 413"
    if ($testDocEntryId) {
        try {
            $huge = [byte[]]::new(65 * 1024 * 1024)
            if (Assert-HttpError -ExpectedCode 413 -Action {
                Set-PDDocumentContent -Session $adminSession -DatabaseId $testDbId `
                    -EntryId $testDocEntryId -Content $huge -ContentType "application/octet-stream" -FileName "huge.bin"
            }) { Pass-Test "413 as expected" }
        } catch { Fail-Test $_.Exception.Message }
    } else { Skip-Test "Document entry not created" }
}

$totalFailures += Write-TestSummary

# ============================================================
#  5. USERS & GROUPS (Admin CRUD)
# ============================================================

Start-TestSuite "Users & Groups (Admin)"

$testUserId = $null
$testGroupId = $null
$ts = Get-Date -Format "yyyyMMdd_HHmmss"

# 5.1 Create user
# `two_factor_mode: disabled` makes the test independent of the server's global
# 2FA setting (otherwise the login test below would hit 460 "TFA code required").
Start-Test "Create user"
try {
    $user = New-PDUser -Session $adminSession -Fields @{
        name = "apitest_$ts"
        display_name = "API Test User"
        new_password = "T3stP@ss!"
        department = "QA"
        email = "test@example.com"
        two_factor_mode = "disabled"
    }
    if ((Assert-NotNull $user.id "id") -and (Assert-Equal "disabled" $user.two_factor_mode "two_factor_mode")) {
        $testUserId = $user.id
        Pass-Test "id=$testUserId"
    }
} catch { Fail-Test $_.Exception.Message }

# 5.1b Newly-created user can actually log in with the password set at creation
Start-Test "Created user can log in"
if ($testUserId) {
    try {
        $probeSession = Connect-PDServer -Server $Server -Username "apitest_$ts" -Password "T3stP@ss!" -Port $Port -Scope "client"
        if (Assert-NotNull $probeSession.Token "access_token") { Pass-Test }
        Disconnect-PDServer -Session $probeSession
    } catch { Fail-Test $_.Exception.Message }
} else { Skip-Test "User not created" }

# 5.1c Create user without new_password when standard auth -> 400
Start-Test "Create user without password -> 400"
if (Assert-HttpError -ExpectedCode 400 -Action {
    New-PDUser -Session $adminSession -Fields @{ name = "nopass_$ts"; display_name = "No password" }
}) { Pass-Test "400 as expected" }

# 5.1c2 C11: service account with two_factor_mode=disabled can log in without email.
# The name "svc_$ts" has no email, so if server-wide 2FA is email-based it would
# otherwise lock this account out. The disabled flag opts out explicitly.
$svcUserId = $null
Start-Test "Service account (no email, 2FA disabled) can log in"
try {
    $svcUser = New-PDUser -Session $adminSession -Fields @{
        name = "svc_$ts"
        new_password = "Svc#P@ss1"
        display_name = "Test Service Account"
        two_factor_mode = "disabled"
    }
    $svcUserId = $svcUser.id
    $svcSession = Connect-PDServer -Server $Server -Username "svc_$ts" -Password "Svc#P@ss1" -Port $Port -Scope "client"
    if (Assert-NotNull $svcSession.Token "access_token") { Pass-Test }
    Disconnect-PDServer -Session $svcSession
} catch { Fail-Test $_.Exception.Message }
# Clean up the service account immediately (independent from $testUserId)
if ($svcUserId) {
    try { Remove-PDUser -Session $adminSession -UserId $svcUserId } catch {}
}

# 5.1c3 Unknown two_factor_mode value -> 400
Start-Test "Unknown two_factor_mode -> 400"
if (Assert-HttpError -ExpectedCode 400 -Action {
    New-PDUser -Session $adminSession -Fields @{
        name = "bad2fa_$ts"; new_password = "x1"; two_factor_mode = "retinascan"
    }
}) { Pass-Test "400 as expected" }

# 5.1d Create user with empty new_password -> 400
Start-Test "Create user with empty password -> 400"
if (Assert-HttpError -ExpectedCode 400 -Action {
    New-PDUser -Session $adminSession -Fields @{ name = "emptypass_$ts"; display_name = "Empty"; new_password = "" }
}) { Pass-Test "400 as expected" }

# 5.1e Admin password change with empty new_password -> 400
Start-Test "Admin password change with empty value -> 400"
if ($testUserId) {
    if (Assert-HttpError -ExpectedCode 400 -Action {
        Invoke-PDRequest -Session $adminSession -Path "/admin/users/$testUserId/password" -Method POST -Body @{ new_password = "" }
    }) { Pass-Test "400 as expected" }
} else { Skip-Test "User not created" }

# 5.1f Admin password change with missing field -> 400
Start-Test "Admin password change without new_password field -> 400"
if ($testUserId) {
    if (Assert-HttpError -ExpectedCode 400 -Action {
        Invoke-PDRequest -Session $adminSession -Path "/admin/users/$testUserId/password" -Method POST -Body @{ password = "wrongfield" }
    }) { Pass-Test "400 as expected" }
} else { Skip-Test "User not created" }

# 5.1g Admin password change updates the password (login works afterwards)
Start-Test "Admin password change takes effect"
if ($testUserId) {
    try {
        Invoke-PDRequest -Session $adminSession -Path "/admin/users/$testUserId/password" -Method POST -Body @{ new_password = "Rot4ted!P@ss" } | Out-Null
        $rotated = Connect-PDServer -Server $Server -Username "apitest_$ts" -Password "Rot4ted!P@ss" -Port $Port -Scope "client"
        if (Assert-NotNull $rotated.Token "access_token after rotation") { Pass-Test "login works with new password" }
        Disconnect-PDServer -Session $rotated
    } catch { Fail-Test $_.Exception.Message }
} else { Skip-Test "User not created" }

# 5.1h PATCH with password field -> 400 (must use /password endpoint)
Start-Test "PATCH with password field -> 400"
if ($testUserId) {
    if (Assert-HttpError -ExpectedCode 400 -Action {
        Set-PDUser -Session $adminSession -UserId $testUserId -Fields @{ password = "sneaky"; display_name = "x" }
    }) { Pass-Test "400 as expected" }
} else { Skip-Test "User not created" }

# 5.1i PATCH with new_password field -> 400 (same rule)
Start-Test "PATCH with new_password field -> 400"
if ($testUserId) {
    if (Assert-HttpError -ExpectedCode 400 -Action {
        Set-PDUser -Session $adminSession -UserId $testUserId -Fields @{ new_password = "sneaky"; display_name = "x" }
    }) { Pass-Test "400 as expected" }
} else { Skip-Test "User not created" }

# 5.1j C13: unknown sub-resources under /admin/users/{id} must 404, not silently
# delete the user. Before the fix, DELETE /admin/users/{id}/tfa silently
# deleted the entire user. Verify by confirming the user still exists after
# each attempted bogus sub-resource call.
Start-Test "C13: /admin/users/{id}/<unknown> -> 404 (user survives)"
if ($testUserId) {
    $c13AdminCases = @(
        @{ method = 'DELETE'; path = "/admin/users/$testUserId/tfa" },
        @{ method = 'DELETE'; path = "/admin/users/$testUserId/bogus" },
        @{ method = 'DELETE'; path = "/admin/users/$testUserId/passkey" },   # typo, not 'passkeys'
        @{ method = 'PATCH';  path = "/admin/users/$testUserId/tfa" },
        @{ method = 'GET';    path = "/admin/users/$testUserId/tfa" },
        @{ method = 'POST';   path = "/admin/users/$testUserId/password/extra" }
    )
    $allRejected = $true
    foreach ($c in $c13AdminCases) {
        if (-not (Assert-HttpError -ExpectedCode 404 -Action {
            Invoke-PDRequest -Session $adminSession -Path $c.path -Method $c.method
        })) {
            $allRejected = $false
            Fail-Test "Expected 404 for $($c.method) $($c.path)"
            break
        }
    }
    if ($allRejected) {
        # Confirm the user still exists
        try {
            $check = Invoke-PDRequest -Session $adminSession -Path "/admin/users/$testUserId"
            if ($check.id -eq $testUserId) {
                Pass-Test "$($c13AdminCases.Count) bogus sub-resources rejected, user intact"
            } else {
                Fail-Test "User lookup returned wrong id after bogus calls"
            }
        } catch { Fail-Test "User vanished after bogus sub-resource calls: $($_.Exception.Message)" }
    }
} else { Skip-Test "User not created" }

# 5.1k R5: malformed JSON body on a non-login endpoint must return 400
# (not 500). Before the fix, ~30 v2.0 endpoints let the raw parser exception
# bubble to ProcessException which mapped it to 500 Internal Server Error.
Start-Test "R5: malformed JSON on PATCH /admin/users/{id} -> 400"
if ($testUserId) {
    # See note at the login malformed-JSON test: Delphi's parser is lenient
    # about numeric overflow, so we only use structurally-unparseable bodies.
    $targets = @(
        @{ method = 'PATCH'; path = "/admin/users/$testUserId";      body = '{not even json' },
        @{ method = 'PATCH'; path = "/admin/users/$testUserId";      body = '{"a":}' },
        @{ method = 'POST';  path = "/admin/users/$testUserId/password"; body = '{"new_password":' }  # truncated
    )
    $all400 = $true
    foreach ($t in $targets) {
        $code = 0
        $label = "$($t.method) $($t.path)"
        try {
            Invoke-WebRequest -Uri "$($adminSession.BaseUri)$($t.path)" -Method $t.method `
                -Headers @{ Authorization = "Bearer $($adminSession.Token)" } `
                -ContentType 'application/json' -Body $t.body -UseBasicParsing | Out-Null
            $all400 = $false
            Fail-Test "Expected 400 for $label"
            break
        } catch {
            if ($_.Exception.Response) { $code = [int] $_.Exception.Response.StatusCode }
        }
        if ($code -ne 400) {
            $all400 = $false
            Fail-Test "Got $code (expected 400) for $label"
            break
        }
    }
    if ($all400) { Pass-Test "$($targets.Count) malformed bodies -> 400 on non-login endpoints" }
} else { Skip-Test "User not created" }

# 5.2 List users
Start-Test "List users"
try {
    $users = Get-PDUsers -Session $adminSession
    if (Assert-GreaterThan $users.total 0 "total") { Pass-Test "$($users.total) user(s)" }
} catch { Fail-Test $_.Exception.Message }

# 5.2a B2: negative limit -> 400
Start-Test "Pagination: limit=-5 -> 400"
if (Assert-HttpError -ExpectedCode 400 -Action {
    Invoke-PDRequest -Session $adminSession -Path "/admin/users" -QueryParams @{ limit = -5 }
}) { Pass-Test "400 as expected" }

# 5.2b B2: zero limit -> 400
Start-Test "Pagination: limit=0 -> 400"
if (Assert-HttpError -ExpectedCode 400 -Action {
    Invoke-PDRequest -Session $adminSession -Path "/admin/users" -QueryParams @{ limit = 0 }
}) { Pass-Test "400 as expected" }

# 5.2c B2: non-numeric limit -> 400
Start-Test "Pagination: limit=abc -> 400"
if (Assert-HttpError -ExpectedCode 400 -Action {
    Invoke-PDRequest -Session $adminSession -Path "/admin/users" -QueryParams @{ limit = "abc" }
}) { Pass-Test "400 as expected" }

# 5.2d B2: negative offset -> 400
Start-Test "Pagination: offset=-1 -> 400"
if (Assert-HttpError -ExpectedCode 400 -Action {
    Invoke-PDRequest -Session $adminSession -Path "/admin/users" -QueryParams @{ offset = -1 }
}) { Pass-Test "400 as expected" }

# 5.2e B3: oversized limit is clamped (not silently accepted, not 400)
Start-Test "Pagination: limit=99999 -> clamped to 1000"
try {
    $res = Invoke-PDRequest -Session $adminSession -Path "/admin/users" -QueryParams @{ limit = 99999 }
    if (Assert-Equal 1000 $res.limit "clamped limit") { Pass-Test "clamped to $($res.limit)" }
} catch { Fail-Test $_.Exception.Message }

# 5.2f B3: overflowing limit -> 400 (was silently falling back to default before)
Start-Test "Pagination: limit overflow -> 400"
if (Assert-HttpError -ExpectedCode 400 -Action {
    Invoke-PDRequest -Session $adminSession -Path "/admin/users" -QueryParams @{ limit = "9999999999999999999" }
}) { Pass-Test "400 as expected" }

# 5.3 Get user detail
Start-Test "Get user detail"
if ($testUserId) {
    try {
        $u = Get-PDUser -Session $adminSession -UserId $testUserId
        if ((Assert-Equal "apitest_$ts" $u.name "name") -and (Assert-Equal "QA" $u.department "department")) { Pass-Test }
    } catch { Fail-Test $_.Exception.Message }
} else { Skip-Test "User not created" }

# 5.4 Update user
Start-Test "Update user"
if ($testUserId) {
    try {
        $upd = Set-PDUser -Session $adminSession -UserId $testUserId -Fields @{ display_name = "Updated Test User"; department = "Engineering" }
        if (Assert-Equal "Engineering" $upd.department "department") { Pass-Test }
    } catch { Fail-Test $_.Exception.Message }
} else { Skip-Test "User not created" }

# 5.5 Create group
Start-Test "Create group"
try {
    $group = New-PDGroup -Session $adminSession -Fields @{
        name = "testgroup_$ts"
        description = "API test group"
    }
    if (Assert-NotNull $group.id "id") {
        $testGroupId = $group.id
        Pass-Test "id=$testGroupId"
    }
} catch { Fail-Test $_.Exception.Message }

# 5.6 List groups
Start-Test "List groups"
try {
    $groups = Get-PDGroups -Session $adminSession
    if (Assert-GreaterThan $groups.total 0 "total") { Pass-Test "$($groups.total) group(s)" }
} catch { Fail-Test $_.Exception.Message }

# 5.7 Update group
Start-Test "Update group"
if ($testGroupId) {
    try {
        $upd = Set-PDGroup -Session $adminSession -GroupId $testGroupId -Fields @{ description = "Updated description" }
        if (Assert-Equal "Updated description" $upd.description "description") { Pass-Test }
    } catch { Fail-Test $_.Exception.Message }
} else { Skip-Test "Group not created" }

$totalFailures += Write-TestSummary

# ============================================================
#  6. ALERTS (Admin CRUD)
# ============================================================

Start-TestSuite "Alerts (Admin)"

$testAlertId = $null

# 6.1 Create alert
Start-Test "Create alert"
try {
    $alert = New-PDAlert -Session $adminSession -Fields @{
        type = "login_failed_admin"
        notes = "Test alert from API test suite"
        recipients = @("test@example.com")
    }
    if ((Assert-NotNull $alert.id "id") -and (Assert-Equal "login_failed_admin" $alert.type "type")) {
        $testAlertId = $alert.id
        Pass-Test "id=$testAlertId"
    }
} catch { Fail-Test $_.Exception.Message }

# 6.2 List alerts
Start-Test "List alerts"
try {
    $alerts = Get-PDAlerts -Session $adminSession
    if (Assert-GreaterThan $alerts.total 0 "total") { Pass-Test "$($alerts.total) alert(s)" }
} catch { Fail-Test $_.Exception.Message }

# 6.3 Get alert detail
Start-Test "Get alert detail (full repr)"
if ($testAlertId) {
    try {
        $a = Get-PDAlert -Session $adminSession -AlertId $testAlertId
        if ((Assert-NotNull $a.recipients "recipients") -and (Assert-NotNull $a.notes "notes")) { Pass-Test }
    } catch { Fail-Test $_.Exception.Message }
} else { Skip-Test "Alert not created" }

# 6.4 Update alert
Start-Test "Update alert"
if ($testAlertId) {
    try {
        $upd = Set-PDAlert -Session $adminSession -AlertId $testAlertId -Fields @{
            notes = "Updated by test suite"
            recipients = @("test@example.com", "ops@example.com")
        }
        if (Assert-Equal "Updated by test suite" $upd.notes "notes") { Pass-Test }
    } catch { Fail-Test $_.Exception.Message }
} else { Skip-Test "Alert not created" }

# 6.5 C8: invalid recipient format (URL-style) -> 400
Start-Test "Invalid recipient URL -> 400"
if ($testAlertId) {
    if (Assert-HttpError -ExpectedCode 400 -Action {
        Set-PDAlert -Session $adminSession -AlertId $testAlertId -Fields @{
            recipients = @("http://attacker.com/leak")
        }
    }) { Pass-Test "400 as expected" }
} else { Skip-Test "Alert not created" }

# 6.6 C8: mailto: scheme in recipient -> 400 (must be bare email)
Start-Test "Invalid recipient mailto: scheme -> 400"
if ($testAlertId) {
    if (Assert-HttpError -ExpectedCode 400 -Action {
        Set-PDAlert -Session $adminSession -AlertId $testAlertId -Fields @{
            recipients = @("mailto:evil@example.com")
        }
    }) { Pass-Test "400 as expected" }
} else { Skip-Test "Alert not created" }

# 6.7 C8: empty string in recipients -> 400
Start-Test "Empty recipient -> 400"
if ($testAlertId) {
    if (Assert-HttpError -ExpectedCode 400 -Action {
        Set-PDAlert -Session $adminSession -AlertId $testAlertId -Fields @{
            recipients = @("valid@example.com", "")
        }
    }) { Pass-Test "400 as expected" }
} else { Skip-Test "Alert not created" }

# 6.8 C8: non-UUID in database_ids -> 400
Start-Test "Non-UUID in database_ids -> 400"
if ($testAlertId) {
    if (Assert-HttpError -ExpectedCode 400 -Action {
        Set-PDAlert -Session $adminSession -AlertId $testAlertId -Fields @{
            database_ids = @("any-id")
        }
    }) { Pass-Test "400 as expected" }
} else { Skip-Test "Alert not created" }

# 6.9 C8: non-UUID in user_ids -> 400
Start-Test "Non-UUID in user_ids -> 400"
if ($testAlertId) {
    if (Assert-HttpError -ExpectedCode 400 -Action {
        Set-PDAlert -Session $adminSession -AlertId $testAlertId -Fields @{
            user_ids = @("not-a-uuid")
        }
    }) { Pass-Test "400 as expected" }
} else { Skip-Test "Alert not created" }

$totalFailures += Write-TestSummary

# ============================================================
#  7. PERMISSIONS (Admin)
# ============================================================

Start-TestSuite "Permissions (Admin)"

$testPermId = $null

if (-not $testDbId -or -not $testUserId) {
    Start-Test "All permission tests"
    Skip-Test "No database or user available"
} else {
    # 7.1 Create permission
    Start-Test "Create permission"
    try {
        $perm = New-PDPermission -Session $adminSession -DatabaseId $testDbId -Fields @{
            principal_id = $testUserId
            allow = @("use", "read")
            deny = @("export", "print")
        }
        if (Assert-NotNull $perm.id "id") {
            $testPermId = $perm.id
            Pass-Test "id=$testPermId"
        }
    } catch { Fail-Test $_.Exception.Message }

    # 7.2 List permissions
    Start-Test "List permissions for database"
    try {
        $perms = Get-PDPermissions -Session $adminSession -DatabaseId $testDbId
        if (Assert-GreaterThan $perms.total 0 "total") { Pass-Test "$($perms.total) permission(s)" }
    } catch { Fail-Test $_.Exception.Message }

    # 7.3 Get permission detail
    Start-Test "Get permission detail (full repr)"
    if ($testPermId) {
        try {
            $p = Get-PDPermission -Session $adminSession -DatabaseId $testDbId -PermissionId $testPermId
            if ((Assert-Contains $p.allow "use" "allow contains use") -and (Assert-Contains $p.deny "export" "deny contains export")) {
                Pass-Test
            }
        } catch { Fail-Test $_.Exception.Message }
    } else { Skip-Test "Permission not created" }

    # 7.4 Update permission
    Start-Test "Update permission"
    if ($testPermId) {
        try {
            $upd = Set-PDPermission -Session $adminSession -DatabaseId $testDbId -PermissionId $testPermId -Fields @{
                allow = @("use", "read", "update", "create")
                deny = @()
            }
            if (Assert-Contains $upd.allow "create" "allow contains create") { Pass-Test }
        } catch { Fail-Test $_.Exception.Message }
    } else { Skip-Test "Permission not created" }

    # 7.5 Delete permission
    Start-Test "Delete permission"
    if ($testPermId) {
        try {
            Remove-PDPermission -Session $adminSession -DatabaseId $testDbId -PermissionId $testPermId
            Pass-Test
            $testPermId = $null
        } catch { Fail-Test $_.Exception.Message }
    } else { Skip-Test "Permission not created" }

    # 7.6 Deleted permission -> 404
    Start-Test "Deleted permission -> 404"
    if (-not $testPermId) {
        if (Assert-HttpError -ExpectedCode 404 -Action {
            Get-PDPermission -Session $adminSession -DatabaseId $testDbId -PermissionId "00000000-0000-0000-0000-000000000000"
        }) { Pass-Test "404 as expected" }
    } else { Skip-Test "Permission still exists" }

    # 7.7 Invalid permission token in allow array -> 400 (C7 fix: silent drops)
    Start-Test "Invalid token in allow array -> 400"
    if ($testUserId) {
        if (Assert-HttpError -ExpectedCode 400 -Action {
            New-PDPermission -Session $adminSession -DatabaseId $testDbId -Fields @{
                principal_id = $testUserId
                allow = @("read", "write", "create")  # "write" is not a valid token
            }
        }) { Pass-Test "400 as expected" }
    } else { Skip-Test "No test user" }

    # 7.8 Invalid role token -> 400
    Start-Test "Invalid role token -> 400"
    if (Assert-HttpError -ExpectedCode 400 -Action {
        New-PDUser -Session $adminSession -Fields @{
            name = "badrole_$ts"
            new_password = "T3stP@ss!"
            roles = @("super_admin", "god_mode")  # "god_mode" is not a valid role
        }
    }) { Pass-Test "400 as expected" }

    # 7.9 Invalid auth_mode -> 400
    Start-Test "Invalid auth_mode -> 400"
    if (Assert-HttpError -ExpectedCode 400 -Action {
        New-PDUser -Session $adminSession -Fields @{
            name = "badauth_$ts"
            auth_modes = @("standard", "retina_scan")  # "retina_scan" is not valid
        }
    }) { Pass-Test "400 as expected" }
}

$totalFailures += Write-TestSummary

# ============================================================
#  7b. SECRETS / SHARED LINKS (Client + Admin)
# ============================================================

Start-TestSuite "Secrets (Shared Links)"

$testSecretId = $null
$testSecretApprovalId = $null

if (-not $testDbId) {
    Start-Test "All secret tests"
    Skip-Test "No database available"
} else {
    # We need an entry to share -- use an existing one or create a temporary one
    $secretEntryId = $null
    Start-Test "Create entry to share"
    try {
        $shareEntry = New-PDEntry -Session $adminSession -DatabaseId $testDbId -Fields @{
            type = "password"
            name = "ShareTarget_$ts"
            login = "shared_user"
            pass = "SharedP@ss!"
            url = "https://shared.example.com"
        }
        $secretEntryId = $shareEntry.id
        Pass-Test "id=$secretEntryId"
    } catch { Fail-Test $_.Exception.Message }

    # 7b.1 Create secret (client scope, simple - no approval)
    Start-Test "Create secret (no approval)"
    if ($secretEntryId) {
        try {
            $expiresAt = (Get-Date).AddDays(7).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            $secret = New-PDSecret -Session $adminSession -Fields @{
                database_id = $testDbId
                entry_id = $secretEntryId
                protocol = "https"
                access_max = 3
                expires_at = $expiresAt
                notes = "Test secret from API test suite"
            }
            if ((Assert-NotNull $secret.id "id") -and
                (Assert-Equal "available" $secret.status "status") -and
                (Assert-NotNull $secret.open_uuid "open_uuid")) {
                $testSecretId = $secret.id
                Pass-Test "id=$testSecretId, status=$($secret.status)"
            }
        } catch { Fail-Test $_.Exception.Message }
    } else { Skip-Test "No entry to share" }

    # 7b.2 List secrets
    Start-Test "List secrets"
    try {
        $secrets = Get-PDSecrets -Session $adminSession
        if (Assert-GreaterThan $secrets.total 0 "total") { Pass-Test "$($secrets.total) secret(s)" }
    } catch { Fail-Test $_.Exception.Message }

    # 7b.3 Get secret detail
    Start-Test "Get secret detail (full repr)"
    if ($testSecretId) {
        try {
            $s = Get-PDSecret -Session $adminSession -SecretId $testSecretId
            $ok = (Assert-Equal "available" $s.status "status") -and
                  (Assert-Equal 3 $s.access_max "access_max") -and
                  (Assert-Equal 0 $s.access_count "access_count") -and
                  (Assert-NotNull $s.open_uuid "open_uuid") -and
                  (Assert-NotNull $s.approve_uuid "approve_uuid") -and
                  (Assert-NotNull $s.database_name "database_name") -and
                  (Assert-NotNull $s.entry_path "entry_path")
            if ($ok) { Pass-Test "open_uuid=$($s.open_uuid.Substring(0,8))..." }
        } catch { Fail-Test $_.Exception.Message }
    } else { Skip-Test "Secret not created" }

    # 7b.4 Revoke secret
    Start-Test "Revoke secret"
    if ($testSecretId) {
        try {
            $revoked = Revoke-PDSecret -Session $adminSession -SecretId $testSecretId
            if (Assert-Equal "revoked" $revoked.status "status") { Pass-Test }
        } catch { Fail-Test $_.Exception.Message }
    } else { Skip-Test "Secret not created" }

    # 7b.5 Revoke already-revoked -> 400
    Start-Test "Revoke already-revoked secret -> error"
    if ($testSecretId) {
        if (Assert-HttpError -ExpectedCode 400 -Action {
            Revoke-PDSecret -Session $adminSession -SecretId $testSecretId
        }) { Pass-Test "400 as expected" }
    } else { Skip-Test "Secret not created" }

    # 7b.6 Create secret with approval workflow
    Start-Test "Create secret (with approval)"
    if ($secretEntryId -and $testUserId) {
        try {
            $secretApproval = New-PDSecret -Session $adminSession -Fields @{
                database_id = $testDbId
                entry_id = $secretEntryId
                protocol = "pd-server"
                expires_at = $expiresAt
                approval_required = $true
                quorum_n = 1
                quorum_m = 1
                approver_ids = @($adminSession.Token | ForEach-Object {
                    # Use the admin user's own ID as approver for testing
                    (Get-PDMe -Session $adminSession).id
                })
                notes = "Approval workflow test"
            }
            if ((Assert-NotNull $secretApproval.id "id") -and
                (Assert-Equal "pending_approval" $secretApproval.status "status")) {
                $testSecretApprovalId = $secretApproval.id
                Pass-Test "id=$testSecretApprovalId, status=$($secretApproval.status)"
            }
        } catch { Fail-Test $_.Exception.Message }
    } else { Skip-Test "No entry or user available" }

    # 7b.7 Approve secret
    Start-Test "Approve secret"
    if ($testSecretApprovalId) {
        try {
            $approved = Approve-PDSecret -Session $adminSession -SecretId $testSecretApprovalId -ExtendMinutes 60
            if ((Assert-Equal "available" $approved.status "status") -and
                (Assert-GreaterThan $approved.approved_by.Count 0 "approved_by count")) {
                Pass-Test "status=$($approved.status), approvals=$($approved.approved_by.Count)"
            }
        } catch { Fail-Test $_.Exception.Message }
    } else { Skip-Test "Approval secret not created" }

    # 7b.8 Update secret (admin only)
    Start-Test "Update secret (admin PATCH)"
    if ($testSecretApprovalId) {
        try {
            $upd = Set-PDSecret -Session $adminSession -SecretId $testSecretApprovalId -Fields @{
                notes = "Updated notes"
                access_max = 10
            }
            if ((Assert-Equal "Updated notes" $upd.notes "notes") -and
                (Assert-Equal 10 $upd.access_max "access_max")) { Pass-Test }
        } catch { Fail-Test $_.Exception.Message }
    } else { Skip-Test "Approval secret not created" }

    # 7b.9 Delete secret
    Start-Test "Delete secret"
    if ($testSecretId) {
        try {
            Remove-PDSecret -Session $adminSession -SecretId $testSecretId
            Pass-Test
            $testSecretId = $null
        } catch { Fail-Test $_.Exception.Message }
    } else { Skip-Test "Secret not created" }

    # 7b.10 Deleted secret -> 404
    Start-Test "Deleted secret -> 404"
    if (Assert-HttpError -ExpectedCode 404 -Action {
        Get-PDSecret -Session $adminSession -SecretId "00000000-0000-0000-0000-000000000000"
    }) { Pass-Test "404 as expected" }

    # Cleanup: delete remaining test secrets and the share entry
    if ($testSecretApprovalId) {
        try { Remove-PDSecret -Session $adminSession -SecretId $testSecretApprovalId } catch {}
    }
    if ($secretEntryId) {
        try { Remove-PDEntry -Session $adminSession -DatabaseId $testDbId -EntryId $secretEntryId } catch {}
    }
}

$totalFailures += Write-TestSummary

# ============================================================
#  8. CLIENT-SCOPE READ ACCESS (users, groups)
# ============================================================

Start-TestSuite "Client-Scope Read Access"

# Re-login as client
$clientSession2 = $null
Start-Test "Client login for read tests"
try {
    $clientSession2 = Connect-PDServer -Server $Server -Username $Username -Password $Password -Port $Port -Scope "client"
    if (Assert-NotNull $clientSession2.Token "access_token") { Pass-Test }
} catch { Fail-Test $_.Exception.Message }

if ($clientSession2) {
    # 8.1 Client can list users (compact repr)
    Start-Test "Client: List users (compact)"
    try {
        $users = Get-PDUsers -Session $clientSession2
        if (Assert-GreaterThan $users.total 0 "total") { Pass-Test "$($users.total) user(s)" }
    } catch { Fail-Test $_.Exception.Message }

    # 8.2 Client can list groups (compact repr)
    Start-Test "Client: List groups (compact)"
    try {
        $groups = Get-PDGroups -Session $clientSession2
        if (Assert-NotNull $groups "response") { Pass-Test "$($groups.total) group(s)" }
    } catch { Fail-Test $_.Exception.Message }

    # 8.3 Client can list databases
    Start-Test "Client: List databases"
    try {
        $dbs = Get-PDDatabases -Session $clientSession2
        if (Assert-NotNull $dbs "response") { Pass-Test "$($dbs.total) database(s)" }
    } catch { Fail-Test $_.Exception.Message }

    # 8.4 Client cannot access admin endpoints
    Start-Test "Client: admin/alerts -> 403"
    if (Assert-HttpError -ExpectedCode 403 -Action {
        Invoke-PDRequest -Session $clientSession2 -Path "/admin/alerts"
    }) { Pass-Test "403 as expected" }

    Disconnect-PDServer -Session $clientSession2
}

# 8.5 IDOR (C5): non-admin user without permission on a DB must get 404 on
# single-GET by UUID, indistinguishable from "UUID does not exist".
# Uses the fresh test user apitest_$ts (password rotated to Rot4ted!P@ss in 5.1g)
# who has no explicit permissions on $testDbId after the permissions suite cleaned up.
Start-Test "IDOR: non-admin cannot fetch DB metadata by UUID"
if ($testUserId -and $testDbId) {
    try {
        $nonAdminSession = Connect-PDServer -Server $Server -Username "apitest_$ts" -Password "Rot4ted!P@ss" -Port $Port -Scope "client"

        # Both of these should look the same to the client (same 404):
        # - Unreachable DB by known UUID
        # - Non-existent UUID
        $reachable404 = Assert-HttpError -ExpectedCode 404 -Action {
            Get-PDDatabase -Session $nonAdminSession -DatabaseId $testDbId
        }
        $unknown404 = Assert-HttpError -ExpectedCode 404 -Action {
            Get-PDDatabase -Session $nonAdminSession -DatabaseId "00000000-0000-0000-0000-000000000000"
        }

        Disconnect-PDServer -Session $nonAdminSession

        if ($reachable404 -and $unknown404) {
            Pass-Test "unreachable and non-existent UUIDs both return 404"
        }
    } catch { Fail-Test $_.Exception.Message }
} else { Skip-Test "No test user or test database" }

$totalFailures += Write-TestSummary

# ============================================================
#  8b. PASSKEYS / WEBAUTHN (read-only tests; registration needs a real authenticator)
# ============================================================

Start-TestSuite "Passkeys"

# 8b.1 List own passkeys (any authenticated user)
Start-Test "List own passkeys (/me/passkeys)"
try {
    $passkeys = Get-PDPasskeys -Session $adminSession
    if ((Assert-NotNull $passkeys "response") -and (Assert-NotNull $passkeys.data "data")) {
        Pass-Test "$($passkeys.total) passkey(s)"
    }
} catch { Fail-Test $_.Exception.Message }

# 8b.2 /me response includes passkeys array (full representation)
Start-Test "GET /me includes passkeys array"
try {
    $me = Get-PDMe -Session $adminSession
    if (Assert-NotNull $me.passkeys "passkeys field") {
        Pass-Test "passkeys count=$($me.passkeys.Count)"
    }
} catch { Fail-Test $_.Exception.Message }

# 8b.3 List passkeys of another user (admin scope)
Start-Test "Admin: list any user's passkeys"
if ($testUserId) {
    try {
        $other = Get-PDPasskeys -Session $adminSession -UserId $testUserId
        if (Assert-NotNull $other.data "data") {
            Pass-Test "$($other.total) passkey(s)"
        }
    } catch { Fail-Test $_.Exception.Message }
} else { Skip-Test "No test user available" }

# 8b.4 Begin registration -> returns session_id + publicKey options
Start-Test "Begin passkey registration"
try {
    $begin = Start-PDPasskeyRegistration -Session $adminSession
    if ((Assert-NotNull $begin.session_id "session_id") -and (Assert-NotNull $begin.publicKey "publicKey")) {
        Pass-Test "challenge issued (session_id=$($begin.session_id.Substring(0,8))...)"
    }
} catch { Fail-Test $_.Exception.Message }

# 8b.5 Complete with bogus session_id -> 401
Start-Test "Complete with invalid session_id -> 401"
if (Assert-HttpError -ExpectedCode 401 -Action {
    Complete-PDPasskeyRegistration -Session $adminSession -AuthenticatorResponse @{
        session_id = "00000000-0000-0000-0000-000000000000"
        id = "fake"
        response = @{}
    }
}) { Pass-Test "401 as expected" }

# 8b.6 Delete non-existent passkey -> 404
Start-Test "Delete non-existent passkey -> 404"
if (Assert-HttpError -ExpectedCode 404 -Action {
    Remove-PDPasskey -Session $adminSession -PasskeyId "00000000-0000-0000-0000-000000000000"
}) { Pass-Test "404 as expected" }

# 8b.7 Rename non-existent passkey -> 404
Start-Test "Rename non-existent passkey -> 404"
if (Assert-HttpError -ExpectedCode 404 -Action {
    Rename-PDPasskey -Session $adminSession -PasskeyId "00000000-0000-0000-0000-000000000000" -NewName "Test"
}) { Pass-Test "404 as expected" }

$totalFailures += Write-TestSummary

# ============================================================
#  9. CLEANUP
# ============================================================

Start-TestSuite "Cleanup"

# Delete test entry
if ($testEntryId -and $testDbId) {
    Start-Test "Delete test entry"
    try {
        Remove-PDEntry -Session $adminSession -DatabaseId $testDbId -EntryId $testEntryId
        Pass-Test
    } catch { Fail-Test $_.Exception.Message }
}

# Delete document entry
if ($testDocEntryId -and $testDbId) {
    Start-Test "Delete document entry"
    try {
        Remove-PDEntry -Session $adminSession -DatabaseId $testDbId -EntryId $testDocEntryId
        Pass-Test
    } catch { Fail-Test $_.Exception.Message }
}

# Delete sub-folder
if ($testSubFolderId -and $testDbId) {
    Start-Test "Delete sub-folder"
    try {
        Remove-PDFolder -Session $adminSession -DatabaseId $testDbId -FolderId $testSubFolderId
        Pass-Test
    } catch { Fail-Test $_.Exception.Message }
}

# Delete test folder
if ($testFolderId -and $testDbId) {
    Start-Test "Delete test folder"
    try {
        Remove-PDFolder -Session $adminSession -DatabaseId $testDbId -FolderId $testFolderId
        Pass-Test
    } catch { Fail-Test $_.Exception.Message }
}

# Delete test alert
if ($testAlertId) {
    Start-Test "Delete test alert"
    try {
        Remove-PDAlert -Session $adminSession -AlertId $testAlertId
        Pass-Test
    } catch { Fail-Test $_.Exception.Message }
}

# Delete test group
if ($testGroupId) {
    Start-Test "Delete test group"
    try {
        Remove-PDGroup -Session $adminSession -GroupId $testGroupId
        Pass-Test
    } catch { Fail-Test $_.Exception.Message }
}

# Delete test user
if ($testUserId) {
    Start-Test "Delete test user"
    try {
        Remove-PDUser -Session $adminSession -UserId $testUserId
        Pass-Test
    } catch { Fail-Test $_.Exception.Message }
}

# Admin logout
Start-Test "Admin logout"
try {
    Disconnect-PDServer -Session $adminSession
    Pass-Test
} catch { Fail-Test $_.Exception.Message }

$totalFailures += Write-TestSummary

# ============================================================
#  14. LONG-LIVED API TOKEN LOGOUT (B14)
# ============================================================

Start-TestSuite "Long-lived API token logout"

if (-not $ApiToken) {
    Start-Test "Long-lived API token logout"
    Skip-Test "No -ApiToken provided (issue one via Password Depot Server Manager)"
} else {
    $apiSession = [PSCustomObject]@{ BaseUri = "https://${Server}:${Port}/v2.0"; Token = $ApiToken; Scope = "client" }

    # 14.1 Token works before logout
    Start-Test "API token works before logout"
    try {
        $me = Invoke-PDRequest -Session $apiSession -Path "/me/profile"
        if (Assert-NotNull $me.name "name") { Pass-Test "$($me.name)" }
    } catch { Fail-Test $_.Exception.Message }

    # 14.2 Logout returns 200 with revoked:false (not 204)
    Start-Test "Logout with long-lived token -> 200 + revoked:false"
    try {
        $logoutResp = Invoke-PDRequest -Session $apiSession -Path "/auth/logout" -Method POST
        if ($null -eq $logoutResp) {
            Fail-Test "Expected JSON body; got 204 No Content (token treated as session token)"
        } elseif ($logoutResp.revoked -ne $false) {
            Fail-Test "Expected 'revoked:false'; got '$($logoutResp.revoked)'"
        } elseif ($logoutResp.token_type -ne "api_token") {
            Fail-Test "Expected 'token_type:api_token'; got '$($logoutResp.token_type)'"
        } else {
            Pass-Test "$($logoutResp.message)"
        }
    } catch { Fail-Test $_.Exception.Message }

    # 14.3 Token still usable after logout (contract: only Server Manager revokes)
    Start-Test "API token still valid after logout"
    try {
        $me2 = Invoke-PDRequest -Session $apiSession -Path "/me/profile"
        if (Assert-NotNull $me2.name "name") { Pass-Test "Token remains valid (as documented)" }
    } catch { Fail-Test "Token was unexpectedly rejected: $($_.Exception.Message)" }
}

$totalFailures += Write-TestSummary

# ============================================================
#  FINAL SUMMARY
# ============================================================

Write-Host ""
Write-Host "=" * 70 -ForegroundColor DarkGray
if ($totalFailures -eq 0) {
    Write-Host "  ALL TESTS PASSED" -ForegroundColor Green
} else {
    Write-Host "  $totalFailures TEST SUITE(S) HAD FAILURES" -ForegroundColor Red
}
Write-Host "=" * 70 -ForegroundColor DarkGray

exit $totalFailures
