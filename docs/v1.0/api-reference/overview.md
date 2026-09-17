# API Reference Overview

## Base URL

All API endpoints are available at:

```
https://<YOUR_SERVER>:8714/v1.0/
```

Entry icons are served at a separate path outside the API version prefix:

```
https://<YOUR_SERVER>:8714/file/<icon_filename>
```

Each entry has an `icon` field (e.g., `"ico0.svg"`). To display the icon, request it from this URL. No authentication headers are required.

**Example:** `https://127.0.0.1:8714/file/ico0.svg`

## Supported HTTP Methods

| Method | Usage |
|--------|-------|
| `GET` | Retrieve resources (databases, entries, search) |
| `POST` | Authenticate, modify entries, move entries, logout |
| `PUT` | Create new entries |
| `DELETE` | Delete entries |
| `PATCH` | Partial updates (reserved) |

## Required Headers

All endpoints except `/login` require these HTTP headers:

| Header | Description | Example |
|--------|-------------|---------|
| `access_token` | Access token from login response | `a1b2c3d4e5f6...` |
| `client_id` | Client identifier from login response | `550e8400-e29b-...` |

The `access_token` expires after **10 minutes** of inactivity.

## Request Format

- All request bodies must be **JSON** with `Content-Type: application/json`
- Character encoding: **UTF-8**
- Query parameters are passed in the URL

## Response Format

All responses are returned as **JSON**.

### Success Response

The structure varies by endpoint. See individual endpoint documentation for details.

### Error Response

On error, the server returns:

```json
{
  "code": <HTTP_ERROR_CODE>,
  "error": "<DESCRIPTION>"
}
```

## Error Codes

| Code | Name | Description |
|------|------|-------------|
| `400` | Bad Request | Unknown command, invalid path, or malformed request |
| `401` | Unauthorized | Invalid credentials, expired token, or missing authentication |
| `403` | Forbidden | Authenticated but insufficient permissions for the requested action |
| `404` | Not Found | The requested resource (database, entry, folder) does not exist |
| `459` | TFA Not Activated | Two-factor authentication needs initial setup (QR code URL returned) |
| `460` | TFA Code Required | A valid 6-digit 2FA code must be provided to complete login |
| `500` | Internal Server Error | Unexpected server-side error |
| `501` | Not Implemented | The requested command or feature is not supported |

## Endpoint Summary

| Endpoint | Method | Description | Auth Required |
|----------|--------|-------------|:-------------:|
| [`/login`](authentication.md#login) | POST | Authenticate user | No |
| [`/logout`](authentication.md#logout) | POST | End session | Yes |
| [`/oidc`](authentication.md#oidc-providers) | GET | List OIDC/Azure identity providers | No |
| [`/list`](databases.md) | GET | List databases | Yes |
| [`/list?db=`](entries.md#list-entries) | GET | List entries in database/folder | Yes |
| [`/read`](entries.md#read-entry) | GET | Read entry details | Yes |
| [`/add`](entries.md#create-entry) | PUT | Create new entry | Yes |
| [`/modify`](entries.md#modify-entry) | POST | Modify existing entry | Yes |
| [`/search`](search.md) | GET | Search entries | Yes |
| [`/delete`](delete.md) | DELETE | Delete entries | Yes |
| [`/move`](move.md) | POST | Move entries | Yes |

## Data Conventions

### Boolean Values

Boolean fields are represented as **strings** `"0"` (false) and `"1"` (true), not as JSON booleans.

```json
{
  "safemode": "1",
  "markassafe": "0"
}
```

### Dates

Dates are returned in **ISO 8601** format (e.g., `"2021-07-05T10:39:50.000Z"`). An empty string or a date before the year 1901 indicates that the field is not set.

### Auto-Complete Templates

The `template` field uses XML-style placeholders for keyboard automation sequences:

```
<USER><TAB><PASS><ENTER>
```

Available placeholders: `<USER>`, `<PASS>`, `<TAB>`, `<ENTER>`, `<DELAY>`.

## Permission Strings

Database and entry responses include a `rights` field (e.g., `"RMIDCFAPE-Y-HL"`). Each character represents a permission:

| Character | Permission |
|-----------|------------|
| `R` | Read |
| `M` | Modify |
| `I` | Insert (create) |
| `D` | Delete |
| `C` | Create folders |
| `F` | Modify folders |
| `A` | Admin |
| `P` | Print |
| `E` | Export |
| `Y` | History |
| `H` | View passwords |
| `L` | List |

A dash (`-`) indicates a separator or unused position.
