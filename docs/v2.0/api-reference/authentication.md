# Authentication Endpoints

API reference for authentication-related endpoints.

---

## Login

Authenticates a user and returns an access token for subsequent API requests.

| | |
|---|---|
| **Endpoint** | `POST /v2.0/auth/login` |
| **Auth required** | No |
| **Content-Type** | `application/json` |

### Request Body

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `auth` | string | No | Authentication method: `"standard"`, `"sspi"`, `"negotiate"`, `"azure"`, `"oidc"`. Defaults to `"standard"` if omitted. WebAuthn uses [separate endpoints](#webauthn). |
| `scope` | string | No | Session scope: `"client"` (default) or `"admin"`. See [Client vs Admin Scope](#client-vs-admin-scope). |
| `user` | string | Conditional | Username (required for `standard` and `sspi`) |
| `pass` | string | Conditional | Password (required for `standard` and `sspi`) |
| `tfacode` | string | No | 6-digit two-factor authentication code |
| `idp` | string | Conditional | Identity Provider ID from `/auth/oidc` (required for `oidc`) |
| `id_token` | string | Conditional | Identity token obtained from the OIDC/Azure flow (required for `oidc` and `azure`) |

### Authentication Methods

#### `standard` (default)

Normal username and password authentication. This is the default method when `auth` is omitted.

**Required fields:** `user`, `pass`

#### `sspi`

Authentication via SSPI (Kerberos / Negotiate / NTLM). The server validates the provided Windows domain credentials against Active Directory using SSPI. The username must be in one of these formats:

- **UPN:** `user@domain.com`
- **Down-level:** `DOMAIN\sAMAccountName`

**Required fields:** `user`, `pass`

!!! tip
    If you need **passwordless** authentication using the caller's Windows identity (e.g., for Group Managed Service Accounts), use the [`negotiate`](#negotiate) method instead.

#### `negotiate`

Passwordless authentication via HTTP Negotiate (SPNEGO/Kerberos). The client's Windows identity is used directly -- no username or password is sent in the request body. This is ideal for:

- **Group Managed Service Accounts (gMSA)** running automated scripts and scheduled tasks
- **Service accounts** where storing passwords is not acceptable
- **Single Sign-On (SSO)** scenarios in Windows domain environments

The authentication follows the standard [HTTP Negotiate protocol (RFC 4559)](https://datatracker.ietf.org/doc/html/rfc4559). From the client's perspective, the flow is transparent -- HTTP client libraries handle the SPNEGO handshake automatically. Under the hood:

1. Client sends `POST /v2.0/auth/login` with `{"auth": "negotiate"}`.
2. Server responds with `401` and `WWW-Authenticate: Negotiate` header.
3. Client's HTTP stack automatically retries with `Authorization: Negotiate <SPNEGO-token>` using the process identity's Kerberos ticket.
4. Server validates the token via SSPI (`AcceptSecurityContext`), maps the authenticated Windows identity to a Password Depot user (by SAM or UPN), and returns a JWT access token.

**Required fields:** none (the `Authorization: Negotiate` header is handled by the HTTP client library)

**Optional fields:** `scope`

!!! warning "Prerequisites"
    - The Password Depot Server must have **Integrated Windows Authentication** enabled in the server options.
    - The PD user account must have the **IWA** authentication method enabled and its **SAM** or **UPN** field populated to match the Windows identity.
    - The client machine must be joined to the same Active Directory domain (or a trusted domain).
    - No additional SPN registration is needed -- the standard `HOST/<servername>` SPNs (registered automatically for every domain-joined computer) cover HTTP Negotiate authentication.

#### `webauthn`

Passwordless authentication via WebAuthn/Passkey. This method enables browser-based clients (e.g., a web interface) to authenticate using biometric authentication, security keys, or platform authenticators -- without any password.

The flow uses two separate endpoints (not `/auth/login`):

**Step 1 -- Begin assertion:**

```
POST /v2.0/auth/webauthn/begin
```

```json
{
    "user": "john.doe",
    "scope": "client"
}
```

The server returns a `session_id` (to correlate Step 2) and the standard WebAuthn `publicKey` options containing the challenge and allowed credentials:

```json
{
    "session_id": "B7F3A1D2-...",
    "publicKey": {
        "challenge": "dGVzdC1jaGFsbGVuZ2U...",
        "rpId": "your-server.example.com",
        "allowCredentials": [
            {
                "type": "public-key",
                "id": "Y3JlZC1pZA..."
            }
        ],
        "userVerification": "preferred",
        "timeout": 60000
    }
}
```

**Step 2 -- Complete assertion:**

The browser calls `navigator.credentials.get()` with the server's challenge, then posts the signed response:

```
POST /v2.0/auth/webauthn/complete
```

```json
{
    "session_id": "B7F3A1D2-...",
    "id": "Y3JlZC1pZA...",
    "response": {
        "authenticatorData": "...",
        "clientDataJSON": "...",
        "signature": "...",
        "userHandle": "..."
    }
}
```

On success, the server returns a JWT access token (same format as all other login methods):

```json
{
    "access_token": "eyJhbGciOiJIUzI1NiIs..."
}
```

**Required fields (Step 1):** `user`

**Optional fields (Step 1):** `scope`

!!! warning "Prerequisites"
    - The Password Depot Server must have **WebAuthn** enabled in the server options.
    - The PD user account must have the **WebAuthn** authentication method enabled and at least one passkey registered.
    - Passkey registration is handled through the native Password Depot client application (not via the REST API).
    - The `session_id` is single-use and expires after the server's configured WebAuthn timeout (default: 60 seconds).

#### `azure` (deprecated)

Predefined Azure AD / Entra ID authentication. Use `oidc` instead for new integrations.

**Required fields:** `id_token`

#### `oidc`

Authentication via one of the OIDC identity providers registered on the server. Use `GET /v2.0/auth/oidc` to discover available providers.

**Required fields:** `idp`, `id_token`

The `id_token` field must carry **either** (a) a signed OIDC `id_token` (JWT) **or** (b) an opaque OAuth access token usable as a Bearer credential at the provider's `userinfo_endpoint`. It **must not** carry a bare authorization `code`. The REST server performs **no** authorization-code exchange -- it validates the supplied value directly (JWT signature / `aud` / `exp` via JWKS, falling back to a Bearer call to the `userinfo_endpoint`) and never posts to the provider's `token_endpoint`. A provider configured for authorization-code flow only (`response_type=code` with no `id_token`, e.g. a Google-style preset) is therefore supported only if the relying party performs the code-to-token exchange itself before calling REST login; the recommended client configuration is to request `response_type=id_token`. An invalid, expired, or forged token, a bare authorization code, or no matching local user returns `401`.

### Request Examples

=== "curl"

    ```bash
    # Standard login (auth can be omitted -- defaults to "standard")
    curl -k -X POST "https://your-server:8714/v2.0/auth/login" \
      -H "Content-Type: application/json" \
      -d '{"user":"admin","pass":"my_password"}'

    # Standard login with 2FA code
    curl -k -X POST "https://your-server:8714/v2.0/auth/login" \
      -H "Content-Type: application/json" \
      -d '{"user":"admin","pass":"my_password","tfacode":"123456"}'

    # SSPI (Windows domain) login
    curl -k -X POST "https://your-server:8714/v2.0/auth/login" \
      -H "Content-Type: application/json" \
      -d '{"auth":"sspi","user":"DOMAIN\\jsmith","pass":"my_password"}'

    # Negotiate (Windows SSO / gMSA) login -- no password needed
    curl -k -X POST "https://your-server:8714/v2.0/auth/login" \
      -H "Content-Type: application/json" \
      -d '{"auth":"negotiate"}' \
      --negotiate -u :

    # OIDC login
    curl -k -X POST "https://your-server:8714/v2.0/auth/login" \
      -H "Content-Type: application/json" \
      -d '{"auth":"oidc","idp":"EF0826B6-45D0-41AF-8C92-9D3E5F8DFAD2","id_token":"eyJhbGciOi..."}'
    ```

=== "PowerShell"

    ```powershell
    # Standard login (auth can be omitted -- defaults to "standard")
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

    # Standard login with 2FA code
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

    # SSPI (Windows domain) login
    $body = @{
        auth = "sspi"
        user = "DOMAIN\jsmith"
        pass = "my_password"
    } | ConvertTo-Json

    $response = Invoke-RestMethod `
      -Uri "https://your-server:8714/v2.0/auth/login" `
      -Method POST `
      -Body $body `
      -ContentType "application/json"

    # Negotiate (Windows SSO / gMSA) login -- no password needed
    # -UseDefaultCredentials sends the process identity's Kerberos ticket
    $response = Invoke-RestMethod `
      -Uri "https://your-server:8714/v2.0/auth/login" `
      -Method POST `
      -Body '{"auth":"negotiate"}' `
      -ContentType "application/json" `
      -UseDefaultCredentials

    $token = $response.access_token

    # Negotiate login with admin scope (e.g., for a gMSA with admin privileges)
    $response = Invoke-RestMethod `
      -Uri "https://your-server:8714/v2.0/auth/login" `
      -Method POST `
      -Body '{"auth":"negotiate","scope":"admin"}' `
      -ContentType "application/json" `
      -UseDefaultCredentials

    # OIDC login
    $body = @{
        auth     = "oidc"
        idp      = "okta-org-id"
        id_token = "eyJhbGciOi..."
    } | ConvertTo-Json

    $response = Invoke-RestMethod `
      -Uri "https://your-server:8714/v2.0/auth/login" `
      -Method POST `
      -Body $body `
      -ContentType "application/json"
    ```

=== "Python"

    ```python
    import requests

    # Standard login (auth can be omitted -- defaults to "standard")
    response = requests.post(
        "https://your-server:8714/v2.0/auth/login",
        json={"user": "admin", "pass": "my_password"},
        verify=False,
    )
    token = response.json()["access_token"]

    # Standard login with 2FA code
    response = requests.post(
        "https://your-server:8714/v2.0/auth/login",
        json={"user": "admin", "pass": "my_password", "tfacode": "123456"},
        verify=False,
    )

    # SSPI (Windows domain) login
    response = requests.post(
        "https://your-server:8714/v2.0/auth/login",
        json={"auth": "sspi", "user": "DOMAIN\\jsmith", "pass": "my_password"},
        verify=False,
    )

    # Negotiate (Windows SSO / gMSA) login -- requires requests-negotiate-sspi
    from requests_negotiate_sspi import HttpNegotiateAuth

    response = requests.post(
        "https://your-server:8714/v2.0/auth/login",
        json={"auth": "negotiate"},
        auth=HttpNegotiateAuth(),
        verify=False,
    )
    token = response.json()["access_token"]

    # OIDC login
    response = requests.post(
        "https://your-server:8714/v2.0/auth/login",
        json={"auth": "oidc", "idp": "EF0826B6-45D0-41AF-8C92-9D3E5F8DFAD2", "id_token": "eyJhbGciOi..."},
        verify=False,
    )
    ```

### Success Response

**Status:** `200 OK`

```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

| Field | Type | Description |
|-------|------|-------------|
| `access_token` | string | Bearer token for authenticating subsequent requests. Use it via the `Authorization: Bearer <token>` header. |

!!! info "Simplified Response"
    Unlike v1.0, the login response returns **only** `access_token`. There is no `client_id` -- the Bearer token alone identifies the session.

### Token Lifetime

By default, access tokens expire after **10 minutes of inactivity** (the timer resets on every authenticated API call). This is suitable for interactive use and short-lived scripts.

For **automation and service accounts** (e.g., scheduled tasks, CI/CD pipelines, monitoring scripts), the Password Depot Server Manager can generate **long-lived tokens** for administrator accounts with configurable lifetimes (6 months, 1 year, 18 months, or 2 years). Long-lived tokens do not expire on inactivity and remain valid until their expiration date is reached, they are explicitly revoked, or deleted by an administrator.

!!! tip "When to Use Long-Lived Tokens"
    - Scheduled tasks and cron jobs that need unattended access
    - CI/CD pipelines that retrieve secrets during deployment
    - Monitoring scripts that periodically check database health
    - Any scenario where re-authenticating every 10 minutes is impractical

    Long-lived tokens are managed exclusively in the **Password Depot Server Manager** -- in the user's properties dialog under the **API Tokens** tab. Each token has a descriptive name, scope, expiry date, and last-used timestamp. Contact your server administrator to generate one.

!!! warning "Security Considerations"
    Long-lived tokens should be treated as sensitive credentials:

    - Store them in a secure location (e.g., Windows Credential Manager, Azure Key Vault, HashiCorp Vault)
    - Never embed them in source code or commit them to version control
    - Use the minimum required scope (`"client"` unless admin access is needed)
    - Revoke tokens immediately when they are no longer needed

### Token Structure

The access token is a standard [JWT](https://datatracker.ietf.org/doc/html/rfc7519) signed with HMAC-SHA256. Clients normally treat it as an opaque Bearer credential, but the claims are documented here for debugging, log aggregation, and audit purposes. The server signs the token with a per-instance secret that is not exposed to clients.

**Claims emitted by both token types:**

| Claim | Name | Type | Description |
|-------|------|------|-------------|
| `iss` | Issuer | string | Server title (set in Server Manager) |
| `sub` | Subject | string | User ID (UUID). Primary identifier for the token's owner |
| `aud` | Audience | string | `https://<server-host>:<rest-port>/` |
| `iat` | Issued At | int (Unix time) | When the token was created |
| `exp` | Expiration | int (Unix time) | Absolute expiry. For session tokens this is rolling (extended on each authenticated call); for long-lived tokens it is the fixed expiry chosen at creation |
| `admin` | -- | boolean | `true` if the token carries admin scope, `false` otherwise. This is what distinguishes an admin session from a client session -- the `scope` field in the login body is only used at token-creation time |
| `refresh` | -- | boolean | `true` for session tokens (eligible for inactivity-based extension), `false` for long-lived tokens |

**Claim only on long-lived API tokens:**

| Claim | Name | Type | Description |
|-------|------|------|-------------|
| `jti` | JWT ID | string | UUID of the `ApiToken` record in the server store. Used server-side for revocation: presenting a token whose `jti` no longer matches an active record returns `401`. Session tokens do **not** carry `jti` -- the server uses the presence of this claim to decide which token type it is looking at (e.g., when deciding the logout behavior) |

**Telling the two token types apart on the client side:**

- A token **without** `jti` is a session token. `/auth/logout` returns `204 No Content`.
- A token **with** `jti` is a long-lived API token. `/auth/logout` returns `200 OK` with `{"revoked": false, "token_type": "api_token", ...}` and the token remains valid. See the [Logout](#logout) section.

!!! warning "Don't rely on JWT internals for security decisions"
    These claims are for informational/debugging use only. Never parse the token on the client to decide whether to call an admin endpoint -- the server is the sole authority on scope. The presence of `"admin": true` in a JWT does not grant admin access if the user's roles have since been revoked; the server re-checks every request.

### Error Responses

**401 -- Unauthorized**

```json
{
  "error": {
    "code": 401,
    "message": "Invalid username or password"
  }
}
```

Returned when credentials are invalid or the account is locked.

---

**429 -- Too Many Requests** *(IP lockout)*

```http
HTTP/1.1 429 Too Many Requests
Retry-After: 1745
Content-Type: application/json
```

```json
{
  "error": {
    "code": 429,
    "message": "Your IP address has been blocked. Please contact your PD server administrator or try again later."
  }
}
```

Returned when the IP address has exceeded the configured number of failed login attempts within the Login Interval (Server Manager &rarr; *Options* &rarr; *Security*). The block applies to **all** endpoints, not just `/auth/login`, for the duration of the Unblock-After period. The `Retry-After` header carries the remaining lockout in seconds -- honor it and back off; retrying immediately will not shorten the lockout.

---

**409 -- Conflict** *(FIDO2 second factor)*

```json
{
  "error": {
    "code": 409,
    "message": "FIDO2 two-factor authentication is not supported via the REST API. Log in via the native Password Depot client, or ask an administrator to switch your second factor to TOTP or email."
  }
}
```

Returned when the user account has FIDO2 (security key / passkey) configured as the second factor. The FIDO2 challenge / assertion flow is interactive and stateful, and cannot be driven from a stateless REST request -- the native Password Depot client and the Server Manager handle it directly. Two ways forward for a REST user:

- Log in via the native client first to register / use the security key, then continue working there. REST sessions for this user are not available.
- Ask an administrator to switch the user's `two_factor_mode` to `totp` (authenticator app) or `email`. Both are supported via REST.

For automation accounts, prefer **long-lived API tokens** (issued in the Server Manager) or **Negotiate / gMSA** authentication -- neither requires a second factor.

---

**401 -- Negotiate Challenge** *(Negotiate auth only)*

```http
HTTP/1.1 401 Unauthorized
WWW-Authenticate: Negotiate
```

This is **not an error** -- it is the first step of the HTTP Negotiate handshake. The client's HTTP library automatically responds with a Kerberos/SPNEGO token. You will not see this response when using `-UseDefaultCredentials` (PowerShell), `--negotiate` (curl), or `HttpNegotiateAuth` (Python) -- the library handles it transparently.

If authentication ultimately fails after the SPNEGO exchange, the server returns:

```json
{
  "error": {
    "code": 401,
    "message": "Windows authentication failed: no matching Password Depot user found for DOMAIN\\svc_account$"
  }
}
```

Common causes:

- The Windows identity does not match any PD user's SAM or UPN field
- The PD user does not have the IWA authentication method enabled
- Kerberos ticket cannot be obtained (e.g., client not domain-joined, clock skew, or DNS resolution failure)
- The client is not in the same domain or a trusted domain

---

**459 -- TFA Not Activated**

```json
{
  "error": {
    "code": 459,
    "message": "https://your-server:8714/v2.0/temp/qr123456.png"
  }
}
```

Returned when two-factor authentication is configured on the server but not yet activated for this user. The `error.message` contains a URL to a QR code image that the user must scan with an authenticator app. After scanning, resend the login request with the `tfacode` field.

!!! info
    2FA initialization/registration is only possible through a standard Password Depot client. The REST API only supports confirming an already-initialized 2FA with a code.

---

**460 -- TFA Code Required**

```json
{
  "error": {
    "code": 460,
    "message": "Password Depot Enterprise Server requires two-factor authentication.\r\nPlease enter the verification code sent to your email address:\r\n us****@*****.com"
  }
}
```

Returned when valid credentials were provided but a 2FA code is required. The 2FA code may be delivered via **email** or via an **authenticator app**, depending on the server configuration. Resend the login request with the `tfacode` field included.

!!! warning "No Trusted Devices"
    The REST API does not support trusted devices or trusted computers. Users must provide a valid 2FA code on **every** login.

### Client vs Admin Scope

The `scope` field determines which endpoints the session can access:

| Scope | Default | Accessible Endpoints |
|-------|:-------:|----------------------|
| `client` | Yes | `/databases` (read), `/databases/{db}/folders`, `/databases/{db}/entries`, `/databases/{db}/search`, `/users` (read), `/groups` (read) |
| `admin` | No | All client endpoints, plus `/admin/databases` (full CRUD), `/admin/databases/{db}/permissions`, `/admin/users`, `/admin/groups`, `/admin/alerts`, `/admin/secrets` |

When `scope` is omitted, it defaults to `"client"`. A client session sees only the databases the user has read access to; an admin session sees all databases on the server and can perform management operations.

!!! note "Admin Login Example"
    ```json
    {
      "user": "admin",
      "pass": "my_password",
      "scope": "admin"
    }
    ```

!!! warning "Admin Privileges"
    Only users with server administrator role can log in with `"scope": "admin"`. Non-admin users will receive a `403 Forbidden` error.

---

## Logout

Ends the current session. The exact behavior depends on the token type.

| | |
|---|---|
| **Endpoint** | `POST /v2.0/auth/logout` |
| **Auth required** | Yes (`Authorization: Bearer <token>`) |

!!! info "Behavior by token type"
    - **Short-lived session tokens** (issued by `POST /auth/login`) are discarded and the server drops the associated session state. The token will be rejected on subsequent use.
    - **Long-lived API tokens** (issued by the Password Depot Server Manager) are **not** revoked by this endpoint. Automated clients often share a single token across runs and should not be able to revoke it via the API. To revoke a long-lived token, use the Password Depot Server Manager.

### Request Headers

| Header | Required | Description |
|--------|:--------:|-------------|
| `Authorization` | Yes | `Bearer <access_token>` |

### Request Examples

=== "curl"

    ```bash
    curl -k -X POST "https://your-server:8714/v2.0/auth/logout" \
      -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIs..."
    ```

=== "PowerShell"

    ```powershell
    Invoke-RestMethod `
      -Uri "https://your-server:8714/v2.0/auth/logout" `
      -Method POST `
      -Headers @{ Authorization = "Bearer $token" }
    ```

=== "Python"

    ```python
    requests.post(
        "https://your-server:8714/v2.0/auth/logout",
        headers={"Authorization": f"Bearer {token}"},
        verify=False,
    )
    ```

### Success Responses

**Status:** `204 No Content` (short-lived session token)

No response body. The session is terminated and the token is rejected on subsequent use.

**Status:** `200 OK` (long-lived API token)

```json
{
  "revoked": false,
  "token_type": "api_token",
  "message": "Long-lived API tokens are not invalidated by logout. Use the Password Depot Server Manager to revoke this token."
}
```

The token remains valid. Clients can detect this case by inspecting the HTTP status (`200` vs `204`) or the `revoked` field in the body.

### Error Responses

**401 -- Unauthorized**

```json
{
  "error": {
    "code": 401,
    "message": "Invalid or expired token"
  }
}
```

Returned when the token is invalid, expired, or missing.

---

## OIDC Providers

Returns the list of OIDC / Azure identity providers configured on the server. Use this endpoint to discover available providers before performing an OIDC login.

| | |
|---|---|
| **Endpoint** | `GET /v2.0/auth/oidc` |
| **Auth required** | No |

### Query Parameters

| Parameter | Type | Required | Description |
|-----------|------|:--------:|-------------|
| `offset` | integer | No | Pagination offset (default: `0`) |
| `limit` | integer | No | Pagination limit (default: `100`) |

### Request Examples

=== "curl"

    ```bash
    curl -k -s "https://your-server:8714/v2.0/auth/oidc" | jq .
    ```

=== "PowerShell"

    ```powershell
    $response = Invoke-RestMethod -Uri "https://your-server:8714/v2.0/auth/oidc"
    $response.data | Format-Table id, display_name, provider_class
    ```

=== "Python"

    ```python
    response = requests.get(
        "https://your-server:8714/v2.0/auth/oidc",
        verify=False,
    )
    providers = response.json()["data"]
    for p in providers:
        print(f"  {p['display_name']} ({p['provider_class']})")
    ```

### Success Response

**Status:** `200 OK`

The response uses the standard v2.0 list envelope (`data` / `total` / `offset` / `limit`). Each item in `data` is an `OidcProvider` object.

```json
{
    "data": [
        {
            "id": "EF0826B6-45D0-41AF-8C92-9D3E5F8DFAD2",
            "provider_class": "PingIdentity",
            "display_name": "Ping Identity",
            "discovery_endpoint": "https://auth.pingone.eu/<env-id>/as/.well-known/openid-configuration",
            "client_id": "19c4be54-f6d1-4b74-964d-45ed2182d248",
            "redirect_uri": "https://www.example.com",
            "scopes": ["openid", "profile", "offline_access"],
            "response_types": ["code", "id_token"]
        },
        {
            "id": "1F86EB56-199E-4721-BFBE-986D2F0FB02D",
            "provider_class": "Entra ID",
            "display_name": "Corporate Entra ID",
            "discovery_endpoint": "https://login.microsoftonline.com/<tenant-id>/v2.0/.well-known/openid-configuration",
            "client_id": "0894763b-8f47-4249-9808-1c2e6d029d9b",
            "redirect_uri": "https://www.example.com",
            "scopes": ["openid", "profile", "offline_access", "User.Read"],
            "response_types": ["code", "id_token"]
        },
        {
            "id": "A96B92D3-3A3F-4C65-8A33-2639D9F035D0",
            "provider_class": "Auth0",
            "display_name": "Auth0 Server",
            "discovery_endpoint": "https://your-tenant.auth0.com/.well-known/openid-configuration",
            "client_id": "wLHaryOSXX6hfsUA0bzvnTNykfrBFprk",
            "redirect_uri": "https://www.example.com",
            "scopes": ["openid", "profile", "offline_access"],
            "response_types": ["code", "id_token"]
        },
        {
            "id": "EAE84E95-6143-4CCC-9FBB-C8C1686F3A9E",
            "provider_class": "OIDC",
            "display_name": "Generic OIDC Provider",
            "discovery_endpoint": "https://sso.example.com/.well-known/openid-configuration",
            "client_id": "169c6de0-659e-4319-ac69-4ba443e9548e",
            "redirect_uri": "https://www.example.com",
            "scopes": ["openid", "profile", "offline_access"],
            "response_types": ["code"]
        }
    ],
    "total": 4,
    "offset": 0,
    "limit": 100
}
```

### OidcProvider Schema

| Field | Type | Description |
|-------|------|-------------|
| `id` | string (UUID) | Unique provider identifier. Pass this as `idp` in the login request. |
| `provider_class` | string | Provider type: `"PingIdentity"`, `"Auth0"`, `"Entra ID"`, or `"OIDC"` (generic) |
| `display_name` | string | Custom name for display in a login UI (configured by the server administrator) |
| `discovery_endpoint` | string | OpenID Connect discovery URL (`.well-known/openid-configuration`) |
| `client_id` | string | OAuth 2.0 client ID registered with the provider |
| `redirect_uri` | string | Redirect URI configured for the OAuth flow |
| `scopes` | array of strings | OAuth scopes (e.g., `["openid", "profile", "email"]`) |
| `response_types` | array of strings | OAuth response types. One or more of: `"code"`, `"id_token"`, `"token"` |

!!! note "Client secret not exposed"
    The provider's `client_secret` is never returned by the REST API -- it is held only in the server configuration. The REST login does not perform an authorization-code exchange; it validates the `id_token` (or access token) you supply directly (see the `oidc` login method above).

### Empty Response

If no OIDC providers are configured, the server returns an empty `data` array:

```json
{
    "data": [],
    "total": 0,
    "offset": 0,
    "limit": 100
}
```

!!! tip "Usage with Login"
    After discovering providers via `/auth/oidc`, authenticate with a chosen provider by posting the obtained token to `/auth/login`:
    ```json
    {
      "auth": "oidc",
      "idp": "<provider id from /auth/oidc response>",
      "id_token": "<token obtained from OIDC flow>"
    }
    ```
