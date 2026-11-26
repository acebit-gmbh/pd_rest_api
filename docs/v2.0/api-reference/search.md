# Search

Search for entries and folders within a database on the Password Depot Enterprise Server.

---

## Search Items

```
GET /v2.0/databases/{db}/search
```

Searches for entries and folders matching the given query within a database. The query is split into words at white space, and an item matches when it holds every word, in any order and with other text between them. Each word is looked for, without regard to letter case, in the item's name, login, URL, additional URLs (`urls`), comments and tags, and different words may be found in different fields: `Test Device` and `device test` both find an entry named "Test One Device", `Test Devices` does not. A word given more than once counts once, and only the first 16 different words of `q` count: further words are ignored. A link matches on the login of the entry it points to only where you may read that entry (see [Link Targets](entries.md#link-targets)). Results are returned as a paginated list of compact representations, each with the `path` of the folders it lies in.

An app that fills in sign-ins can search for the domain of a site: `q=squareup.com` finds an entry whose additional URL is `*squareup.com*`, and the entry's `urls` come with the result, so that the app can match the site against them without reading the entry.

When a `folder` parameter is provided, the search is scoped to that folder and its subfolders (recursive).

### Parameters

| Parameter | In | Type | Required | Description |
|-----------|-----|------|----------|-------------|
| `db` | path | string (UUID) | Yes | Database ID |
| `q` | query | string | Yes | Search words, separated by white space: an item matches when it holds every word (each a case-insensitive substring match). A repeated word counts once; only the first 16 different words count. Minimum 3 characters for the whole query; a query of white space only finds nothing |
| `folder` | query | string (UUID) | No | Restrict search to a specific folder and its subfolders |
| `offset` | query | integer | No | Pagination offset (default: `0`) |
| `limit` | query | integer | No | Pagination limit (default: `100`) |

### Response

`200 OK`

Returns a paginated list of matching items. Each item is a **compact representation** — folders use the [Folder compact representation](folders.md#compact-representation) and entries use the [Entry compact representation](entries.md#compact-representation). Use the `type` field to distinguish between them.

Each item also carries `path`: the folders it lies in, nearest first, as `{"id", "name"}` objects, and `[]` for an item at the top of the database (see [Path / Breadcrumb](folders.md#path-breadcrumb)). A search below a folder still names every folder up to the top of the database.

```json
{
    "data": [
        {
            "type": "folder",
            "id": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
            "name": "Production Servers",
            "icon": "ico3.svg",
            "database_icon": null,
            "importance": "normal",
            "category": "Infrastructure",
            "tags": "production,servers",
            "has_second_pass": false,
            "updated_at": "2024-02-05T16:30:00.000Z",
            "entry_count": 8,
            "folder_count": 2,
            "path": []
        },
        {
            "type": "password",
            "id": "e1a2b3c4-d5e6-7890-abcd-ef1234567890",
            "name": "Production Database",
            "has_second_pass": false,
            "has_otp": false,
            "totp": {
              "state": "none"
            },
            "warning": null,
            "login": "admin",
            "url": "https://db.example.com",
            "urls": ["https://db-backup.example.com"],
            "icon": "ico0.svg",
            "database_icon": {
                "id": "3",
                "name": "db.example.com",
                "version": "9c1e5f2a-10f4-2b1"
            },
            "importance": "high",
            "category": "Databases",
            "tags": "production,database",
            "updated_at": "2024-11-20T16:45:00.000Z",
            "expires_at": "2025-06-01T00:00:00.000Z",
            "path": [
                { "id": "f1a2b3c4-d5e6-7890-abcd-ef1234567890", "name": "Production Servers" }
            ]
        }
    ],
    "total": 2,
    "offset": 0,
    "limit": 100
}
```

!!! info "Icons"
    The second item uses a [database icon](icons.md): `database_icon` names it, and `icon` is the standard icon of the item's type, to be shown as the fallback. Fetch the images of a result page in one call with [List Icons](icons.md#list-icons) (`ids` and `include=data`). Servers older than 20.0.0 do not send `database_icon`.

!!! info "Feature test"
    `path` on a result tells a client that the server matches every word of `q` and searches the additional URLs. Servers older than 20.0.0 send no `path` with a result, match `q` as one text and do not search the additional URLs; they send `urls` in the full representation only.

!!! info
    Search results use compact representations only. Sensitive fields such as `pass`, `comments`, and `custom_fields` are **not** included. Use the [Get Entry](entries.md#get-entry) or [Get Folder](folders.md#get-folder) endpoint to retrieve the full representation.

!!! note "Encrypted-file and certificate entries"
    Server 20.0.0 includes accessible `encrypted_file` and `certificate` entries in search, with the same compact representation used by [List Children](folders.md#list-children-navigation). Their `has_otp` is always `false`; use [Get Entry](entries.md#get-entry) for their type-specific fields. Existing policies, permissions and recycle-bin filtering still determine visibility, counts and pagination. Server 19.x excludes these types.

### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | Missing or too short `q` parameter (minimum 3 characters) |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions to access this database |
| `404 Not Found` | Database or folder not found |
| `503 Service Unavailable` | *Server 20.0.0 and later.* The database is not available at the moment (see [Databases Not Available at the Moment](databases.md#databases-not-available-at-the-moment)). Try again later |

### Example

=== "curl"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/search?q=production" \
        -H "Authorization: Bearer <token>"
    ```

=== "curl (several words)"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/search?q=production%20database" \
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
