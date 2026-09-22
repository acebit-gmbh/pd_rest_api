# Databases

Reference for database endpoints. Databases are accessible in both **client** and **admin** scopes, but with different capabilities.

| Scope | Endpoints | Description |
|-------|-----------|-------------|
| Client | `GET /v2.0/databases`, `GET /v2.0/databases/{id}` | Read-only access to databases the user has permissions on |
| Admin | `GET/POST /v2.0/admin/databases`, `GET/PATCH/DELETE /v2.0/admin/databases/{id}` | Full CRUD on all server databases |

---

## Database Object

The database object uses different representations depending on scope and context:

- **Client scope** and **admin list** responses return a **compact representation**: `id`, `name`, `description`, `updated_at`, `icons`, `recycle_bin`.
- **Admin detail** responses (`GET /v2.0/admin/databases/{id}`) return the **full representation** with all fields.

| Field | Type | Writable | Description |
|-------|------|:--------:|-------------|
| `id` | string (UUID) | No | Unique identifier (server-generated) |
| `name` | string | Yes | Database filename |
| `description` | string | Yes | Database description |
| `size` | integer | No | File size in bytes (admin detail only) |
| `entries_count` | integer | No | Number of password entries (admin detail only) |
| `icons_count` | integer | No | Number of icon slots in the database's icon collection, removed icons included (admin detail only). Unrelated to `icons`: it is not a capability marker, and it can be larger than the `total` of [List Icons](icons.md#list-icons), which leaves removed icons out |
| `disabled` | boolean | Restricted | Whether the database is disabled (admin detail only). Requires database management permission. |
| `db_admins` | array of UUIDs | Restricted | User IDs designated as Database Administrators (admin detail only). Requires database management permission. |
| `db_supervisors` | array of UUIDs | Restricted | User IDs designated as Database Supervisors (admin detail only). Requires database management permission. |
| `include_server_supervisors` | boolean | Restricted | Whether server-level supervisors have access to this database (admin detail only). Requires database management permission. |
| `updated_at` | string (ISO 8601) | No | Last modification timestamp |
| `icons` | object | No | [Database icon](icons.md) capability of this database for the current caller, in every representation and both scopes - see [Icons Capability](#icons-capability). Absent on servers older than 20.0.0 |
| `recycle_bin` | object | No | [Recycle bin](recyclebin.md) capability of this database for the current caller, in every representation and both scopes - see [Recycle Bin Capability](#recycle-bin-capability). Absent on servers older than 20.0.0 |

!!! warning "Field-Level Authorization"
    The `disabled`, `db_admins`, `db_supervisors`, and `include_server_supervisors` fields can only be modified by users with database management permission (Server Administrators or Database Administrators for this database). If an unauthorized user attempts to change these fields, the server returns `403 Forbidden`.

### Icons Capability

*Server 20.0.0 and later.*

Every database object - client and admin scope, list and detail, compact and full - carries a read-only `icons` object. Its presence is how a client detects that the server implements [Database Icons](icons.md) as a whole: the `/icons` endpoints, the `database_icon` field on entries and folders, the validated `image_*` writes and the corrected `icon` field. When it is absent, the server is older than 20.0.0: never call `/icons`, never probe by uploading, and treat `icon` as the legacy value. A client whose JSON layer cannot tell `null` from an absent key should use this marker rather than `database_icon`.

| Field | Type | Description |
|-------|------|-------------|
| `can_upload` | boolean | Whether the current caller can upload an icon to this database right now: the server is not a mirror, the caller holds the upload right (everyone who can open the database does), and the database has fewer than `max_count` icon slots. An upload can still answer `403` / `4034`, for example when the byte quota is reached |
| `accepted_types` | array of strings | The image types an upload accepts: `["image/png"]` |
| `max_bytes` | integer | Largest accepted image, in bytes after Base64 decoding: `32768` |
| `max_side` | integer | Largest accepted width and height in pixels: `64` |
| `max_count` | integer | Largest number of icon slots a database can hold, removed icons included: `1024` |
| `batch_max` | integer | Largest number of ids in one [List Icons](icons.md#list-icons) call with `ids`: `32` |

Read the limits from this object rather than hard-coding them.

### Recycle Bin Capability

*Server 20.0.0 and later.*

Every database object - client and admin scope, list and detail, compact and full - carries a read-only `recycle_bin` object. Its presence is how a client detects that the server implements the [Recycle Bin](recyclebin.md) as a whole: the `/recyclebin` endpoints, and the `mode` parameter on [Delete Entry](entries.md#delete-entry) and [Delete Folder](folders.md#delete-folder). When it is absent, the server is older than 20.0.0: never call `/recyclebin`, and do not send `mode`.

| Field | Type | Description |
|-------|------|-------------|
| `enabled` | boolean | Whether the server keeps a recycle bin. When `false`, a delete with `mode=recycle` - or without `mode` - removes the item permanently, which is what the Windows client does under the same setting |
| `keep` | integer | How many items the bin holds: `1000` unless an administrator has changed it, and `0` when the bin is off. Beyond that number the oldest items are dropped |
| `can_manage` | boolean | Whether the current caller may see and act on the items **other** people deleted in this database. Everyone always sees what they deleted themselves, whatever this field says; restoring and destroying still need the rights described under [Recycle Bin](recyclebin.md) |

Like `icons`, this object is on every database object, but only `can_manage` describes the **current caller** on **this one** database, so it can differ from one database to the next within the same session. `enabled` and `keep` are a server-wide setting and read the same on every database of a server. Read `can_manage` from here rather than deriving it from a role, and read `enabled` before you tell a user that a deletion can be undone. See [Recycle Bin](recyclebin.md) for the endpoints and for what a caller finds in the bin.

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
            "updated_at": "2025-02-28T13:22:22.753Z",
            "icons": {
                "can_upload": true,
                "accepted_types": ["image/png"],
                "max_bytes": 32768,
                "max_side": 64,
                "max_count": 1024,
                "batch_max": 32
            },
            "recycle_bin": {
                "enabled": true,
                "keep": 1000,
                "can_manage": false
            }
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
    "updated_at": "2025-02-28T13:22:22.753Z",
    "icons": {
        "can_upload": true,
        "accepted_types": ["image/png"],
        "max_bytes": 32768,
        "max_side": 64,
        "max_count": 1024,
        "batch_max": 32
    },
    "recycle_bin": {
        "enabled": true,
        "keep": 1000,
        "can_manage": false
    }
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
            "updated_at": "2025-02-28T13:22:22.753Z",
            "icons": {
                "can_upload": true,
                "accepted_types": ["image/png"],
                "max_bytes": 32768,
                "max_side": 64,
                "max_count": 1024,
                "batch_max": 32
            },
            "recycle_bin": {
                "enabled": true,
                "keep": 1000,
                "can_manage": false
            }
        },
        {
            "id": "CD089F93-A0CF-475E-A7A0-7F060D005A8D",
            "name": "IT Department.pswe",
            "description": "Shared IT team credentials",
            "updated_at": "2022-10-17T10:58:40.349Z",
            "icons": {
                "can_upload": true,
                "accepted_types": ["image/png"],
                "max_bytes": 32768,
                "max_side": 64,
                "max_count": 1024,
                "batch_max": 32
            },
            "recycle_bin": {
                "enabled": true,
                "keep": 1000,
                "can_manage": false
            }
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
    "updated_at": "2025-02-17T09:00:00.000Z",
    "icons": {
        "can_upload": true,
        "accepted_types": ["image/png"],
        "max_bytes": 32768,
        "max_side": 64,
        "max_count": 1024,
        "batch_max": 32
    },
    "recycle_bin": {
        "enabled": true,
        "keep": 1000,
        "can_manage": false
    }
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
    "updated_at": "2025-02-28T13:22:22.753Z",
    "icons": {
        "can_upload": true,
        "accepted_types": ["image/png"],
        "max_bytes": 32768,
        "max_side": 64,
        "max_count": 1024,
        "batch_max": 32
    },
    "recycle_bin": {
        "enabled": true,
        "keep": 1000,
        "can_manage": false
    }
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
    "updated_at": "2025-03-10T11:00:00.000Z",
    "icons": {
        "can_upload": true,
        "accepted_types": ["image/png"],
        "max_bytes": 32768,
        "max_side": 64,
        "max_count": 1024,
        "batch_max": 32
    },
    "recycle_bin": {
        "enabled": true,
        "keep": 1000,
        "can_manage": false
    }
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
