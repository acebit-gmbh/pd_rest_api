<#
.SYNOPSIS
    Lightweight test framework for Password Depot REST API v2.0.
    Provides Assert-* functions, test runner, and summary reporting.
#>

$script:TestResults = @()
$script:CurrentTest = ""
$script:PassCount = 0
$script:FailCount = 0
$script:SkipCount = 0

function Start-TestSuite {
    param([string] $Name)
    Write-Host ""
    Write-Host "=" * 70 -ForegroundColor DarkGray
    Write-Host "  TEST SUITE: $Name" -ForegroundColor Cyan
    Write-Host "=" * 70 -ForegroundColor DarkGray
    $script:TestResults = @()
    $script:PassCount = 0
    $script:FailCount = 0
    $script:SkipCount = 0
}

function Start-Test {
    param([Parameter(Mandatory)] [string] $Name)
    $script:CurrentTest = $Name
    Write-Host "  [$Name] " -NoNewline
}

function Pass-Test {
    param([string] $Message = "OK")
    Write-Host $Message -ForegroundColor Green
    $script:PassCount++
    $script:TestResults += [PSCustomObject]@{ Name = $script:CurrentTest; Result = "PASS"; Message = $Message }
}

function Fail-Test {
    param([Parameter(Mandatory)] [string] $Message)
    Write-Host "FAIL: $Message" -ForegroundColor Red
    $script:FailCount++
    $script:TestResults += [PSCustomObject]@{ Name = $script:CurrentTest; Result = "FAIL"; Message = $Message }
}

function Skip-Test {
    param([Parameter(Mandatory)] [string] $Reason)
    Write-Host "SKIP: $Reason" -ForegroundColor Yellow
    $script:SkipCount++
    $script:TestResults += [PSCustomObject]@{ Name = $script:CurrentTest; Result = "SKIP"; Message = $Reason }
}

function Write-TestSummary {
    $total = $script:PassCount + $script:FailCount + $script:SkipCount
    Write-Host ""
    Write-Host "-" * 70 -ForegroundColor DarkGray
    Write-Host "  Results: $total total, " -NoNewline
    Write-Host "$($script:PassCount) passed" -NoNewline -ForegroundColor Green
    Write-Host ", " -NoNewline
    if ($script:FailCount -gt 0) {
        Write-Host "$($script:FailCount) failed" -NoNewline -ForegroundColor Red
    } else {
        Write-Host "0 failed" -NoNewline
    }
    Write-Host ", " -NoNewline
    Write-Host "$($script:SkipCount) skipped" -ForegroundColor Yellow
    Write-Host "-" * 70 -ForegroundColor DarkGray

    if ($script:FailCount -gt 0) {
        Write-Host ""
        Write-Host "  FAILURES:" -ForegroundColor Red
        $script:TestResults | Where-Object { $_.Result -eq "FAIL" } | ForEach-Object {
            Write-Host "    - $($_.Name): $($_.Message)" -ForegroundColor Red
        }
    }

    return $script:FailCount
}

# --- Assert helpers ---

function Assert-Equal {
    param($Expected, $Actual, [string] $Label = "")
    if ($Expected -ne $Actual) {
        $msg = "Expected '$Expected', got '$Actual'"
        if ($Label) { $msg = "$Label -- $msg" }
        Fail-Test $msg
        return $false
    }
    return $true
}

function Assert-NotNull {
    param($Value, [string] $Label = "")
    if ($null -eq $Value -or $Value -eq "") {
        $msg = "Expected non-null value"
        if ($Label) { $msg = "$Label -- $msg" }
        Fail-Test $msg
        return $false
    }
    return $true
}

function Assert-True {
    param([bool] $Condition, [string] $Label = "")
    if (-not $Condition) {
        $msg = "Expected true"
        if ($Label) { $msg = "$Label -- $msg" }
        Fail-Test $msg
        return $false
    }
    return $true
}

function Assert-GreaterThan {
    param($Value, $Threshold, [string] $Label = "")
    if ($Value -le $Threshold) {
        $msg = "Expected > $Threshold, got $Value"
        if ($Label) { $msg = "$Label -- $msg" }
        Fail-Test $msg
        return $false
    }
    return $true
}

function Assert-Contains {
    param([array] $Collection, $Item, [string] $Label = "")
    if ($Collection -notcontains $Item) {
        $msg = "Collection does not contain '$Item'"
        if ($Label) { $msg = "$Label -- $msg" }
        Fail-Test $msg
        return $false
    }
    return $true
}

function Assert-HttpError {
    <#
    .SYNOPSIS
        Executes a script block and asserts it throws an HTTP error with the expected status code.
    #>
    param(
        [Parameter(Mandatory)] [int] $ExpectedCode,
        [Parameter(Mandatory)] [scriptblock] $Action,
        [string] $Label = ""
    )
    try {
        & $Action
        $msg = "Expected HTTP $ExpectedCode but no error was thrown"
        if ($Label) { $msg = "$Label -- $msg" }
        Fail-Test $msg
        return $false
    }
    catch {
        # Try to extract HTTP status code from various exception formats
        $statusCode = $null

        # WebException from Invoke-WebRequest / Invoke-RestMethod
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
        # Nested WebException (e.g., from Connect-PDServer wrapping the error)
        elseif ($_.Exception.InnerException -and $_.Exception.InnerException.Response) {
            $statusCode = [int]$_.Exception.InnerException.Response.StatusCode
        }
        # ErrorDetails contains the parsed error body
        elseif ($_.ErrorDetails.Message) {
            try {
                $parsed = $_.ErrorDetails.Message | ConvertFrom-Json
                if ($parsed.error.code) { $statusCode = $parsed.error.code }
            } catch {}
        }
        # Last resort: check if the error message contains the status code
        if (-not $statusCode -and $_.Exception.Message -match '\((\d{3})\)') {
            $statusCode = [int]$Matches[1]
        }

        if ($statusCode -eq $ExpectedCode) {
            return $true
        } else {
            $msg = "Expected HTTP $ExpectedCode, got $statusCode ($($_.Exception.Message))"
            if ($Label) { $msg = "$Label -- $msg" }
            Fail-Test $msg
            return $false
        }
    }
}

function Get-HttpErrorInfo {
    <#
    .SYNOPSIS
        Extracts the HTTP status and the JSON body's error.code from the error
        record of a failed Invoke-WebRequest / Invoke-RestMethod call.
        Returns @{ Status = <int or $null>; Code = <int or $null>; Body = <string or $null> }.
        Works with Windows PowerShell 5.1 (WebException) and PowerShell 7
        (HttpResponseException).
    #>
    param([Parameter(Mandatory)] $ErrorRecord)

    $status = $null
    $code = $null
    $body = $null

    $response = $null
    if ($ErrorRecord.Exception.Response) {
        $response = $ErrorRecord.Exception.Response
    } elseif ($ErrorRecord.Exception.InnerException -and $ErrorRecord.Exception.InnerException.Response) {
        $response = $ErrorRecord.Exception.InnerException.Response
    }
    if ($response) { $status = [int] $response.StatusCode }

    # The parsed error body: ErrorDetails first, the raw response stream (5.1) as a fallback
    if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
        $body = $ErrorRecord.ErrorDetails.Message
    } elseif ($response -and ($response | Get-Member -Name GetResponseStream -MemberType Method)) {
        try {
            $stream = $response.GetResponseStream()
            if ($stream.CanSeek) { $stream.Position = 0 }
            $reader = New-Object System.IO.StreamReader($stream)
            $body = $reader.ReadToEnd()
        } catch {}
    }
    if ($body) {
        try {
            $parsed = $body | ConvertFrom-Json
            if ($null -ne $parsed.error -and $null -ne $parsed.error.code) { $code = [int] $parsed.error.code }
        } catch {}
    }

    if (-not $status -and $ErrorRecord.Exception.Message -match '\((\d{3})\)') {
        $status = [int] $Matches[1]
    }

    return @{ Status = $status; Code = $code; Body = $body }
}

function Assert-HttpErrorCode {
    <#
    .SYNOPSIS
        Executes a script block and asserts that it fails with the expected HTTP
        status AND the expected error.code in the JSON body, for example
        400 / 4008. Assert-HttpError checks the status only; the API's sub-codes
        (error.code >= 1000) need both. Pass the status as -ExpectedCode as well
        to assert a plain error (400 / 400).
    #>
    param(
        [Parameter(Mandatory)] [int] $ExpectedStatus,
        [Parameter(Mandatory)] [int] $ExpectedCode,
        [Parameter(Mandatory)] [scriptblock] $Action,
        [string] $Label = ""
    )
    try {
        & $Action | Out-Null
        $msg = "Expected HTTP $ExpectedStatus / error.code $ExpectedCode but no error was thrown"
        if ($Label) { $msg = "$Label -- $msg" }
        Fail-Test $msg
        return $false
    }
    catch {
        $info = Get-HttpErrorInfo $_
        if ($info.Status -eq $ExpectedStatus -and $info.Code -eq $ExpectedCode) {
            return $true
        }
        $msg = "Expected HTTP $ExpectedStatus / error.code $ExpectedCode, got $($info.Status) / $($info.Code) ($($_.Exception.Message))"
        if ($Label) { $msg = "$Label -- $msg" }
        Fail-Test $msg
        return $false
    }
}
