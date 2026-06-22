# Changelog

All notable changes to the Password Depot REST API will be documented in this file.

## REST API v1.0

Included in **Password Depot Enterprise Server v18.0.x**.

### Endpoints

- `POST /login` -- User authentication (standard, Windows, OIDC/Azure)
- `POST /logout` -- Session termination
- `GET /list` -- List databases and browse folder contents
- `GET /read` -- Read entry attributes
- `PUT /add` -- Create new entries
- `POST /modify` -- Modify existing entries
- `GET /search` -- Search entries across databases
- `DELETE /delete` -- Delete entries (single or bulk)
- `POST /move` -- Move entries between folders

### Authentication

- Token-based authentication via `access_token` and `client_id` headers
- 10-minute inactivity timeout on access tokens
- Two-factor authentication (TOTP) support with codes 459 and 460
- OIDC/Azure identity provider support via `idp` and `id_token`

### Breaking Change: Login Credential Submission (v18.0.0)

Starting with **v18.0.0**, login credentials (`user`, `pass`, `tfacode`) are submitted as a **JSON-formatted request body**:

```json
POST /v1.0/login
Content-Type: application/json

{"user": "admin", "pass": "my_password"}
```

In versions **prior to 18.0.0**, these same parameters were passed as **custom HTTP headers**:

```
POST /v1.0/login
user: admin
pass: my_password
```

If you are connecting to a server running v17.x or earlier, you must use the header-based format. See the [API Reference: Authentication](api-reference/authentication.md) for legacy examples in curl, PowerShell, and Python.

### Security

- HTTPS mandatory (since v18.0.0)
- Valid SSL certificate required
- Default port: 8714 (configurable via `pdserver.ini`)

---

## Documentation Changelog

### 2025-02-16

- Initial documentation release
- Complete API reference for all v1.0 endpoints
- OpenAPI 3.0 specification
- Code examples in curl, PowerShell, and Python
- Standalone PowerShell client module (`PD-RestClient.ps1`)
- Standalone Python client library (`pd_client.py`)
- Guides for 2FA, bulk operations, and troubleshooting
