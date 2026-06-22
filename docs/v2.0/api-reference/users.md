# Users

Reference for user endpoints. Users are accessible in both **client** and **admin** scopes, but with different capabilities.

| Scope | Endpoints | Description |
|-------|-----------|-------------|
| Client | `GET /v2.0/users`, `GET /v2.0/users/{id}` | Read-only access to the user directory (compact representation) |
| Admin | `GET/POST /v2.0/admin/users`, `GET/PATCH/DELETE /v2.0/admin/users/{id}`, `POST /v2.0/admin/users/{id}/password` | Full CRUD on all server users |

---

## User Object

| Field | Type | Writable | Description |
|-------|------|:--------:|-------------|
| `id` | string (UUID) | No | Unique identifier (server-generated, ignored on input) |
| `name` | string | Yes | Username |
| `auth_modes` | array of strings | Yes | Allowed authentication methods (see values below) |
| `display_name` | string | Yes | Display name |
| `department` | string | Yes | Department |
| `email` | string | Yes | Email address. **Required** when the user's effective 2FA mode is `email` (see `two_factor_mode` below). |
| `phone` | string | Yes | Phone number |
| `two_factor_mode` | string | Yes | Per-user two-factor authentication mode (see values below). Default is `"default"` (inherit server-wide setting). |
| `sam` | string | Yes | SAM account name (e.g., `"DOMAIN\\username"`) |
| `upn` | string | Yes | User Principal Name (e.g., `"user@domain.local"`) |
| `dn` | string | Yes | Distinguished Name (LDAP DN) |
| `objectId` | string | Yes | Active Directory object ID (GUID) |
| `disabled` | boolean | Yes | Whether the account is disabled |
| `must_change_pass` | boolean | Yes | User must change password on next login |
| `cannot_change_pass` | boolean | Yes | User is not allowed to change their own password |
| `roles` | array of strings | Restricted | Server roles (see values below). Only modifiable by Server Administrators. |
| `member_of` | array of UUIDs | Restricted | Group IDs this user belongs to. Only modifiable by Server Administrators or User Administrators. |
| `updated_at` | string (ISO 8601) | No | Last modification timestamp |

### `auth_modes` Values

| Value | Description |
|-------|-------------|
| `"standard"` | Username and password authentication |
| `"sspi"` | SSPI (Kerberos / Negotiate / NTLM) |
| `"iwa"` | Integrated Windows Authentication |
| `"azure"` | Azure AD (deprecated -- use `oidc` instead) |
| `"oidc"` | OpenID Connect |
| `"webauthn"` | WebAuthn / FIDO2 passkeys |

### `two_factor_mode` Values

| Value | Description |
|-------|-------------|
| `"default"` | Inherit the server-wide 2FA setting |
| `"disabled"` | Never require 2FA for this user (useful for service accounts) |
| `"totp"` | TOTP (authenticator app). User must register a secret first. |
| `"email"` | Email-based one-time codes. **Requires `email` field to be set.** |
| `"fido2"` | FIDO2 / WebAuthn. User must register a FIDO2 credential first. |

!!! warning "Service accounts and 2FA"
    If the server-wide 2FA default is `"email"` and you create a user without an `email` address, login will fail at runtime with an unhelpful error. For service / automation accounts (gMSA, CI pipelines, API tokens), set `"two_factor_mode": "disabled"` at creation to opt out explicitly.

!!! note "Email requirement"
    When a user's effective 2FA mode resolves to `email`, the server requires a non-empty `email` field. Setting `two_factor_mode` to `email` without an email address is permitted at the API level but the user will not be able to log in until an email is added.

### `roles` Values

| Value | Description |
|-------|-------------|
| `"super_admin"` | Built-in super administrator (read-only, cannot be assigned via API) |
| `"server_admin"` | Server administrator -- full server management access |
| `"db_admin"` | Database administrator -- manage assigned databases |
| `"user_admin"` | User administrator -- manage user accounts |
| `"group_admin"` | Group administrator -- manage assigned groups |
| `"ad_operator"` | Active Directory operator -- manage AD synchronization |
| `"log_reader"` | Log reader -- view server logs |

!!! important "Group Membership Model"
    - `member_of` is the **source of truth** for group membership.
    - To add a user to a group, include the group ID in the user's `member_of` array via `PATCH /v2.0/admin/users/{id}`.
    - The group's `members` field is **automatically calculated** from all users and groups that list it in their `member_of`.
    - You do not modify group membership from the group side -- always update the user's (or child group's) `member_of` field.

!!! warning "Field-Level Authorization"
    - The `roles` field can only be modified by users with the `server_admin` role. If a non-Server-Administrator attempts to change `roles`, the server returns `403 Forbidden`. Submitting the existing `roles` value unchanged is always allowed.
    - The `member_of` field can only be modified by users with the `server_admin` or `user_admin` role.

---

## User Profile

```
GET /v2.0/me
```

Returns the full profile of the currently authenticated user. This endpoint does not require admin scope -- any authenticated user can retrieve their own profile. The response includes all fields from the [User Object](#user-object), including roles and group memberships.

### Response

`200 OK`

```json
{
    "id": "3D1C91F6-754D-427E-9D76-8CC20E8C326E",
    "name": "jdoe",
    "auth_modes": ["sspi", "iwa"],
    "display_name": "John Doe",
    "department": "Engineering",
    "email": "jdoe@example.com",
    "phone": null,
    "sam": "DOMAIN\\jdoe",
    "upn": "jdoe@domain.local",
    "dn": "CN=John Doe,CN=Users,DC=domain,DC=local",
    "objectId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "disabled": false,
    "must_change_pass": false,
    "cannot_change_pass": false,
    "roles": ["server_admin", "db_admin"],
    "member_of": [
        "FEAE7AC9-58D1-4A76-82A6-2C7DB135CFDD"
    ],
    "updated_at": "2024-11-20T16:45:00.000Z"
}
```

### Error Responses

| Status | Description |
|--------|-------------|
| `401 Unauthorized` | Missing or invalid authentication token |

### Example

=== "curl"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/me" \
        -H "Authorization: Bearer <token>"
    ```

=== "PowerShell"

    ```powershell
    $me = Invoke-RestMethod -Uri "https://<server>:8714/v2.0/me" -Headers @{ Authorization = "Bearer $token" }
    Write-Host "Logged in as: $($me.display_name) ($($me.name))"
    ```

=== "Python"

    ```python
    me = requests.get(
        f"{BASE}/me",
        headers={"Authorization": f"Bearer {token}"},
        verify=False,
    ).json()
    print(f"Logged in as: {me['display_name']} ({me['name']})")
    ```

---

### Update Own Profile

```
PATCH /v2.0/me
```

Updates a restricted set of profile fields on the caller's own account. Available in both `client` and `admin` sessions.

!!! warning "Only three fields are accepted"
    To prevent privilege escalation and account-integrity issues, only the following fields can be changed through this endpoint:

    - `display_name`
    - `department`
    - `phone`

    Any other field in the request body (including `name`, `email`, `roles`, `member_of`, `auth_modes`, `two_factor_mode`, `disabled`, `sam`, `upn`, `dn`, etc.) causes `400 Bad Request`.

    For password changes use [`POST /v2.0/me/password`](#change-own-password). For passkey management use the [`/me/passkeys/...`](#passkeys-webauthn) endpoints. Changes to username, email, roles, groups, AD binding, or 2FA settings remain admin-only via [`PATCH /v2.0/admin/users/{id}`](#update-user).

The request body is a partial JSON document -- fields omitted keep their current values. An empty body (`{}`) is accepted and returns the current profile unchanged.

#### Request Body

| Field | Type | Description |
|-------|------|-------------|
| `display_name` | string | User-friendly name (maps to `FullName` internally) |
| `department` | string | Department or organizational unit |
| `phone` | string | Mobile phone number |

#### Response

`200 OK` -- returns the full updated profile (same shape as `GET /me`).

#### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | Request body is not valid JSON, or contains a field outside the allow-list |
| `401 Unauthorized` | Missing or invalid authentication token |

#### Example

=== "curl"

    ```bash
    curl -X PATCH "https://<server>:8714/v2.0/me" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -d '{
              "display_name": "Jane Doe",
              "department": "Engineering",
              "phone": "+1-555-0199"
            }'
    ```

=== "PowerShell"

    ```powershell
    $body = @{
        display_name = "Jane Doe"
        department   = "Engineering"
        phone        = "+1-555-0199"
    } | ConvertTo-Json

    Invoke-RestMethod `
        -Uri "https://<server>:8714/v2.0/me" `
        -Method PATCH `
        -Headers @{ Authorization = "Bearer $token" } `
        -ContentType "application/json" `
        -Body $body
    ```

=== "Python"

    ```python
    requests.patch(
        f"{BASE}/me",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "display_name": "Jane Doe",
            "department":   "Engineering",
            "phone":        "+1-555-0199",
        },
        verify=False,
    )
    ```

!!! info "Active Directory note"
    For users bound to AD, fields like `display_name`, `department`, and `phone` may be overwritten on the next AD sync. To make changes persist, edit them in AD and let the sync propagate, or ask an administrator to unbind the user first.

---

### Change Own Password

```
POST /v2.0/me/password
```

Changes the password of the currently authenticated user. Unlike the admin [Change Password](#change-password-admin) endpoint, this requires the **current password** for verification. Available in both `client` and `admin` sessions.

#### Request Body

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `current_password` | string | Yes | The user's current password |
| `new_password` | string | Yes | The new password |

```json
{
    "current_password": "oldP@ssword123",
    "new_password": "newSecureP@ss456"
}
```

#### Response

`204 No Content`

No response body.

#### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | Missing or empty `current_password` / `new_password` field, or new password violates the server's password policy |
| `401 Unauthorized` | Missing/invalid authentication token, or incorrect `current_password` |
| `403 Forbidden` | User is a built-in super administrator, **or** the per-user `cannot_change_pass` flag is set. The response `error.message` distinguishes the two cases. |
| `409 Conflict` | User does not use `standard` authentication (password change is not applicable) |

!!! warning "Super-administrator accounts"
    The built-in super-administrator password **cannot** be changed via the REST API. Use the Password Depot Server Manager (native admin application) instead. This is a deliberate restriction -- super-admin credentials are infrastructure-critical and managed outside the REST surface.

!!! warning "`cannot_change_pass` flag"
    If the account has `cannot_change_pass: true` (set by an administrator), this endpoint returns `403`. The user must ask their administrator to either clear the flag or rotate the password via `POST /admin/users/{id}/password`.

!!! note
    - Only users whose `auth_modes` include `"standard"` can change their password here. Users authenticating via OIDC, SSPI, IWA, or WebAuthn manage their password through the respective identity provider.
    - If a password policy is configured on the server, the new password must satisfy its requirements (length, complexity, history).
    - After a successful password change, the `must_change_pass` flag is automatically cleared.

#### Example

=== "curl"

    ```bash
    curl -X POST "https://<server>:8714/v2.0/me/password" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -d '{
            "current_password": "oldP@ssword123",
            "new_password": "newSecureP@ss456"
        }'
    ```

---

## Client Endpoints

These endpoints are available in both `client` and `admin` sessions. They return a compact representation suitable for user lookups (e.g., when assigning permissions or sharing secrets). No admin-specific fields (roles, auth_modes, AD attributes, group memberships) are included.

### Client User Object (Compact)

| Field | Type | Description |
|-------|------|-------------|
| `id` | string (UUID) | Unique identifier |
| `name` | string | Username |
| `display_name` | string | Display name |
| `department` | string | Department |
| `email` | string | Email address |
| `disabled` | boolean | Whether the account is disabled |
| `updated_at` | string (ISO 8601) | Last modification timestamp |

### List Users

```
GET /v2.0/users
```

Returns a paginated list of all users on the server. Returns the compact representation (no admin-specific fields).

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
            "id": "9A6DBC50-B8FF-487F-964A-96858296B8F5",
            "name": "admin",
            "display_name": "Administrator (built-in account)",
            "department": "R&D",
            "email": "admin@example.com",
            "disabled": false,
            "updated_at": "2024-01-15T09:00:00.000Z"
        },
        {
            "id": "3D1C91F6-754D-427E-9D76-8CC20E8C326E",
            "name": "jdoe",
            "display_name": "John Doe",
            "department": "Engineering",
            "email": "jdoe@example.com",
            "disabled": false,
            "updated_at": "2024-11-20T16:45:00.000Z"
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
    curl -X GET "https://<server>:8714/v2.0/users?offset=0&limit=100" \
        -H "Authorization: Bearer <token>"
    ```

---

### Get User

```
GET /v2.0/users/{id}
```

Returns the compact representation of a specific user.

##### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string (UUID) | Yes | User unique identifier |

##### Response

`200 OK`

```json
{
    "id": "3D1C91F6-754D-427E-9D76-8CC20E8C326E",
    "name": "jdoe",
    "display_name": "John Doe",
    "department": "Engineering",
    "email": "jdoe@example.com",
    "disabled": false,
    "updated_at": "2024-11-20T16:45:00.000Z"
}
```

##### Error Responses

| Status | Description |
|--------|-------------|
| `401 Unauthorized` | Missing or invalid authentication token |
| `404 Not Found` | User not found |

##### Example

=== "curl"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/users/3D1C91F6-754D-427E-9D76-8CC20E8C326E" \
        -H "Authorization: Bearer <token>"
    ```

---

## Admin Endpoints

These endpoints require an **admin-scoped session** (`"scope": "admin"` at login).

### List Users (Admin)

```
GET /v2.0/admin/users
```

Returns a paginated list of all users on the server.

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
            "id": "9A6DBC50-B8FF-487F-964A-96858296B8F5",
            "name": "admin",
            "auth_modes": ["standard"],
            "display_name": "Administrator (built-in account)",
            "department": "R&D",
            "email": "admin@example.com",
            "phone": null,
            "sam": null,
            "upn": null,
            "dn": null,
            "objectId": null,
            "disabled": false,
            "must_change_pass": false,
            "cannot_change_pass": false,
            "roles": ["super_admin", "server_admin"],
            "member_of": [],
            "updated_at": "2024-01-15T09:00:00.000Z"
        },
        {
            "id": "3D1C91F6-754D-427E-9D76-8CC20E8C326E",
            "name": "jdoe",
            "auth_modes": ["sspi", "iwa", "webauthn"],
            "display_name": "John Doe",
            "department": "Engineering",
            "email": "jdoe@example.com",
            "phone": null,
            "sam": "DOMAIN\\jdoe",
            "upn": "jdoe@domain.local",
            "dn": "CN=John Doe,CN=Users,DC=domain,DC=local",
            "objectId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
            "disabled": false,
            "must_change_pass": false,
            "cannot_change_pass": false,
            "roles": ["server_admin", "db_admin", "log_reader"],
            "member_of": [
                "FEAE7AC9-58D1-4A76-82A6-2C7DB135CFDD"
            ],
            "updated_at": "2024-11-20T16:45:00.000Z"
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
    curl -X GET "https://<server>:8714/v2.0/admin/users?offset=0&limit=100" \
        -H "Authorization: Bearer <token>"
    ```

---

### Create User (Admin)

```
POST /v2.0/admin/users
```

Creates a new user.

#### Request Body

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `name` | string | Yes | Username |
| `new_password` | string | Conditional | Initial password (plaintext). **Required** when `auth_modes` contains `"standard"` (the default). Optional for users that will only authenticate via OIDC, SSPI, IWA, or WebAuthn. |
| `auth_modes` | array of strings | No | Allowed authentication methods (default: `["standard"]`) |
| `display_name` | string | No | Display name |
| `department` | string | No | Department |
| `email` | string | Conditional | Email address. **Required** if the effective 2FA mode for this user is `email` (see `two_factor_mode`). |
| `phone` | string | No | Phone number |
| `two_factor_mode` | string | No | Per-user 2FA mode: `"default"` (inherit server setting), `"disabled"`, `"totp"`, `"email"`, `"fido2"`. See the [User Object](#user-object) reference. For service accounts, set `"disabled"` to opt out. |
| `sam` | string | No | SAM account name |
| `upn` | string | No | User Principal Name |
| `dn` | string | No | Distinguished Name |
| `objectId` | string | No | Active Directory object ID (GUID) |
| `disabled` | boolean | No | Whether the account is disabled (default: `false`) |
| `must_change_pass` | boolean | No | User must change password on next login (default: `false`) |
| `cannot_change_pass` | boolean | No | User is not allowed to change their own password (default: `false`) |
| `roles` | array of strings | No | Server roles (requires `server_admin` role) |
| `member_of` | array of UUIDs | No | Group IDs this user should belong to |

```json
{
    "name": "jsmith",
    "new_password": "Initial!P@ss1",
    "auth_modes": ["standard"],
    "display_name": "Jane Smith",
    "department": "Engineering",
    "email": "jsmith@example.com",
    "member_of": [
        "FEAE7AC9-58D1-4A76-82A6-2C7DB135CFDD"
    ]
}
```

!!! warning "Password transport"
    `new_password` is sent as **plaintext** in the JSON body -- the server hashes and stores it. Always call this endpoint over HTTPS. The server applies the configured password policy (complexity, length) if one is active; otherwise it only rejects empty strings.

!!! tip "Service account recipe"
    Automation / service accounts (CI pipelines, cron jobs, gMSA) usually don't have an email address. If the server-wide 2FA default is `"email"`, the account will be locked out at first login. Opt out explicitly:

    ```json
    {
        "name": "svc_ci",
        "new_password": "<long random>",
        "auth_modes": ["standard"],
        "two_factor_mode": "disabled",
        "display_name": "CI Service Account"
    }
    ```

!!! note "Response never includes the password"
    The response object for `POST /admin/users` never echoes the `new_password` field back. The password is hashed immediately and only the hash is retained server-side.

#### Response

`201 Created`

```json
{
    "id": "56E4205C-0D50-47E9-90B8-B751EF19A165",
    "name": "jsmith",
    "auth_modes": ["standard"],
    "display_name": "Jane Smith",
    "department": "Engineering",
    "email": "jsmith@example.com",
    "phone": null,
    "sam": null,
    "upn": null,
    "dn": null,
    "objectId": null,
    "disabled": false,
    "must_change_pass": false,
    "cannot_change_pass": false,
    "roles": [],
    "member_of": [
        "FEAE7AC9-58D1-4A76-82A6-2C7DB135CFDD"
    ],
    "updated_at": "2024-11-20T14:30:00.000Z"
}
```

#### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | Invalid or missing required fields. Includes: missing `new_password` for a standard-auth user, empty `new_password`, or password that violates the configured policy. |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions to create users, or attempted to set `roles` without `server_admin` role |
| `409 Conflict` | A user with this username already exists |

#### Example

=== "curl"

    ```bash
    curl -X POST "https://<server>:8714/v2.0/admin/users" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "jsmith",
            "new_password": "Initial!P@ss1",
            "auth_modes": ["standard"],
            "display_name": "Jane Smith",
            "department": "Engineering",
            "email": "jsmith@example.com",
            "member_of": ["FEAE7AC9-58D1-4A76-82A6-2C7DB135CFDD"]
        }'
    ```

---

### Get User (Admin)

```
GET /v2.0/admin/users/{id}
```

Returns details of a specific user.

#### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string (UUID) | Yes | User unique identifier |

#### Response

`200 OK`

```json
{
    "id": "3D1C91F6-754D-427E-9D76-8CC20E8C326E",
    "name": "jdoe",
    "auth_modes": ["sspi", "iwa", "webauthn"],
    "display_name": "John Doe",
    "department": "Engineering",
    "email": "jdoe@example.com",
    "phone": null,
    "sam": "DOMAIN\\jdoe",
    "upn": "jdoe@domain.local",
    "dn": "CN=John Doe,CN=Users,DC=domain,DC=local",
    "objectId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "disabled": false,
    "must_change_pass": false,
    "cannot_change_pass": false,
    "roles": ["server_admin", "db_admin", "log_reader"],
    "member_of": [
        "FEAE7AC9-58D1-4A76-82A6-2C7DB135CFDD"
    ],
    "updated_at": "2024-11-20T16:45:00.000Z"
}
```

#### Error Responses

| Status | Description |
|--------|-------------|
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions |
| `404 Not Found` | User not found |

#### Example

=== "curl"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/admin/users/3D1C91F6-754D-427E-9D76-8CC20E8C326E" \
        -H "Authorization: Bearer <token>"
    ```

---

### Update User (Admin)

```
PATCH /v2.0/admin/users/{id}
```

Updates an existing user. This endpoint is also used to modify group membership by updating the `member_of` field.

#### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string (UUID) | Yes | User unique identifier |

#### Request Body

Include only the fields you want to update.

```json
{
    "display_name": "John A. Doe",
    "department": "R&D",
    "member_of": [
        "FEAE7AC9-58D1-4A76-82A6-2C7DB135CFDD",
        "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
    ]
}
```

!!! tip "Managing Group Membership"
    To add a user to a group, include the new group ID in the `member_of` array alongside the existing group IDs. To remove a user from a group, omit that group ID from the array.

!!! warning "Passwords cannot be changed via PATCH"
    Including `password` or `new_password` in a PATCH body returns `400 Bad Request`. Use the dedicated endpoint [POST /admin/users/{id}/password](#change-password-admin) to rotate a user's password.

#### Response

`200 OK`

```json
{
    "id": "3D1C91F6-754D-427E-9D76-8CC20E8C326E",
    "name": "jdoe",
    "auth_modes": ["sspi", "iwa", "webauthn"],
    "display_name": "John A. Doe",
    "department": "R&D",
    "email": "jdoe@example.com",
    "phone": null,
    "sam": "DOMAIN\\jdoe",
    "upn": "jdoe@domain.local",
    "dn": "CN=John Doe,CN=Users,DC=domain,DC=local",
    "objectId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "disabled": false,
    "must_change_pass": false,
    "cannot_change_pass": false,
    "roles": ["server_admin", "db_admin", "log_reader"],
    "member_of": [
        "FEAE7AC9-58D1-4A76-82A6-2C7DB135CFDD",
        "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
    ],
    "updated_at": "2024-11-21T10:15:00.000Z"
}
```

#### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | Invalid fields |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions, or attempted to modify `roles` without `server_admin` role |
| `404 Not Found` | User or referenced group not found |
| `409 Conflict` | Username conflict |

#### Example

=== "curl"

    ```bash
    curl -X PATCH "https://<server>:8714/v2.0/admin/users/3D1C91F6-754D-427E-9D76-8CC20E8C326E" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -d '{
            "display_name": "John A. Doe",
            "department": "R&D",
            "member_of": [
                "FEAE7AC9-58D1-4A76-82A6-2C7DB135CFDD",
                "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
            ]
        }'
    ```

---

### Delete User (Admin)

```
DELETE /v2.0/admin/users/{id}
```

Deletes a user.

#### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string (UUID) | Yes | User unique identifier |

#### Response

`204 No Content`

No response body.

#### Error Responses

| Status | Description |
|--------|-------------|
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions to delete users |
| `404 Not Found` | User not found |

#### Example

=== "curl"

    ```bash
    curl -X DELETE "https://<server>:8714/v2.0/admin/users/u1a2b3c4-d5e6-7890-abcd-ef1234567890" \
        -H "Authorization: Bearer <token>"
    ```

---

### Change Password (Admin)

```
POST /v2.0/admin/users/{id}/password
```

Sets a new password for a user. Only users whose `auth_modes` include `"standard"` support password changes via this endpoint.

!!! note "Plaintext in, hash stored"
    `new_password` is sent as **plaintext** -- the server hashes it and only stores the hash. Always call this endpoint over HTTPS. The server applies the configured password policy if one is active.

!!! warning "Not for self-service"
    A regular admin cannot call this endpoint against their own account (returns `403`) -- use [`POST /v2.0/me/password`](#change-own-password) instead, which requires the current password for self-service changes.

    The built-in **super-administrator** password cannot be changed via **any** REST endpoint (both `/admin/users/{id}/password` and `/me/password` return `403` for this account). Use the Password Depot Server Manager (native admin application) to change the super-admin password.

#### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string (UUID) | Yes | User unique identifier |

#### Request Body

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `new_password` | string | Yes | The new password (plaintext; must be non-empty) |

```json
{
    "new_password": "newSecureP@ss123"
}
```

#### Response

`204 No Content`

No response body.

#### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | `new_password` field is missing, empty, or violates the active password policy |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions (includes self-reset attempts -- use `/me/password`), or target user is a built-in super admin account |
| `404 Not Found` | User not found |
| `409 Conflict` | Target user does not use standard authentication (`auth_modes` does not include `"standard"`) |

#### Example

=== "curl"

    ```bash
    curl -X POST "https://<server>:8714/v2.0/admin/users/u1a2b3c4-d5e6-7890-abcd-ef1234567890/password" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -d '{
            "new_password": "newSecureP@ss123"
        }'
    ```

---

## Passkeys (WebAuthn)

Endpoints to manage WebAuthn / FIDO2 passkeys for the current user (`/me/passkeys/...`) and -- for administrators -- to view and revoke any user's passkeys (`/admin/users/{id}/passkeys/...`).

Passkeys can be used as a passwordless login method via the [`webauthn`](authentication.md#webauthn) auth flow. Server-wide WebAuthn must be enabled in the server options, and the user must have the `webauthn` auth mode in their `auth_modes`.

!!! note
    The public key material (`pk`) and signature counter internals are never exposed via the REST API -- the server uses them only for assertion verification.

### Passkey Object

**Compact representation** (returned in lists and inside the user `passkeys` array):

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Credential ID (Base64URL-encoded), unique per credential |
| `name` | string | Friendly display name (e.g., `"MacBook TouchID"`, `"YubiKey 5C"`) |
| `transports` | array of strings | Authenticator transports: `"usb"`, `"nfc"`, `"ble"`, `"internal"`, `"hybrid"` |
| `created_at` | string (ISO 8601) | When the passkey was registered |
| `last_used_at` | string (ISO 8601) | Last time the passkey was used to authenticate |

**Full representation** (returned by registration completion):

Adds:

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | Always `"public-key"` (WebAuthn standard) |
| `alg` | integer | COSE algorithm identifier (e.g., `-7` for ES256, `-257` for RS256) |
| `sign_count` | integer | Server-tracked signature counter (used to detect cloned authenticators) |

---

### List Own Passkeys

```
GET /v2.0/me/passkeys
```

Returns the authenticated user's registered passkeys. Same as the `passkeys` array embedded in `GET /me`, but useful when you only need passkey data.

#### Response

`200 OK`

```json
{
    "data": [
        {
            "id": "AQIDBAUGBwgJCgsMDQ4PEA",
            "name": "MacBook TouchID",
            "transports": ["internal", "hybrid"],
            "created_at": "2026-01-15T08:30:00.000Z",
            "last_used_at": "2026-03-30T14:22:11.000Z"
        }
    ],
    "total": 1,
    "offset": 0,
    "limit": 100
}
```

---

### Register Passkey -- Begin

```
POST /v2.0/me/passkeys/begin
```

Starts the registration ceremony. The server returns standard WebAuthn `PublicKeyCredentialCreationOptions`. The browser should pass these options (after Base64URL-decoding the challenge and user.id) to `navigator.credentials.create()`.

The response also includes a `session_id` that **must** be sent back in the completion request. Pending sessions expire after the server-configured WebAuthn timeout (default 120 seconds).

#### Request Body

Empty (or `{}`).

#### Response

`200 OK`

```json
{
    "session_id": "B7F3A1D2-9C42-4E18-A6E1-3F5C7B8A9D0E",
    "publicKey": {
        "rp": { "id": "your-server.example.com", "name": "Password Depot Server" },
        "user": { "id": "...", "name": "john.doe", "displayName": "John Doe" },
        "challenge": "...",
        "pubKeyCredParams": [...],
        "timeout": 120000,
        "excludeCredentials": [
            { "id": "AQIDBAU...", "type": "public-key", "transports": ["internal"] }
        ],
        "authenticatorSelection": {...},
        "attestation": "none"
    }
}
```

#### Errors

| Status | Description |
|--------|-------------|
| `400 Bad Request` | WebAuthn is disabled on the server |
| `401 Unauthorized` | Missing or invalid token |

---

### Register Passkey -- Complete

```
POST /v2.0/me/passkeys/complete
```

Finishes the registration ceremony. Pass the `session_id` from `/begin`, the authenticator's response (Base64URL-encoded fields), and an optional friendly `name`. If `name` is omitted or already in use, the server auto-generates a unique name (`Passkey_1`, `Passkey_2`, ...).

#### Request Body

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `session_id` | string | Yes | Returned by `/begin` |
| `name` | string | No | Friendly name (e.g., `"YubiKey 5C"`) |
| `id` | string | Yes | Credential ID (Base64URL) |
| `rawId` | string | Yes | Same as `id`, raw bytes |
| `type` | string | Yes | Always `"public-key"` |
| `response.attestationObject` | string | Yes | Base64URL CBOR attestation |
| `response.clientDataJSON` | string | Yes | Base64URL JSON client data |
| `response.transports` | array | No | Reported authenticator transports |

#### Response

`201 Created` -- full representation of the newly registered passkey.

```json
{
    "id": "AQIDBAUGBwgJCgsMDQ4PEA",
    "name": "MacBook TouchID",
    "transports": ["internal", "hybrid"],
    "created_at": "2026-03-30T15:00:00.000Z",
    "last_used_at": "2026-03-30T15:00:00.000Z",
    "type": "public-key",
    "alg": -7,
    "sign_count": 0
}
```

#### Errors

| Status | Description |
|--------|-------------|
| `400 Bad Request` | Attestation validation failed (returns the underlying reason in `error.message`) |
| `401 Unauthorized` | `session_id` not found, expired, or already used |
| `403 Forbidden` | Completion attempted by a different user than the one that initiated `/begin` |
| `408 Request Timeout` | Session expired before completion |

---

### Rename Passkey

```
PATCH /v2.0/me/passkeys/{id}
```

Updates the friendly name of one of the caller's passkeys.

#### Request Body

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `name` | string | Yes | New friendly name (must be unique within the user's passkeys) |

```json
{ "name": "Office YubiKey" }
```

#### Response

`200 OK` -- full representation of the renamed passkey.

#### Errors

| Status | Description |
|--------|-------------|
| `400 Bad Request` | Empty name |
| `404 Not Found` | Passkey with the given `id` doesn't exist on this user |
| `409 Conflict` | Another passkey with that name already exists |

---

### Delete Own Passkey

```
DELETE /v2.0/me/passkeys/{id}
```

Removes one of the caller's passkeys. Cannot be undone -- the passkey can no longer be used to log in (the user must re-register it from the same authenticator).

#### Response

`204 No Content`

#### Errors

| Status | Description |
|--------|-------------|
| `404 Not Found` | Passkey not found |

---

### Admin: List Any User's Passkeys

```
GET /v2.0/admin/users/{user_id}/passkeys
```

Same response format as `GET /me/passkeys`, but returns the passkeys of any user. Requires the **server administrator** or **user administrator** role.

#### Errors

| Status | Description |
|--------|-------------|
| `403 Forbidden` | Caller does not have the required role |
| `404 Not Found` | User not found |

---

### Admin: Revoke Any User's Passkey

```
DELETE /v2.0/admin/users/{user_id}/passkeys/{id}
```

Revokes (deletes) any passkey belonging to any user. Useful when a user loses an authenticator. Requires the **server administrator** or **user administrator** role.

#### Response

`204 No Content`

#### Errors

| Status | Description |
|--------|-------------|
| `403 Forbidden` | Caller does not have the required role |
| `404 Not Found` | User or passkey not found |

!!! note "Why no admin POST?"
    Admins cannot register a passkey *for* another user -- the authenticator (security key, biometric sensor) must be physically present at the user's machine. The user must perform `/me/passkeys/begin` + `/complete` themselves.
