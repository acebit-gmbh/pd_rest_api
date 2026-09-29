# Server Setup

The REST service configuration for v2.0 is the same as for v1.0. If the REST service is already enabled, no additional server configuration is needed.

## Prerequisites

- **Password Depot Enterprise Server** installed and running
- **REST web service** enabled in Server Manager
- **SSL certificate** configured (mandatory since v18.0.0)
- **Port 8714** open and accessible (default REST port)
- For sign-in with an identity provider in the user's own web browser (the Windows client and the Server Manager, *Server 20.0.0 and later*): the REST port reachable **from the users' computers**, with a certificate those computers trust, and reached by the users' browsers from the same network address as the Password Depot program on the same computer (not through a web proxy that only the browser uses); see [Browser Sign-In Relay](../api-reference/authentication.md#browser-sign-in-relay)

## Setup Instructions

!!! tip "Same Server Configuration"
    The server setup process is the same as v1.0. Refer to the **[v1.0 Server Setup Guide](../../v1.0/getting-started/setup.md)** for detailed step-by-step instructions covering:

    - Enabling the Web Client in Server Manager
    - SSL certificate configuration (trusted CA or self-signed)
    - Port configuration via `pdserver.ini`
    - Firewall and network considerations

!!! note "Supported Clients (Server 20.0.0 and later)"
    Sign-in and every authenticated v2.0 request are checked against the **Supported Clients** option for the client's platform; see [Client Identity and Supported Clients](../api-reference/authentication.md#client-identity-and-supported-clients). The **Web Client** option covers the Password Depot Web Client and any client that declares no platform: scripts and long-lived API tokens that send no `X-PD-Client` header, and the example PowerShell scripts in `examples/v2.0`, such as `PD-RestClient-v2.ps1`. The Android, iOS, macOS and Linux editions and the Standard and Corporate editions for Windows each have their own option.

## v2.0 Endpoint Availability

Once the REST service is enabled, v2.0 endpoints are available automatically:

| API Version | Base URL |
|-------------|----------|
| v2.0 | `https://<YOUR_SERVER>:8714/v2.0/` |

On Servers 19.1.0 to 19.x, v1.0 is served beside v2.0 at `https://<YOUR_SERVER>:8714/v1.0/`, on the same server process, port and SSL certificate. Server 20.0.0 serves v2.0 only and answers `/v1.0/...` with `410 Gone`; see **REST API v1.0 Removed** in the [changelog](../changelog.md). No additional configuration is required to enable v2.0.

## Verifying the Setup

Confirm that v2.0 endpoints are accessible:

=== "curl"

    ```bash
    curl -k -s "https://YOUR_SERVER:8714/v2.0/databases"
    ```

=== "PowerShell"

    ```powershell
    Invoke-RestMethod -Uri "https://YOUR_SERVER:8714/v2.0/databases" 2>&1
    ```

=== "Browser"

    Navigate to `https://YOUR_SERVER:8714/v2.0/databases` and accept the certificate warning if using a self-signed certificate.

You should receive a `401 Unauthorized` JSON error response, confirming the v2.0 service is running:

```json
{
  "error": {
    "code": 401,
    "message": "Authorization header required"
  }
}
```

## Next Steps

- [Authentication](authentication.md) -- Learn the Bearer token authentication flow
- [Quick Start](quick-start.md) -- Make your first v2.0 API call
