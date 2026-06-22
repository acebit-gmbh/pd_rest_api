# Alerts

Full CRUD reference for server-wide alert management on the Password Depot Enterprise Server. All alert management endpoints are under `/admin/` and require an **admin-scoped session** (`"scope": "admin"` at login). Only **Server Administrators** can create, modify, or delete alerts.

Alerts are server-side notification rules that trigger email notifications when specific events occur (e.g., failed logins, password changes, database modifications). Each alert monitors a specific event type and can optionally be scoped to specific databases, users, or entries.

---

## Alert Object

The alert object uses different representations depending on context:

- **List** responses return a **compact representation**: `id`, `name`, `type`, `notes`, `updated_at`.
- **Detail** responses (`GET /v2.0/admin/alerts/{id}`) and mutation responses return the **full representation** with all fields, including recipients and scope filters.

### Compact Representation

| Field | Type | Description |
|-------|------|-------------|
| `id` | string (UUID) | Unique identifier (read-only) |
| `name` | string | Alert display name (auto-generated from type, can be overridden) |
| `type` | string | Alert event type (see [Alert Types](#alert-types)) |
| `notes` | string | Free-text note included in notification emails |
| `updated_at` | string (ISO 8601) | Last modification timestamp (read-only) |

### Full Representation

Includes all compact fields plus:

| Field | Type | Writable | Description |
|-------|------|:--------:|-------------|
| `recipients` | array of **email** strings | Yes | Bare email addresses that will receive notification when the alert triggers. Each entry must be a valid `local@domain.tld` address -- URLs, `mailto:` schemes, and empty strings are rejected with 400. |
| `filter_by_databases` | boolean | Yes | If `true`, restrict this alert to the databases listed in `database_ids` |
| `database_ids` | array of UUIDs | Yes | Database IDs this alert is scoped to (only used when `filter_by_databases` is `true`). Each entry must be a valid UUID (`XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX`); non-UUID strings are rejected with 400. |
| `filter_by_users` | boolean | Yes | If `true`, restrict this alert to the users listed in `user_ids` |
| `user_ids` | array of UUIDs | Yes | User IDs this alert is scoped to (only used when `filter_by_users` is `true`). Each entry must be a valid UUID. |
| `filter_by_entries` | boolean | Yes | If `true`, restrict this alert to the entries listed in `entry_ids` |
| `entry_ids` | array of UUIDs | Yes | Entry IDs this alert is scoped to (only used when `filter_by_entries` is `true`). Each entry must be a valid UUID. |

!!! tip "Scope Filters"
    The `filter_by_*` booleans act as toggles. When `false`, the corresponding `*_ids` array is ignored and the alert applies to **all** items of that type. This allows you to configure a list of databases/users/entries and temporarily disable the filter without losing the selection.

!!! note "Input validation"
    All array fields are validated per-element on create and update. A single invalid entry causes the entire request to fail with `400 Bad Request` and an error message naming the bad value. The ID existence is **not** verified -- only the syntactic form is checked. Filters pointing at UUIDs of deleted resources match no items (same as an empty array).

### Alert Types

| Value | Description |
|-------|-------------|
| `login_failed_admin` | Failed admin login attempt |
| `login_failed_client` | Failed client login attempt |
| `login_admin` | Successful admin login |
| `login_client` | Successful client login |
| `server_policy_modified` | Server password policy was modified |
| `server_options_modified` | Server options were modified |
| `database_added` | A new database was added |
| `database_deleted` | A database was deleted |
| `database_modified` | A database was modified |
| `database_exported` | A database was exported/sent |
| `database_size_changed` | A database size changed significantly |
| `user_added` | A new user was added |
| `user_deleted` | A user was deleted |
| `user_modified` | A user was modified |
| `user_disabled` | A user account was disabled |
| `group_added` | A new group was added |
| `group_deleted` | A group was deleted |
| `group_modified` | A group was modified |
| `alert_added` | A new alert was added |
| `alert_deleted` | An alert was deleted |
| `alert_modified` | An alert was modified |
| `password_added` | A new password entry was added |
| `password_deleted` | A password entry was deleted |
| `password_modified` | A password entry was modified |
| `password_accessed` | A password was accessed/viewed |
| `folder_added` | A new folder was added |
| `folder_deleted` | A folder was deleted |
| `folder_modified` | A folder was modified |
| `entry_expires` | An entry is about to expire |
| `bulk_delete` | Multiple items were deleted at once |
| `backup_created` | A server backup was created |
| `permission_added` | A permission rule was added |
| `permission_modified` | A permission rule was modified |
| `permission_deleted` | A permission rule was deleted |
| `shared_secret_created` | A shared secret was created |
| `shared_secret_updated` | A shared secret was updated |
| `shared_secret_deleted` | A shared secret was deleted |
| `shared_secret_approved` | A shared secret was approved |
| `shared_secret_rejected` | A shared secret was rejected |
| `shared_secret_accessed` | A shared secret was accessed |

---

## List Alerts

```
GET /v2.0/admin/alerts
```

Returns a paginated list of all alerts. Returns the compact representation -- use [Get Alert](#get-alert) to retrieve the full representation for a specific alert.

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
            "id": "0E760C33-C297-40F9-986C-109F9462EFC5",
            "name": "A000001",
            "type": "login_failed_admin",
            "notes": "Notify security team on failed admin logins",
            "updated_at": "2026-01-16T12:33:02.357Z"
        },
        {
            "id": "FA141E2E-6BCA-40CC-A75B-6A13D8833A97",
            "name": "A1F0002",
            "type": "permission_added",
            "notes": "Track permission changes",
            "updated_at": "2022-11-01T11:38:31.889Z"
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
| `403 Forbidden` | Session does not have admin scope |

### Example

=== "curl"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/admin/alerts?offset=0&limit=100" \
        -H "Authorization: Bearer <token>"
    ```

---

## Create Alert

```
POST /v2.0/admin/alerts
```

Creates a new alert. Requires Server Administrator role.

### Request Body

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `name` | string | No | Alert display name (auto-generated from type if omitted) |
| `type` | string | Yes | Alert event type (see [Alert Types](#alert-types)) |
| `notes` | string | No | Free-text note included in notification emails |
| `recipients` | array of emails | No | Bare email addresses to notify. Each element must match `local@domain.tld`; see [Input validation](#full-representation). |
| `filter_by_databases` | boolean | No | Restrict to specific databases (default: `false`) |
| `database_ids` | array of UUIDs | No | Database IDs to scope to (UUIDs only). |
| `filter_by_users` | boolean | No | Restrict to specific users (default: `false`) |
| `user_ids` | array of UUIDs | No | User IDs to scope to (UUIDs only). |
| `filter_by_entries` | boolean | No | Restrict to specific entries (default: `false`) |
| `entry_ids` | array of UUIDs | No | Entry IDs to scope to (UUIDs only). |

```json
{
    "type": "entry_expires",
    "notes": "Remind team about expiring credentials",
    "recipients": ["admin@example.com", "security@example.com"],
    "filter_by_databases": true,
    "database_ids": ["E79BDEB2-1A58-4715-B74C-28A87A2AFD37"]
}
```

### Response

`201 Created`

Returns the full representation of the created alert.

```json
{
    "id": "al1a2b3c-d5e6-7890-abcd-ef1234567890",
    "name": "Entry expires",
    "type": "entry_expires",
    "notes": "Remind team about expiring credentials",
    "recipients": ["admin@example.com", "security@example.com"],
    "filter_by_databases": true,
    "database_ids": ["E79BDEB2-1A58-4715-B74C-28A87A2AFD37"],
    "filter_by_users": false,
    "user_ids": [],
    "filter_by_entries": false,
    "entry_ids": [],
    "updated_at": "2025-03-18T10:00:00.000Z"
}
```

### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | Invalid or missing required fields |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions (requires Server Administrator role) |

### Example

=== "curl"

    ```bash
    curl -X POST "https://<server>:8714/v2.0/admin/alerts" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -d '{
            "type": "entry_expires",
            "notes": "Remind team about expiring credentials",
            "recipients": ["admin@example.com"],
            "filter_by_databases": true,
            "database_ids": ["E79BDEB2-1A58-4715-B74C-28A87A2AFD37"]
        }'
    ```

---

## Get Alert

```
GET /v2.0/admin/alerts/{id}
```

Returns the **full representation** of a specific alert, including recipients and scope filters.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string (UUID) | Yes | Alert unique identifier |

### Response

`200 OK`

```json
{
    "id": "0E760C33-C297-40F9-986C-109F9462EFC5",
    "name": "A000001",
    "type": "login_failed_admin",
    "notes": "Notify security team on failed admin logins",
    "recipients": ["admin@example.com", "security@example.com"],
    "filter_by_databases": false,
    "database_ids": [],
    "filter_by_users": true,
    "user_ids": ["3FA85F64-5717-4562-B3FC-2C963F66AFA6"],
    "filter_by_entries": false,
    "entry_ids": [],
    "updated_at": "2026-01-16T12:33:02.357Z"
}
```

### Error Responses

| Status | Description |
|--------|-------------|
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Session does not have admin scope |
| `404 Not Found` | Alert not found |

### Example

=== "curl"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/admin/alerts/0E760C33-C297-40F9-986C-109F9462EFC5" \
        -H "Authorization: Bearer <token>"
    ```

---

## Update Alert

```
PATCH /v2.0/admin/alerts/{id}
```

Updates an existing alert. Include only the fields you want to update. Requires Server Administrator role.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string (UUID) | Yes | Alert unique identifier |

### Request Body

```json
{
    "name": "Critical Login Alert",
    "notes": "Updated: now includes ops team notification",
    "recipients": ["admin@example.com", "security@example.com", "ops@example.com"]
}
```

### Response

`200 OK`

Returns the full representation of the updated alert.

```json
{
    "id": "0E760C33-C297-40F9-986C-109F9462EFC5",
    "name": "Critical Login Alert",
    "type": "login_failed_admin",
    "notes": "Updated: now includes ops team notification",
    "recipients": ["admin@example.com", "security@example.com", "ops@example.com"],
    "filter_by_databases": false,
    "database_ids": [],
    "filter_by_users": true,
    "user_ids": ["3FA85F64-5717-4562-B3FC-2C963F66AFA6"],
    "filter_by_entries": false,
    "entry_ids": [],
    "updated_at": "2026-03-18T11:30:00.000Z"
}
```

!!! note
    The `database_ids` array is preserved even when `filter_by_databases` is set to `false`. The IDs are simply not used for filtering until the toggle is re-enabled.

### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | Invalid fields |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions (requires Server Administrator role) |
| `404 Not Found` | Alert not found |

### Example

=== "curl"

    ```bash
    curl -X PATCH "https://<server>:8714/v2.0/admin/alerts/0E760C33-C297-40F9-986C-109F9462EFC5" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "Critical Login Alert",
            "notes": "Updated: now includes ops team notification",
            "recipients": ["admin@example.com", "security@example.com", "ops@example.com"]
        }'
    ```

---

## Delete Alert

```
DELETE /v2.0/admin/alerts/{id}
```

Deletes an alert. Requires Server Administrator role.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string (UUID) | Yes | Alert unique identifier |

### Response

`204 No Content`

No response body.

### Error Responses

| Status | Description |
|--------|-------------|
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions (requires Server Administrator role) |
| `404 Not Found` | Alert not found |

### Example

=== "curl"

    ```bash
    curl -X DELETE "https://<server>:8714/v2.0/admin/alerts/0E760C33-C297-40F9-986C-109F9462EFC5" \
        -H "Authorization: Bearer <token>"
    ```
