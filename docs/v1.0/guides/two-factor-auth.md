# Two-Factor Authentication (2FA) Guide

This guide covers how to handle two-factor authentication when integrating with the Password Depot REST API.

## Overview

Password Depot Server supports two-factor authentication via **email codes** or **Authenticator apps** (TOTP). When 2FA is enabled for a user, the login flow requires an additional code.

!!! info "No Trusted Devices"
    The REST API does **not** support trusted devices or trusted computers. A valid 6-digit code must be provided on **every** login.

!!! warning "2FA Initialization"
    The REST API does **not** support initializing or registering 2FA for a user. Initial 2FA setup must be done through a standard Password Depot client application. The REST API only handles providing the 2FA code during login.

## 2FA Login Flow

```
Client                                  Server
  |                                       |
  |  POST /login (user + pass)            |
  |----- -------------------------------->|
  |                                       |
  |  459: TFA Not Activated (QR URL)      |  <-- First-time TOTP setup only
  |  OR                                   |
  |  460: TFA Code Required               |  <-- Normal 2FA login
  |<--------------------------------------|
  |                                       |
  |  (User scans QR / enters code)        |
  |                                       |
  |  POST /login (user + pass + tfacode)  |
  |-------------------------------------->|
  |                                       |
  |  200: { access_token, client_id }     |
  |<--------------------------------------|
```

## Scenario 1: TFA Code Required (Code 460)

This is the **most common** scenario. When 2FA is configured and active for the user, the server responds with status `460`:

**Server Response:**
```json
{
  "code": "460",
  "error": "Password Depot Enterprise Server requires two-factor authentication.\r\nPlease enter the verification code sent to your email address:\r\n us****@*****.com"
}
```

The error message indicates how the code is delivered (email or authenticator app). The client must:

1. Detect the `460` response
2. Prompt the user for their 6-digit code
3. Resend the login request with `tfacode`

=== "curl"

    ```bash
    # Step 1: Initial login attempt
    RESPONSE=$(curl -k -s -X POST "https://YOUR_SERVER:8714/v1.0/login" \
      -H "Content-Type: application/json" \
      -d '{"user":"admin","pass":"my_password"}')

    CODE=$(echo "$RESPONSE" | jq -r '.code')

    if [ "$CODE" = "460" ]; then
      echo "2FA code required."
      echo "$RESPONSE" | jq -r '.error'
      read -p "Enter 6-digit code: " TFA_CODE

      # Step 2: Resend with tfacode
      LOGIN=$(curl -k -s -X POST "https://YOUR_SERVER:8714/v1.0/login" \
        -H "Content-Type: application/json" \
        -d "{\"user\":\"admin\",\"pass\":\"my_password\",\"tfacode\":\"${TFA_CODE}\"}")
      echo "$LOGIN" | jq .
    fi
    ```

=== "PowerShell"

    ```powershell
    $BaseUri = "https://YOUR_SERVER:8714/v1.0"

    try {
        $login = Invoke-RestMethod -Uri "$BaseUri/login" -Method POST `
            -Body (@{ user = "admin"; pass = "my_password" } | ConvertTo-Json) `
            -ContentType "application/json"
    }
    catch {
        $errorResponse = $_.ErrorDetails.Message | ConvertFrom-Json

        if ($errorResponse.code -eq "460") {
            Write-Host $errorResponse.error
            $tfaCode = Read-Host "Enter your 2FA code"

            $login = Invoke-RestMethod -Uri "$BaseUri/login" -Method POST `
                -Body (@{
                    user    = "admin"
                    pass    = "my_password"
                    tfacode = $tfaCode
                } | ConvertTo-Json) `
                -ContentType "application/json"

            Write-Host "Logged in. Client ID: $($login.client_id)"
        }
    }
    ```

=== "Python"

    ```python
    response = requests.post(f"{BASE_URL}/login",
        json={"user": "admin", "pass": "my_password"},
        verify=False)

    if response.status_code == 460:
        data = response.json()
        print(data["error"])
        tfa_code = input("Enter your 2FA code: ")
        response = requests.post(f"{BASE_URL}/login",
            json={"user": "admin", "pass": "my_password", "tfacode": tfa_code},
            verify=False)
        response.raise_for_status()
        print(f"Logged in. Client ID: {response.json()['client_id']}")
    ```

## Scenario 2: First-Time TOTP Setup (Code 459)

When 2FA is enabled but the user has **not yet registered** their authenticator app, the server returns status `459` with a QR code URL:

**Server Response:**
```json
{
  "code": "459",
  "error": "https://your-server:8714/v1.0/temp/as123453456.png"
}
```

The `error` field contains a URL to a temporary PNG image of a QR code containing the TOTP secret.

**Steps:**

1. Download or display the QR code image from the URL in the `error` field
2. Have the user scan it with their authenticator app (Google Authenticator, Microsoft Authenticator, etc.)
3. Resend the login request with the 6-digit `tfacode` from the authenticator app

=== "curl"

    ```bash
    RESPONSE=$(curl -k -s -X POST "https://YOUR_SERVER:8714/v1.0/login" \
      -H "Content-Type: application/json" \
      -d '{"user":"admin","pass":"my_password"}')

    CODE=$(echo "$RESPONSE" | jq -r '.code')

    if [ "$CODE" = "459" ]; then
      QR_URL=$(echo "$RESPONSE" | jq -r '.error')
      echo "2FA not activated. QR code available at: $QR_URL"

      # Download the QR code image
      curl -k -s "$QR_URL" -o qr_code.png
      echo "QR code saved to qr_code.png -- scan with your authenticator app."

      read -p "Enter the 6-digit code from your authenticator app: " TFA_CODE

      LOGIN=$(curl -k -s -X POST "https://YOUR_SERVER:8714/v1.0/login" \
        -H "Content-Type: application/json" \
        -d "{\"user\":\"admin\",\"pass\":\"my_password\",\"tfacode\":\"${TFA_CODE}\"}")
      echo "$LOGIN" | jq .
    fi
    ```

=== "PowerShell"

    ```powershell
    try {
        $login = Invoke-RestMethod -Uri "$BaseUri/login" -Method POST `
            -Body (@{ user = "admin"; pass = "my_password" } | ConvertTo-Json) `
            -ContentType "application/json"
    }
    catch {
        $errorResponse = $_.ErrorDetails.Message | ConvertFrom-Json

        if ($errorResponse.code -eq "459") {
            $qrUrl = $errorResponse.error
            Write-Host "2FA setup required. QR code URL: $qrUrl"

            # Download QR code
            Invoke-WebRequest -Uri $qrUrl -OutFile "qr_code.png"
            Write-Host "QR code saved to qr_code.png -- scan with your authenticator app."

            $tfaCode = Read-Host "Enter 6-digit code"

            $login = Invoke-RestMethod -Uri "$BaseUri/login" -Method POST `
                -Body (@{
                    user    = "admin"
                    pass    = "my_password"
                    tfacode = $tfaCode
                } | ConvertTo-Json) `
                -ContentType "application/json"

            Write-Host "Logged in with 2FA. Client ID: $($login.client_id)"
        }
    }
    ```

=== "Python"

    ```python
    response = requests.post(f"{BASE_URL}/login",
        json={"user": "admin", "pass": "my_password"},
        verify=False)

    if response.status_code == 459:
        data = response.json()
        qr_url = data["error"]
        print(f"2FA setup required. QR code URL: {qr_url}")

        # Download QR code
        qr_response = requests.get(qr_url, verify=False)
        with open("qr_code.png", "wb") as f:
            f.write(qr_response.content)
        print("QR code saved to qr_code.png")

        tfa_code = input("Enter 6-digit code: ")
        response = requests.post(f"{BASE_URL}/login",
            json={"user": "admin", "pass": "my_password", "tfacode": tfa_code},
            verify=False)
        response.raise_for_status()
        print(f"Logged in. Client ID: {response.json()['client_id']}")
    ```

## Robust Login Function

A reusable login function that handles all authentication scenarios (normal, 459, and 460):

=== "PowerShell"

    ```powershell
    function Connect-PDServer {
        param(
            [Parameter(Mandatory)] [string] $Server,
            [Parameter(Mandatory)] [string] $Username,
            [Parameter(Mandatory)] [string] $Password,
            [int] $Port = 8714
        )

        $uri = "https://${Server}:${Port}/v1.0/login"
        $body = @{ user = $Username; pass = $Password }

        try {
            $result = Invoke-RestMethod -Uri $uri -Method POST `
                -Body ($body | ConvertTo-Json) `
                -ContentType "application/json"
            return $result
        }
        catch {
            $err = $_.ErrorDetails.Message | ConvertFrom-Json

            switch ($err.code) {
                "459" {
                    Write-Host "2FA setup required. QR code: $($err.error)"
                    Invoke-WebRequest -Uri $err.error -OutFile "qr_code.png"
                    Write-Host "QR code saved. Scan with your authenticator app."
                    $tfaCode = Read-Host "Enter 6-digit code"
                    $body.tfacode = $tfaCode
                }
                "460" {
                    Write-Host $err.error
                    $tfaCode = Read-Host "Enter your 2FA code"
                    $body.tfacode = $tfaCode
                }
                default {
                    throw "Login failed: $($err.error)"
                }
            }

            # Retry with 2FA code
            return Invoke-RestMethod -Uri $uri -Method POST `
                -Body ($body | ConvertTo-Json) `
                -ContentType "application/json"
        }
    }

    # Usage
    $session = Connect-PDServer -Server "your-server" -Username "admin" -Password "pass"
    ```

=== "Python"

    ```python
    def login_with_2fa(base_url, username, password, verify_ssl=False):
        """Login with automatic 2FA handling."""
        payload = {"user": username, "pass": password}

        response = requests.post(f"{base_url}/login",
            json=payload, verify=verify_ssl)

        if response.status_code == 200:
            return response.json()

        data = response.json()
        code = str(data.get("code", ""))

        if code == "459":
            qr_url = data["error"]
            print(f"2FA setup required. QR code: {qr_url}")
            qr = requests.get(qr_url, verify=verify_ssl)
            with open("qr_code.png", "wb") as f:
                f.write(qr.content)
            print("QR code saved to qr_code.png")
            tfa_code = input("Enter 6-digit code: ")
            payload["tfacode"] = tfa_code

        elif code == "460":
            print(data["error"])
            tfa_code = input("Enter your 2FA code: ")
            payload["tfacode"] = tfa_code

        else:
            response.raise_for_status()

        response = requests.post(f"{base_url}/login",
            json=payload, verify=verify_ssl)
        response.raise_for_status()
        return response.json()

    # Usage
    creds = login_with_2fa(BASE_URL, "admin", "my_password")
    ```

## Automated Scripts with 2FA

For automation scenarios where interactive input is not possible, you can use TOTP libraries to generate the 6-digit code programmatically (requires the TOTP secret obtained during initial setup):

=== "PowerShell"

    ```powershell
    # Requires: Install-Module -Name OTP
    Import-Module OTP

    $secret = "YOUR_BASE32_TOTP_SECRET"
    $tfaCode = Get-OTP -Secret $secret

    $body = @{
        user    = "admin"
        pass    = "my_password"
        tfacode = $tfaCode
    } | ConvertTo-Json

    $login = Invoke-RestMethod -Uri "$BaseUri/login" -Method POST `
        -Body $body -ContentType "application/json"
    ```

=== "Python"

    ```python
    # Requires: pip install pyotp
    import pyotp

    secret = "YOUR_BASE32_TOTP_SECRET"
    totp = pyotp.TOTP(secret)
    tfa_code = totp.now()

    response = requests.post(f"{BASE_URL}/login",
        json={"user": "admin", "pass": "my_password", "tfacode": tfa_code},
        verify=False)
    ```

!!! tip
    This approach only works when the server is configured to use **Authenticator app** for 2FA. If the server uses **email-based** 2FA codes, automated generation is not possible.
