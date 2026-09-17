# Quick Start

This guide takes you from zero to listing your first password entry in under 5 minutes.

## Prerequisites

- Password Depot Server with REST service enabled ([setup guide](setup.md))
- A valid user account on the server
- `curl`, PowerShell, or Python installed on your machine

## Step 1: Log In

!!! warning "Legacy Servers (prior to v18.0.0)"
    The examples below use JSON request body for credentials, which requires **v18.0.0 or later**. For older servers, credentials must be passed as custom HTTP headers. See the [API Reference: Authentication](../api-reference/authentication.md) for legacy examples.

=== "curl"

    ```bash
    # Replace YOUR_SERVER, USERNAME, and PASSWORD
    curl -k -X POST "https://YOUR_SERVER:8714/v1.0/login" \
      -H "Content-Type: application/json" \
      -d '{"user":"USERNAME","pass":"PASSWORD"}'
    ```

=== "PowerShell"

    ```powershell
    # Replace YOUR_SERVER, USERNAME, and PASSWORD
    $loginBody = @{
        user = "USERNAME"
        pass = "PASSWORD"
    } | ConvertTo-Json

    $login = Invoke-RestMethod `
      -Uri "https://YOUR_SERVER:8714/v1.0/login" `
      -Method POST `
      -Body $loginBody `
      -ContentType "application/json"

    # Save credentials for subsequent requests
    $headers = @{
        access_token = $login.access_token
        client_id    = $login.client_id
    }

    Write-Host "Logged in successfully. Client ID: $($login.client_id)"
    ```

**Response:**
```json
{
  "access_token": "a1b2c3d4e5f6...",
  "client_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

Save both values -- you'll need them for every subsequent request.

## Step 2: List Databases

=== "curl"

    ```bash
    curl -k -X GET "https://YOUR_SERVER:8714/v1.0/list" \
      -H "access_token: YOUR_ACCESS_TOKEN" \
      -H "client_id: YOUR_CLIENT_ID"
    ```

=== "PowerShell"

    ```powershell
    $databases = Invoke-RestMethod `
      -Uri "https://YOUR_SERVER:8714/v1.0/list" `
      -Headers $headers

    $databases.databases | Format-Table name, fingerprint
    ```

**Response:**
```json
{
  "databases": [
    {
      "name": "db_1.pswe",
      "fingerprint": "550e8400-e29b-41d4-a716-446655440000",
      "date": "2020-12-09T11:12:45.202Z",
      "rights": "RMIDCFAPE-Y-HL",
      "reasondelete": "1"
    }
  ],
  "infoclasses": "000007FF",
  "policyforce": "1",
  "policyminlength": "10",
  "policyincludeatleast": "0",
  "policymingroups": "3",
  "policyselectedgroups": "15"
}
```

Note the `fingerprint` of the database you want to access.

## Step 3: List Entries

=== "curl"

    ```bash
    # Replace DB_FINGERPRINT with the fingerprint from Step 2
    curl -k -X GET "https://YOUR_SERVER:8714/v1.0/list?db=DB_FINGERPRINT" \
      -H "access_token: YOUR_ACCESS_TOKEN" \
      -H "client_id: YOUR_CLIENT_ID"
    ```

=== "PowerShell"

    ```powershell
    $dbFingerprint = $databases.databases[0].fingerprint

    $entries = Invoke-RestMethod `
      -Uri "https://YOUR_SERVER:8714/v1.0/list?db=$dbFingerprint" `
      -Headers $headers

    $entries.entries | Format-Table name, login, url
    ```

**Response:**
```json
{
  "name": "Root",
  "parent": "",
  "entries": [
    {
      "name": "Example Entry",
      "fingerprint": "660e8400-e29b-41d4-a716-446655440001",
      "rights": "RMID",
      "itemclass": "0",
      "login": "user1",
      "url": "http://example.com",
      "date": "2021-07-05T10:39:50.000Z",
      "icon": "ico0.png",
      "hash": ""
    }
  ]
}
```

## Step 4: Read Entry Details

=== "curl"

    ```bash
    curl -k -X GET \
      "https://YOUR_SERVER:8714/v1.0/read?db=DB_FINGERPRINT&entry=ENTRY_FINGERPRINT" \
      -H "access_token: YOUR_ACCESS_TOKEN" \
      -H "client_id: YOUR_CLIENT_ID"
    ```

=== "PowerShell"

    ```powershell
    $entryFingerprint = $entries.entries[0].fingerprint

    $detail = Invoke-RestMethod `
      -Uri "https://YOUR_SERVER:8714/v1.0/read?db=$dbFingerprint&entry=$entryFingerprint" `
      -Headers $headers

    $detail | ConvertTo-Json -Depth 5
    ```

This returns the full entry including the password, custom fields, and TANs.

## Step 5: Log Out

Always log out when you're done:

=== "curl"

    ```bash
    curl -k -X POST "https://YOUR_SERVER:8714/v1.0/logout" \
      -H "client_id: YOUR_CLIENT_ID"
    ```

=== "PowerShell"

    ```powershell
    Invoke-RestMethod `
      -Uri "https://YOUR_SERVER:8714/v1.0/logout" `
      -Method POST `
      -Headers @{ client_id = $login.client_id }

    Write-Host "Logged out successfully."
    ```

## Complete Script

Here's the entire workflow as a single copy-paste script:

=== "curl (Bash)"

    ```bash
    #!/bin/bash
    SERVER="YOUR_SERVER"
    PORT="8714"
    BASE="https://${SERVER}:${PORT}/v1.0"

    # Login
    LOGIN=$(curl -k -s -X POST "${BASE}/login" \
      -H "Content-Type: application/json" \
      -d '{"user":"USERNAME","pass":"PASSWORD"}')

    TOKEN=$(echo "$LOGIN" | jq -r '.access_token')
    CLIENT=$(echo "$LOGIN" | jq -r '.client_id')

    echo "Logged in: client_id=$CLIENT"

    # List databases
    DATABASES=$(curl -k -s -X GET "${BASE}/list" \
      -H "access_token: ${TOKEN}" \
      -H "client_id: ${CLIENT}")

    echo "Databases:"
    echo "$DATABASES" | jq '.databases[] | {name, fingerprint}'

    # List entries in first database
    DB_FP=$(echo "$DATABASES" | jq -r '.databases[0].fingerprint')
    ENTRIES=$(curl -k -s -X GET "${BASE}/list?db=${DB_FP}" \
      -H "access_token: ${TOKEN}" \
      -H "client_id: ${CLIENT}")

    echo "Entries:"
    echo "$ENTRIES" | jq '.entries[] | {name, login, url}'

    # Logout
    curl -k -s -X POST "${BASE}/logout" -H "client_id: ${CLIENT}"
    echo "Logged out."
    ```

=== "PowerShell"

    ```powershell
    $Server = "YOUR_SERVER"
    $Port = 8714
    $Base = "https://${Server}:${Port}/v1.0"

    # Login
    $loginBody = @{ user = "USERNAME"; pass = "PASSWORD" } | ConvertTo-Json
    $login = Invoke-RestMethod -Uri "$Base/login" -Method POST `
      -Body $loginBody -ContentType "application/json"

    $headers = @{
        access_token = $login.access_token
        client_id    = $login.client_id
    }
    Write-Host "Logged in: client_id = $($login.client_id)"

    # List databases
    $dbs = Invoke-RestMethod -Uri "$Base/list" -Headers $headers
    $dbs.databases | Format-Table name, fingerprint

    # List entries in first database
    $dbFp = $dbs.databases[0].fingerprint
    $entries = Invoke-RestMethod -Uri "$Base/list?db=$dbFp" `
      -Headers $headers
    $entries.entries | Format-Table name, login, url

    # Logout
    Invoke-RestMethod -Uri "$Base/logout" -Method POST `
      -Headers @{ client_id = $login.client_id }
    Write-Host "Logged out."
    ```

## Next Steps

- [API Reference](../api-reference/overview.md) -- Explore all endpoints in detail
- [PowerShell Examples](../examples/powershell.md) -- Advanced PowerShell automation
- [Two-Factor Authentication](../guides/two-factor-auth.md) -- Handle 2FA in your scripts
