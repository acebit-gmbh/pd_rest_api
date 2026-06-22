# Changelog

All notable changes to the Password Depot REST API v2.0 will be documented in this file.

---

## v2.0.0 (In Development)

!!! warning "In Development"
    This version is currently under active development. All changes listed below are subject to modification before the final release.

### Breaking Changes from v1.0

#### New URL Structure

API endpoints have been redesigned from verb-based commands to RESTful noun-based resource URLs with standard HTTP methods.

| v1.0 (Verb-based) | v2.0 (Noun-based) | Method |
|--------------------|--------------------| -------|
| `POST /login` | `POST /auth/login` | POST |
| `POST /logout` | `POST /auth/logout` | POST |
| `GET /oidc` | `GET /auth/oidc` | GET |
| `GET /list` | `GET /databases` | GET |
| `GET /list?db=...` | `GET /databases/{db}/entries` | GET |
| `GET /read?db=...&entry=...` | `GET /databases/{db}/entries/{id}` | GET |
| `PUT /add` | `POST /databases/{db}/entries` | POST |
| `POST /modify` | `PATCH /databases/{db}/entries/{id}` | PATCH |
| `DELETE /delete` | `DELETE /databases/{db}/entries/{id}` | DELETE |
| `POST /move` | `POST /databases/{db}/entries/{id}/move` | POST |
| `GET /search` | `GET /databases/{db}/search` | GET |

#### Standard Bearer Token Authentication

Custom `access_token` and `client_id` headers have been replaced with the industry-standard `Authorization: Bearer <token>` header.

| Aspect | v1.0 | v2.0 |
|--------|------|------|
| Login response | `{"access_token": "...", "client_id": "..."}` | `{"access_token": "..."}` |
| Auth headers | `access_token: ...` + `client_id: ...` | `Authorization: Bearer ...` |
| Header count | 2 custom headers per request | 1 standard header per request |

#### Negotiate Authentication (Windows SSO)

New `"auth": "negotiate"` login method enables passwordless authentication via HTTP Negotiate (SPNEGO/Kerberos). The client's Windows process identity is used directly -- no username or password is sent in the request body. This is ideal for Group Managed Service Accounts (gMSA), scheduled tasks, and CI/CD pipelines in Windows domain environments.

#### Long-Lived Tokens for Service Accounts

The Password Depot Server Manager can now generate **long-lived access tokens** for administrator accounts. These tokens do not expire on inactivity, making them suitable for automation scenarios where re-authenticating every 10 minutes is impractical.

#### Native JSON Types

String-encoded values have been replaced with native JSON types throughout all responses and request bodies.

| Field type | v1.0 | v2.0 |
|------------|------|------|
| Booleans | `"1"` / `"0"` | `true` / `false` |
| Integers | `"42"` | `42` |
| Null values | `""` or date before 1901 | `null` |

#### Folders as a Separate Resource

Folders are no longer mixed with entries via the `itemclass` field. They are a dedicated resource type with their own CRUD endpoints.

| Operation | v1.0 | v2.0 |
|-----------|------|------|
| List folders | `GET /list?db=...` (filter by `itemclass`) | `GET /databases/{db}/folders` |
| Create folder | `PUT /add` with `itemclass: "1"` | `POST /databases/{db}/folders` |
| Update folder | `POST /modify` | `PATCH /databases/{db}/folders/{id}` |
| Delete folder | `DELETE /delete` | `DELETE /databases/{db}/folders/{id}` |

#### Standardized Error Format

The error response format has been restructured with a nested `error` object.

**v1.0:**
```json
{
  "code": 404,
  "error": "Entry not found"
}
```

**v2.0:**
```json
{
  "error": {
    "code": 404,
    "message": "Entry not found"
  }
}
```

### New Features

#### Server Administration Endpoints

v2.0 adds comprehensive server administration capabilities that were not available in v1.0:

- **Users** -- Full CRUD management of server users (`GET/POST /users`, `GET/PATCH/DELETE /users/{id}`)
- **Groups** -- Full CRUD management of user groups (`GET/POST /groups`, `GET/PATCH/DELETE /groups/{id}`)
- **Permissions** -- Granular access control per database with database-level and entry-level rights, allow/deny model, validity periods, and seal workflow (`GET/POST /databases/{db}/permissions`, `GET/PATCH/DELETE /databases/{db}/permissions/{id}`)

#### User Profile and Self-Service

- `GET /me` -- Retrieve the authenticated user's own profile (works in both client and admin scope)
- `POST /me/password` -- Change own password (requires current password verification)

#### Client-Scope User and Group Directory

Users and groups are now accessible in **client scope** with a read-only compact representation, enabling client applications to look up users and groups for sharing, permission assignment, and secret creation:

- `GET /users`, `GET /users/{id}` -- List/get users (compact: id, name, display_name, department, email, disabled)
- `GET /groups`, `GET /groups/{id}` -- List/get groups (compact: id, name, description, department, email, disabled)

#### Alerts Management

New endpoints for managing server alert rules with full event type support, email notification recipients, and optional scoping to specific databases, users, or entries:

- `GET /admin/alerts` -- List all configured alerts
- `POST /admin/alerts` -- Create a new alert
- `GET /admin/alerts/{id}` -- Get alert details (including recipients and scope filters)
- `PATCH /admin/alerts/{id}` -- Update an alert
- `DELETE /admin/alerts/{id}` -- Delete an alert

#### Secrets (Shared Links) Management

New endpoints for sharing password entries with other users via secure links. Available in both client and admin scopes with an approval workflow:

- `GET/POST /secrets` -- List own secrets / create a shared secret (client scope)
- `GET/DELETE /secrets/{id}` -- Get or delete own secret
- `POST /secrets/{id}/approve` -- Approve a secret (designated approvers)
- `POST /secrets/{id}/reject` -- Reject a secret (designated approvers)
- `POST /secrets/{id}/revoke` -- Revoke a secret (author or admin)
- `GET/POST/PATCH/DELETE /admin/secrets[/{id}]` -- Full CRUD on all secrets (admin scope)

Supports HTTPS (anonymous browser access) and `pd-server://` (binary client) protocols, configurable quorum-based approval, 2FA requirement, and access count limits.

#### Document Content Endpoints

One of the most requested features from customers: **document entries now support binary content retrieval and upload via the REST API**, a capability that was not available in v1.0. Entries of type `document` can store files up to 64 MB, and the content is managed via dedicated sub-resource endpoints:

- `GET /databases/{db}/entries/{id}/content` -- Download document content
- `PUT /databases/{db}/entries/{id}/content` -- Upload or replace document content (max 64 MB)

#### Type-Specific Fields

Entry types other than `password` and `custom` now return their type-specific attributes as a sub-object keyed by the entry type name (e.g., `"document": {"name": "report.pdf", "type": "application/pdf", "size": 2458621}`). This keeps the common entry schema clean and supports future type extensions without schema conflicts. Supported type sub-objects: `credit_card`, `license`, `identity`, `information`, `banking`, `document`, `rdp`, `putty`, `teamviewer`, `passkey`. The `fields` array has been renamed to `custom_fields` and is only present for `password` and `custom` entry types. The `ec_card` type has been renamed to `banking`. Entry types `encrypted_file` and `certificate` are not exposed via the REST API.

#### Database Management

Databases now support full CRUD operations:

- `POST /databases` -- Create a new database
- `PATCH /databases/{id}` -- Update database settings
- `DELETE /databases/{id}` -- Delete a database

#### Pagination on All List Endpoints

All list endpoints now support pagination via `offset` and `limit` query parameters with a standardized response envelope:

```json
{
  "data": [...],
  "total": 125,
  "offset": 0,
  "limit": 100
}
```

#### Additional Error Code

- `409 Conflict` -- Returned when a resource conflict occurs (e.g., duplicate name, concurrent modification)

### Security & Bug Fixes

#### No-Cache Response Headers

Every API response now includes `Cache-Control: no-store` and `Pragma: no-cache`. This applies to all `/v2.0` and `/v1.0` endpoints, `/file` and `/temp` downloads, OPTIONS preflight responses, and JSON error responses. The shared-link HTML page (`GET /shared/...`) uses the slightly stricter `Cache-Control: no-cache, no-store`. Because API responses can carry plaintext secrets (entry passwords, shared-secret values, second-password-decrypted fields), they must never be written to a shared or browser disk cache. No status codes or body fields change.

#### UTC Timestamps Corrected (Behavior Change)

All entity timestamp fields are now genuine UTC instants with the trailing `Z` (RFC 3339). Previously these fields emitted the server's **local** wall-clock time with a `Z` suffix (mislabeled as UTC). Now the `Z` value is the true UTC instant.

!!! warning "Behavior change for clients"
    Clients that parsed the old mislabeled values as UTC will see times shift by the server's UTC offset -- this is the intended correction. For example, a server at UTC+2 with a 14:00 local timestamp changed from `...T14:00:00Z` (wrong) to `...T12:00:00Z` (correct).

Affected fields: users `updated_at` + `last_login`; groups `updated_at`; databases `updated_at`; folders `updated_at`; entries `updated_at` + `expires_at`; alerts `updated_at`; api tokens `created_at` + `expires_at` + `lastused_at`; secrets `created_at` + `expires_at`; credentials/passkeys `created_at` + `last_used_at`; permissions `valid_from` + `valid_until`; approvals `timestamp`.

Inbound request fields `expires_at` (entries, api_tokens, secrets) and `valid_from`/`valid_until` (permissions) are now interpreted as true UTC and round-trip exactly (previously a write/read cycle drifted by the offset). Date-only custom-field values are unchanged (no timezone shift). No field names or status codes change; malformed inbound dates still return `400`.

#### Search Filters Unsupported Entry Types

`GET /databases/{db}/search` no longer returns entries whose type is unsupported by the REST/web surface -- i.e. the desktop-only legacy types `encrypted_file` and `certificate`. This brings `/search` into parity with `GET /children`, which already excludes them. The result array, the `total`/result count, and pagination all reflect the filtered set. Previously such entries appeared in results but returned `501 Not Implemented` when opened.

#### Second Password Enforced on Update

`PATCH /databases/{db}/entries/{id}` and `PATCH /databases/{db}/folders/{id}` now **require** a correct `X-Second-Password` header when the target item is second-password protected (`has_second_pass=true`); otherwise the server responds `403 Forbidden`. This also applies to the change-second-password flow: when sending `X-New-Second-Password`, the client must additionally send the correct current `X-Second-Password`. Previously the current second password was not verified on update, so a wrong or missing one was silently accepted (a security gap). Items without a second password are unaffected.

#### Error Code 4031 for Wrong Second Password

A wrong or missing second password -- on READ or UPDATE of a protected entry or folder -- now returns HTTP `403` with the JSON body `error.code = 4031` (`PD_ERRCODE_INVALID_SECOND_PASS`), distinct from a generic access-denied / sealed `403` (which keeps `error.code = 403`).

More generally, `error.code` may now carry an application sub-code (`>= 1000`) that differs from the HTTP status: the HTTP status remains the authority for the response class, while `error.code` can convey a finer machine-readable reason.

**Client guidance:** detect the wrong-second-password condition by `HTTP status == 403 && body.error.code == 4031` (and re-prompt for the second password) versus a generic `403` (do not re-prompt). Always match the numeric code, never the localized message. The obsolete v1.0 error format is unchanged (still emits `403`).

#### OIDC Login Token Contract (Clarification)

`POST /v2.0/auth/login` with `auth: "oidc"` sends `{ auth, idp, id_token }`. The `id_token` field **must** carry either (a) a signed OIDC `id_token` JWT, or (b) an opaque OAuth access token usable as a Bearer credential at the provider's `userinfo_endpoint`. It **must not** carry a bare authorization `code`.

The REST server performs **no** authorization-code exchange: it validates the supplied value directly (JWT signature/aud/exp via JWKS, then falls back to Bearer-to-`userinfo`) and never POSTs to the `token_endpoint`. A provider configured for authorization-code-flow-only (`response_type` `code` with no `id_token`, e.g. a Google-style preset) is supported only if the relying party performs the code-to-token exchange itself before calling REST login; the recommended client configuration is to request `response_type=id_token`. An invalid/expired/forged token, a bare code, or no matching local user returns HTTP `401`. This is a clarification only -- no behavior change.

#### `/children` Response Envelope Correction (Doc Fix)

The `GET /databases/{db}/children` (and `/folders/{id}/children`) response envelope contains only: `path`, `data`, `total`, `offset`, `limit`. The previously-documented top-level fields `name`, `parent`, and `has_second_pass` are **not** emitted by the server and never have been; they have been removed from the documentation. (The per-item objects inside `data` still carry their own `has_second_pass`; only the top-level envelope fields were in error.)

