# Folders & Navigation

Reference for folder management and explorer-style navigation within databases. Folders form a hierarchical tree structure similar to a file system -- each folder can contain sub-folders and password entries.

In v2.0, folders are a first-class resource. In v1.0, folders were represented as entries with `itemclass=-1`; this is no longer the case.

---

## Folder Object

The folder object uses different representations depending on context:

- **List/children** responses return a **compact representation**: basic metadata without `comments` or image details.
- **Detail** responses (`GET /v2.0/databases/{db}/folders/{id}`) return the **full representation** with all fields, including `author`, `comments`, and image fields.

### Compact Representation

Returned by list/children endpoints and create/update responses.

| Field | Type | Writable | Description |
|-------|------|:--------:|-------------|
| `type` | string | No | Always `"folder"` |
| `id` | string (UUID) | No | Unique identifier (server-generated) |
| `name` | string | Yes | Folder name |
| `icon` | string | No | Icon filename (e.g., `"ico3.svg"`). Served at `/file/{icon}`. |
| `importance` | string | Yes | Importance level: `"low"`, `"normal"`, or `"high"` (default: `"normal"`) |
| `category` | string | Yes | Category label |
| `tags` | string | Yes | Tags (comma-separated) |
| `has_second_pass` | boolean | No | Whether the folder is protected by a second password |
| `updated_at` | string (ISO 8601) | No | Last modification timestamp (UTC, RFC 3339, trailing `Z`) |

### Full Representation

Returned by the detail endpoint (`GET /v2.0/databases/{db}/folders/{id}`). Includes all compact fields plus:

| Field | Type | Writable | Description |
|-------|------|:--------:|-------------|
| `author` | string | No | Author of the folder (read-only) |
| `image_custom` | boolean | Yes | Whether a custom image is used instead of a standard icon |
| `image_index` | integer | Yes | Standard icon index number |
| `image_name` | string | Yes | Custom image filename (e.g., `"twitter.com"`) |
| `comments` | string | Yes | Folder comments/notes. May require `X-Second-Password` header if `has_second_pass` is `true`. |

!!! info "Second Password Protection"
    Folders can be protected with an optional second password. When `has_second_pass` is `true`, retrieving the full representation (including `comments`) requires the `X-Second-Password` request header with the correct password. The same correct `X-Second-Password` is also **required and verified** when **updating** a protected folder (`PATCH`); a wrong or missing second password is rejected with `403 Forbidden` and `error.code` `4031`.

    Both headers must be **Base64-encoded** (UTF-8 bytes → Base64). This ensures reliable transport of passwords containing non-ASCII characters (e.g., umlauts, accented letters).

    | Header | Description |
    |--------|-------------|
    | `X-Second-Password` | Base64-encoded current second password (required to read/modify protected fields) |
    | `X-New-Second-Password` | Base64-encoded new second password (to set, change, or remove protection) |

    To **change or remove** second password protection, send `X-New-Second-Password` together with the correct current `X-Second-Password` (to remove, set `X-New-Second-Password` to an empty string; both Base64-encoded).

---

## Path / Breadcrumb

Several folder-related responses include a `path` array that represents the ancestor chain from the database root down to (but not including) the current item. This enables breadcrumb navigation in client UIs without extra API calls.

```json
"path": [
    { "id": "3BF225B7-48BC-4AA4-888D-605E61A0F2D4", "name": "Infrastructure" },
    { "id": "174992DC-06A2-475F-BC6E-CD8768B2C054", "name": "Servers" }
]
```

| Field | Type | Description |
|-------|------|-------------|
| `id` | string (UUID) | Ancestor folder ID |
| `name` | string | Ancestor folder name |

**Rules:**

- Elements are ordered from the root towards the current item (first element = top-level ancestor).
- For **root-level** items, `path` is an empty array `[]`.
- The current folder itself is **not** included in the `path`.

**Where it appears:**

| Endpoint | Description |
|----------|-------------|
| `GET .../children` | Ancestors of the folder being listed |
| `GET .../folders/{id}` | Ancestors of the requested folder |
| `GET .../entries/{id}` | Ancestors of the entry's parent folder |

---

## List Children (Navigation)

The primary navigation endpoint for explorer-style browsing. Returns both **folders** and **entries** that are direct children of a given location, similar to how OneDrive, Google Drive, and Dropbox APIs work.

### Root-Level Children

```
GET /v2.0/databases/{db}/children
```

Returns a paginated list of all items (folders and entries) at the root level of a database.

### Folder Children

```
GET /v2.0/databases/{db}/folders/{id}/children
```

Returns a paginated list of all items (folders and entries) inside a specific folder.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `db` | string (UUID) | Yes | Database ID |
| `id` | string (UUID) | Yes | Parent folder ID (folder children only) |

### Query Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `offset` | integer | No | Pagination offset (default: `0`) |
| `limit` | integer | No | Pagination limit (default: `100`) |

### Response

`200 OK`

The response envelope includes the ancestor `path` followed by the `data` array and pagination metadata. Each item in the `data` array includes a `type` field so the client can distinguish between them -- folders have `type: "folder"`, while entries have a specific type such as `"password"`, `"credit_card"`, etc. Folder items use the compact folder representation; entry items use the compact entry representation (without `password`).

The `path` array contains the ancestor chain from the database root down to the current folder (not including the current folder itself). Each element provides the `id` and `name` of an ancestor. For root-level requests, `path` is an empty array.

| Field | Type | Description |
|-------|------|-------------|
| `path` | array of objects | Ancestor breadcrumb trail (see [Path / Breadcrumb](#path--breadcrumb)) |
| `data` | array | Items in this folder (folders and entries) |
| `total` | integer | Total number of items |
| `offset` | integer | Current pagination offset |
| `limit` | integer | Current pagination limit |

```json
{
    "path": [
        {
            "id": "3BF225B7-48BC-4AA4-888D-605E61A0F2D4",
            "name": "Infrastructure"
        }
    ],
    "data": [
        {
            "type": "folder",
            "id": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
            "name": "Production",
            "icon": "ico3.svg",
            "importance": "normal",
            "category": "",
            "tags": "",
            "has_second_pass": false,
            "updated_at": "2024-02-05T16:30:00.000Z"
        },
        {
            "type": "folder",
            "id": "f2b3c4d5-e6f7-8901-bcde-f12345678901",
            "name": "Staging",
            "icon": "ico3.svg",
            "importance": "high",
            "category": "Infrastructure",
            "tags": "cloud,aws,azure",
            "has_second_pass": false,
            "updated_at": "2024-02-12T11:00:00.000Z"
        },
        {
            "type": "password",
            "id": "e1a2b3c4-d5e6-7890-abcd-ef1234567890",
            "name": "GitHub Account",
            "has_second_pass": false,
            "login": "devteam",
            "url": "https://github.com",
            "icon": "ico12.svg",
            "importance": "normal",
            "category": "",
            "tags": "",
            "updated_at": "2024-11-20T16:45:00.000Z",
            "expires_at": null
        }
    ],
    "total": 3,
    "offset": 0,
    "limit": 100
}
```

!!! tip "Explorer-Style Navigation"
    This endpoint is designed for building explorer/tree-view interfaces:

    1. Call `GET /databases/{db}/children` to load the root level.
    2. Display folders in the tree view and entries in the list view.
    3. When the user clicks a folder, call `GET /databases/{db}/folders/{folder_id}/children` to load its contents.
    4. To inspect or edit a specific item, use `GET /databases/{db}/folders/{id}` or `GET /databases/{db}/entries/{id}`.

### Error Responses

| Status | Description |
|--------|-------------|
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions to access this database |
| `404 Not Found` | Database or folder not found |

### Examples

=== "curl (root)"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/children?offset=0&limit=100" \
        -H "Authorization: Bearer <token>"
    ```

=== "curl (folder)"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/folders/f1a2b3c4-d5e6-7890-abcd-ef1234567890/children" \
        -H "Authorization: Bearer <token>"
    ```

---

## Get Folder

```
GET /v2.0/databases/{db}/folders/{id}
```

Returns the **full representation** of a specific folder, including `comments` and the ancestor `path` for breadcrumb navigation. If the folder is protected by a second password, the `X-Second-Password` header is required.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `db` | string (UUID) | Yes | Database ID |
| `id` | string (UUID) | Yes | Folder unique identifier |

### Request Headers

| Header | Required | Description |
|--------|----------|-------------|
| `X-Second-Password` | Conditional | Base64-encoded. Required if the folder has a second password (`has_second_pass: true`) |

### Response

`200 OK`

```json
{
    "path": [
        {
            "id": "3BF225B7-48BC-4AA4-888D-605E61A0F2D4",
            "name": "Infrastructure"
        }
    ],
    "type": "folder",
    "id": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
    "name": "Servers",
    "icon": "ico3.svg",
    "importance": "normal",
    "category": "Infrastructure",
    "tags": "production,servers",
    "has_second_pass": false,
    "author": "admin",
    "image_custom": false,
    "image_index": 3,
    "image_name": "",
    "comments": "All production server credentials are stored here.",
    "updated_at": "2024-02-05T16:30:00.000Z"
}
```

### Error Responses

| Status | Description |
|--------|-------------|
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions (`error.code` `403`), or a missing/incorrect `X-Second-Password` on a protected folder (`error.code` `4031`) |
| `404 Not Found` | Database or folder not found |

### Example

=== "curl"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/folders/f1a2b3c4-d5e6-7890-abcd-ef1234567890" \
        -H "Authorization: Bearer <token>"
    ```

=== "curl (with second password)"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/folders/f1a2b3c4-d5e6-7890-abcd-ef1234567890" \
        -H "Authorization: Bearer <token>" \
        -H "X-Second-Password: $(echo -n 'mySecretPass' | base64)"
    ```

---

## Create Folder

```
POST /v2.0/databases/{db}/folders
POST /v2.0/databases/{db}/folders?parent={folder_id}
```

Creates a new folder within a database. Use the `parent` query parameter to place the folder inside an existing folder; omit it to create at root level.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `db` | string (UUID) | Yes | Database ID |

### Query Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `parent` | string (UUID) | No | Parent folder ID. Omit to create at root level. |

### Request Body

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `name` | string | Yes | Folder name |
| `importance` | string | No | `"low"`, `"normal"`, or `"high"` (default: `"normal"`) |
| `category` | string | No | Category label |
| `tags` | string | No | Tags (comma-separated) |
| `comments` | string | No | Folder comments/notes |

### Request Headers

| Header | Required | Description |
|--------|----------|-------------|
| `X-New-Second-Password` | No | Base64-encoded. Set a second password on the new folder |

```json
{
    "name": "Web Applications",
    "importance": "high",
    "category": "Web"
}
```

### Response

`201 Created`

Returns the compact representation of the created folder.

```json
{
    "type": "folder",
    "id": "f3c4d5e6-f7a8-9012-cdef-123456789012",
    "name": "Web Applications",
    "icon": "ico3.svg",
    "importance": "high",
    "category": "Web",
    "tags": "",
    "has_second_pass": false,
    "updated_at": "2024-02-17T09:00:00.000Z"
}
```

### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | Invalid or missing required fields |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions |
| `404 Not Found` | Database or parent folder not found |

### Example

=== "curl"

    ```bash
    curl -X POST "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/folders?parent=f1a2b3c4-d5e6-7890-abcd-ef1234567890" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "Web Applications",
            "importance": "high"
        }'
    ```

---

## Update Folder

```
PATCH /v2.0/databases/{db}/folders/{id}
```

Updates an existing folder. Include only the fields you want to update.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `db` | string (UUID) | Yes | Database ID |
| `id` | string (UUID) | Yes | Folder unique identifier |

### Request Headers

| Header | Required | Description |
|--------|----------|-------------|
| `X-Second-Password` | Conditional | Base64-encoded. Required **and verified** if the folder has a second password (`has_second_pass: true`); a wrong or missing value is rejected with `403` and `error.code` `4031` |
| `X-New-Second-Password` | No | Base64-encoded. Set or change the second password (when set, the correct current `X-Second-Password` must also be sent) |

### Request Body

```json
{
    "name": "Production Servers",
    "importance": "high",
    "comments": "Updated server credentials folder"
}
```

### Response

`200 OK`

Returns the compact representation of the updated folder.

```json
{
    "type": "folder",
    "id": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
    "name": "Production Servers",
    "icon": "ico3.svg",
    "importance": "high",
    "category": "Infrastructure",
    "tags": "production,servers",
    "has_second_pass": false,
    "updated_at": "2024-02-17T12:00:00.000Z"
}
```

### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | Invalid fields |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions (`error.code` `403`), or a missing/incorrect `X-Second-Password` on a protected folder (`error.code` `4031`) |
| `404 Not Found` | Database or folder not found |

### Example

=== "curl"

    ```bash
    curl -X PATCH "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/folders/f1a2b3c4-d5e6-7890-abcd-ef1234567890" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "Production Servers",
            "importance": "high"
        }'
    ```

---

## Delete Folder

```
DELETE /v2.0/databases/{db}/folders/{id}
```

Deletes a folder and all its contents (sub-folders and entries).

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `db` | string (UUID) | Yes | Database ID |
| `id` | string (UUID) | Yes | Folder unique identifier |

### Response

`204 No Content`

No response body.

### Error Responses

| Status | Description |
|--------|-------------|
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions |
| `404 Not Found` | Database or folder not found |

### Example

=== "curl"

    ```bash
    curl -X DELETE "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/folders/f1a2b3c4-d5e6-7890-abcd-ef1234567890" \
        -H "Authorization: Bearer <token>"
    ```

---

## Move Folder

```
POST /v2.0/databases/{db}/folders/{id}/move
```

Moves a folder to a different parent folder within the same database.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `db` | string (UUID) | Yes | Database ID |
| `id` | string (UUID) | Yes | Folder unique identifier |

### Request Body

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `target` | string (UUID) or null | Yes | Target parent folder ID. Set to `null` to move to root level. |

```json
{
    "target": "f2b3c4d5-e6f7-8901-bcde-f12345678901"
}
```

### Response

`200 OK`

Returns the compact representation of the moved folder.

```json
{
    "type": "folder",
    "id": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
    "name": "Servers",
    "icon": "ico3.svg",
    "importance": "normal",
    "category": "Infrastructure",
    "tags": "production,servers",
    "has_second_pass": false,
    "updated_at": "2024-02-17T15:00:00.000Z"
}
```

### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | Invalid target folder or circular reference (cannot move a folder into itself or its descendants) |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions |
| `404 Not Found` | Database, folder, or target folder not found |

### Example

=== "curl"

    ```bash
    curl -X POST "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/folders/f1a2b3c4-d5e6-7890-abcd-ef1234567890/move" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -d '{
            "target": "f2b3c4d5-e6f7-8901-bcde-f12345678901"
        }'
    ```

=== "curl (move to root)"

    ```bash
    curl -X POST "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/folders/f1a2b3c4-d5e6-7890-abcd-ef1234567890/move" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -d '{
            "target": null
        }'
    ```
