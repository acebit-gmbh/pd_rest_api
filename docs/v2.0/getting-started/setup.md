# Server Setup

The REST service configuration for v2.0 is identical to v1.0 -- both API versions run on the same server instance and port. If you already have the REST service enabled for v1.0, no additional server configuration is needed.

## Prerequisites

- **Password Depot Enterprise Server** installed and running
- **REST web service** enabled in Server Manager
- **SSL certificate** configured (mandatory since v18.0.0)
- **Port 8714** open and accessible (default REST port)

## Setup Instructions

!!! tip "Same Server Configuration"
    The server setup process is the same as v1.0. Refer to the **[v1.0 Server Setup Guide](../../v1.0/getting-started/setup.md)** for detailed step-by-step instructions covering:

    - Enabling the Web Client in Server Manager
    - SSL certificate configuration (trusted CA or self-signed)
    - Port configuration via `pdserver.ini`
    - Firewall and network considerations

## v2.0 Endpoint Availability

Once the REST service is enabled, v2.0 endpoints are automatically available alongside v1.0:

| API Version | Base URL |
|-------------|----------|
| v1.0 | `https://<YOUR_SERVER>:8714/v1.0/` |
| v2.0 | `https://<YOUR_SERVER>:8714/v2.0/` |

Both versions share the same server process, port, and SSL certificate. No additional configuration is required to enable v2.0.

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
