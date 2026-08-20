# Server Setup

This guide walks you through enabling and configuring the REST web service on your Password Depot Enterprise Server.

!!! warning "v1.0 is legacy and is not available on Server 20"

    REST API v1.0 was **removed in Password Depot Enterprise Server 20.0.0**. A
    Server 20 answers `/v1.0/...` with **410 Gone**. Use the **v2.0** API
    instead - it is available from Server 19.2.0 onward, so an application can
    be moved over before the server it talks to is upgraded. See the v2.0
    documentation for setup and the changelog for what differs.

## Prerequisites

- Password Depot Enterprise Server **v15.0.0 through 19.x** installed and running
- Access to the **Server Manager** application
- Administrator privileges on the server

## Enabling the REST Web Service

1. Open the **Server Manager** and connect to your running Password Depot Server.
2. Navigate to **Manage > Server Options > Connections > Supported Clients**.
3. Enable the **Web Client** option.
4. Click **OK** to save and apply.

The REST service will start automatically on port **8714**.

## SSL Certificate Configuration

!!! warning "SSL Required"
    Starting from version 18.0.0, a valid SSL certificate is **mandatory**. Modern browsers and HTTP clients will reject connections if the server certificate does not match the domain name or IP address being used.

### Option 1: Trusted CA Certificate

If you have a certificate issued by a trusted Certificate Authority (CA):

- Ensure the `commonName` and `subjectAltName` fields contain the correct domain name or IP address of your Password Depot Server.
- Install the certificate through the Server Manager.

### Option 2: Self-Signed Certificate

You can generate a self-signed certificate using the built-in wizard:

1. Open **Server Manager**.
2. Use the **Create Certificate Wizard**.
3. Enter your server's **domain name** and **IP address**.
4. Complete the wizard and distribute the generated certificate to users.

!!! tip
    When using self-signed certificates, clients will need to explicitly trust the certificate or disable certificate verification. See the examples section for how to handle this in [curl](../examples/curl.md), [PowerShell](../examples/powershell.md), and [Python](../examples/python.md).

## Port Configuration

The REST service listens on port **8714** by default. To change it:

1. Locate the `pdserver.ini` configuration file on your server.
2. Edit the `PortREST` value:
   ```ini
   PortREST=8714
   ```
3. Save the file.
4. **Restart** the Password Depot Server service.

## Verifying the Setup

After enabling the REST service, verify it is running by opening your browser and navigating to:

```
https://<YOUR_SERVER>:8714/v1.0/list
```

You should receive a JSON response (likely a `401 Unauthorized` error, which confirms the service is running and requires authentication).

=== "curl"

    ```bash
    curl -k -s https://your-server:8714/v1.0/list | head
    ```

=== "PowerShell"

    ```powershell
    Invoke-RestMethod -Uri "https://your-server:8714/v1.0/list" 2>&1
    ```

=== "Browser"

    Navigate to `https://your-server:8714/v1.0/list` and accept the certificate warning if using a self-signed certificate.

## Next Steps

- [Authentication](authentication.md) -- Learn how to log in and manage sessions
- [Quick Start](quick-start.md) -- Make your first API call
