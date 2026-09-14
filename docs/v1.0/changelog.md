# Changelog

All notable changes to the Password Depot REST API will be documented in this file.

## Removed in Server 20.0.0

!!! danger "Not available on Server 20.0.0 and later"
    REST API v1.0 is served by Password Depot Enterprise Server up to and including 19.x only.

On Server 20.0.0 and later, a `GET`, `POST`, `PUT`, `PATCH` or `DELETE` request whose path contains `/v1.0/` answers HTTP `410 Gone`. The path is matched case-insensitively. The response comes before authentication, so no token is needed. The body uses the v2.0 error object:

```json
{
  "error": {
    "message": "REST API v1.0 was removed in Password Depot Server 20.0.0. Use /v2.0/ instead.",
    "code": 410
  }
}
```

The general request checks still come first: an address that is currently blocked receives `429`, and an `OPTIONS` preflight is answered with `204`.

All v1.0 routes are gone, together with the `access_token` / `client_id` header scheme and the flat v1.0 error body. `/file/`, `/temp/` and `/shared/` belong to neither API version. A path that contains one of them goes to that handler before the version check and keeps working.

**What to do:** move to REST API v2.0 before the server is upgraded. v2.0 is supported on Server 19.2.0 and later, so you can make and test the migration against a 19.2.x server first. Then check it again on 20.0.0: the REST API v2.0 changelog lists the v2.0 behaviour that changes in 20.0.0. Detect the removal by the HTTP status `410`, not by the message, which is localizable.

| v1.0 | v2.0 |
|------|------|
| `POST /login` | `POST /v2.0/auth/login`, then send `Authorization: Bearer <access_token>` |
| `POST /logout` | `POST /v2.0/auth/logout` |
| `GET /oidc` | `GET /v2.0/auth/oidc` |
| `GET /list` | `GET /v2.0/databases`; `GET /v2.0/databases/{db}/children`; `GET /v2.0/databases/{db}/folders/{id}/children` |
| `GET /read` | `GET /v2.0/databases/{db}/entries/{id}` |
| `PUT /add` | `POST /v2.0/databases/{db}/entries` or `POST /v2.0/databases/{db}/folders` |
| `POST /modify` | `PATCH /v2.0/databases/{db}/entries/{id}` or `PATCH /v2.0/databases/{db}/folders/{id}` |
| `GET /search` | `GET /v2.0/databases/{db}/search` |
| `DELETE /delete` | `DELETE /v2.0/databases/{db}/entries/{id}` or `DELETE /v2.0/databases/{db}/folders/{id}` (one item per request) |
| `POST /move` | `POST /v2.0/databases/{db}/entries/{id}/move` or `POST /v2.0/databases/{db}/folders/{id}/move` |

See the REST API v2.0 documentation and its changelog for how v2.0 differs in authentication, JSON types and error handling. Everything below describes v1.0 on servers up to and including 19.x.

---

## REST API v1.0

Included in **Password Depot Enterprise Server 19.x and earlier**; this entry describes it as of **v18.0.x**. Not available on Server **20.0.0** and later -- see [Removed in Server 20.0.0](#removed-in-server-2000).

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

### 2026-09-14

- Added **Removed in Server 20.0.0** with the v1.0 to v2.0 route mapping
- `hash` is documented as a flag that says whether a second password is set, with guidance for updates and the `secondeye` parameter
- The add and modify examples send the password as `pass`

### 2026-08-20

- Documented the removal of REST API v1.0 in Password Depot Enterprise Server 20.0.0, which answers `/v1.0/...` requests with `410 Gone`; the Server Setup page now names REST API v2.0 as the replacement and applies to Server 15.0.0 through 19.x

### 2025-02-16

- Initial documentation release
- Complete API reference for all v1.0 endpoints
- OpenAPI 3.0 specification
- Code examples in curl, PowerShell, and Python
- Standalone PowerShell client module (`PD-RestClient.ps1`)
- Standalone Python client library (`pd_client.py`)
- Guides for 2FA, bulk operations, and troubleshooting
