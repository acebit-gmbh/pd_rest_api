# Databases

Reference for database endpoints. Databases are accessible in both **client** and **admin** scopes, but with different capabilities.

| Scope | Endpoints | Description |
|-------|-----------|-------------|
| Client | `GET /v2.0/databases`, `GET /v2.0/databases/{id}` | Read-only access to databases the user has permissions on |
| Admin | `GET/POST /v2.0/admin/databases`, `GET/PATCH/DELETE /v2.0/admin/databases/{id}` | Full CRUD on all server databases |

---

## Database Object

The database object uses different representations depending on scope and context:

- **Client scope** and **admin list** responses return a **compact representation**: `id`, `name`, `description`, `updated_at`.
- **Admin detail** responses (`GET /v2.0/admin/databases/{id}`) return the **full representation** with all fields.

| Field | Type | Writable | Description |
|-------|------|:--------:|-------------|
| `id` | string (UUID) | No | Unique identifier (server-generated) |
| `name` | string | Yes | Database filename |
| `description` | string | Yes | Database description |
| `size` | integer | No | File size in bytes (admin detail only) |
| `entries_count` | integer | No | Number of password entries (admin detail only) |
| `icons_count` | integer | No | Number of custom icons (admin detail only) |
| `disabled` | boolean | Restricted | Whether the database is disabled (admin detail only). Requires database management permission. |
| `db_admins` | array of UUIDs | Restricted | User IDs designated as Database Administrators (admin detail only). Requires database management permission. |
| `db_supervisors` | array of UUIDs | Restricted | User IDs designated as Database Supervisors (admin detail only). Requires database management permission. |
| `include_server_supervisors` | boolean | Restricted | Whether server-level supervisors have access to this database (admin detail only). Requires database management permission. |
| `updated_at` | string (ISO 8601) | No | Last modification timestamp |

!!! warning "Field-Level Authorization"
    The `disabled`, `db_admins`, `db_supervisors`, and `include_server_supervisors` fields can only be modified by users with database management permission (Server Administrators or Database Administrators for this database). If an unauthorized user attempts to change these fields, the server returns `403 Forbidden`.

---

## Client Endpoints

These endpoints are available in both `client` and `admin` sessions. They return only databases the authenticated user has read access to.

!!! warning "Read-only for client scope"
    Only `GET` is supported under `/v2.0/databases/*`. Any attempt to create (`POST`), modify (`PATCH`), or delete (`DELETE`) a database on this path returns `405 Method Not Allowed`. Database management operations are **admin-only** and live under [`/v2.0/admin/databases`](#admin-endpoints) -- the session must be opened with `"scope": "admin"` at login.

### List Databases

```
GET /v2.0/databases
```

Returns a paginated list of databases accessible by the authenticated user. Only databases the user has effective access rights on are included. Returns the compact representation (no admin-specific fields).

#### Query Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `offset` | integer | No | Pagination offset (default: `0`) |
| `limit` | integer | No | Pagination limit (default: `100`) |

#### Response

`200 OK`

```json
{
    "data": [
        {
            "id": "E79BDEB2-1A58-4715-B74C-28A87A2AFD37",
            "name": "Corporate Passwords.pswe",
            "description": "Main corporate password database",
            "updated_at": "2025-02-28T13:22:22.753Z"
        }
    ],
    "total": 1,
    "offset": 0,
    "limit": 100
}
```

#### Error Responses

| Status | Description |
|--------|-------------|
| `401 Unauthorized` | Missing or invalid authentication token |

#### Example

=== "curl"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/databases?offset=0&limit=100" \
        -H "Authorization: Bearer <token>"
    ```

---

### Get Database

```
GET /v2.0/databases/{id}
```

Returns details of a specific database that the user has access to. Returns the compact representation (no admin-specific fields).

#### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string (UUID) | Yes | Database unique identifier |

#### Response

`200 OK`

```json
{
    "id": "E79BDEB2-1A58-4715-B74C-28A87A2AFD37",
    "name": "Corporate Passwords.pswe",
    "description": "Main corporate password database",
    "updated_at": "2025-02-28T13:22:22.753Z"
}
```

#### Error Responses

| Status | Description |
|--------|-------------|
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions to access this database |
| `404 Not Found` | Database not found |

#### Example

=== "curl"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/databases/E79BDEB2-1A58-4715-B74C-28A87A2AFD37" \
        -H "Authorization: Bearer <token>"
    ```

---

## Admin Endpoints

These endpoints require an **admin-scoped session** (`"scope": "admin"` at login).

!!! note "Filtered Pagination for Database Administrators"
    Database Administrators only see databases they are designated to manage. Server Administrators see all databases. The `total` count reflects the number of databases visible to the caller.

### List All Databases (Admin)

```
GET /v2.0/admin/databases
```

Returns a paginated list of databases on the server. Returns the compact representation (use [Get Database (Admin)](#get-database-admin) to retrieve the full representation for a specific database).

#### Query Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `offset` | integer | No | Pagination offset (default: `0`) |
| `limit` | integer | No | Pagination limit (default: `100`) |

#### Response

`200 OK`

```json
{
    "data": [
        {
            "id": "E79BDEB2-1A58-4715-B74C-28A87A2AFD37",
            "name": "Corporate Passwords.pswe",
            "description": "Main corporate password database",
            "updated_at": "2025-02-28T13:22:22.753Z"
        },
        {
            "id": "CD089F93-A0CF-475E-A7A0-7F060D005A8D",
            "name": "IT Department.pswe",
            "description": "Shared IT team credentials",
            "updated_at": "2022-10-17T10:58:40.349Z"
        }
    ],
    "total": 64,
    "offset": 0,
    "limit": 100
}
```

#### Error Responses

| Status | Description |
|--------|-------------|
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Session does not have admin scope |

#### Example

=== "curl"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/admin/databases?offset=0&limit=100" \
        -H "Authorization: Bearer <token>"
    ```

---

### Create Database (Admin)

```
POST /v2.0/admin/databases
```

Creates a new database.

#### Request Body

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `name` | string | Yes | Database filename. Must follow the [Database Name Rules](#database-name-rules) below. |
| `description` | string | No | Database description |
| `disabled` | boolean | No | Whether the database is disabled (default: `false`). Requires database management permission. |
| `db_admins` | array of UUIDs | No | Database Administrator user IDs. Requires database management permission. |
| `db_supervisors` | array of UUIDs | No | Database Supervisor user IDs. Requires database management permission. |
| `include_server_supervisors` | boolean | No | Whether server-level supervisors have access (default: `true`). Requires database management permission. |

```json
{
    "name": "New Database.pswe",
    "description": "A new password database"
}
```

##### Database Name Rules

Database names are mapped directly to directory names on the server's filesystem, so the API enforces the following rules to prevent path traversal and reserved-name collisions. Submitting a name that violates any rule returns `400 Bad Request`.

| Rule | Example of rejected value |
|------|---------------------------|
| No path separators | `"foo/bar"`, `"foo\\bar"` |
| No drive letter or alternate data stream separator | `"C:\\evil"`, `"name:stream"` |
| No `..` sequence anywhere in the name | `"../../evil"`, `"..\\evil"`, `"foo..bar"` |
| No wildcards or shell metacharacters | `"weird*file"`, `"name?"`, `"a<b>c"`, `'na"me'`, `"a\|b"` |
| No control characters (bytes 0x00-0x1F) including tabs and newlines | `"bad\\ttab"`, `"line1\\nline2"` |
| No leading or trailing dots | `".leading"`, `"trailing."` |
| No leading or trailing whitespace | `"  spaces  "` |
| No reserved Windows device names (with or without extension) | `"CON"`, `"PRN"`, `"AUX"`, `"NUL"`, `"COM1"`..`"COM9"`, `"LPT1"`..`"LPT9"` |
| Length between 1 and 200 characters | -- |

The same rules are enforced when renaming a database via `PATCH /v2.0/admin/databases/{id}`.

#### Response

`201 Created`

```json
{
    "id": "F5A6B7C8-D9E0-1234-ABCD-567890123456",
    "name": "New Database.pswe",
    "description": "A new password database",
    "updated_at": "2025-02-17T09:00:00.000Z"
}
```

#### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | Invalid or missing required fields |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Session does not have admin scope, or attempted to set restricted fields without database management permission |
| `409 Conflict` | A database with this name already exists |

#### Example

=== "curl"

    ```bash
    curl -X POST "https://<server>:8714/v2.0/admin/databases" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "New Database.pswe",
            "description": "A new password database"
        }'
    ```

---

### Get Database (Admin)

```
GET /v2.0/admin/databases/{id}
```

Returns the **full representation** of a specific database, including size, entry count, admin assignments, and other management fields.

#### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string (UUID) | Yes | Database unique identifier |

#### Response

`200 OK`

```json
{
    "id": "E79BDEB2-1A58-4715-B74C-28A87A2AFD37",
    "name": "Corporate Passwords.pswe",
    "description": "Main corporate password database",
    "size": 2462395,
    "entries_count": 391,
    "icons_count": 31,
    "disabled": false,
    "db_admins": [
        "83664092-DF61-45F0-AEA5-DD9E14C8C519"
    ],
    "db_supervisors": [
        "83664092-DF61-45F0-AEA5-DD9E14C8C519"
    ],
    "include_server_supervisors": true,
    "updated_at": "2025-02-28T13:22:22.753Z"
}
```

#### Error Responses

| Status | Description |
|--------|-------------|
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Session does not have admin scope |
| `404 Not Found` | Database not found |

#### Example

=== "curl"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/admin/databases/E79BDEB2-1A58-4715-B74C-28A87A2AFD37" \
        -H "Authorization: Bearer <token>"
    ```

---

### Update Database (Admin)

```
PATCH /v2.0/admin/databases/{id}
```

Updates an existing database. Include only the fields you want to update.

#### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string (UUID) | Yes | Database unique identifier |

#### Request Body

```json
{
    "description": "Updated description",
    "db_admins": [
        "83664092-DF61-45F0-AEA5-DD9E14C8C519",
        "3D1C91F6-754D-427E-9D76-8CC20E8C326E"
    ]
}
```

#### Response

`200 OK`

```json
{
    "id": "E79BDEB2-1A58-4715-B74C-28A87A2AFD37",
    "name": "Corporate Passwords.pswe",
    "description": "Updated description",
    "size": 2462395,
    "entries_count": 391,
    "icons_count": 31,
    "disabled": false,
    "db_admins": [
        "83664092-DF61-45F0-AEA5-DD9E14C8C519",
        "3D1C91F6-754D-427E-9D76-8CC20E8C326E"
    ],
    "db_supervisors": [
        "83664092-DF61-45F0-AEA5-DD9E14C8C519"
    ],
    "include_server_supervisors": true,
    "updated_at": "2025-03-10T11:00:00.000Z"
}
```

#### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | Invalid fields |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Session does not have admin scope, or attempted to modify restricted fields without database management permission |
| `404 Not Found` | Database not found |
| `409 Conflict` | Database name conflict |

#### Example

=== "curl"

    ```bash
    curl -X PATCH "https://<server>:8714/v2.0/admin/databases/E79BDEB2-1A58-4715-B74C-28A87A2AFD37" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -d '{
            "description": "Updated description",
            "db_admins": [
                "83664092-DF61-45F0-AEA5-DD9E14C8C519",
                "3D1C91F6-754D-427E-9D76-8CC20E8C326E"
            ]
        }'
    ```

---

### Delete Database (Admin)

```
DELETE /v2.0/admin/databases/{id}
```

Deletes a database.

#### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string (UUID) | Yes | Database unique identifier |

#### Response

`204 No Content`

No response body.

#### Error Responses

| Status | Description |
|--------|-------------|
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Session does not have admin scope |
| `404 Not Found` | Database not found |

#### Example

=== "curl"

    ```bash
    curl -X DELETE "https://<server>:8714/v2.0/admin/databases/E79BDEB2-1A58-4715-B74C-28A87A2AFD37" \
        -H "Authorization: Bearer <token>"
    ```
