# Search

Search for entries and folders within a database on the Password Depot Enterprise Server.

---

## Search Items

```
GET /v2.0/databases/{db}/search
```

Searches for entries and folders matching the given query within a database. The search matches against the item name, login, URL, comments, and tags. Results are returned as a paginated list of compact representations.

When a `folder` parameter is provided, the search is scoped to that folder and its subfolders (recursive).

### Parameters

| Parameter | In | Type | Required | Description |
|-----------|-----|------|----------|-------------|
| `db` | path | string (UUID) | Yes | Database ID |
| `q` | query | string | Yes | Search term (case-insensitive substring match, minimum 3 characters) |
| `folder` | query | string (UUID) | No | Restrict search to a specific folder and its subfolders |
| `offset` | query | integer | No | Pagination offset (default: `0`) |
| `limit` | query | integer | No | Pagination limit (default: `100`) |

### Response

`200 OK`

Returns a paginated list of matching items. Each item is a **compact representation** — folders use the [Folder compact representation](folders.md#compact-representation) and entries use the [Entry compact representation](entries.md#compact-representation). Use the `type` field to distinguish between them.

```json
{
    "data": [
        {
            "type": "folder",
            "id": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
            "name": "Production Servers",
            "icon": "ico3.svg",
            "importance": "normal",
            "category": "Infrastructure",
            "tags": "production,servers",
            "has_second_pass": false,
            "updated_at": "2024-02-05T16:30:00.000Z"
        },
        {
            "type": "password",
            "id": "e1a2b3c4-d5e6-7890-abcd-ef1234567890",
            "name": "Production Database",
            "has_second_pass": false,
            "login": "admin",
            "url": "https://db.example.com",
            "icon": "ico5.svg",
            "importance": "high",
            "category": "Databases",
            "tags": "production,database",
            "updated_at": "2024-11-20T16:45:00.000Z",
            "expires_at": "2025-06-01T00:00:00.000Z"
        }
    ],
    "total": 2,
    "offset": 0,
    "limit": 100
}
```

!!! info
    Search results use compact representations only. Sensitive fields such as `pass`, `comments`, and `custom_fields` are **not** included. Use the [Get Entry](entries.md#get-entry) or [Get Folder](folders.md#get-folder) endpoint to retrieve the full representation.

!!! note "Unsupported entry types are excluded"
    Search results exclude entries of desktop-only types that are not supported by the REST/web surface — specifically `encrypted_file` and `certificate`. This matches the behavior of [List Children](folders.md#list-children-navigation), which already excludes them. The `data` array, the `total` count, and pagination all reflect the filtered set. (Such entries previously appeared in results but returned `501 Not Implemented` when opened.)

### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | Missing or too short `q` parameter (minimum 3 characters) |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions to access this database |
| `404 Not Found` | Database or folder not found |

### Example

=== "curl"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/search?q=production" \
        -H "Authorization: Bearer <token>"
    ```

=== "curl (with folder filter)"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/search?q=production&folder=f1a2b3c4-d5e6-7890-abcd-ef1234567890" \
        -H "Authorization: Bearer <token>"
    ```

=== "curl (with pagination)"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/search?q=admin&offset=0&limit=10" \
        -H "Authorization: Bearer <token>"
    ```
