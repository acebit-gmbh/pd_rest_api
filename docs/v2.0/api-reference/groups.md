# Groups

Reference for group endpoints. Groups are accessible in both **client** and **admin** scopes, but with different capabilities.

| Scope | Endpoints | Description |
|-------|-----------|-------------|
| Client | `GET /v2.0/groups`, `GET /v2.0/groups/{id}` | Read-only access to the group directory (compact representation) |
| Admin | `GET/POST /v2.0/admin/groups`, `GET/PATCH/DELETE /v2.0/admin/groups/{id}` | Full CRUD on all server groups |

Groups can be nested: a group can be a member of another group via the `member_of` field.

---

## Group Object

The group object uses different representations depending on context:

- **List** responses return a **compact representation**: `id`, `name`, `description`, `department`, `email`, `disabled`, `updated_at`.
- **Detail** responses (`GET /v2.0/admin/groups/{id}`) return the **full representation** with all fields, including `dn`, `objectId`, `ad_sync`, `member_of`, `members`, and `admins`.

| Field | Type | Writable | Description |
|-------|------|:--------:|-------------|
| `id` | string (UUID) | No | Unique identifier (server-generated, ignored on input) |
| `name` | string | Yes | Group name |
| `description` | string | Yes | Group description |
| `department` | string | Yes | Department |
| `email` | string | Yes | Email address |
| `disabled` | boolean | Yes | Whether the group is disabled |
| `dn` | string | Yes | Distinguished Name (LDAP DN). Detail only. |
| `objectId` | string | Yes | Active Directory object ID (GUID). Detail only. |
| `ad_sync` | boolean | Yes | Whether the group is synchronized from Active Directory. Detail only. |
| `member_of` | array of UUIDs | Restricted | Parent group IDs this group belongs to. Only modifiable by Server Administrators or User Administrators. Detail only. |
| `members` | array of UUIDs | No | Computed list of user/group IDs that are members of this group. Detail only. |
| `admins` | array of UUIDs | Restricted | User IDs designated as Group Administrators for this group. Only modifiable by Server Administrators. Detail only. |
| `updated_at` | string (ISO 8601) | No | Last modification timestamp |

!!! important "Group Membership Model"
    - **`member_of`** (writable): which parent groups THIS group belongs to.
    - **`members`** (read-only, calculated): which users and groups belong to THIS group.
    - To add a user to this group, update the **user's** `member_of` to include this group's ID (see [Users](users.md#update-user)).
    - To nest this group inside another group, update this group's `member_of` to include the parent group's ID.
    - The `members` field is automatically derived from all users and groups that reference this group in their `member_of`.
    - You cannot modify `members` directly -- always update the member's `member_of` field.

!!! warning "Field-Level Authorization"
    - The `member_of` field can only be modified by users with the `server_admin` or `user_admin` role.
    - The `admins` field can only be modified by users with the `server_admin` role. If a non-Server-Administrator attempts to change `admins`, the server returns `403 Forbidden`.

---

## Client Endpoints

These endpoints are available in both `client` and `admin` sessions. They return a compact representation suitable for group lookups (e.g., when assigning permissions or sharing secrets). No admin-specific fields (dn, objectId, ad_sync, member_of, members, admins) are included.

### Client Group Object (Compact)

| Field | Type | Description |
|-------|------|-------------|
| `id` | string (UUID) | Unique identifier |
| `name` | string | Group name |
| `description` | string | Group description |
| `department` | string | Department |
| `email` | string | Email address |
| `disabled` | boolean | Whether the group is disabled |
| `updated_at` | string (ISO 8601) | Last modification timestamp |

### List Groups

```
GET /v2.0/groups
```

Returns a paginated list of all groups on the server. Returns the compact representation (no admin-specific fields).

##### Query Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `offset` | integer | No | Pagination offset (default: `0`) |
| `limit` | integer | No | Pagination limit (default: `100`) |

##### Response

`200 OK`

```json
{
    "data": [
        {
            "id": "FEAE7AC9-58D1-4A76-82A6-2C7DB135CFDD",
            "name": "Engineering",
            "description": "Engineering department group",
            "department": "Engineering",
            "email": "engineering@example.com",
            "disabled": false,
            "updated_at": "2024-11-20T16:45:00.000Z"
        },
        {
            "id": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
            "name": "Backend Team",
            "description": "Backend development team",
            "department": "Engineering",
            "email": null,
            "disabled": false,
            "updated_at": "2024-06-15T10:30:00.000Z"
        }
    ],
    "total": 2,
    "offset": 0,
    "limit": 100
}
```

##### Error Responses

| Status | Description |
|--------|-------------|
| `401 Unauthorized` | Missing or invalid authentication token |

##### Example

=== "curl"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/groups?offset=0&limit=100" \
        -H "Authorization: Bearer <token>"
    ```

---

### Get Group

```
GET /v2.0/groups/{id}
```

Returns the compact representation of a specific group.

##### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string (UUID) | Yes | Group unique identifier |

##### Response

`200 OK`

```json
{
    "id": "FEAE7AC9-58D1-4A76-82A6-2C7DB135CFDD",
    "name": "Engineering",
    "description": "Engineering department group",
    "department": "Engineering",
    "email": "engineering@example.com",
    "disabled": false,
    "updated_at": "2024-11-20T16:45:00.000Z"
}
```

##### Error Responses

| Status | Description |
|--------|-------------|
| `401 Unauthorized` | Missing or invalid authentication token |
| `404 Not Found` | Group not found |

##### Example

=== "curl"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/groups/FEAE7AC9-58D1-4A76-82A6-2C7DB135CFDD" \
        -H "Authorization: Bearer <token>"
    ```

---

## Admin Endpoints

These endpoints require an **admin-scoped session** (`"scope": "admin"` at login).

### List Groups (Admin)

```
GET /v2.0/admin/groups
```

Returns a paginated list of all groups on the server. Returns the compact representation -- use [Get Group](#get-group) to retrieve the full representation for a specific group.

!!! note "Filtered Pagination for Group Administrators"
    Group Administrators only see groups they are designated to manage. The `total` count reflects the number of groups visible to the caller, not the total number of groups on the server.

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
            "id": "FEAE7AC9-58D1-4A76-82A6-2C7DB135CFDD",
            "name": "Engineering",
            "description": "Engineering department group",
            "department": "Engineering",
            "email": "engineering@example.com",
            "disabled": false,
            "updated_at": "2024-11-20T16:45:00.000Z"
        },
        {
            "id": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
            "name": "Backend Team",
            "description": "Backend development team",
            "department": "Engineering",
            "email": null,
            "disabled": false,
            "updated_at": "2024-06-15T10:30:00.000Z"
        }
    ],
    "total": 2,
    "offset": 0,
    "limit": 100
}
```

#### Error Responses

| Status | Description |
|--------|-------------|
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions |

#### Example

=== "curl"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/admin/groups?offset=0&limit=100" \
        -H "Authorization: Bearer <token>"
    ```

---

### Create Group (Admin)

```
POST /v2.0/admin/groups
```

Creates a new group.

#### Request Body

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `name` | string | Yes | Group name |
| `description` | string | No | Group description |
| `department` | string | No | Department |
| `email` | string | No | Email address |
| `dn` | string | No | Distinguished Name |
| `objectId` | string | No | Active Directory object ID (GUID) |
| `ad_sync` | boolean | No | Whether the group is AD-synchronized (default: `false`) |
| `disabled` | boolean | No | Whether the group is disabled (default: `false`) |
| `member_of` | array of UUIDs | No | Parent group IDs (requires `server_admin` or `user_admin` role) |
| `admins` | array of UUIDs | No | Group Administrator user IDs (requires `server_admin` role) |

```json
{
    "name": "Frontend Team",
    "description": "Frontend development team",
    "department": "Engineering",
    "member_of": [
        "FEAE7AC9-58D1-4A76-82A6-2C7DB135CFDD"
    ]
}
```

#### Response

`201 Created`

```json
{
    "id": "C4D5E6F7-A8B9-0123-CDEF-456789012345",
    "name": "Frontend Team",
    "description": "Frontend development team",
    "department": "Engineering",
    "email": null,
    "disabled": false,
    "updated_at": "2024-11-21T09:00:00.000Z"
}
```

#### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | Invalid or missing required fields |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions, or attempted to set restricted fields without required role |
| `409 Conflict` | A group with this name already exists |

#### Example

=== "curl"

    ```bash
    curl -X POST "https://<server>:8714/v2.0/admin/groups" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "Frontend Team",
            "description": "Frontend development team",
            "department": "Engineering",
            "member_of": ["FEAE7AC9-58D1-4A76-82A6-2C7DB135CFDD"]
        }'
    ```

---

### Get Group (Admin)

```
GET /v2.0/admin/groups/{id}
```

Returns the **full representation** of a specific group, including `dn`, `objectId`, `ad_sync`, `member_of`, `members`, and `admins`.

#### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string (UUID) | Yes | Group unique identifier |

#### Response

`200 OK`

```json
{
    "id": "FEAE7AC9-58D1-4A76-82A6-2C7DB135CFDD",
    "name": "Engineering",
    "description": "Engineering department group",
    "department": "Engineering",
    "email": "engineering@example.com",
    "disabled": false,
    "dn": "CN=Engineering,OU=Groups,DC=domain,DC=local",
    "objectId": "b2c3d4e5-f6a7-8901-bcde-f23456789012",
    "ad_sync": true,
    "member_of": [],
    "members": [
        "3D1C91F6-754D-427E-9D76-8CC20E8C326E",
        "56E4205C-0D50-47E9-90B8-B751EF19A165",
        "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
    ],
    "admins": [
        "3D1C91F6-754D-427E-9D76-8CC20E8C326E"
    ],
    "updated_at": "2024-11-20T16:45:00.000Z"
}
```

!!! note
    The `members` array contains UUIDs of both users and groups. To determine the type of each member, look up the ID in the users or groups endpoint.

#### Error Responses

| Status | Description |
|--------|-------------|
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions |
| `404 Not Found` | Group not found |

#### Example

=== "curl"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/admin/groups/FEAE7AC9-58D1-4A76-82A6-2C7DB135CFDD" \
        -H "Authorization: Bearer <token>"
    ```

---

### Update Group (Admin)

```
PATCH /v2.0/admin/groups/{id}
```

Updates an existing group. Include only the fields you want to update.

#### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string (UUID) | Yes | Group unique identifier |

#### Request Body

```json
{
    "description": "Engineering department (all teams)",
    "admins": [
        "3D1C91F6-754D-427E-9D76-8CC20E8C326E",
        "56E4205C-0D50-47E9-90B8-B751EF19A165"
    ]
}
```

!!! tip "Nesting Groups"
    To nest this group inside another group, add the parent group's ID to the `member_of` array. To remove it from a parent group, omit that ID from the array.

#### Response

`200 OK`

Returns the full representation of the updated group.

```json
{
    "id": "FEAE7AC9-58D1-4A76-82A6-2C7DB135CFDD",
    "name": "Engineering",
    "description": "Engineering department (all teams)",
    "department": "Engineering",
    "email": "engineering@example.com",
    "disabled": false,
    "dn": "CN=Engineering,OU=Groups,DC=domain,DC=local",
    "objectId": "b2c3d4e5-f6a7-8901-bcde-f23456789012",
    "ad_sync": true,
    "member_of": [],
    "members": [
        "3D1C91F6-754D-427E-9D76-8CC20E8C326E",
        "56E4205C-0D50-47E9-90B8-B751EF19A165",
        "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
    ],
    "admins": [
        "3D1C91F6-754D-427E-9D76-8CC20E8C326E",
        "56E4205C-0D50-47E9-90B8-B751EF19A165"
    ],
    "updated_at": "2024-11-21T11:00:00.000Z"
}
```

#### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | Invalid fields |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions, or attempted to modify restricted fields without required role |
| `404 Not Found` | Group or referenced parent group not found |
| `409 Conflict` | Group name conflict |

#### Example

=== "curl"

    ```bash
    curl -X PATCH "https://<server>:8714/v2.0/admin/groups/FEAE7AC9-58D1-4A76-82A6-2C7DB135CFDD" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -d '{
            "description": "Engineering department (all teams)",
            "admins": [
                "3D1C91F6-754D-427E-9D76-8CC20E8C326E",
                "56E4205C-0D50-47E9-90B8-B751EF19A165"
            ]
        }'
    ```

---

### Delete Group (Admin)

```
DELETE /v2.0/admin/groups/{id}
```

Deletes a group. Any users or child groups that had this group in their `member_of` will have the reference automatically removed.

#### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string (UUID) | Yes | Group unique identifier |

#### Response

`204 No Content`

No response body.

#### Error Responses

| Status | Description |
|--------|-------------|
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions to delete groups |
| `404 Not Found` | Group not found |

#### Example

=== "curl"

    ```bash
    curl -X DELETE "https://<server>:8714/v2.0/admin/groups/A1B2C3D4-E5F6-7890-ABCD-EF1234567890" \
        -H "Authorization: Bearer <token>"
    ```
