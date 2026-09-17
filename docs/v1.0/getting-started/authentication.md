# Authentication

The Password Depot REST API uses token-based authentication. Every session begins with a login request that returns an `access_token` and `client_id`, which must be included in all subsequent requests.

## Authentication Flow

```
Client                              Server
  |                                    |
  |  POST /login (credentials)         |
  |----------------------------------->|
  |                                    |
  |  { access_token, client_id }       |
  |<-----------------------------------|
  |                                    |
  |  GET /list (with token headers)    |
  |----------------------------------->|
  |                                    |
  |  { databases: [...] }              |
  |<-----------------------------------|
  |                                    |
  |  POST /logout                      |
  |----------------------------------->|
  |                                    |
```

## Login

**Endpoint:** `POST /v1.0/login`

!!! warning "Legacy Servers (prior to v18.0.0)"
    In Password Depot Server versions **prior to 18.0.0**, login credentials (`user`, `pass`, `tfacode`) are passed as **custom HTTP headers** instead of a JSON request body. See the [API Reference: Authentication](../api-reference/authentication.md) for details and legacy examples.

The login endpoint accepts three authentication methods:

### Standard Authentication

Provide `user` and `pass` in the JSON request body:

=== "curl"

    ```bash
    curl -k -X POST "https://your-server:8714/v1.0/login" \
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
      -Uri "https://your-server:8714/v1.0/login" `
      -Method POST `
      -Body $body `
      -ContentType "application/json"

    $response.access_token
    $response.client_id
    ```

### OIDC / Azure Authentication

For identity provider authentication, provide `idp` and `id_token`:

```json
{
  "idp": "<IDENTITY_PROVIDER_ID>",
  "id_token": "<OIDC_OR_AZURE_TOKEN>"
}
```

### Successful Response

```json
{
  "access_token": "a1b2c3d4e5f6...",
  "client_id": "client-uuid-here"
}
```

## Using the Token

Include both `access_token` and `client_id` as HTTP headers in every subsequent request:

=== "curl"

    ```bash
    curl -k -X GET "https://your-server:8714/v1.0/list" \
      -H "access_token: a1b2c3d4e5f6..." \
      -H "client_id: client-uuid-here"
    ```

=== "PowerShell"

    ```powershell
    $headers = @{
        access_token = $response.access_token
        client_id    = $response.client_id
    }

    Invoke-RestMethod `
      -Uri "https://your-server:8714/v1.0/list" `
      -Headers $headers
    ```

## Token Expiration

!!! warning "10-Minute Timeout"
    The `access_token` expires after **10 minutes of inactivity**. If a request returns `401 Unauthorized`, the client must re-authenticate by calling the login endpoint again.

## Two-Factor Authentication (2FA)

If two-factor authentication is enabled for the user, the login flow has additional steps. See the dedicated [Two-Factor Authentication Guide](../guides/two-factor-auth.md) for details.

**Summary:**

| Response Code | Meaning | Action Required |
|---------------|---------|-----------------|
| `459` | TFA not yet activated | Scan QR code from URL in `error` field, then resend login with `tfacode` |
| `460` | TFA code required | Prompt user for 6-digit code, resend login with `tfacode` |

!!! info "No Trusted Devices"
    The REST API does not support trusted devices. Users must supply a valid 2FA code on **every** login.

## Logout

**Endpoint:** `POST /v1.0/logout`

Always log out when done to free server resources:

=== "curl"

    ```bash
    curl -k -X POST "https://your-server:8714/v1.0/logout" \
      -H "client_id: client-uuid-here"
    ```

=== "PowerShell"

    ```powershell
    Invoke-RestMethod `
      -Uri "https://your-server:8714/v1.0/logout" `
      -Method POST `
      -Headers @{ client_id = $response.client_id }
    ```

## Next Steps

- [Quick Start](quick-start.md) -- Complete walkthrough from login to listing entries
- [API Reference: Authentication](../api-reference/authentication.md) -- Full endpoint specification
