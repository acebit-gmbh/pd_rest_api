# Permissions

Full CRUD reference for managing access permissions on databases in the Password Depot Enterprise Server. All permissions endpoints are under `/admin/` and require an **admin-scoped session** (`"scope": "admin"` at login).

!!! note "Server 20.0.0 and later"
    This page describes Server 20.0.0 and later. What changed is listed under [Administration and Permissions](../changelog.md#administration-and-permissions) in the changelog.

Permissions control which users and groups can access a database and what operations they can perform. Each permission is scoped to a single database and a single **principal** (a user or a group). A permission defines:

- **Database-level rights** (`allow`) -- whether the database opens for the principal, and what the principal can do on the database as a whole.
- **Entry-level rights** (`entry_allow`) -- rights on individual entries and folders, for example to give a user access to a single password.

Multiple permissions can exist for the same principal on the same database, with different validity periods or different entries and folders. A permission only gives rights: what a principal holds is the sum of what the permissions of the principal and of its groups give, and a right given on a folder reaches everything below it. A folder or entry that has its own permissions takes nothing from the folders above it; the `own_permissions` member of an `entry_allow` element says where. To narrow what someone holds, remove the right, or give the object its own permissions in the Server Manager.

---

## Permission Object

The permission object uses different representations depending on context:

- **List** responses return a **compact representation**: `id`, `principal_id`, `issuer_id`, `valid_from`, `valid_until`.
- **Detail** responses (`GET .../permissions/{id}`) and mutation responses return the **full representation** with all fields, including the rights, entry-level rights and seal workflow.

### Compact Representation

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique identifier (read-only). Treat it as an opaque string: it is the permission's id, or the id of its record where the permission was written in the Server Manager, and it is not always a UUID |
| `principal_id` | string (UUID) | User or group ID this permission applies to |
| `issuer_id` | string (UUID) | User ID who created this permission (read-only); empty when the permission names no issuer |
| `valid_from` | string (ISO 8601) or null | Permission is active from this date (`null` = no start restriction). Where the parts of a permission differ, the latest start |
| `valid_until` | string (ISO 8601) or null | Permission expires at this date (`null` = no expiration). Where the parts of a permission differ, the earliest end |

### Full Representation

Includes all compact fields plus:

| Field | Type | Writable | Description |
|-------|------|:--------:|-------------|
| `allow` | array of strings | Yes | Rights at the database level (see [Rights Values](#rights-values)) |
| `deny` | array of strings | No | Always empty. A request that names a right here is [refused](#refused-requests) |
| `entry_allow` | array of objects | Yes | Rights on entries and folders (see [Entry Rights](#entry-level-rights)) |
| `entry_deny` | array of objects | No | Always empty. A request that names a right here is [refused](#refused-requests) |
| `seal_status` | integer | Yes | Seal workflow status (see [Seal Status](#seal-status)). A seal applies to the entries and folders in `entry_allow`, never to `allow` |
| `approver_ids` | array of UUIDs | Yes | User IDs designated as seal approvers |
| `level` | string or null | No | The level this permission gives on the database: `view`, `use`, `read` or `edit`; `null` where it gives no level there |
| `caps` | array of strings | No | The capabilities this permission gives on the database: `create`, `delete`, `share`, `protect` (the right `second_pass`), `seal`, and `manage` and `own`, which are no tokens of `allow` |
| `origin` | string or null | No | How the permission came about: `manual` (written by an administrator), `conversion` (carried over when the database was converted to the new format), `provisioning` (written by directory provisioning) or `client` (issued by a user who holds no server role and does not manage the database) |

`level`, `caps` and `origin` are ignored in a request, and empty `deny` and `entry_deny` lists are accepted, so a permission read with [Get Permission](#get-permission) can be sent back as it is.

### Rights Values

Rights are represented as a JSON array of string tokens. The same tokens are used in `allow` and in the `rights` of an `entry_allow` element, but `use` does not mean the same in both.

| Value | Needs | In `allow` | In `entry_allow` |
|-------|-------|------------|------------------|
| `use` | | The database is in the principal's list and opens. No entry or folder is reached through it | The entry or folder can be used, for example to sign in, without its secret being shown |
| `read` | `use` | Read every entry and folder of the database | Read the entry or folder |
| `update` | `read` | Modify existing entries and folders | Modify the entry or folder |
| `create` | `use` | Create new entries and folders | Create new entries and folders in the folder |
| `delete` | `use` | Delete entries and folders | Delete the entry or folder |
| `share` | `read` | Create shared secrets for entries | Create shared secrets for the entry, or for the entries in the folder |
| `second_pass` | `update` | Access entries protected by a second password | Access the entry or folder protected by a second password |
| `seal` | `share` | Manage seal protection on entries | Manage seal protection on the entry or folder |

In `allow`, `use` can stand alone, with or without `entry_allow`: the principal then reaches exactly what `entry_allow` gives. Every other right in `allow` needs `read` as well: `use` with a right such as `create` and without `read` is [refused](#refused-requests).

An `allow` list that does not hold `use`, the empty list included, opens nothing. It is accepted: what the permission gave at the database level goes, and its entry-level rights stay and wait. They count once a permission opens the database for the principal.

A permission can give a level that the tokens cannot show: a level of `view` or `use` on the database shows no level token in `allow`. The `level` and `caps` members say exactly what the permission gives.

Printing, exporting, saving a copy, auto-complete, the browser add-on and synchronization are set by policy, in the Server Manager under *Policies*, and not per permission. The tokens `print`, `export`, `save`, `auto_complete`, `addon_fill`, `addon_offer` and `sync` never appear in a permission, and a request that names one is [refused](#refused-requests).

**Example:**

```json
"allow": ["use", "read", "update", "create", "delete", "share"]
```

### Entry-Level Rights

Entry-level rights give specific rights on individual entries or folders. Each element specifies the entry/folder `id` and its rights array:

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

Entry-level rights are typically used when a user should have limited database-level access but needs specific rights on certain entries (e.g., a user whose `allow` holds `use` alone, with `read` on one entry).

A new or changed element needs `use` in its `rights`; an element that repeats what the permission shows is accepted as it is. A right on a folder reaches everything below it, unless an entry or folder below has its own permissions.

In a response each element also says what it gives exactly. These members are read-only:

| Field | Type | Description |
|-------|------|-------------|
| `level` | string or null | The level on this entry or folder: `view`, `use`, `read` or `edit`. `view` has no token in `rights`: the entry or folder is listed and nothing more |
| `caps` | array of strings | The capabilities on this entry or folder: `create`, `delete`, `share`, `protect` (the right `second_pass`) and `seal` |
| `origin` | string or null | How this element came about, as for the permission's `origin` |
| `own_permissions` | boolean | Whether this entry or folder has its own permissions: it takes nothing from the folders above it |
| `valid_from` | string (ISO 8601) or null | The start of this element alone |
| `valid_until` | string (ISO 8601) or null | The end of this element alone |

### Refused Requests

These requests answer `400 Bad Request` and change nothing. The message says what to change, and points to the Server Manager where the change belongs there. What repeats what the permission shows is never refused, so a permission read with [Get Permission](#get-permission) can be sent back as it is, and sending it back changes nothing.

| The request | What to do |
|-------------|------------|
| names a right in `deny`, or in an element of `entry_deny` | A permission only gives rights. Remove the right, or give the object its own permissions in the Server Manager. An empty list is accepted |
| names `print`, `export`, `save`, `auto_complete`, `addon_fill`, `addon_offer` or `sync` in any list | These are set by policy, in the Server Manager under *Policies* |
| holds `update` or `share` without `read`, `second_pass` without `update`, or `seal` without `share`, in an `allow` list that holds `use` or in an element of `entry_allow` | The rights build on each other; see [Rights Values](#rights-values) |
| holds `use` and another right in `allow`, without `read` | Add `read`, or name the right on the entries |
| has an element of `entry_allow` without `use` | Add `use` |
| has an element of `entry_allow` that would give less than an element above it in the same permission | Entry-level rights add to those above them. Give the object its own permissions in the Server Manager |
| has a `seal_status` that [Seal Status](#seal-status) does not list | Use a listed value |
| names a date, and `valid_until` is not after `valid_from` | Correct the dates |
| names a date, and `valid_until` lies before 1970 | Correct the date |
| creates a permission that gives nothing: no `use` in `allow` and no element in `entry_allow` | Add `use` to `allow`, or name at least one entry |

### Seal Status

The seal mechanism provides an additional layer of approval for sensitive entries.

| Value | Name | Description |
|-------|------|-------------|
| `0` | Unset | No seal (default) |
| `1` | Set | Seal is active |
| `2` | Waiting | Seal approval is pending |
| `3` | Approved | Seal has been approved |
| `4` | Broken | Seal has been broken/violated |

*Server 20.0.0 and later.* Changing `seal_status` with [Update Permission](#update-permission) needs the permission's issuer, a manager of the database, or seal permission on the items the permission names; see [Changing the Seal Status](#changing-the-seal-status).

### Authorization

Permission management requires one of:

- **Server Administrator** -- can read, create, change and delete every permission on every database, within the rules below
- **Database Administrator** -- whoever the database's `db_admins` lists, directly or through a group: can read, create, change and delete every permission on that database, within the rules below
- **Permission Issuer** -- can read, update or delete the permissions they created. An update requires the `share` right on the database and on the referenced entries, and can give only what the issuer holds there

These rules hold for every caller, administrators included:

- A permission that administers the database (its `caps` holds `manage`) can be changed or deleted only by an owner of the database or a Server Administrator. A permission that owns the database (its `caps` holds `own`) can be changed or deleted only by an owner. Otherwise the request answers `403`. The owners are listed in `db_owners` of the [database object](databases.md#database-object). `allow` and `entry_allow` never add or remove `manage` or `own`: administrators are changed with [`db_admins`](databases.md#changing-db_admins), owners in the Server Manager.
- A change that would leave the database without an owner whose ownership has no end date answers `409 Conflict`. A database that has no such owner is not affected.
- A permission written in the Server Manager can be changed or deleted only by those who manage the database, also where its `issuer_id` names the caller.
- The server's **Access granted to oneself by managers and administrators** policy (`access.self_grant`, set in the Server Manager under *Policies*) applies to a Server Administrator or Database Administrator who gives themselves, or a group they belong to, more than they hold: at **Forbidden** or **Needs approval** the request answers `403`.

!!! warning "Deprecated"
    Permissions issued by a user who does not manage the database -- with the Grant Access wizard of the Windows client or over these routes -- and seals work as described here in Server 20.0.0, and will be removed in version 21. To give someone access to an entry, create a [shared secret](secrets.md).

---

## List Permissions

```
GET /v2.0/admin/databases/{db}/permissions
```

Returns a paginated list of the permissions of a database, in the order of their `id`. A caller who manages the database sees all of them; any other caller sees those it issued. Returns the compact representation.

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
            "valid_until": null
        },
        {
            "id": "B2C3D4E5-F6A7-8901-BCDE-F12345678901",
            "principal_id": "7FB95F64-8828-4562-C4GD-3D074G77BGB7",
            "issuer_id": "3FA85F64-5717-4562-B3FC-2C963F66AFA6",
            "valid_from": "2026-01-01T00:00:00.000Z",
            "valid_until": "2026-12-31T23:59:59.000Z"
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
| `501 Not Implemented` | *Server 20.0.0 and later.* The database has not been converted to the new format |
| `503 Service Unavailable` | The database is not available at the moment. Try again later |

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

Creates a new permission for a database. The caller must have `use` access on the database or be a Database Administrator / Server Administrator. A caller who does not manage the database also needs the `share` right on the database and on every entry and folder the request names, and can give only rights the caller holds there.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `db` | string (UUID) | Yes | Database ID |

### Request Body

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `principal_id` | string (UUID) | Yes | User or group ID this permission applies to |
| `allow` | array of strings | No | Rights at the database level (default: empty). Without `use` the database does not open for the principal and the entry-level rights wait; see [Rights Values](#rights-values) |
| `deny` | array of strings | No | Must be empty or left out |
| `valid_from` | string (ISO 8601) or null | No | Start date |
| `valid_until` | string (ISO 8601) or null | No | Expiry date |
| `entry_allow` | array of objects | No | Rights on entries and folders |
| `entry_deny` | array of objects | No | Must be empty or left out |
| `seal_status` | integer | No | Seal status (default: `0`) |
| `approver_ids` | array of UUIDs | No | Seal approver IDs |

!!! note
    The `issuer_id` is automatically set to the authenticated user and cannot be overridden.

```json
{
    "principal_id": "3FA85F64-5717-4562-B3FC-2C963F66AFA6",
    "allow": ["use", "read", "update", "create", "delete", "share"],
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
    "deny": [],
    "entry_allow": [
        {
            "id": "D4FEC05E-7866-4424-A998-4D96FF8B183E",
            "rights": ["use", "read", "update", "share"],
            "level": "edit",
            "caps": ["share"],
            "origin": "manual",
            "own_permissions": false,
            "valid_from": null,
            "valid_until": "2026-12-31T23:59:59.000Z"
        }
    ],
    "entry_deny": [],
    "seal_status": 0,
    "approver_ids": [],
    "level": "edit",
    "caps": ["create", "delete", "share"],
    "origin": "manual"
}
```

### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | Invalid or missing required fields, or one of the [Refused Requests](#refused-requests) |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions (no `use` access on database, no `share` right on the database or on referenced entries, or a right the caller does not hold), or the server's policy on access given to oneself; see [Authorization](#authorization) |
| `404 Not Found` | Database, user/group, or referenced entry not found |
| `501 Not Implemented` | *Server 20.0.0 and later.* The database has not been converted to the new format; nothing is created |
| `503 Service Unavailable` | The database is not available at the moment, or the change could not be written to the database or recorded in the audit trail; nothing is created. Try again later |

### Example

=== "curl"

    ```bash
    curl -X POST "https://<server>:8714/v2.0/admin/databases/E79BDEB2-1A58-4715-B74C-28A87A2AFD37/permissions" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -d '{
            "principal_id": "3FA85F64-5717-4562-B3FC-2C963F66AFA6",
            "allow": ["use", "read", "update", "create", "delete", "share"]
        }'
    ```

---

## Get Permission

```
GET /v2.0/admin/databases/{db}/permissions/{id}
```

Returns the **full representation** of a specific permission, including entry-level rights and seal status.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `db` | string (UUID) | Yes | Database ID |
| `id` | string | Yes | Permission unique identifier |

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
    "deny": [],
    "entry_allow": [
        {
            "id": "D4FEC05E-7866-4424-A998-4D96FF8B183E",
            "rights": ["use", "read", "update", "share"],
            "level": "edit",
            "caps": ["share"],
            "origin": "manual",
            "own_permissions": false,
            "valid_from": null,
            "valid_until": "2026-12-31T23:59:59.000Z"
        }
    ],
    "entry_deny": [],
    "seal_status": 0,
    "approver_ids": [],
    "level": "edit",
    "caps": ["create", "delete", "share"],
    "origin": "manual"
}
```

### Error Responses

| Status | Description |
|--------|-------------|
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions to manage this database |
| `404 Not Found` | Database or permission not found |
| `501 Not Implemented` | *Server 20.0.0 and later.* The database has not been converted to the new format |
| `503 Service Unavailable` | The database is not available at the moment. Try again later |

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

Updates an existing permission. Include only the members you want to change; a member you leave out stays as it is. A member you send replaces that member as a whole: `entry_allow` names every entry and folder the permission gives rights on afterwards, and an element you leave out is removed. A permission read with [Get Permission](#get-permission) and sent back as it is changes nothing. The caller must be the permission's issuer, a designated seal approver, or a Database/Server Administrator.

- `allow` with `use` alone keeps the database open for the principal and reaches no entry: what the permission gave at the database level beyond that goes. An `allow` list without `use` opens nothing; see [Rights Values](#rights-values).
- `valid_from`, `valid_until` and `principal_id`, when the request names them, apply to the whole permission.
- A request that leaves a permission giving nothing removes it: the answer is `200` with the permission as requested, and a later `GET` or `PATCH` of its `id` answers `404`.

*Server 20.0.0 and later.* `principal_id`, as the request would leave it, must name a user or a group of the server, as on [Create Permission](#create-permission); otherwise the request answers `404` and the permission is not changed.

### Changing the Seal Status

*Server 20.0.0 and later.* A request that changes `seal_status` -- to any value, `0` included -- answers `403 Forbidden` unless the caller:

- is the permission's issuer; or
- manages the database (a Server Administrator, or a Database Administrator of this database); or
- holds `seal` permission on every entry and folder the permission names in `entry_allow`, as stored and as the request would leave it -- on the database itself when it names none the database holds.

A request that leaves out `seal_status`, or sends the stored value, is not affected. The check comes after the `404` for a `principal_id` that names no user or group, and before the checks of the rights the permission grants. A request answered `403` leaves the permission unchanged.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `db` | string (UUID) | Yes | Database ID |
| `id` | string | Yes | Permission unique identifier |

### Request Body

```json
{
    "allow": ["use", "read"],
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
            "rights": ["use", "read"],
            "level": "read",
            "caps": [],
            "origin": "manual",
            "own_permissions": false,
            "valid_from": null,
            "valid_until": "2027-06-30T23:59:59.000Z"
        }
    ],
    "entry_deny": [],
    "seal_status": 0,
    "approver_ids": [],
    "level": "read",
    "caps": [],
    "origin": "manual"
}
```

### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | Invalid fields, or one of the [Refused Requests](#refused-requests) |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Not the issuer/approver and not a DB manager, no `share` right on the database or on referenced entries, a right the caller does not hold, a change of a permission that administers the database the caller may not make, the server's policy on access given to oneself -- see [Authorization](#authorization) -- or (*Server 20.0.0 and later*) a change of `seal_status` the caller may not make -- see [Changing the Seal Status](#changing-the-seal-status) |
| `404 Not Found` | Database, permission, or referenced entry not found, or (*Server 20.0.0 and later*) a `principal_id` that names no user or group of the server |
| `409 Conflict` | The change would leave the database without an owner whose ownership has no end date; nothing is changed |
| `501 Not Implemented` | *Server 20.0.0 and later.* The database has not been converted to the new format; nothing is changed |
| `503 Service Unavailable` | The database is not available at the moment, or the change could not be written to the database or recorded in the audit trail; nothing is changed. Try again later |

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

Deletes a permission, with everything it gives on the database and on its entries and folders. The caller must be the permission's issuer or a Database/Server Administrator.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `db` | string (UUID) | Yes | Database ID |
| `id` | string | Yes | Permission unique identifier |

### Response

`204 No Content`

No response body.

### Error Responses

| Status | Description |
|--------|-------------|
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Not the issuer and not a DB manager, or a permission that administers the database the caller may not delete -- see [Authorization](#authorization) |
| `404 Not Found` | Database or permission not found |
| `409 Conflict` | The delete would leave the database without an owner whose ownership has no end date; nothing is deleted |
| `501 Not Implemented` | *Server 20.0.0 and later.* The database has not been converted to the new format; nothing is deleted. Delete opens the database as [Create Permission](#create-permission) and [Update Permission](#update-permission) do, and gives the same answers when it cannot be opened |
| `503 Service Unavailable` | The database is not available at the moment, or the change could not be written to the database or recorded in the audit trail; nothing is deleted. Try again later |

### Example

=== "curl"

    ```bash
    curl -X DELETE "https://<server>:8714/v2.0/admin/databases/E79BDEB2-1A58-4715-B74C-28A87A2AFD37/permissions/C3D4E5F6-A7B8-9012-CDEF-123456789012" \
        -H "Authorization: Bearer <token>"
    ```
