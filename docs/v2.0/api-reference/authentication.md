# Authentication Endpoints

API reference for authentication-related endpoints.

---

## Client Identity and Supported Clients

*Server 20.0.0 and later.* Maintained native clients must identify their platform on every REST request, including login, OIDC discovery and both WebAuthn steps:

```http
X-PD-Client: android; version=20.0.0; build=123
```

The platform is required when the header is supplied. Accepted values are `web`, `android`, `ios`, `macos`, `linux`, `windows` and `windows-corp`; input is case-insensitive. `version` and `build` are optional information about the client release.

| Value | Format |
|-------|--------|
| Platform | One of the supported platform names above |
| `version` | Nonempty HTTP token, at most 64 ASCII characters (for example `20.0.0-beta+1`); no spaces, quotes, slashes, colons or semicolons |
| `build` | Nonnegative integer, at most `9223372036854775807` |
| Whole header | At most 256 characters |

### Login and WebAuthn Body Alternative

`POST /auth/login` and `POST /auth/webauthn/begin` also accept a `client` object in their JSON bodies. For example, a login request can send:

```json
{
    "user": "example-user",
    "pass": "example-password",
    "client": {
        "platform": "android",
        "version": "20.0.0",
        "build": 123
    }
}
```

`client` must be a JSON object. `client.platform` is a required string, at most 32 characters, containing one of the platform names above. `client.version` is an optional string with the same limit as the header value. `client.build` is an optional JSON integer with the same range as the header value. `null` is not accepted for `client`, `client.platform`, `client.version` or `client.build`; leave out a value you do not send. If the header and body both declare a platform, they must agree. WebAuthn complete ignores a `client` member in its body, and OIDC discovery is a `GET` without a body. A WebAuthn challenge retains the platform declared at begin through the header or body; complete may omit the header and use that platform, but a conflicting platform returns `400`. A disabled platform is refused with `403` first, whether the challenge stored it or the header of the complete request declares it. The Negotiate handshake also retains the declared platform across retries that have no JSON body.

Unknown platforms, malformed identity values, unknown header parameters, duplicate recognized identity members and conflicting header/body platforms return `400 Bad Request`, as does an `X-PD-Client` header that is sent more than once, is empty, or contains a comma or a character outside printable ASCII. Send the header once, with a single identity. None of these `400`s counts towards the IP lockout (`429`). Extra members of the `client` object are ignored. Do not send the build as a JSON string.

### Platform Policy and Sessions

The server checks the platform's existing **Supported Clients** setting at login (including both WebAuthn steps), on OIDC discovery (`GET /auth/oidc`) and on every authenticated request. The setting for `web` is independent: disabling the Web Client does not disable identified native REST clients whose own platforms are enabled. An admin-scoped session has no platform-policy exemption.

Each platform is governed by one of the Supported Clients settings in the Server Manager:

| Platform | Supported Clients setting in the Server Manager |
|----------|-------------------------------------------------|
| `web` | Web Client |
| `android` | Android Edition |
| `ios` | iOS Edition |
| `macos` | macOS Edition |
| `linux` | Linux Edition |
| `windows` | Standard Edition for Windows |
| `windows-corp` | Corporate Edition for Windows |

New session tokens retain the platform established at login. Later requests without the header use that stored platform; a header declaring a different platform returns `400`. If the stored platform is disabled, that policy refusal takes precedence over a conflicting header. Clients cannot change the platform of an established session by omitting or changing the header.

For compatibility, a login with neither identity declaration defaults to `web`. Long-lived API tokens carry no platform: a request made with one uses its `X-PD-Client` header when supplied and otherwise defaults to `web`, so automation that sends no header works only while the Web Client is enabled under **Supported Clients**. Maintained native clients must send their identity instead of relying on this fallback. Web clients can omit the header for compatibility with older servers that do not allow it through CORS. The Web Client declares `web` in the JSON `client` object at `/auth/login` or `/auth/webauthn/begin`, then uses the stored challenge/session identity without a custom header. The server does not infer a platform from `User-Agent`.

When Android is disabled, the response is **HTTP `403` with `error.code: 4036`**:

```json
{
    "error": {
        "code": 4036,
        "message": "The Android client is disabled on this server."
    }
}
```

Other disabled platforms return HTTP `403` with `error.code: 403` and a platform-specific message. Treat these responses as an administrator policy restriction, not as incorrect credentials or a request to retry login. They do not count towards the IP lockout (`429`). Branch on the numeric status and code.

`X-PD-Client` is permitted by the server's CORS preflight response. Client identity is supplied by the application; it is not device attestation. Version and build are informational and do not grant permissions.

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
| `trust_device` | boolean | No | *Server 20.0.0 and later.* With a `tfacode`, asks the server to trust this device and return a `tfatoken`. Default `false`; `null` means absent. See [Trusted Devices](#trusted-devices) |
| `tfatoken` | string | No | *Server 20.0.0 and later.* Trusted-device token from an earlier login, sent instead of `tfacode`; at most 128 characters. `null` and `""` mean absent. See [Trusted Devices](#trusted-devices) |
| `client` | object | No | Client platform, version and build; see [Client Identity](#client-identity-and-supported-clients). When the header also declares a platform they must agree |
| `idp` | string | Conditional | Identity Provider ID from `/auth/oidc` (required for `oidc`) |
| `id_token` | string | Conditional | Identity token obtained from the OIDC/Azure flow (required for `oidc` and `azure`) |

`trust_device` must be a JSON boolean and `tfatoken` a JSON string. Any other JSON type, a `tfatoken` longer than 128 characters, or either key sent twice answers `400`, which does not count towards the IP lockout (`429`). When a request carries both `tfatoken` and `tfacode`, the token is tried first; if the server does not accept it, the code is verified as usual.

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

**Optional fields:** `scope`, `client` (see [Client Identity](#client-identity-and-supported-clients)), and for two-factor authentication `tfacode`, `trust_device` and `tfatoken` (see [Trusted Devices](#trusted-devices)). The two-factor members must be in the body of the request that completes the handshake. The platform declared on the first request holds for the whole handshake; a retry may omit it but must not declare a different one.

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

A passkey sign-in involves no second factor, so this response never carries a `tfatoken`, and the WebAuthn endpoints do not read one (see [Trusted Devices](#trusted-devices)).

**Required fields (Step 1):** `user`

**Optional fields (Step 1):** `scope`, `client` (see [Client Identity](#client-identity-and-supported-clients))

!!! warning "Prerequisites"
    - The Password Depot Server must have **WebAuthn** enabled in the server options. Otherwise Step 1 answers `400` "This method of authentication is not supported..." for every user name; this answer does not count towards the failed-login limit (`429`).
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

    # 2FA code, and trust this device (Server 20.0.0 and later)
    curl -k -X POST "https://your-server:8714/v2.0/auth/login" \
      -H "Content-Type: application/json" \
      -d '{"user":"admin","pass":"my_password","tfacode":"123456","trust_device":true}'

    # Trusted device: the stored tfatoken instead of a code (the password is still required)
    curl -k -X POST "https://your-server:8714/v2.0/auth/login" \
      -H "Content-Type: application/json" \
      -d '{"user":"admin","pass":"my_password","tfatoken":"V2u_NKF0FJFp1KQayE24Z36Up-CncbSVg65JiReTBkU"}'

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

    # 2FA code, and trust this device (Server 20.0.0 and later)
    $body = @{
        user         = "admin"
        pass         = "my_password"
        tfacode      = "123456"
        trust_device = $true
    } | ConvertTo-Json

    $response = Invoke-RestMethod `
      -Uri "https://your-server:8714/v2.0/auth/login" `
      -Method POST `
      -Body $body `
      -ContentType "application/json"

    # Absent when the server did not trust the device; store it like a password
    $tfaToken = $response.tfatoken

    # Trusted device: the stored tfatoken instead of a code (the password is still required)
    $body = @{
        user     = "admin"
        pass     = "my_password"
        tfatoken = $tfaToken
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

    # 2FA code, and trust this device (Server 20.0.0 and later)
    response = requests.post(
        "https://your-server:8714/v2.0/auth/login",
        json={"user": "admin", "pass": "my_password", "tfacode": "123456", "trust_device": True},
        verify=False,
    )
    tfa_token = response.json().get("tfatoken")  # None when the device was not trusted

    # Trusted device: the stored tfatoken instead of a code (the password is still required)
    response = requests.post(
        "https://your-server:8714/v2.0/auth/login",
        json={"user": "admin", "pass": "my_password", "tfatoken": tfa_token},
        verify=False,
    )
    if response.status_code in (459, 460):
        tfa_token = None  # not accepted: discard it and ask for the code

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

When the request carried `"trust_device": true` and made the device trusted (Server 20.0.0 and later; see [Trusted Devices](#trusted-devices)):

```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "tfatoken": "V2u_NKF0FJFp1KQayE24Z36Up-CncbSVg65JiReTBkU",
  "tfatoken_expires_at": "2026-10-18T09:12:00.000Z"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `access_token` | string | Bearer token for authenticating subsequent requests. Use it via the `Authorization: Bearer <token>` header. |
| `tfatoken` | string | Only when this request made the device trusted. Send it as `tfatoken` on later logins instead of `tfacode`. Opaque, not a JWT, and never a Bearer credential. Returned only this once. |
| `tfatoken_expires_at` | string (UTC, ISO 8601) | Present with `tfatoken`: when the server stops accepting the token under the trusted-device period in force at issue. Advisory: the server can stop accepting it earlier, and accepts it for longer if the period is raised. |

!!! info "Simplified Response"
    Unlike v1.0, the login response has no `client_id` -- the Bearer token alone identifies the session. Besides `access_token` it carries only the trusted-device fields above, and those only when the login asked for them with `trust_device`.

### Token Lifetime

By default, access tokens expire after **10 minutes of inactivity** (the timer resets on every authenticated API call). This is suitable for interactive use and short-lived scripts.

For **automation and service accounts** (e.g., scheduled tasks, CI/CD pipelines, monitoring scripts), a Super Administrator can generate **long-lived tokens** in the Password Depot Server Manager for any user account, in client or admin scope, with an expiry date 1 to 730 days ahead (180 by default). Long-lived tokens do not expire on inactivity. They stay valid until 00:00 on their expiry date, or until they are revoked or deleted in the Server Manager. An admin-scope token needs an account with a server role, and a Super Administrator's token must be admin scope.

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

A `tfatoken` is not an access token. It authenticates no API request and has no inactivity timeout; it stands in for the two-factor code at `/auth/login` for the server's trusted-device period. See [Trusted Devices](#trusted-devices).

### Token Structure

The access token is a standard [JWT](https://datatracker.ietf.org/doc/html/rfc7519) signed with HMAC-SHA256. Clients normally treat it as an opaque Bearer credential, but the claims are documented here for debugging, log aggregation, and audit purposes. The server signs the token with a per-instance secret that is not exposed to clients. This section describes `access_token` only: a `tfatoken` is an opaque random string, not a JWT, and carries no claims.

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

**Claim only on session tokens:**

| Claim | Name | Type | Description |
|-------|------|------|-------------|
| `client_platform` | -- | string | *Server 20.0.0 and later.* The client platform established at login: `web`, `android`, `ios`, `macos`, `linux`, `windows` or `windows-corp`. Requests made with the token are checked against that platform's **Supported Clients** setting; see [Platform Policy and Sessions](#platform-policy-and-sessions). Long-lived API tokens do not carry it |

**Telling the two token types apart on the client side:**

- A token **without** `jti` is a session token. `/auth/logout` returns `204 No Content`.
- A token **with** `jti` is a long-lived API token. `/auth/logout` returns `200 OK` with `{"revoked": false, "token_type": "api_token", ...}` and the token remains valid. See the [Logout](#logout) section.

!!! warning "Don't rely on JWT internals for security decisions"
    These claims are for informational/debugging use only. Never parse the token on the client to decide whether to call an admin endpoint -- the server is the sole authority on scope. The presence of `"admin": true` in a JWT does not grant admin access if the user's roles have since been revoked; the server re-checks every request.

### Error Responses

**400 -- Invalid client identity**

Malformed or conflicting [client identity](#client-identity-and-supported-clients) returns `400`. A new-session token and request header must also name the same platform.

**403 -- Client platform disabled**

A disabled Android client returns `403` with `error.code: 4036` and the message `The Android client is disabled on this server.` Other disabled platforms use `error.code: 403`. This check also applies after login, on authenticated requests; see [Platform Policy and Sessions](#platform-policy-and-sessions).

**401 -- Unauthorized**

```json
{
  "error": {
    "code": 401,
    "message": "Logon failure: unknown user name or bad password."
  }
}
```

Returned when credentials are invalid or the account is locked (`error.code` `401`). A sign-in with a method the account may not use -- one not among its `auth_modes`, or one the server's **Authentication methods** policy does not allow for it -- receives the answer the same request gets for an account the server does not know: this one for `standard` and `sspi`, `401` "The server cannot find the user account specified." for `azure` and `oidc`. A `standard` or `sspi` sign-in is answered like a method switched off on the server, `401` "This method of authentication is not supported..." for every user name, when the **Authentication methods** policy is enforced at server scope and does not include the method. The server log names the actual reason.

---

**401 -- Verification e-mail cannot be sent** *(`error.code` `4012`)*

```json
{
  "error": {
    "code": 4012,
    "message": "Failed to send the authentication email. Please contact your administrator."
  }
}
```

Returned when the user's effective two-factor mode is `email` and the server cannot send e-mail: no SMTP server is configured, or the server's e-mail sender has stopped after repeated connection failures (it resumes only when the Password Depot Server service is restarted). While this lasts, a login that already carries `tfacode` is refused the same way. A login with a `tfatoken` the server accepts is not affected: the [trusted device](#trusted-devices) stands in for the e-mailed code. The HTTP status stays `401` and no token is issued. An administrator must fix this: do not report it as a wrong password and do not retry automatically. It is only reported after the password or identity token was accepted, it does not count towards the IP lockout (`429`), and it is still logged and alerted as a failed login.

An SMTP server that accepts the connection but refuses the message (for example, rejected SMTP credentials) is not detected at login: the client receives `460` and no e-mail arrives.

*Changed in Server 20.0.0.* Earlier servers returned `error.code` `401`, and with no SMTP server configured they answered `460` although no e-mail could be sent.

---

**401 -- No e-mail address for two-factor authentication** *(`error.code` `4013`)*

```json
{
  "error": {
    "code": 4013,
    "message": "User email is not defined. Please contact your Password Depot Server administrator."
  }
}
```

Returned when the user's effective two-factor mode is `email` but the account has no e-mail address. An administrator must set `email` on the user or change its `two_factor_mode` (see [Users](users.md#two_factor_mode-values)). It is only reported after the password or identity token was accepted, it does not count towards the IP lockout (`429`), and it is still logged and alerted as a failed login. When the server also cannot send e-mail, `4012` is reported instead. A login with a `tfatoken` the server accepts is not affected.

*Changed in Server 20.0.0.* Earlier servers returned `error.code` `401`.

!!! tip "Telling the 401 responses apart"
    Check `HTTP status == 401`, then `body.error.code`: `401` -- invalid credentials or locked account; `4012` -- the verification e-mail cannot be sent; `4013` -- no e-mail address on the account. For any other sub-code show a neutral sign-in failure, never "wrong password". The `message` is localized by the server; never match on it.

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

Returned when the IP address has exceeded the configured number of failed login attempts within the Login Interval (Server Manager &rarr; *Options* &rarr; *Security*). The block applies to **all** endpoints, not just `/auth/login`, for the duration of the Unblock-After period. The `Retry-After` header carries the remaining lockout in seconds -- honor it and back off; retrying immediately will not shorten the lockout. Responses with `error.code` `4012` or `4013` do not count towards this limit, and neither does a `tfatoken` the server does not accept.

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
    "message": "Windows authentication succeeded but no matching Password Depot user found for \"DOMAIN\\svc_account$\"."
  }
}
```

Common causes:

- The Windows identity does not match any PD user's SAM or UPN field
- The PD user does not have the IWA authentication method enabled, or the server's **Authentication methods** policy does not allow `iwa` for the user
- Kerberos ticket cannot be obtained (e.g., client not domain-joined, clock skew, or DNS resolution failure)
- The client is not in the same domain or a trusted domain

---

**459 -- TFA Not Activated**

```json
{
  "error": {
    "code": 459,
    "message": "/temp/2d711642b726b04401627ca9fbac32f5c8530fb1903cc4db02258717921a4881.png",
    "trust_device_possible": true
  }
}
```

Returned when the user's second factor is an authenticator app (TOTP) that has not been activated for this account yet. `error.message` holds the path of a QR code image, relative to the server's address and without the `/v2.0` prefix (here `https://your-server:8714/temp/2d71...4881.png`). The image can be fetched once; every `459` carries a new path. The user scans it with an authenticator app; then resend the login request with the `tfacode` field.

!!! info
    Activation is completed over REST: the first code that verifies activates the authenticator app for the account, and later logins answer `460`. Add `"trust_device": true` to that request to trust the device at the same time (see [Trusted Devices](#trusted-devices)).

---

**460 -- TFA Code Required**

```json
{
  "error": {
    "code": 460,
    "message": "Please enter the verification code that was sent to your email address: use*@*******.com",
    "trust_device_possible": true
  }
}
```

Returned when valid credentials were provided but a 2FA code is required. The 2FA code may be delivered via **email** or via an **authenticator app**, depending on the server configuration. Resend the login request with the `tfacode` field included. A wrong `tfacode` is answered `460` as well, and counts towards the IP lockout (`429`) and the account's failed-login count.

A `460` in answer to a request that carried `tfatoken` means the server did not accept the token: discard it and ask for the code. With e-mail two-factor authentication, that answer has sent a new code as usual.

**`trust_device_possible`** *(Server 20.0.0 and later)*: `459` and `460` from `/auth/login` carry this boolean inside `error`, always `true` or `false`. `true` means that a code verified together with `"trust_device": true` makes the device trusted and returns a `tfatoken`. Its presence tells a client that the server supports trusted devices. The HTTP status, `error.code` and `error.message` are the same as without it. Ignore members of `error` you do not know.

### Trusted Devices

*Server 20.0.0 and later.* A client can ask the server to trust the device it runs on, so that later logins from it need the password (or identity token) but no two-factor code. This suits clients that sign in often, such as a mobile app that replays the stored password after a biometric unlock. The trusted devices form one list per user, shared with the Password Depot Windows client.

**Flow:**

1. A login is answered `460` (or `459`) with `"trust_device_possible": true`.
2. The client resends the login with `tfacode` and `"trust_device": true`. When the code verifies, the `200` carries `tfatoken` and `tfatoken_expires_at` beside `access_token` (see [Success Response](#success-response)).
3. Later logins send the credential as usual, plus `tfatoken` instead of `tfacode`:

    ```json
    {
      "user": "john.doe",
      "pass": "my_password",
      "tfatoken": "V2u_NKF0FJFp1KQayE24Z36Up-CncbSVg65JiReTBkU"
    }
    ```

    When the server accepts the token, the login completes with `200` and `access_token` only. No new token is issued: the token is not renewed by use, and its lifetime runs from when the code was entered.

**The token:**

- An opaque string of at most 128 characters (currently 43). It is not a JWT and never a Bearer credential: never send it in `Authorization`, and send it only to `/auth/login`.
- Returned exactly once. The server keeps only a hash of it and cannot show it again.
- It belongs to the user who received it, and it replaces only the second factor: the password, or the identity token for `oidc` and `azure`, is always required.

**A token the server does not accept** -- unknown, expired, revoked, or for a second factor it cannot stand in for -- is treated as if none had been sent. The login answers `460` and asks for the code (with e-mail two-factor authentication a new code is sent), or `459` when the authenticator app has to be activated first. Such a token does not count towards the IP lockout (`429`) or the account's failed-login count. When the request also carries `tfacode`, the code is then verified as usual, and with `"trust_device": true` a new token is issued.

**Where trusted devices apply:**

| Situation | Token issued | Token accepted |
|-----------|--------------|----------------|
| Authenticator app (TOTP), activated | Yes, with a verified code | Yes |
| Authenticator app not activated yet (`459`) | Yes, with the first verified code, which also activates the app | No: the user activates the app first |
| E-mail code | Yes, with a verified code | Yes, also while the server cannot send e-mail (no `4012` / `4013` then) |
| FIDO2 second factor (`409` over REST) | No | No |
| Two-factor authentication off for the server or the user | No: `trust_device` is ignored | Ignored |
| `"scope": "admin"` | No | Ignored |
| Mirror server | No | Yes, tokens the main server issued |
| Passkey sign-in (`/auth/webauthn/complete`) | No: no second factor is involved | Not used |

The `auth` methods `standard`, `sspi`, `azure` and `oidc` all support trusted devices. With `negotiate`, `trust_device` and `tfatoken` must be in the body of the request that completes the handshake, as `tfacode` must.

**Lifetime and revocation:**

- A token is accepted for the server's trusted-device period, counted from when it was issued: Server Manager &rarr; *Options* &rarr; *2FA Settings* &rarr; **Trust period for user devices (hours)**, 480 hours (20 days) by default and up to 2400. The server applies its current period at each login, so lowering it shortens tokens already issued and raising it lengthens them. Turning it off means no token is accepted or issued.
- **Reset 2FA** for the user in the Server Manager revokes all of that user's trusted devices, those of the Windows client and of REST clients alike. Deleting the user revokes them as well.
- Logout, a password change and disabling the account do not end a token. A disabled account cannot sign in anyway.
- A user has at most 10 trusted devices from REST logins; issuing another drops the oldest.

**Client guidance:**

- Key the token by server and user, and store it like a credential. On Android, encrypt it with the same Keystore key as the stored password and exclude it from backups.
- Ask for `trust_device` only when the user opted in and `trust_device_possible` was `true`.
- Discard the token only when a login that sent it is answered `459` or `460`. Keep it on `401`, `403` and `429`, which say nothing about the token, and on `4012` / `4013`, which need an administrator first: a login after that still shows whether the token is accepted.
- Never send it as a Bearer token, and send it to no endpoint other than `/auth/login`.
- Treat `tfatoken_expires_at` as advisory: the server decides at each login whether it still accepts the token, so a token can end before or after that time.
- A server without trusted devices ignores `trust_device` and `tfatoken`: its `459` and `460` carry no `trust_device_possible`, and its `200` never carries `tfatoken`.

### Client vs Admin Scope

The `scope` field determines which endpoints the session can access:

| Scope | Default | Accessible Endpoints |
|-------|:-------:|----------------------|
| `client` | Yes | `/databases` (read), `/databases/{db}/folders`, `/databases/{db}/entries`, `/databases/{db}/search`, `/users` (read), `/groups` (read) |
| `admin` | No | All client endpoints, plus `/admin/databases` (full CRUD), `/admin/databases/{db}/permissions`, `/admin/users`, `/admin/groups`, `/admin/alerts`, `/admin/secrets` |

When `scope` is omitted, it defaults to `"client"`. A client session sees only the databases the user has read access to; an admin session sees all databases on the server and can perform management operations.

[Trusted devices](#trusted-devices) apply to `client` scope only. An admin-scope login is never issued a `tfatoken` and ignores one it is sent: it needs the two-factor code whenever two-factor authentication applies to the user.

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
    - A [trusted device](#trusted-devices) is not forgotten: a `tfatoken` stays valid after logout.

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
