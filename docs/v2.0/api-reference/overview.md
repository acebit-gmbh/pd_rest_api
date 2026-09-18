# API Reference Overview

!!! warning "In Development"
    API v2.0 is currently in development. Endpoints, schemas, and behaviors are subject to change.

## Base URL

All v2.0 API endpoints are available at:

```
https://<YOUR_SERVER>:8714/v2.0/
```

Replace `<YOUR_SERVER>` with your Password Depot Server's hostname or IP address. The default port is **8714**.

### Entry Icons

An entry or folder shows one of two kinds of icon.

**Standard icons.** The 135 icons that ship with Password Depot are served at a separate path outside the API version prefix:

```
https://<YOUR_SERVER>:8714/file/<filename>
```

Each entry and folder has an `icon` field that names one of them - always `ico0.svg` to `ico134.svg`. **No authentication is required** for these requests, and from Server 20.0.0 on the path serves nothing else: only `GET` and `HEAD`, only those 135 names (in any letter case), as `image/svg+xml`; any other name answers `404`. The files are single-colour SVG templates that take their colour from the page (`currentColor`), so a client may just as well bundle its own set and use `icon` only as the number.

**Example:** `https://<YOUR_SERVER>:8714/file/ico12.svg`

**Database icons.** *Server 20.0.0 and later.* Images that belong to one database - what the Windows client calls custom icons - are never served from `/file/`. They are per database, need a bearer token like everything else under `/v2.0/`, and travel as Base64 inside JSON; see [Database Icons](icons.md). An entry or folder that uses one names it in its `database_icon` field, and its `icon` field then names the standard icon to fall back on.

**Fallback chain.** Show the `database_icon` image when the field is not `null` and the image can be fetched; otherwise the standard icon named by `icon`; otherwise your client's own symbol for the item's `type`.

## Authentication

All endpoints require an `Authorization: Bearer <token>` header, **except**:

- `POST /v2.0/auth/login` -- obtain a token (supports `standard`, `sspi`, `negotiate`, `oidc`, and `azure` auth methods)
- `POST /v2.0/auth/webauthn/begin` -- begin a WebAuthn/Passkey authentication
- `POST /v2.0/auth/webauthn/complete` -- complete a WebAuthn/Passkey authentication
- `GET /v2.0/auth/oidc` -- discover OIDC providers

Include the header on every authenticated request:

```
Authorization: Bearer eyJhbGciOiJIUzI1NiIs...
```

The token expires after **10 minutes of inactivity**. Each successful request resets the timer.

## Request Format

- All request bodies must be **JSON** with `Content-Type: application/json`
- Character encoding: **UTF-8**
- Query parameters are passed in the URL
- The one binary request body is the document upload (`PUT .../entries/{id}/content`). A [database icon](icons.md#upload-icon) is uploaded as JSON, with the image as Base64 in the `data` field - there is no multipart or binary icon upload

## Response Format

All responses are returned as **JSON** with native types:

- Booleans: `true` / `false` (not `"1"` / `"0"` as in v1.0)
- Integers: `42` (not `"42"`)
- Dates: ISO 8601 format (e.g., `"2024-11-20T16:45:00.000Z"`)

### Cache Headers

Every API response includes the headers `Cache-Control: no-store` and `Pragma: no-cache`. This applies to all `/v2.0` and `/v1.0` endpoints, `/file` and `/temp` downloads, `OPTIONS` preflight responses, and JSON error responses. API responses can carry plaintext secrets (entry passwords, shared-secret values, second-password-decrypted fields), so they must never be written to a shared or browser disk cache. The shared-link HTML page (`GET /shared/...`) uses the slightly stricter `Cache-Control: no-cache, no-store`. These headers do not change any status code or response body.

## Pagination

All list endpoints support pagination via query parameters:

| Parameter | Type | Default | Allowed range | Description |
|-----------|------|---------|---------------|-------------|
| `offset` | integer | `0` | `>= 0` | Number of items to skip |
| `limit` | integer | `100` | `1..1000` | Maximum number of items to return |

**Validation rules (19.0.5):**

- Non-integer or overflowing values (e.g., `limit=abc`, `offset=9999999999999999999`) → `400 Bad Request`.
- `offset < 0` or `limit < 1` → `400 Bad Request`.
- `limit > 1000` is **silently clamped** to `1000`. The response echoes the clamped value (e.g., `"limit": 1000`) so clients can detect it. Iterate with multiple requests for larger result sets.

**Example request:**

```
GET /v2.0/databases?offset=0&limit=100
```

**Paginated response envelope:**

```json
{
  "data": [
    { "id": "...", "name": "..." },
    { "id": "...", "name": "..." }
  ],
  "total": 125,
  "offset": 0,
  "limit": 100
}
```

| Field | Type | Description |
|-------|------|-------------|
| `data` | array | Array of resource objects for the current page |
| `total` | integer | Total number of items across all pages |
| `offset` | integer | The offset used for this request |
| `limit` | integer | The **effective** limit used for this request (may differ from the request value if clamped) |

!!! tip "Fetching All Results"
    To retrieve all items, increment `offset` by `limit` until `offset >= total`:
    ```
    GET /v2.0/admin/users?offset=0&limit=100    → items 1-100
    GET /v2.0/admin/users?offset=100&limit=100  → items 101-125
    ```

## Error Format

On error, the server returns a JSON object with a nested `error` object:

```json
{
  "error": {
    "code": 404,
    "message": "Entry not found"
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `error.code` | integer | HTTP status code, or an application sub-code (see below) |
| `error.message` | string | Human-readable error description |

!!! note "Difference from v1.0"
    v1.0 used a flat format: `{"code": 404, "error": "..."}`. v2.0 uses a nested structure: `{"error": {"code": 404, "message": "..."}}`.

!!! note "Application sub-codes in `error.code`"
    `error.code` usually equals the HTTP status, but it may carry an application sub-code (`>= 1000`) that conveys a finer, machine-readable reason. The **HTTP status is authoritative** for the response class (for example, whether a token was issued); `error.code` only refines it. Always match the numeric code, never the localized message. A client must not infer a specific reason from a sub-code it does not recognise: show a neutral message rather than the reason a plain status would imply -- an unrecognised `401` sub-code on login does not mean the password was wrong.

    | Sub-code | HTTP | Constant | Meaning |
    |:--------:|:----:|----------|---------|
    | `4001` | `400` | `PD_ERRCODE_TOTP_SECRET` | Entry `totp` write: `secret` is not strict Base32 of 16 to 128 characters, or yields no code |
    | `4002` | `400` | `PD_ERRCODE_TOTP_ALGORITHM` | Entry `totp` write: `algorithm` is not `SHA1`, `SHA256` or `SHA512` |
    | `4003` | `400` | `PD_ERRCODE_TOTP_DIGITS` | Entry `totp` write: `digits` outside `6` to `8` |
    | `4004` | `400` | `PD_ERRCODE_TOTP_PERIOD` | Entry `totp` write: `period` outside `15` to `120` |
    | `4005` | `400` | `PD_ERRCODE_TOTP_SHAPE` | Entry `totp` write: wrong shape (`{}`, an unknown member, a wrong JSON type, or no `secret` where one is required) |
    | `4006` | `400` | `PD_ERRCODE_TOTP_ENTRY_TYPE` | Entry `totp` write: the entry's type cannot carry a one-time code written over REST |
    | `4007` | `400` | `PD_ERRCODE_ICON_ASSIGNMENT` | Entry or folder `POST` / `PATCH`: `image_custom`, `image_index` and `image_name` do not name a usable icon; nothing was written |
    | `4008` | `400` | `PD_ERRCODE_ICON_IMAGE` | `POST /databases/{db}/icons`: `data` is not a usable PNG |
    | `4012` | `401` | `PD_ERRCODE_2FA_EMAIL_SEND_FAILED` | Login: e-mail two-factor authentication is required, but the server cannot send the verification e-mail |
    | `4013` | `401` | `PD_ERRCODE_2FA_EMAIL_MISSING` | Login: e-mail two-factor authentication is required, but the account has no e-mail address |
    | `4031` | `403` | `PD_ERRCODE_INVALID_SECOND_PASS` | Wrong or missing second password; a generic access-denied `403` keeps `error.code = 403` |
    | `4032` | `403` | `PD_ERRCODE_LICENSE_LIMIT` | `POST /admin/users`: the server's licensed number of users is reached |
    | `4033` | `403` | `PD_ERRCODE_TOTP_READ_REQUIRED` | Entry `totp` write on `PATCH`: read permission on the entry is required as well |
    | `4034` | `403` | `PD_ERRCODE_ICON_QUOTA` | `POST /databases/{db}/icons`: the database cannot hold another icon |
    | `4041` | `404` | `PD_ERRCODE_NO_ONE_TIME_CODE` | The entry has no one-time code; a `404` for an entry that does not exist keeps `error.code = 404` |
    | `4042` | `404` | `PD_ERRCODE_ICON_NOT_FOUND` | `GET /databases/{db}/icons/{icon_id}`: no usable icon with that id in this database; a `404` for a database that does not exist keeps `error.code = 404` |
    | `4131` | `413` | `PD_ERRCODE_ICON_TOO_LARGE` | `POST /databases/{db}/icons`: too many bytes, too many pixels, or too large a stored record |

    *Changed in Server 20.0.0.* `4001` to `4008`, `4012`, `4013`, `4032`, `4033`, `4034`, `4041`, `4042` and `4131` are new. `4007`, `4008`, `4034`, `4042` and `4131` belong to [Database Icons](icons.md#sub-codes); `4131` is the first sub-code of the `413` family. Earlier servers answer the two e-mail two-factor conditions with `401` and `error.code` `401`. `4001` to `4006` (see [One-Time Code Settings](entries.md#one-time-code-settings)) are the first sub-codes of the `400` family: a client that recognised a bad request by `error.code == 400` must widen that test to the HTTP status.

## Error Codes

| Code | Name | Description |
|:----:|------|-------------|
| `400` | Bad Request | Invalid request body, missing required fields, or malformed parameters |
| `401` | Unauthorized | Invalid credentials, expired token, or missing `Authorization` header |
| `403` | Forbidden | Authenticated but insufficient permissions for the requested action |
| `404` | Not Found | The requested resource (database, entry, folder, user, etc.) does not exist |
| `409` | Conflict | Resource conflict (e.g., duplicate name, concurrent modification) |
| `410` | Gone | A `/v1.0/` path on Server 20.0.0 or later: REST API v1.0 was removed |
| `413` | Payload Too Large | Request body over the limit: 1 MB for JSON bodies, 64 MB for document content; `4131` for an icon upload over its own, smaller limits |
| `459` | TFA Not Activated | Two-factor authentication needs initial setup (QR code URL returned in `error.message`) |
| `460` | TFA Code Required | A valid 6-digit 2FA code must be provided to complete login |
| `500` | Internal Server Error | Unexpected server-side error |
| `501` | Not Implemented | The entry is of a type this API does not support (`encrypted_file`, `certificate`) |

## HTTP Methods

| Method | Usage | Typical Response |
|--------|-------|------------------|
| `GET` | Retrieve a resource or list of resources | `200 OK` |
| `POST` | Create a new resource or perform an action (login, logout, move) | `201 Created` or `200 OK` / `204 No Content` |
| `PUT` | Full replacement of a resource's content (used for binary uploads) | `200 OK` |
| `PATCH` | Partial update of an existing resource | `200 OK` |
| `DELETE` | Remove a resource | `204 No Content` |

!!! note "Unsupported methods"
    `HEAD` is not implemented. The server responds with `405 Method Not Allowed` for any method outside the table above, per [RFC 7231 §4.1](https://datatracker.ietf.org/doc/html/rfc7231#section-4.1). If you receive a HEAD response with `Content-Length: 0`, that is the spec-compliant result of the server returning a 405 plus Indy stripping the body (HEAD responses MUST NOT include a message body, per [RFC 7231 §4.3.2](https://datatracker.ietf.org/doc/html/rfc7231#section-4.3.2)). `OPTIONS` is supported only as a CORS preflight -- it returns `204 No Content` with an empty body and the standard CORS headers.

!!! note "Path casing"
    v2.0 URL paths are **case-sensitive** (per [RFC 3986](https://datatracker.ietf.org/doc/html/rfc3986#section-6.2.2.1) and industry convention -- GitHub, Stripe, AWS, etc.). `/v2.0/me` works; `/v2.0/ME` returns `404 Not Found`. This makes WAF/proxy allowlists deterministic and log aggregation reliable. v1.0 retains case-insensitive matching for backward compatibility. HTTP header names, JSON field names, and query parameter names are not affected by this rule.

!!! note "Path slashes"
    A **trailing slash** is accepted and treated as equivalent to the same path without it -- `/v2.0/me` and `/v2.0/me/` both reach the profile endpoint. This is the standard REST convention.

    **Empty path segments in the middle** (e.g. `/v2.0//me`, `/v2.0/admin//users`) are **not** normalized and return `404 Not Found`. Per [RFC 3986 §3.3](https://datatracker.ietf.org/doc/html/rfc3986#section-3.3) a double slash is a distinct path from a single slash; automatically collapsing them would also create a WAF-bypass vector (a proxy that allowlists `/v2.0/users` but not `/v2.0/admin/users` could be bypassed by a server that silently normalizes `/v2.0/admin//users`). Always build your URLs with exactly one slash between segments.

!!! warning "Unknown sub-resources return 404"
    The router performs **strict** sub-resource validation. Any segment past what the endpoint documents causes `404 Not Found`, regardless of HTTP method. Examples:

    ```
    DELETE /v2.0/admin/users/{id}/tfa           -> 404
    DELETE /v2.0/admin/users/{id}/anything      -> 404
    POST   /v2.0/me/password/extra              -> 404
    GET    /v2.0/users/{id}/profile             -> 404
    GET    /v2.0/databases/{id}/search/foo      -> 404
    ```

    This guards against silent-drop bugs where a typo on a destructive call (e.g. `DELETE /admin/users/{id}/passkey` vs `/passkeys`) could target the wrong resource. Only the exact documented paths are accepted.

## HTTP Status Codes

| Code | Meaning | Description |
|:----:|---------|-------------|
| `200` | OK | Request succeeded; response body contains the result |
| `201` | Created | Resource was successfully created; response body contains the new resource |
| `204` | No Content | Request succeeded; no response body (used for DELETE and logout) |
| `400` | Bad Request | Client error in the request |
| `401` | Unauthorized | Authentication required or failed |
| `403` | Forbidden | Insufficient permissions |
| `404` | Not Found | Resource does not exist |
| `405` | Method Not Allowed | HTTP method not supported for this endpoint; `Allow` header lists supported methods |
| `409` | Conflict | Resource conflict |
| `410` | Gone | REST API v1.0 path on Server 20.0.0 or later |
| `413` | Payload Too Large | Request body over the size limit |
| `429` | Too Many Requests | IP lockout / rate limit; see `Retry-After` header |
| `459` | TFA Not Activated | 2FA initial setup required |
| `460` | TFA Code Required | 2FA code needed |
| `500` | Internal Server Error | Server-side failure |
| `501` | Not Implemented | Entry type not supported by this API |

!!! info "Method Not Allowed (`405`)"
    When a method is not supported for a given endpoint the server returns `405 Method Not Allowed`, and the response includes an `Allow` header listing the supported methods (per [RFC 7231 §6.5.5](https://datatracker.ietf.org/doc/html/rfc7231#section-6.5.5)).

    ```http
    HTTP/1.1 405 Method Not Allowed
    Allow: GET, POST, PATCH, DELETE
    Content-Type: application/json; charset=utf-8
    ```

    ```json
    {
      "error": {
        "code": 405,
        "message": "Supported methods: GET POST PATCH DELETE"
      }
    }
    ```

    Clients can parse the `Allow` header programmatically to retry with a supported method.

!!! info "IP lockout (`429`)"
    After repeated failed `POST /auth/login` attempts from the same IP address, the server blocks that IP for a configurable period (Server Manager &rarr; *Options* &rarr; *Security* &rarr; *Login Attempts*). While the block is active **every** request from that IP is rejected with `429 Too Many Requests` and a `Retry-After` header containing the number of seconds until the block expires. Clients should honor `Retry-After` and back off; retrying immediately will not shorten the lockout. Login responses with `error.code` `4012` or `4013` do not count as failed attempts (*Server 20.0.0 and later*).

!!! info "Payload too large (`413`)"
    The server reads the `Content-Length` header before it reads the body and refuses a request over the limit - 1 MB for JSON bodies, 64 MB for `PUT .../entries/{id}/content` - with `413` and `error.code` `413`. This happens before authentication and before the CORS headers are added, and the connection is closed: a browser reports a network error rather than a status, so a web client must check sizes before it sends. The [icon upload](icons.md#upload-icon) has smaller limits of its own, which it reports as a regular JSON error with `413` and `error.code` `4131`.

!!! note "Mirror servers are read-only"
    A Password Depot server that runs as a mirror of another server accepts only `GET` on authenticated routes. Every other request that carries a bearer token - `POST`, `PUT`, `PATCH`, `DELETE`, including `POST /auth/logout` - answers `403 Forbidden` with `error.code` `403` ("The mirror server does not support this operation.", localized), before the token itself is examined. `POST /auth/login` and the other routes that need no token are not affected. Send writes to the primary server. The `icons.can_upload` flag of a [database](databases.md#icons-capability) is `false` on a mirror.

---

## Client vs Admin Scope

The v2.0 API separates endpoints into **client** and **admin** scopes:

- **Client scope** (`"scope": "client"`, the default) -- Access to databases (read-only), folders, entries, search, and the user/group directory (read-only, compact representation). Client sessions see only databases the user has permissions on.
- **Admin scope** (`"scope": "admin"`) -- All client endpoints, plus management endpoints under `/admin/` for database CRUD, user/group CRUD, permissions, alerts, and secrets. Admin sessions see all server databases.

The scope is set at login time via the `scope` field in the request body. See [Authentication](authentication.md#client-vs-admin-scope) for details.

## Endpoint Summary

All paths below are relative to the base URL (`/v2.0/`).

### Auth

| Method | Path | Description | Scope |
|--------|------|-------------|:-----:|
| `POST` | [`/auth/login`](authentication.md#login) | Authenticate and obtain access token | -- |
| `POST` | [`/auth/logout`](authentication.md#logout) | End session, invalidate token | Any |
| `GET` | [`/auth/oidc`](authentication.md#oidc-providers) | List configured OIDC/Azure identity providers | -- |
| `POST` | [`/auth/webauthn/begin`](authentication.md#webauthn) | Begin WebAuthn/Passkey authentication | -- |
| `POST` | [`/auth/webauthn/complete`](authentication.md#webauthn) | Complete WebAuthn/Passkey authentication | -- |

### User Profile

| Method | Path | Description | Scope |
|--------|------|-------------|:-----:|
| `GET` | [`/me`](users.md#user-profile) | Get current user's profile (includes passkeys) | Any |
| `POST` | [`/me/password`](users.md#change-own-password) | Change own password | Any |
| `GET` | [`/me/passkeys`](users.md#list-own-passkeys) | List own passkeys | Any |
| `POST` | [`/me/passkeys/begin`](users.md#register-passkey-begin) | Begin passkey registration | Any |
| `POST` | [`/me/passkeys/complete`](users.md#register-passkey-complete) | Complete passkey registration | Any |
| `PATCH` | [`/me/passkeys/{id}`](users.md#rename-passkey) | Rename own passkey | Any |
| `DELETE` | [`/me/passkeys/{id}`](users.md#delete-own-passkey) | Delete own passkey | Any |

### Databases (Client)

| Method | Path | Description | Scope |
|--------|------|-------------|:-----:|
| `GET` | [`/databases`](databases.md#list-databases) | List accessible databases | Any |
| `GET` | [`/databases/{id}`](databases.md#get-database) | Get database details | Any |

### Navigation (Children)

| Method | Path | Description | Scope |
|--------|------|-------------|:-----:|
| `GET` | [`/databases/{db}/children`](folders.md#root-level-children) | List root-level folders and entries | Any |
| `GET` | [`/databases/{db}/folders/{id}/children`](folders.md#folder-children) | List children of a folder | Any |

### Folders

| Method | Path | Description | Scope |
|--------|------|-------------|:-----:|
| `POST` | [`/databases/{db}/folders`](folders.md#create-folder) | Create a new folder | Any |
| `GET` | [`/databases/{db}/folders/{id}`](folders.md#get-folder) | Get folder details | Any |
| `PATCH` | [`/databases/{db}/folders/{id}`](folders.md#update-folder) | Update a folder | Any |
| `DELETE` | [`/databases/{db}/folders/{id}`](folders.md#delete-folder) | Delete a folder | Any |
| `POST` | [`/databases/{db}/folders/{id}/move`](folders.md#move-folder) | Move a folder to a different parent | Any |

### Entries

| Method | Path | Description | Scope |
|--------|------|-------------|:-----:|
| `POST` | [`/databases/{db}/entries`](entries.md#create-entry) | Create a new entry | Any |
| `GET` | [`/databases/{db}/entries/{id}`](entries.md#get-entry) | Get full entry details (including password) | Any |
| `PATCH` | [`/databases/{db}/entries/{id}`](entries.md#update-entry) | Update an entry | Any |
| `DELETE` | [`/databases/{db}/entries/{id}`](entries.md#delete-entry) | Delete an entry | Any |
| `POST` | [`/databases/{db}/entries/{id}/move`](entries.md#move-entry) | Move an entry to a different folder | Any |
| `GET` | [`/databases/{db}/entries/{id}/otp`](entries.md#get-one-time-code) | Get the entry's current one-time code (TOTP) | Any |
| `GET` | [`/databases/{db}/entries/{id}/content`](entries.md#get-document-content) | Download document content (BLOB) | Any |
| `PUT` | [`/databases/{db}/entries/{id}/content`](entries.md#upload-document-content) | Upload/replace document content (BLOB) | Any |

### Database Icons

| Method | Path | Description | Scope |
|--------|------|-------------|:-----:|
| `GET` | [`/databases/{db}/icons`](icons.md#list-icons) | List a database's icons, or fetch several images in one call | Any |
| `GET` | [`/databases/{db}/icons/{icon_id}`](icons.md#get-icon) | Get one icon with its image | Any |
| `POST` | [`/databases/{db}/icons`](icons.md#upload-icon) | Upload a new icon (PNG, Base64 in JSON) | Any |

### Search

| Method | Path | Description | Scope |
|--------|------|-------------|:-----:|
| `GET` | `/databases/{db}/search` | Search entries within a database | Any |

### Users (Client)

| Method | Path | Description | Scope |
|--------|------|-------------|:-----:|
| `GET` | [`/users`](users.md#list-users) | List all users (compact) | Any |
| `GET` | [`/users/{id}`](users.md#get-user) | Get user details (compact) | Any |

### Groups (Client)

| Method | Path | Description | Scope |
|--------|------|-------------|:-----:|
| `GET` | [`/groups`](groups.md#list-groups) | List all groups (compact) | Any |
| `GET` | [`/groups/{id}`](groups.md#get-group) | Get group details (compact) | Any |

### Databases (Admin)

| Method | Path | Description | Scope |
|--------|------|-------------|:-----:|
| `GET` | [`/admin/databases`](databases.md#list-all-databases-admin) | List all server databases | Admin |
| `POST` | [`/admin/databases`](databases.md#create-database-admin) | Create a new database | Admin |
| `GET` | [`/admin/databases/{id}`](databases.md#get-database-admin) | Get database details | Admin |
| `PATCH` | [`/admin/databases/{id}`](databases.md#update-database-admin) | Update database settings | Admin |
| `DELETE` | [`/admin/databases/{id}`](databases.md#delete-database-admin) | Delete a database | Admin |

### Permissions (Admin)

| Method | Path | Description | Scope |
|--------|------|-------------|:-----:|
| `GET` | [`/admin/databases/{db}/permissions`](permissions.md#list-permissions) | List permissions for a database | Admin |
| `POST` | [`/admin/databases/{db}/permissions`](permissions.md#create-permission) | Create a permission rule | Admin |
| `GET` | [`/admin/databases/{db}/permissions/{id}`](permissions.md#get-permission) | Get permission rule details | Admin |
| `PATCH` | [`/admin/databases/{db}/permissions/{id}`](permissions.md#update-permission) | Update a permission rule | Admin |
| `DELETE` | [`/admin/databases/{db}/permissions/{id}`](permissions.md#delete-permission) | Delete a permission rule | Admin |

### Users (Admin)

| Method | Path | Description | Scope |
|--------|------|-------------|:-----:|
| `GET` | [`/admin/users`](users.md#list-users-admin) | List all users | Admin |
| `POST` | [`/admin/users`](users.md#create-user-admin) | Create a new user | Admin |
| `GET` | [`/admin/users/{id}`](users.md#get-user-admin) | Get user details | Admin |
| `PATCH` | [`/admin/users/{id}`](users.md#update-user-admin) | Update a user | Admin |
| `DELETE` | [`/admin/users/{id}`](users.md#delete-user-admin) | Delete a user | Admin |
| `POST` | [`/admin/users/{id}/password`](users.md#change-password-admin) | Change a user's password | Admin |
| `GET` | [`/admin/users/{id}/passkeys`](users.md#admin-list-any-users-passkeys) | List any user's passkeys | Admin |
| `DELETE` | [`/admin/users/{id}/passkeys/{pid}`](users.md#admin-revoke-any-users-passkey) | Revoke any user's passkey | Admin |

### Groups (Admin)

| Method | Path | Description | Scope |
|--------|------|-------------|:-----:|
| `GET` | [`/admin/groups`](groups.md#list-groups-admin) | List all groups | Admin |
| `POST` | [`/admin/groups`](groups.md#create-group-admin) | Create a new group | Admin |
| `GET` | [`/admin/groups/{id}`](groups.md#get-group-admin) | Get group details | Admin |
| `PATCH` | [`/admin/groups/{id}`](groups.md#update-group-admin) | Update a group | Admin |
| `DELETE` | [`/admin/groups/{id}`](groups.md#delete-group-admin) | Delete a group | Admin |

### Alerts (Admin)

| Method | Path | Description | Scope |
|--------|------|-------------|:-----:|
| `GET` | [`/admin/alerts`](alerts.md#list-alerts) | List all alerts | Admin |
| `POST` | [`/admin/alerts`](alerts.md#create-alert) | Create a new alert | Admin |
| `GET` | [`/admin/alerts/{id}`](alerts.md#get-alert) | Get alert details | Admin |
| `PATCH` | [`/admin/alerts/{id}`](alerts.md#update-alert) | Update an alert | Admin |
| `DELETE` | [`/admin/alerts/{id}`](alerts.md#delete-alert) | Delete an alert | Admin |

### Secrets

| Method | Path | Description | Scope |
|--------|------|-------------|:-----:|
| `GET` | [`/secrets`](secrets.md#list-secrets) | List own secrets | Any |
| `POST` | [`/secrets`](secrets.md#create-secret) | Create a shared secret | Any |
| `GET` | [`/secrets/{id}`](secrets.md#get-secret) | Get own secret details | Any |
| `DELETE` | [`/secrets/{id}`](secrets.md#delete-secret) | Delete own secret | Any |
| `POST` | [`/secrets/{id}/approve`](secrets.md#approve-secret) | Approve a secret | Any |
| `POST` | [`/secrets/{id}/reject`](secrets.md#reject-secret) | Reject a secret | Any |
| `POST` | [`/secrets/{id}/revoke`](secrets.md#revoke-secret) | Revoke a secret | Any |
| `GET` | [`/admin/secrets`](secrets.md#list-secrets) | List all secrets | Admin |
| `POST` | [`/admin/secrets`](secrets.md#create-secret) | Create a shared secret | Admin |
| `GET` | [`/admin/secrets/{id}`](secrets.md#get-secret) | Get any secret details | Admin |
| `PATCH` | [`/admin/secrets/{id}`](secrets.md#update-secret-admin) | Update a secret | Admin |
| `DELETE` | [`/admin/secrets/{id}`](secrets.md#delete-secret) | Delete any secret | Admin |

---

## Data Conventions

### Booleans

Boolean fields use native JSON booleans:

```json
{
  "disabled": true,
  "ad_sync": false
}
```

!!! note "Difference from v1.0"
    v1.0 encoded booleans as strings (`"1"` / `"0"`). v2.0 uses native `true` / `false`.

### Dates

Dates are returned in **ISO 8601** format:

```json
{
  "updated_at": "2024-06-01T08:00:00.000Z",
  "expires_at": "2025-06-01T00:00:00.000Z"
}
```

All entity timestamp fields are genuine UTC instants with the trailing `Z`, and inbound timestamp fields are interpreted as UTC.

A `null` value indicates the field is not set.

### Resource Identifiers

All resources use UUID-style string identifiers:

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000"
}
```

The one exception is a [database icon](icons.md#icon-object): its `id` is a short string of decimal digits that is valid only inside its database, and the icon's `name` is its identifier.

### Permissions

v2.0 responses do not carry a permission string. Database, folder and entry representations have no `rights` field - that was part of REST API v1.0. A request you lack the permission for answers `403`.

Where permissions appear as data - in the permission rules under [`/admin/databases/{db}/permissions`](permissions.md) - they are JSON arrays of tokens such as `"read"`, `"update"` or `"share"`; see [Rights Values](permissions.md#rights-values).
