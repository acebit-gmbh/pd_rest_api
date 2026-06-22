# Permissions

Full CRUD reference for managing access permissions on databases in the Password Depot Enterprise Server. All permissions endpoints are under `/admin/` and require an **admin-scoped session** (`"scope": "admin"` at login).

Permissions control which users and groups can access a database and what operations they can perform. Each permission rule is scoped to a single database and a single **principal** (a user or a group). A permission defines:

- **Database-level rights** (`allow` / `deny`) -- what the principal can do on the database as a whole.
- **Entry-level overrides** (`entry_allow` / `entry_deny`) -- per-entry/folder rights that override the database-level defaults. This allows granting or restricting access to individual entries (e.g., sharing a single password with a user).

Multiple permission rules can exist for the same principal on the same database, with different validity periods or different entry-level scopes.

---

## Permission Object

The permission object uses different representations depending on context:

- **List** responses return a **compact representation**: `id`, `principal_id`, `issuer_id`, `valid_from`, `valid_until`, `allow`, `deny`.
- **Detail** responses (`GET .../permissions/{id}`) and mutation responses return the **full representation** with all fields, including entry-level overrides and seal workflow.

### Compact Representation

| Field | Type | Description |
|-------|------|-------------|
| `id` | string (UUID) | Unique identifier (read-only) |
| `principal_id` | string (UUID) | User or group ID this permission applies to |
| `issuer_id` | string (UUID) | User ID who created this permission (read-only) |
| `valid_from` | string (ISO 8601) or null | Permission is active from this date (`null` = no start restriction) |
| `valid_until` | string (ISO 8601) or null | Permission expires at this date (`null` = no expiration) |
| `allow` | array of strings | Allowed rights at the database level (see [Rights Values](#rights-values)) |
| `deny` | array of strings | Denied rights at the database level |

### Full Representation

Includes all compact fields plus:

| Field | Type | Writable | Description |
|-------|------|:--------:|-------------|
| `entry_allow` | array of objects | Yes | Per-entry/folder allow overrides (see [Entry Rights](#entry-level-rights)) |
| `entry_deny` | array of objects | Yes | Per-entry/folder deny overrides |
| `seal_status` | integer | Yes | Seal workflow status (see [Seal Status](#seal-status)) |
| `approver_ids` | array of UUIDs | Yes | User IDs designated as seal approvers |

### Rights Values

Rights are represented as a JSON array of string tokens. The effective rights are computed as `allow AND NOT deny` -- a right present in both `allow` and `deny` is denied.

| Value | Description |
|-------|-------------|
| `use` | Access the database (required for any other operation) |
| `read` | Read entries and folders |
| `update` | Modify existing entries and folders |
| `create` | Create new entries and folders |
| `delete` | Delete entries and folders |
| `print` | Print entries |
| `export` | Export the database |
| `save` | Save the database locally (Save As) |
| `auto_complete` | Use browser auto-complete |
| `addon_fill` | Use browser add-on auto-fill |
| `addon_offer` | Allow add-on to offer to save passwords |
| `sync` | Synchronize the database |
| `share` | Share entries via shared secrets |
| `seal` | Manage seal protection on entries |
| `second_pass` | Access entries protected by a second password |

**Example:**

```json
"allow": ["use", "read", "update", "create", "delete", "share"],
"deny": ["export", "print"]
```

### Entry-Level Rights

Entry-level overrides allow granting or restricting specific rights on individual entries or folders. Each element specifies the entry/folder `id` and its rights array:

```json
"entry_allow": [
    {
        "id": "D4FEC05E-7866-4424-A998-4D96FF8B183E",
        "rights": ["use", "read"]
    },
    {
        "id": "1CA4DF0E-2E59-4735-8FD7-3DF7DF43C638",
        "rights": ["use", "read", "update", "share"]
    }
]
```

Entry-level rights are typically used when a user should have limited database-level access but needs specific rights on certain entries (e.g., a user with no database-level `read` but with `read` on a shared entry).

### Seal Status

The seal mechanism provides an additional layer of approval for sensitive entries.

| Value | Name | Description |
|-------|------|-------------|
| `0` | Unset | No seal (default) |
| `1` | Set | Seal is active |
| `2` | Waiting | Seal approval is pending |
| `3` | Approved | Seal has been approved |
| `4` | Broken | Seal has been broken/violated |

### Authorization

Permission management requires one of:

- **Server Administrator** -- full access to all permissions on all databases
- **Database Administrator** -- full access to permissions on databases they administer
- **Permission Issuer** -- can update or delete permissions they created (requires `share` right on referenced entries)

---

## List Permissions

```
GET /v2.0/admin/databases/{db}/permissions
```

Returns a paginated list of all permissions for a database. Returns the compact representation.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `db` | string (UUID) | Yes | Database ID |

### Query Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `offset` | integer | No | Pagination offset (default: `0`) |
| `limit` | integer | No | Pagination limit (default: `100`) |

### Response

`200 OK`

```json
{
    "data": [
        {
            "id": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
            "principal_id": "3FA85F64-5717-4562-B3FC-2C963F66AFA6",
            "issuer_id": "00000000-0000-0000-0000-000000000001",
            "valid_from": null,
            "valid_until": null,
            "allow": ["use", "read", "update", "create", "delete", "auto_complete", "addon_fill", "addon_offer", "print", "export", "save", "sync", "share"],
            "deny": []
        },
        {
            "id": "B2C3D4E5-F6A7-8901-BCDE-F12345678901",
            "principal_id": "7FB95F64-8828-4562-C4GD-3D074G77BGB7",
            "issuer_id": "3FA85F64-5717-4562-B3FC-2C963F66AFA6",
            "valid_from": "2026-01-01T00:00:00.000Z",
            "valid_until": "2026-12-31T23:59:59.000Z",
            "allow": ["use", "read"],
            "deny": ["export", "print"]
        }
    ],
    "total": 2,
    "offset": 0,
    "limit": 100
}
```

### Error Responses

| Status | Description |
|--------|-------------|
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions to manage this database |
| `404 Not Found` | Database not found |

### Example

=== "curl"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/admin/databases/E79BDEB2-1A58-4715-B74C-28A87A2AFD37/permissions" \
        -H "Authorization: Bearer <token>"
    ```

---

## Create Permission

```
POST /v2.0/admin/databases/{db}/permissions
```

Creates a new permission rule for a database. The caller must have `use` access on the database or be a Database Administrator / Server Administrator.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `db` | string (UUID) | Yes | Database ID |

### Request Body

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `principal_id` | string (UUID) | Yes | User or group ID this permission applies to |
| `allow` | array of strings | No | Allowed rights (default: empty) |
| `deny` | array of strings | No | Denied rights (default: empty) |
| `valid_from` | string (ISO 8601) or null | No | Start date |
| `valid_until` | string (ISO 8601) or null | No | Expiry date |
| `entry_allow` | array of objects | No | Per-entry allow overrides |
| `entry_deny` | array of objects | No | Per-entry deny overrides |
| `seal_status` | integer | No | Seal status (default: `0`) |
| `approver_ids` | array of UUIDs | No | Seal approver IDs |

!!! note
    The `issuer_id` is automatically set to the authenticated user and cannot be overridden.

```json
{
    "principal_id": "3FA85F64-5717-4562-B3FC-2C963F66AFA6",
    "allow": ["use", "read", "update", "create", "delete", "share"],
    "deny": ["export", "print"],
    "valid_until": "2026-12-31T23:59:59.000Z",
    "entry_allow": [
        {
            "id": "D4FEC05E-7866-4424-A998-4D96FF8B183E",
            "rights": ["use", "read", "update", "share"]
        }
    ]
}
```

### Response

`201 Created`

Returns the full representation of the created permission.

```json
{
    "id": "C3D4E5F6-A7B8-9012-CDEF-123456789012",
    "principal_id": "3FA85F64-5717-4562-B3FC-2C963F66AFA6",
    "issuer_id": "00000000-0000-0000-0000-000000000001",
    "valid_from": null,
    "valid_until": "2026-12-31T23:59:59.000Z",
    "allow": ["use", "read", "update", "create", "delete", "share"],
    "deny": ["export", "print"],
    "entry_allow": [
        {
            "id": "D4FEC05E-7866-4424-A998-4D96FF8B183E",
            "rights": ["use", "read", "update", "share"]
        }
    ],
    "entry_deny": [],
    "seal_status": 0,
    "approver_ids": []
}
```

### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | Invalid or missing required fields |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions (no `use` access on database, or no `share` right on referenced entries) |
| `404 Not Found` | Database, user/group, or referenced entry not found |

### Example

=== "curl"

    ```bash
    curl -X POST "https://<server>:8714/v2.0/admin/databases/E79BDEB2-1A58-4715-B74C-28A87A2AFD37/permissions" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -d '{
            "principal_id": "3FA85F64-5717-4562-B3FC-2C963F66AFA6",
            "allow": ["use", "read", "update", "create", "delete", "share"],
            "deny": ["export", "print"]
        }'
    ```

---

## Get Permission

```
GET /v2.0/admin/databases/{db}/permissions/{id}
```

Returns the **full representation** of a specific permission, including entry-level overrides and seal status.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `db` | string (UUID) | Yes | Database ID |
| `id` | string (UUID) | Yes | Permission unique identifier |

### Response

`200 OK`

```json
{
    "id": "C3D4E5F6-A7B8-9012-CDEF-123456789012",
    "principal_id": "3FA85F64-5717-4562-B3FC-2C963F66AFA6",
    "issuer_id": "00000000-0000-0000-0000-000000000001",
    "valid_from": null,
    "valid_until": "2026-12-31T23:59:59.000Z",
    "allow": ["use", "read", "update", "create", "delete", "share"],
    "deny": ["export", "print"],
    "entry_allow": [
        {
            "id": "D4FEC05E-7866-4424-A998-4D96FF8B183E",
            "rights": ["use", "read", "update", "share"]
        }
    ],
    "entry_deny": [],
    "seal_status": 0,
    "approver_ids": []
}
```

### Error Responses

| Status | Description |
|--------|-------------|
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions to manage this database |
| `404 Not Found` | Database or permission not found |

### Example

=== "curl"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/admin/databases/E79BDEB2-1A58-4715-B74C-28A87A2AFD37/permissions/C3D4E5F6-A7B8-9012-CDEF-123456789012" \
        -H "Authorization: Bearer <token>"
    ```

---

## Update Permission

```
PATCH /v2.0/admin/databases/{db}/permissions/{id}
```

Updates an existing permission. Include only the fields you want to update. The caller must be the permission's issuer, a designated seal approver, or a Database/Server Administrator.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `db` | string (UUID) | Yes | Database ID |
| `id` | string (UUID) | Yes | Permission unique identifier |

### Request Body

```json
{
    "allow": ["use", "read"],
    "deny": [],
    "valid_until": "2027-06-30T23:59:59.000Z",
    "entry_allow": [
        {
            "id": "D4FEC05E-7866-4424-A998-4D96FF8B183E",
            "rights": ["use", "read"]
        }
    ]
}
```

### Response

`200 OK`

Returns the full representation of the updated permission.

```json
{
    "id": "C3D4E5F6-A7B8-9012-CDEF-123456789012",
    "principal_id": "3FA85F64-5717-4562-B3FC-2C963F66AFA6",
    "issuer_id": "00000000-0000-0000-0000-000000000001",
    "valid_from": null,
    "valid_until": "2027-06-30T23:59:59.000Z",
    "allow": ["use", "read"],
    "deny": [],
    "entry_allow": [
        {
            "id": "D4FEC05E-7866-4424-A998-4D96FF8B183E",
            "rights": ["use", "read"]
        }
    ],
    "entry_deny": [],
    "seal_status": 0,
    "approver_ids": []
}
```

### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | Invalid fields |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Not the issuer/approver and not a DB manager, or no `share` right on referenced entries |
| `404 Not Found` | Database, permission, or referenced entry not found |

### Example

=== "curl"

    ```bash
    curl -X PATCH "https://<server>:8714/v2.0/admin/databases/E79BDEB2-1A58-4715-B74C-28A87A2AFD37/permissions/C3D4E5F6-A7B8-9012-CDEF-123456789012" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -d '{
            "allow": ["use", "read"],
            "valid_until": "2027-06-30T23:59:59.000Z"
        }'
    ```

---

## Delete Permission

```
DELETE /v2.0/admin/databases/{db}/permissions/{id}
```

Deletes a permission rule. The caller must be the permission's issuer or a Database/Server Administrator.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `db` | string (UUID) | Yes | Database ID |
| `id` | string (UUID) | Yes | Permission unique identifier |

### Response

`204 No Content`

No response body.

### Error Responses

| Status | Description |
|--------|-------------|
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Not the issuer and not a DB manager |
| `404 Not Found` | Database or permission not found |

### Example

=== "curl"

    ```bash
    curl -X DELETE "https://<server>:8714/v2.0/admin/databases/E79BDEB2-1A58-4715-B74C-28A87A2AFD37/permissions/C3D4E5F6-A7B8-9012-CDEF-123456789012" \
        -H "Authorization: Bearer <token>"
    ```
