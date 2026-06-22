# Authentication

The Password Depot REST API v2.0 uses standard **Bearer token** authentication. Every session begins with a login request that returns an `access_token`, which is then included as an `Authorization` header in all subsequent requests.

!!! note "Difference from v1.0"
    **v1.0** required two custom headers on every request: `access_token` and `client_id`.
    **v2.0** uses the industry-standard `Authorization: Bearer <token>` header -- a single header that works natively with HTTP clients, API gateways, and middleware.

## Authentication Flow

```
Client                                    Server
  |                                          |
  |  POST /v2.0/auth/login (credentials)     |
  |----------------------------------------->|
  |                                          |
  |  { "access_token": "eyJ..." }            |
  |<-----------------------------------------|
  |                                          |
  |  GET /v2.0/databases                     |
  |  Authorization: Bearer eyJ...            |
  |----------------------------------------->|
  |                                          |
  |  { "data": [...], "total": 3 }           |
  |<-----------------------------------------|
  |                                          |
  |  POST /v2.0/auth/logout                  |
  |  Authorization: Bearer eyJ...            |
  |----------------------------------------->|
  |                                          |
  |  204 No Content                          |
  |<-----------------------------------------|
```

## Step 1: Login

**Endpoint:** `POST /v2.0/auth/login`

The login endpoint supports five authentication methods, selected via the `auth` field in the request body. If `auth` is omitted, `standard` is used by default.

Additionally, the `scope` field determines the session type:

- **`"client"`** (default) -- Normal client session for accessing databases, folders, entries, and search.
- **`"admin"`** -- Server administration session with access to all client endpoints plus management endpoints under `/admin/` (database CRUD, users, groups, permissions, alerts, secrets).

| Method | `auth` value | Required fields |
|--------|:------------:|-----------------|
| Standard (default) | `standard` | `user`, `pass` |
| SSPI (Kerberos / NTLM) | `sspi` | `user`, `pass` |
| Negotiate (Windows SSO) | `negotiate` | *(none -- uses process identity)* |
| Azure AD *(deprecated)* | `azure` | `id_token` |
| OIDC | `oidc` | `idp`, `id_token` |

### Standard Authentication

Normal username and password authentication. The `auth` field can be omitted since `standard` is the default.

=== "curl"

    ```bash
    curl -k -X POST "https://your-server:8714/v2.0/auth/login" \
      -H "Content-Type: application/json" \
      -d '{"user":"admin","pass":"my_password"}'
    ```

=== "PowerShell"

    ```powershell
    $body = @{
        user = "admin"
        pass = "my_password"
    } | ConvertTo-Json

    $response = Invoke-RestMethod `
      -Uri "https://your-server:8714/v2.0/auth/login" `
      -Method POST `
      -Body $body `
      -ContentType "application/json"

    $token = $response.access_token
    Write-Host "Token: $token"
    ```

=== "Python"

    ```python
    import requests

    response = requests.post(
        "https://your-server:8714/v2.0/auth/login",
        json={"user": "admin", "pass": "my_password"},
        verify=False  # Set to True with a valid SSL cert
    )
    data = response.json()
    token = data["access_token"]
    ```

### SSPI Authentication

Authentication via SSPI (Kerberos / Negotiate / NTLM). The server validates the provided Windows domain credentials against Active Directory. The username must be in one of these formats:

- **UPN:** `user@domain.com`
- **Down-level:** `DOMAIN\sAMAccountName`

```json
{
  "auth": "sspi",
  "user": "DOMAIN\\jsmith",
  "pass": "windows_password"
}
```

!!! tip
    SSPI still requires the password in the request body. For **passwordless** authentication using the caller's Windows identity (gMSA, service accounts), use `negotiate` instead.

### Negotiate Authentication (Windows SSO)

Passwordless authentication via HTTP Negotiate (SPNEGO/Kerberos). The client's Windows process identity is used directly -- no username or password is sent in the request body. This is ideal for Group Managed Service Accounts (gMSA), scheduled tasks, and CI/CD pipelines.

The HTTP client library handles the Negotiate handshake automatically:

=== "PowerShell"

    ```powershell
    # -UseDefaultCredentials sends the process identity's Kerberos ticket
    $response = Invoke-RestMethod `
      -Uri "https://your-server:8714/v2.0/auth/login" `
      -Method POST `
      -Body '{"auth":"negotiate"}' `
      -ContentType "application/json" `
      -UseDefaultCredentials

    $token = $response.access_token
    ```

=== "curl"

    ```bash
    curl -k -X POST "https://your-server:8714/v2.0/auth/login" \
      -H "Content-Type: application/json" \
      -d '{"auth":"negotiate"}' \
      --negotiate -u :
    ```

=== "Python"

    ```python
    from requests_negotiate_sspi import HttpNegotiateAuth

    response = requests.post(
        "https://your-server:8714/v2.0/auth/login",
        json={"auth": "negotiate"},
        auth=HttpNegotiateAuth(),
        verify=False,
    )
    token = response.json()["access_token"]
    ```

!!! warning "Prerequisites"
    - **Integrated Windows Authentication** must be enabled in the server options
    - The PD user must have the **IWA** auth method enabled with SAM or UPN populated
    - The client must be in the same or a trusted Active Directory domain
    - No additional SPN registration is needed -- the standard `HOST` SPNs on the server's computer account cover HTTP Negotiate
    - See the [full reference](../api-reference/authentication.md#negotiate) for details

### OIDC Authentication

Authentication via one of the OIDC identity providers registered on the server. Use `GET /v2.0/auth/oidc` to discover available providers (see [OIDC Discovery](#oidc-discovery) below).

```json
{
  "auth": "oidc",
  "idp": "<provider id>",
  "id_token": "<token from OIDC flow>"
}
```

### Azure AD Authentication *(deprecated)*

Predefined Azure AD / Entra ID authentication. Use `oidc` instead for new integrations.

```json
{
  "auth": "azure",
  "id_token": "<Azure AD token>"
}
```

### Successful Response

```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIs..."
}
```

!!! info "Simplified Response"
    Unlike v1.0, the login response no longer includes a `client_id`. The `access_token` alone is sufficient for all authenticated requests.

### Token Lifetime

Access tokens expire after **10 minutes of inactivity** by default. The inactivity timer resets on every authenticated API call, so active sessions stay alive indefinitely.

For **automation and service accounts**, the Password Depot Server Manager can generate **long-lived tokens** that do not expire on inactivity. See the [full reference](../api-reference/authentication.md#token-lifetime) for details and security recommendations.

## Step 2: Use the Token

Include the `Authorization: Bearer` header in every subsequent request:

=== "curl"

    ```bash
    curl -k -X GET "https://your-server:8714/v2.0/databases" \
      -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIs..."
    ```

=== "PowerShell"

    ```powershell
    $headers = @{
        Authorization = "Bearer $token"
    }

    $databases = Invoke-RestMethod `
      -Uri "https://your-server:8714/v2.0/databases" `
      -Headers $headers

    $databases.data | Format-Table name, id
    ```

=== "Python"

    ```python
    headers = {"Authorization": f"Bearer {token}"}

    response = requests.get(
        "https://your-server:8714/v2.0/databases",
        headers=headers,
        verify=False
    )
    databases = response.json()
    ```

## Current User Profile

After authenticating, you can verify your identity and check your roles by calling `GET /v2.0/me`:

```bash
curl -k -X GET "https://your-server:8714/v2.0/me" \
  -H "Authorization: Bearer $TOKEN"
```

This returns the full user profile including display name, roles, and group memberships. See the [User Profile](../api-reference/users.md#user-profile) API reference for the complete response schema.

## Token Expiration

!!! warning "10-Minute Timeout"
    The `access_token` expires after **10 minutes of inactivity**. Each successful API request resets the timer. If a request returns `401 Unauthorized`, the client must re-authenticate by calling the login endpoint again.

## Two-Factor Authentication (2FA)

If two-factor authentication is enabled for the user, the login flow has additional steps. The 2FA flow is the same as v1.0.

**Summary:**

| Response Code | Meaning | Action Required |
|:-------------:|---------|-----------------|
| `459` | TFA not yet activated | Scan QR code from URL in `error.message` field, then resend login with `tfacode` |
| `460` | TFA code required | Prompt user for 6-digit code, resend login with `tfacode` |

### Login with 2FA Code

=== "curl"

    ```bash
    curl -k -X POST "https://your-server:8714/v2.0/auth/login" \
      -H "Content-Type: application/json" \
      -d '{"user":"admin","pass":"my_password","tfacode":"123456"}'
    ```

=== "PowerShell"

    ```powershell
    $body = @{
        user    = "admin"
        pass    = "my_password"
        tfacode = "123456"
    } | ConvertTo-Json

    $response = Invoke-RestMethod `
      -Uri "https://your-server:8714/v2.0/auth/login" `
      -Method POST `
      -Body $body `
      -ContentType "application/json"
    ```

=== "Python"

    ```python
    response = requests.post(
        "https://your-server:8714/v2.0/auth/login",
        json={"user": "admin", "pass": "my_password", "tfacode": "123456"},
        verify=False
    )
    ```

!!! warning "No Trusted Devices"
    The REST API does not support trusted devices. Users must supply a valid 2FA code on **every** login.

## OIDC Discovery

**Endpoint:** `GET /v2.0/auth/oidc`

Retrieve the list of configured OIDC/Azure identity providers. No authentication is required.

=== "curl"

    ```bash
    curl -k -s "https://your-server:8714/v2.0/auth/oidc" | jq .
    ```

=== "PowerShell"

    ```powershell
    $providers = Invoke-RestMethod -Uri "https://your-server:8714/v2.0/auth/oidc"
    $providers | Format-Table id, display_name, provider_class
    ```

=== "Python"

    ```python
    response = requests.get(
        "https://your-server:8714/v2.0/auth/oidc",
        verify=False
    )
    providers = response.json()
    for p in providers:
        print(f"  {p['display_name']} ({p['provider_class']})")
    ```

## Step 3: Logout

**Endpoint:** `POST /v2.0/auth/logout`

Always log out when done to free server resources:

=== "curl"

    ```bash
    curl -k -X POST "https://your-server:8714/v2.0/auth/logout" \
      -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
    ```

=== "PowerShell"

    ```powershell
    Invoke-RestMethod `
      -Uri "https://your-server:8714/v2.0/auth/logout" `
      -Method POST `
      -Headers @{ Authorization = "Bearer $token" }

    Write-Host "Logged out successfully."
    ```

=== "Python"

    ```python
    requests.post(
        "https://your-server:8714/v2.0/auth/logout",
        headers=headers,
        verify=False
    )
    ```

The server responds with `204 No Content` on success.

## v1.0 vs v2.0 Comparison

| Aspect | v1.0 | v2.0 |
|--------|------|------|
| Login endpoint | `POST /v1.0/login` | `POST /v2.0/auth/login` |
| Login response | `access_token` + `client_id` | `access_token` only |
| Auth headers | `access_token: ...` and `client_id: ...` | `Authorization: Bearer ...` |
| Logout endpoint | `POST /v1.0/logout` | `POST /v2.0/auth/logout` |
| Logout auth | `client_id` header only | `Authorization: Bearer` header |
| OIDC endpoint | `GET /v1.0/oidc` | `GET /v2.0/auth/oidc` |

## Next Steps

- [Quick Start](quick-start.md) -- Complete CRUD walkthrough from login to logout
- [API Reference: Authentication](../api-reference/authentication.md) -- Full endpoint specification with schemas
