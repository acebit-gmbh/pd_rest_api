# Password Depot Server REST API v2.0

!!! info "Availability"
    REST API v2.0 is served by Password Depot Enterprise Server 19.1.0 and later; this documentation describes 19.2.0 and later. Changes made in Server 20.0.0, which is still in development, are listed in the [changelog](changelog.md).

Welcome to the official documentation for the **Password Depot Enterprise Server REST API v2.0** -- a modern RESTful API for Password Depot Enterprise Server administration and password management.

API v2.0 is a ground-up redesign that brings industry-standard conventions, comprehensive server administration capabilities, and a cleaner developer experience.

## What's New in v2.0

API v2.0 introduces significant improvements over [v1.0](../v1.0/):

| Feature | v1.0 | v2.0 |
|---------|------|------|
| **Authentication** | Custom `access_token` + `client_id` headers | Standard `Authorization: Bearer <token>` header, plus Negotiate SSO, OIDC, and WebAuthn/Passkey |
| **Windows SSO** | Not supported | HTTP Negotiate (SPNEGO/Kerberos) -- passwordless auth for gMSA and service accounts |
| **Long-lived tokens** | Not supported | Server Manager can generate long-lived tokens for automation, with an expiry date 1 to 730 days ahead (180 by default) |
| **URL structure** | Verb-based commands (`/login`, `/list`, `/read`, `/add`, `/modify`) | RESTful noun-based resources (`/databases`, `/entries/{id}`, `/users`) |
| **Data types** | String-encoded values (`"1"`, `"0"`) | Native JSON types (`true`, `false`, `42`) |
| **Administration** | Password operations only | Full server administration via `/admin/` endpoints: users, groups, permissions, alerts, secrets |
| **Session scope** | N/A | `"client"` (default) or `"admin"` -- separates normal usage from server management |
| **Folders** | Mixed with entries via `itemclass` field | First-class resource with dedicated CRUD endpoints |
| **Document content** | Not supported | Download and upload document BLOBs via `/entries/{id}/content` |
| **Pagination** | Not supported | All JSON list endpoints support `?offset=0&limit=100` |
| **Error format** | `{"code": 401, "error": "..."}` | `{"error": {"code": 401, "message": "..."}}` |

### Key Highlights

- **Windows SSO / gMSA support** -- New `"auth": "negotiate"` login method enables passwordless authentication via HTTP Negotiate (SPNEGO/Kerberos). Scripts running under a Group Managed Service Account (gMSA) or domain service account can authenticate using their Windows identity -- no passwords stored in scripts or on the file system. In PowerShell, a single `-UseDefaultCredentials` flag is all that's needed. See [Authentication](api-reference/authentication.md#negotiate) for details.
- **Long-lived tokens for automation** -- The Password Depot Server Manager can generate long-lived access tokens (expiry date 1 to 730 days ahead, 180 by default) for any user account, in client or admin scope, ideal for scheduled tasks, CI/CD pipelines, and monitoring scripts that cannot re-authenticate every 10 minutes. Tokens can be individually named, revoked, and tracked with last-used timestamps. See [Token Lifetime](api-reference/authentication.md#token-lifetime).
- **Standard Bearer token authentication** -- No more custom headers. Use the widely-supported `Authorization: Bearer <token>` pattern that works out of the box with HTTP clients, API gateways, and middleware.
- **RESTful noun-based resource URLs** -- Resources are addressable nouns (`/databases`, `/users`, `/entries/{id}`) with standard HTTP methods (GET, POST, PATCH, DELETE) instead of verb-style commands.
- **Native JSON types** -- Boolean fields return `true`/`false`, numeric fields return integers, eliminating the need to parse string-encoded values.
- **Full server administration** -- Manage users, groups, permissions, alerts, and secrets programmatically, not just password entries.
- **Folder management as a first-class resource** -- Folders have their own endpoints with full CRUD operations, separate from entries.
- **Document content management** -- Download and upload document entry BLOBs (up to 64 MB) via the REST API -- a long-requested feature that was not available in v1.0.
- **Pagination on all list endpoints** -- Efficiently handle large datasets with `offset`/`limit` parameters and total count metadata.

## Getting Started

New to the REST API? Start here:

1. **[Server Setup](getting-started/setup.md)** -- Enable the REST service and configure SSL
2. **[Authentication](getting-started/authentication.md)** -- Understand the Bearer token flow
3. **[Quick Start](getting-started/quick-start.md)** -- Complete CRUD walkthrough in minutes

## Quick Links

| Resource | Description |
|----------|-------------|
| [Getting Started](getting-started/setup.md) | Server setup, authentication, and first API call |
| [API Reference](api-reference/overview.md) | Complete documentation of every endpoint |
| [OpenAPI Specification](openapi.yaml) | Machine-readable API spec for code generation and tooling |
| [Changelog](changelog.md) | Version history and breaking changes |
| [v1.0 Documentation](../v1.0/) | Legacy API, served by Server 19.x and earlier only |

## Base URL

All v2.0 endpoints are available at:

```
https://<YOUR_SERVER>:8714/v2.0/
```

!!! info "v1.0 alongside v2.0"
    Servers 19.1.0 to 19.x serve v1.0 at `/v1.0/` and v2.0 at `/v2.0/` on the same port. Server 20.0.0 serves v2.0 only and answers `/v1.0/` with `410 Gone`.

## API at a Glance

v2.0 groups its endpoints by resource, separated into client and admin scopes:

**Client Endpoints** (accessible with any session):

| Resource | Description |
|----------|-------------|
| [Auth](api-reference/authentication.md) | Login, logout, OIDC discovery, WebAuthn begin/complete |
| [Profile (`/me`)](api-reference/users.md#user-profile) | Get profile; change own password; manage own passkeys (list/register/rename/delete) |
| [Databases](api-reference/databases.md#client-endpoints) | List and read accessible databases |
| [Folders](api-reference/overview.md#folders) | Folder management within databases |
| [Entries](api-reference/overview.md#entries) | Password entry CRUD, move, and document content |
| [Recycle Bin](api-reference/recyclebin.md) | List, restore and destroy deleted entries and folders (Server 20.0.0 and later) |
| [Database Icons](api-reference/icons.md) | List, fetch and upload the icons stored in a database (Server 20.0.0 and later) |
| [Search](api-reference/overview.md#search) | Search within a database |
| [Secrets](api-reference/secrets.md) | Create, list, get, delete own secrets; approve, reject, revoke |

**Admin Endpoints** (require `"scope": "admin"` at login):

| Resource | Description |
|----------|-------------|
| [Databases](api-reference/databases.md#admin-endpoints) | Full database CRUD (all server databases) |
| [Permissions](api-reference/permissions.md) | Access control management |
| [Users](api-reference/users.md) | User administration, password management, and passkey revocation |
| [Groups](api-reference/groups.md) | Group administration |
| [Alerts](api-reference/alerts.md) | Alert management |
| [Secrets](api-reference/secrets.md) | Full CRUD + workflow on all secrets |
