# Password Depot Server REST API

Welcome to the official documentation for the **Password Depot Enterprise Server REST API v1.0**.


!!! tip "API v2.0 Available"
    A new version of the REST API is in development with RESTful resource-based URLs, standard Bearer token authentication, native JSON types, pagination, and full server administration capabilities. See the [v2.0 documentation](../v2.0/) for details.

Password Depot Enterprise Server, in addition to its internal custom TCP-based communication protocol, implements a RESTful HTTPS interface for lightweight client access. This API enables the creation of custom web services, automation scripts, and integrations with Password Depot Server as the backend.

## What You Can Do

- **Authenticate** users (including two-factor authentication and OIDC/Azure)
- **List** available databases and browse folder structures
- **Read** entry details including passwords, custom fields, and TANs
- **Create, modify, and delete** entries programmatically
- **Search** across databases
- **Move** entries between folders

## Getting Started

New to the REST API? Start here:

1. **[Server Setup](getting-started/setup.md)** -- Enable the REST service and configure SSL
2. **[Authentication](getting-started/authentication.md)** -- Understand login flows and token management
3. **[Quick Start](getting-started/quick-start.md)** -- Make your first API call in minutes

## API Reference

Detailed documentation for every endpoint:

| Endpoint | Method | Description |
|----------|--------|-------------|
| [`/login`](api-reference/authentication.md#login) | POST | Authenticate and obtain access token |
| [`/logout`](api-reference/authentication.md#logout) | POST | End session |
| [`/list`](api-reference/databases.md) | GET | List databases |
| [`/list?db=...`](api-reference/entries.md#list-entries) | GET | List entries in a database/folder |
| [`/read`](api-reference/entries.md#read-entry) | GET | Read entry attributes |
| [`/add`](api-reference/entries.md#create-entry) | PUT | Create a new entry |
| [`/modify`](api-reference/entries.md#modify-entry) | POST | Update an existing entry |
| [`/search`](api-reference/search.md) | GET | Search entries |
| [`/delete`](api-reference/delete.md) | DELETE | Delete entries |
| [`/move`](api-reference/move.md) | POST | Move entries between folders |

## Code Examples

Every endpoint includes examples in multiple languages:

- **[curl](examples/curl.md)** -- Command-line examples for quick testing
- **[PowerShell](examples/powershell.md)** -- Scripts for Windows automation
- **[Python](examples/python.md)** -- Python client library and examples

## Base URL

All API endpoints use the following base URL:

```
https://<YOUR_SERVER>:8714/v1.0/
```

Replace `<YOUR_SERVER>` with your Password Depot Server's hostname or IP address. The default port is **8714**.

!!! info "HTTPS Required"
    Starting from v18.0.0, a valid SSL certificate is mandatory. See [Server Setup](getting-started/setup.md) for details.
