# Password Depot Server REST API Documentation

Official documentation and examples for the **Password Depot Enterprise Server** REST API.

## API Versions

| Version | Status | Server support | Documentation | OpenAPI Spec |
|---------|--------|----------------|---------------|--------------|
| **v2.0** | **Recommended** | Server **19.2.0 and later**, including **20.0.0 and later** | [docs/v2.0/](docs/v2.0/) | [openapi/v2.0/openapi.yaml](openapi/v2.0/openapi.yaml) |
| **v1.0** | Legacy | Server **19.x and earlier** -- **not available in 20.0.0 or later** | [docs/v1.0/](docs/v1.0/) | [openapi/v1.0/openapi.yaml](openapi/v1.0/openapi.yaml) |

v1.0 is closed to new development and is documented here for the servers that
still carry it. **Password Depot Enterprise Server 20.0.0 serves v2.0 only**, so
an application still calling `/v1.0/...` has to move to v2.0 before the server it
talks to is upgraded. The [v2.0 changelog](docs/v2.0/changelog.md) lists what
changes between the two.

### What's New in v2.0

**Authentication & security**

- **Windows SSO / gMSA support** -- HTTP Negotiate (SPNEGO/Kerberos) authentication for passwordless login with domain service accounts
- **WebAuthn / passkeys** -- Passwordless authentication via biometrics, security keys, or platform authenticators, with dedicated management endpoints (`/me/passkeys/...`, `/admin/users/{id}/passkeys/...`)
- **OIDC identity providers** -- Federated login against configured identity providers, listed via `GET /auth/oidc`
- **Long-lived API tokens** -- Configurable-lifetime tokens (6 months to 2 years) for automation, issued to administrator accounts and managed (created and revoked) in the Server Manager; they are not revoked by `/auth/logout`
- **Standard Bearer token auth** -- Industry-standard `Authorization: Bearer <token>` header; no custom `client_id` header
- **IP lockout with `429` + `Retry-After`** -- RFC-compliant rate-limit responses; loopback addresses are exempt so the Server Manager stays reachable during an external brute-force

**Resources & endpoints**

- **RESTful resource URLs** -- Noun-based paths (`/databases`, `/users/{id}`) with standard HTTP methods
- **Full server administration** -- Users, groups, permissions, alerts, and shared secrets via `/admin/` endpoints
- **Self-service profile** -- `PATCH /v2.0/me` lets users update their own display name, department, and phone; dedicated endpoints for password and passkey changes
- **Shared secrets with approval workflow** -- Share entries via signed links, with optional multi-approver review and HTTPS/protocol-handler delivery
- **Alerts management** -- Create, list, update, and delete server alert rules with recipient and scope filters
- **Folder navigation with breadcrumbs** -- `path` array in folder/entry responses for explorer-style UIs
- **Document content management** -- Upload/download document BLOBs (up to 64 MB)

**HTTP & developer experience**

- **Pagination on list endpoints** -- `?offset=...&limit=...` with a standardized `{data, total, offset, limit}` envelope on the paginated collections (a few simple lookups, such as the OIDC provider list, return a bare array)
- **Native JSON types** -- `true`/`false` and numbers instead of string-encoded values
- **Standardized error format** -- `{"error": {"code": N, "message": "..."}}`; `Allow` header on `405`, `Retry-After` on `429`
- **Case-sensitive routes** -- Per RFC 3986; v1.0 remains case-insensitive for backward compatibility

See the [v2.0 changelog](docs/v2.0/changelog.md) for the full list of changes vs v1.0.

## Overview

Password Depot Enterprise Server provides a RESTful HTTPS interface for lightweight client access. This repository holds the **public documentation, examples, and OpenAPI specifications** for that API -- it does not contain the server's source code, which ships as part of Password Depot Enterprise Server. Specifically, it contains:

- **Complete API reference** with endpoint-by-endpoint documentation
- **Code examples** in curl, PowerShell, and Python
- **Guides** for common tasks like two-factor authentication and bulk operations
- **OpenAPI 3.0 specifications** for tooling and client generation

## Reference Client

The [Password Depot Web Client](https://github.com/acebit-gmbh/web_client_2) is a React + TypeScript single-page application that consumes this API. It exercises the v2.0 contract end to end -- authentication, vault browsing, entry/folder CRUD, document upload/download, and search -- and serves as a working reference implementation of these docs.

## Quick Links

### v2.0 (recommended)

| Resource | Description |
|----------|-------------|
| [Getting Started](docs/v2.0/getting-started/setup.md) | Enable and configure the REST service |
| [Authentication](docs/v2.0/api-reference/authentication.md) | Login, Negotiate SSO, WebAuthn, OIDC, long-lived tokens |
| [API Reference](docs/v2.0/api-reference/overview.md) | Full endpoint documentation |
| [Changelog](docs/v2.0/changelog.md) | Breaking changes and new features vs v1.0 |
| [PowerShell Examples](examples/v2.0/) | Helper module, login example, integration test suite |
| [OpenAPI Spec](openapi/v2.0/openapi.yaml) | Machine-readable API definition |

### v1.0 (legacy)

| Resource | Description |
|----------|-------------|
| [Getting Started](docs/v1.0/getting-started/setup.md) | Enable and configure the REST service |
| [API Reference](docs/v1.0/api-reference/overview.md) | Full endpoint documentation |
| [PowerShell Examples](examples/v1.0/powershell/) | Ready-to-use PowerShell scripts |
| [OpenAPI Spec](openapi/v1.0/openapi.yaml) | Machine-readable API definition |

## Prerequisites

- Password Depot Enterprise Server **v19.2.0 or later** for the v2.0 API. The v1.0 API is present in **19.x and earlier** only -- it was removed in **20.0.0**
- REST Web Service enabled in Server Manager
- Valid SSL certificate configured
- Default port: **8714** (configurable via `pdserver.ini`)

## Running Examples

### curl (v2.0)

```bash
# Login -- the response carries a JWT in `access_token`
curl -k -X POST "https://your-server:8714/v2.0/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"user":"your_username","pass":"your_password"}'

# Use the token as a Bearer credential
curl -k "https://your-server:8714/v2.0/databases" \
  -H "Authorization: Bearer <access_token>"
```

### PowerShell (v2.0)

```powershell
# Using the helper module
. .\examples\v2.0\PD-RestClient-v2.ps1
$session = Connect-PDServer -Server "your-server" -Username "your_username" -Password "your_password"
Get-PDDatabases -Session $session
```

To run the full integration test suite:

```powershell
.\examples\v2.0\Run-Tests.ps1 -Server "your-server" -Username "admin" -Password "your_password"
```

### curl (v1.0)

```bash
# Login
curl -k -X POST "https://your-server:8714/v1.0/login" \
  -H "Content-Type: application/json" \
  -d '{"user":"your_username","pass":"your_password"}'
```

### PowerShell (v1.0)

```powershell
. .\examples\v1.0\powershell\PD-RestClient.ps1
$session = Connect-PDServer -Server "your-server" -Username "your_username" -Password "your_password"
Get-PDDatabases -Session $session
```

### Python (v1.0)

```python
from examples.v1_0.python.pd_client import PDClient
client = PDClient("your-server")
client.login("your_username", "your_password")
databases = client.list_databases()
```

## Building the Documentation

This project uses [MkDocs](https://www.mkdocs.org/) with the [Material theme](https://squidfunk.github.io/mkdocs-material/).

### Prerequisites

```bash
pip install "mkdocs>=1.6,<2.0" mkdocs-material
```

> **Note:** MkDocs 2.0 is currently incompatible with the Material theme. Pin to 1.x as shown above.

### Local Preview

```bash
# Serve v1.0 docs locally
mkdocs serve -f mkdocs.v1.yml

# Serve v2.0 docs locally
mkdocs serve -f mkdocs.v2.yml
```

### Building Static HTML

Build both versions into a single `site/` directory for deployment:

```bash
mkdocs build -f mkdocs.v1.yml -d site/v1.0
mkdocs build -f mkdocs.v2.yml -d site/v2.0
```

This produces a self-contained folder of static HTML/CSS/JS files:

```
site/
├── v1.0/    # v1.0 documentation
└── v2.0/    # v2.0 documentation
```

### Deploying to a Local Web Server

Copy the `site/` folder to any web server (Apache, Nginx, IIS, etc.). No Python or MkDocs is required on the server -- the output is entirely static.

**IIS example:** Point a virtual directory or website to the `site/` folder.

To redirect the root URL to the default version, copy the `index.html` from the project root into the `site/` folder:

```html
<!DOCTYPE html>
<html>
<head><meta http-equiv="refresh" content="0; url=v2.0/"></head>
</html>
```

## Project Structure

```
pd_rest_api/
├── docs/
│   ├── v1.0/                   # v1.0 documentation (Markdown)
│   │   ├── getting-started/    # Setup and first steps
│   │   ├── api-reference/      # Endpoint-by-endpoint reference
│   │   ├── examples/           # Inline code examples
│   │   └── guides/             # Task-oriented guides
│   └── v2.0/                   # v2.0 documentation
│       ├── getting-started/    # Setup, quick start, authentication
│       ├── api-reference/      # Per-resource reference: auth, databases,
│       │                       #   folders, entries, search, users, groups,
│       │                       #   permissions, alerts, secrets
│       └── changelog.md        # Breaking changes and new features
├── examples/
│   ├── v1.0/                   # v1.0 runnable scripts
│   │   ├── powershell/         # PowerShell scripts and module
│   │   ├── curl/               # Shell scripts
│   │   └── python/             # Python client and examples
│   └── v2.0/                   # v2.0 runnable scripts
│       ├── PD-RestClient-v2.ps1   # PowerShell client module
│       ├── Login-Example.ps1      # Minimal login/logout example
│       ├── Negotiate.ps1          # Windows SSO / gMSA (Negotiate) login example
│       ├── Test-Framework.ps1     # Test helpers (Start-Test, Assert-*, etc.)
│       └── Run-Tests.ps1          # Full integration test suite
├── openapi/
│   ├── v1.0/                   # OpenAPI 3.0 spec for v1.0
│   └── v2.0/                   # OpenAPI 3.0 spec for v2.0
├── overrides/                  # MkDocs Material theme overrides
│   ├── main.html               # Custom header with logo
│   └── assets/images/          # Logo and branding assets
├── mkdocs.v1.yml               # MkDocs configuration (v1.0)
├── mkdocs.v2.yml               # MkDocs configuration (v2.0)
├── build_site.bat              # Build script for both doc versions
├── index.html                  # Root redirect to default version
├── CONTRIBUTING.md             # How to contribute (docs, examples, specs)
├── SECURITY.md                 # Responsible-disclosure policy
├── LICENSE                     # MIT License
└── README.md
```

## Contributing

Contributions are welcome -- corrections, clarifications, new examples, and spec fixes. See [CONTRIBUTING.md](CONTRIBUTING.md) for how to build the docs locally, the conventions we follow (keep `openapi/` in sync with `docs/`, use neutral placeholders such as `your-server` and `example.com`), and the pull-request checklist.

## Security

Password Depot is a password manager, so we take security seriously. **Please do not report vulnerabilities in public GitHub issues** -- follow the responsible-disclosure process in [SECURITY.md](SECURITY.md).

## License

This project is licensed under the **MIT License** -- Copyright © 2025 AceBIT GmbH. See [LICENSE](LICENSE) for the full text.
