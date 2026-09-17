# Authentication

## Login

Authenticates a user and returns session credentials.

| | |
|---|---|
| **Endpoint** | `POST /v1.0/login` |
| **Auth required** | No |
| **Content-Type** | `application/json` |

### Request Body (v18.0.0+)

Starting from **Password Depot Server v18.0.0**, credentials are sent as a JSON object in the request body:

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `user` | string | Conditional | Username (for standard/Windows authentication) |
| `pass` | string | Conditional | Password (for standard/Windows authentication) |
| `tfacode` | string | Optional | 6-digit two-factor authentication code |
| `idp` | string | Conditional | Identity Provider ID (for OIDC/Azure authentication) |
| `id_token` | string | Conditional | OIDC/Azure identity token |

!!! note
    Either `user`/`pass` or `idp`/`id_token` must be provided, depending on the authentication method. If the username contains `\` or `@`, Windows (NTLM) authentication is used automatically.

!!! warning "Legacy Servers (v17.x and earlier)"
    In Password Depot Server **v17.x and earlier**, login credentials are passed as **custom HTTP headers** instead of a JSON body:

    ```
    POST /v1.0/login
    user: admin
    pass: my_password
    tfacode: 123456    (optional)
    ```

    All other endpoints (list, read, modify, etc.) work the same way across both versions. Only the login method differs.

### Request Examples

=== "curl"

    ```bash
    # Standard login (v18+)
    curl -k -X POST "https://your-server:8714/v1.0/login" \
      -H "Content-Type: application/json" \
      -d '{"user":"admin","pass":"my_password"}'

    # Login with 2FA code
    curl -k -X POST "https://your-server:8714/v1.0/login" \
      -H "Content-Type: application/json" \
      -d '{"user":"admin","pass":"my_password","tfacode":"123456"}'

    # Legacy login (v17.x) -- credentials as headers
    curl -k -X POST "https://your-server:8714/v1.0/login" \
      -H "user: admin" \
      -H "pass: my_password"
    ```

=== "PowerShell"

    ```powershell
    # Standard login (v18+)
    $body = @{
        user = "admin"
        pass = "my_password"
    } | ConvertTo-Json

    $response = Invoke-RestMethod `
      -Uri "https://your-server:8714/v1.0/login" `
      -Method POST `
      -Body $body `
      -ContentType "application/json"

    # Login with 2FA code
    $body = @{
        user    = "admin"
        pass    = "my_password"
        tfacode = "123456"
    } | ConvertTo-Json

    $response = Invoke-RestMethod `
      -Uri "https://your-server:8714/v1.0/login" `
      -Method POST `
      -Body $body `
      -ContentType "application/json"

    # Legacy login (v17.x) -- credentials as headers
    $response = Invoke-RestMethod `
      -Uri "https://your-server:8714/v1.0/login" `
      -Method POST `
      -Headers @{ user = "admin"; pass = "my_password" }
    ```

=== "Python"

    ```python
    import requests

    # Standard login (v18+)
    response = requests.post(
        "https://your-server:8714/v1.0/login",
        json={"user": "admin", "pass": "my_password"},
        verify=False  # Set to True with valid SSL cert
    )
    data = response.json()
    token = data["access_token"]
    client_id = data["client_id"]

    # Legacy login (v17.x) -- credentials as headers
    response = requests.post(
        "https://your-server:8714/v1.0/login",
        headers={"user": "admin", "pass": "my_password"},
        verify=False
    )
    ```

### Success Response

**Status:** `200 OK`

```json
{
  "access_token": "a6f256498b7ed49e4483aff29f0b6341cc6135c80dac3b114da4992471e6fc6c...",
  "client_id": "EF038E16-30E1-47D7-AA23-B592C1D7E3C0"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `access_token` | string | Access token for authenticating subsequent requests. **Expires after 10 minutes of inactivity.** |
| `client_id` | string | Unique session identifier (UUID). Include in all subsequent requests. |

### Error Responses

**401 -- Unauthorized**
```json
{
  "code": 401,
  "error": "Invalid username or password"
}
```

**459 -- TFA Not Activated**
```json
{
  "code": "459",
  "error": "https://your-server:8714/v1.0/temp/as123453456.png"
}
```
The `error` field contains a URL to a QR code image. The user must scan this with an authenticator app and resend the login request with the `tfacode` field. This response occurs only during first-time 2FA setup.

!!! info
    2FA initialization/registration is only possible through a standard Password Depot client. The REST API only supports confirming an already-initialized 2FA with a code.

**460 -- TFA Code Required**
```json
{
  "code": "460",
  "error": "Password Depot Enterprise Server requires two-factor authentication.\r\nPlease enter the verification code sent to your email address:\r\n us****@*****.com"
}
```
The 2FA code may be delivered via **email** or via an **Authenticator app**, depending on the server configuration. The client must prompt the user for the 6-digit code and resend the login request with the `tfacode` field.

!!! warning "No Trusted Devices"
    The REST API does not support trusted devices or trusted computers. Users must provide a valid 2FA code on **every** login.

---

## OIDC Providers

Returns the list of OIDC/Azure identity providers configured on the server. Use this to discover available providers before performing an OIDC login.

| | |
|---|---|
| **Endpoint** | `GET /v1.0/oidc` |
| **Auth required** | No |

### Success Response

**Status:** `200 OK`

The response is a **JSON array** of provider objects:

```json
[
  {
    "id": "azure-tenant-id",
    "provider_class": "Azure",
    "display_name": "Contoso Azure AD",
    "discovery_endpoint": "https://login.microsoftonline.com/tenant-id/v2.0/.well-known/openid-configuration",
    "client_id": "app-client-id",
    "redirect_uri": "https://your-app/callback",
    "scope": "openid profile email",
    "response_type": "id_token"
  }
]
```

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique provider identifier. Pass this as `idp` in the login request. |
| `provider_class` | string | Provider type (e.g., `"Azure"`, `"OIDC"`) |
| `display_name` | string | Human-readable name for display in a login UI |
| `discovery_endpoint` | string | OpenID Connect discovery URL (`.well-known/openid-configuration`) |
| `client_id` | string | OAuth 2.0 client ID registered with the provider |
| `redirect_uri` | string | Redirect URI configured for the OAuth flow |
| `scope` | string | Space-separated list of OAuth scopes (e.g., `"openid profile email"`) |
| `response_type` | string | Space-separated OAuth response types: `code`, `id_token`, and/or `token` |

!!! tip "Usage with Login"
    After discovering providers via `/oidc`, authenticate with a chosen provider by posting the obtained token to `/login`:
    ```json
    {
      "idp": "<provider id>",
      "id_token": "<token from OIDC flow>"
    }
    ```

### Request Examples

=== "curl"

    ```bash
    curl -k -s "https://your-server:8714/v1.0/oidc" | jq .
    ```

=== "PowerShell"

    ```powershell
    $providers = Invoke-RestMethod -Uri "https://your-server:8714/v1.0/oidc"
    $providers | Format-Table id, display_name, provider_class
    ```

=== "Python"

    ```python
    response = requests.get(
        "https://your-server:8714/v1.0/oidc",
        verify=False
    )
    providers = response.json()
    for p in providers:
        print(f"  {p['display_name']} ({p['provider_class']})")
    ```

### Empty Response

If no OIDC providers are configured, the server returns an empty array:

```json
[]
```

---

## Logout

Ends the current session and invalidates the access token.

| | |
|---|---|
| **Endpoint** | `POST /v1.0/logout` |
| **Auth required** | Yes (`client_id` header) |

### Required Headers

| Header | Description |
|--------|-------------|
| `client_id` | Client ID from the login response |

### Request Examples

=== "curl"

    ```bash
    curl -k -X POST "https://your-server:8714/v1.0/logout" \
      -H "client_id: YOUR_CLIENT_ID"
    ```

=== "PowerShell"

    ```powershell
    Invoke-RestMethod `
      -Uri "https://your-server:8714/v1.0/logout" `
      -Method POST `
      -Headers @{ client_id = $response.client_id }
    ```

=== "Python"

    ```python
    requests.post(
        "https://your-server:8714/v1.0/logout",
        headers={"client_id": client_id},
        verify=False
    )
    ```

### Success Response

**Status:** `200 OK`
