# Secrets

Reference for managing shared secrets (shared links) on the Password Depot Enterprise Server. Secrets allow a user to share access to a specific password entry with other users or groups, either via an HTTPS link (accessible in a browser) or via the `pd-server://` protocol (accessible in the Password Depot binary client).

Secrets are accessible in both **client** and **admin** scopes:

| Scope | Endpoints | Description |
|-------|-----------|-------------|
| Client | `GET/POST /v2.0/secrets`, `GET/DELETE /v2.0/secrets/{id}` | Create and manage own secrets. Users see only secrets they authored. |
| Client | `POST /v2.0/secrets/{id}/approve`, `POST /v2.0/secrets/{id}/reject` | Approve or reject secrets where the user is a designated approver |
| Client | `POST /v2.0/secrets/{id}/revoke` | Revoke own secrets |
| Admin | `GET/POST /v2.0/admin/secrets`, `GET/PATCH/DELETE /v2.0/admin/secrets/{id}` | Full CRUD on all secrets |
| Admin | `POST /v2.0/admin/secrets/{id}/approve`, `POST /v2.0/admin/secrets/{id}/reject`, `POST /v2.0/admin/secrets/{id}/revoke` | All workflow actions on any secret |

---

## Secret Object

The secret object uses different representations depending on context:

- **List** responses return a **compact representation**: core identification and status fields.
- **Detail** responses (`GET .../secrets/{id}`) and mutation responses return the **full representation** with all fields, including approval workflow details and access UUIDs.

### Compact Representation

| Field | Type | Description |
|-------|------|-------------|
| `id` | string (UUID) | Unique identifier (read-only) |
| `type` | string | Content type: `"entry"`, `"text"`, or `"file"` (currently only `"entry"` is supported) |
| `status` | string | Current status (see [Secret Statuses](#secret-statuses)) |
| `protocol` | string | Access protocol: `"https"` or `"pd-server"` |
| `author` | string (UUID) | User ID of the secret creator (read-only) |
| `database_id` | string (UUID) | Database containing the shared entry |
| `database_name` | string | Database display name |
| `entry_id` | string (UUID) | Shared entry ID |
| `entry_path` | string | Full path to the entry within the database |
| `entry_user` | string | Username field of the shared entry |
| `entry_type` | string | Entry type (e.g., `"password"`, `"credit_card"`) |
| `created_at` | string (ISO 8601) | Creation timestamp (read-only) |
| `expires_at` | string (ISO 8601) or null | Expiration timestamp, or `null` if not set |

### Full Representation

Includes all compact fields plus:

| Field | Type | Writable | Description |
|-------|------|:--------:|-------------|
| `notes` | string | Yes | Notes for approvers or recipients |
| `access_max` | integer | Yes | Maximum number of times the secret can be opened (default: `1`) |
| `access_count` | integer | No | Current number of times the secret has been opened (read-only) |
| `include_totp` | boolean | Yes | Whether to include TOTP codes when displaying the secret (default: `true`) |
| `approval_required` | boolean | Yes | Whether supervisor approval is required before the secret becomes available |
| `quorum_n` | integer | Yes | Number of approvals required (default: `1`) |
| `quorum_m` | integer | Yes | Total number of designated approvers (default: `2`) |
| `require_2fa` | boolean | Yes | Whether 2FA is required to open the secret |
| `recipient_ids` | array of UUIDs | Yes | User or group IDs who can open the secret (for `pd-server` protocol) |
| `approver_ids` | array of UUIDs | Yes | User IDs designated as approvers |
| `approved_by` | array of objects | No | List of received approvals (read-only, see below) |
| `rejected_by` | array of objects | No | List of received rejections (read-only, see below) |
| `open_uuid` | string | No | Bearer token for the open link (read-only). Returned only to the author and to the users in `recipient_ids` — see [Who receives the link tokens](#who-receives-the-link-tokens) |
| `approve_uuid` | string | No | Bearer token for the approve link (read-only). Returned only to the author and to the users in `approver_ids` |

**Approval/rejection entries:**

```json
{
    "user_id": "3FA85F64-5717-4562-B3FC-2C963F66AFA6",
    "timestamp": "2026-03-18T14:30:00.000Z"
}
```

### Secret Statuses

| Value | Description |
|-------|-------------|
| `pending` | Secret created, not yet processed |
| `pending_approval` | Waiting for supervisor approval (when `approval_required` is `true`) |
| `approved` | Approved but not yet available |
| `available` | Ready to be opened by recipients |
| `consumed` | All allowed accesses have been used (`access_count >= access_max`) |
| `rejected` | Rejected by an approver |
| `revoked` | Revoked by the author or an admin |
| `expired` | Expiration date has passed |

### Secret Lifecycle

```
                                ┌─────────────┐
                    ┌──────────►│  available   │◄──── quorum reached
                    │           └──────┬───────┘
                    │                  │ opened access_max times
                    │                  ▼
  POST /secrets ───►│           ┌─────────────┐
                    │           │  consumed    │
  approval_required │           └─────────────┘
  = false           │
                    │
  approval_required │    ┌──────────────────┐
  = true  ─────────►│   │ pending_approval  │
                         └───────┬──────┬───┘
                        approved │      │ rejected
                                 ▼      ▼
                          ┌─────────┐ ┌──────────┐
                          │available│ │ rejected  │
                          └─────────┘ └──────────┘

  At any time (by author or admin):
  POST .../revoke ────► revoked
  Expiration reached ─► expired
```

### Access URLs

When a secret is created, the server generates two UUID hashes (`open_uuid` and `approve_uuid`) that are used to construct access links:

| Protocol | Open Link | Approve Link |
|----------|-----------|--------------|
| `https` | `https://<server>:<port>/shared/<open_uuid>` | N/A (approval via API or binary client) |
| `pd-server` | `pd-server://<server>:<port>/shared/open/<open_uuid>` | `pd-server://<server>:<port>/shared/approve/<approve_uuid>` |

The `open_uuid` and `approve_uuid` are returned in the full representation, but only to the callers each token is for. Clients construct the final URLs using the server hostname and port.

### Who receives the link tokens

!!! warning "These UUIDs are credentials"
    `open_uuid` is a **bearer token**. Anyone holding it can redeem the secret
    at the anonymous `/shared/` page — with no session, without being named in
    `recipient_ids`, and without the access being attributable to a user
    account. `approve_uuid` is the same for the approval step.

    They are therefore returned only to the caller each token is for:

    | Field | Returned to |
    |-------|-------------|
    | `open_uuid` | the secret's `author`, and the users named in `recipient_ids` |
    | `approve_uuid` | the secret's `author`, and the users named in `approver_ids` |

    Any other caller receives the secret's metadata with the token field simply
    **absent** — including an administrator reading or listing secrets in the
    admin scope. Approving or rejecting a secret does **not** return
    `open_uuid`: an approver authorises somebody else's access, not their own.

    Treat a missing field as "not for you", not as an error.

    *Changed in Server 20.0.0.* Earlier releases returned both tokens to every
    caller who could see the secret at all.

---

## List Secrets

```
GET /v2.0/secrets
GET /v2.0/admin/secrets
```

Returns a paginated list of secrets. In **client scope**, only secrets authored by the current user are returned. In **admin scope**, all secrets are returned.

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
            "type": "entry",
            "status": "available",
            "protocol": "https",
            "author": "3FA85F64-5717-4562-B3FC-2C963F66AFA6",
            "database_id": "E79BDEB2-1A58-4715-B74C-28A87A2AFD37",
            "database_name": "Production",
            "entry_id": "D4FEC05E-7866-4424-A998-4D96FF8B183E",
            "entry_path": "Infrastructure\\Servers\\AWS Root",
            "entry_user": "admin@aws.com",
            "entry_type": "password",
            "created_at": "2026-03-18T10:00:00.000Z",
            "expires_at": "2026-03-25T10:00:00.000Z"
        },
        {
            "id": "B2C3D4E5-F6A7-8901-BCDE-F12345678901",
            "type": "entry",
            "status": "pending_approval",
            "protocol": "pd-server",
            "author": "3FA85F64-5717-4562-B3FC-2C963F66AFA6",
            "database_id": "E79BDEB2-1A58-4715-B74C-28A87A2AFD37",
            "database_name": "Production",
            "entry_id": "1CA4DF0E-2E59-4735-8FD7-3DF7DF43C638",
            "entry_path": "Infrastructure\\Servers\\DB Master",
            "entry_user": "root",
            "entry_type": "password",
            "created_at": "2026-03-18T11:00:00.000Z",
            "expires_at": "2026-03-19T11:00:00.000Z"
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
| `403 Forbidden` | Session does not have admin scope (admin endpoint only) |

### Examples

=== "curl (client scope)"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/secrets?offset=0&limit=100" \
        -H "Authorization: Bearer <token>"
    ```

=== "curl (admin scope)"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/admin/secrets?offset=0&limit=100" \
        -H "Authorization: Bearer <token>"
    ```

---

## Create Secret

```
POST /v2.0/secrets
POST /v2.0/admin/secrets
```

Creates a new shared secret for an entry. The caller must have **share permission** on the referenced entry. Entries protected by a second password cannot be shared.

### Request Body

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `type` | string | No | Content type (default: `"entry"`). Currently only `"entry"` is supported. |
| `protocol` | string | No | Access protocol: `"https"` (default) or `"pd-server"` |
| `database_id` | string (UUID) | Yes | Database containing the entry to share |
| `entry_id` | string (UUID) | Yes | Entry to share |
| `expires_at` | string (ISO 8601) | No | Expiration timestamp |
| `notes` | string | No | Notes for approvers or recipients |
| `access_max` | integer | No | Maximum number of openings (default: `1`) |
| `include_totp` | boolean | No | Include TOTP codes (default: `true`) |
| `approval_required` | boolean | No | Require supervisor approval (default: `false`) |
| `quorum_n` | integer | No | Approvals required (default: `1`) |
| `quorum_m` | integer | No | Total approvers (default: `2`) |
| `require_2fa` | boolean | No | Require 2FA to open (default: `false`) |
| `recipient_ids` | array of UUIDs | No | User/group IDs who can open the secret |
| `approver_ids` | array of UUIDs | No | User IDs designated as approvers |

!!! note
    The `database_name`, `entry_path`, `entry_user`, and `entry_type` fields are auto-populated from the referenced entry if not provided in the request.

```json
{
    "database_id": "E79BDEB2-1A58-4715-B74C-28A87A2AFD37",
    "entry_id": "D4FEC05E-7866-4424-A998-4D96FF8B183E",
    "protocol": "https",
    "expires_at": "2026-03-25T10:00:00.000Z",
    "access_max": 3,
    "notes": "Temporary access for the ops team"
}
```

### Response

`201 Created`

Returns the full representation of the created secret. The `status` is set to `"available"` (or `"pending_approval"` if `approval_required` is `true`).

```json
{
    "id": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
    "type": "entry",
    "status": "available",
    "protocol": "https",
    "author": "3FA85F64-5717-4562-B3FC-2C963F66AFA6",
    "database_id": "E79BDEB2-1A58-4715-B74C-28A87A2AFD37",
    "database_name": "Production",
    "entry_id": "D4FEC05E-7866-4424-A998-4D96FF8B183E",
    "entry_path": "Infrastructure\\Servers\\AWS Root",
    "entry_user": "admin@aws.com",
    "entry_type": "password",
    "created_at": "2026-03-18T10:00:00.000Z",
    "expires_at": "2026-03-25T10:00:00.000Z",
    "notes": "Temporary access for the ops team",
    "access_max": 3,
    "access_count": 0,
    "include_totp": true,
    "approval_required": false,
    "quorum_n": 1,
    "quorum_m": 2,
    "require_2fa": false,
    "recipient_ids": [],
    "approver_ids": [],
    "approved_by": [],
    "rejected_by": [],
    "open_uuid": "a8f5f167f44f4964e6c998dee827110c",
    "approve_uuid": "b9e6e278e55e5a75f7da99eff938221d"
}
```

!!! tip "Constructing Access Links"
    Use the returned `open_uuid` to construct the access link:

    - **HTTPS**: `https://<server>:8714/shared/a8f5f167f44f4964e6c998dee827110c`
    - **PD Server**: `pd-server://<server>:25019/shared/open/a8f5f167f44f4964e6c998dee827110c`

### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | Invalid or missing required fields, or entry is protected by a second password |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions (no share permission on the entry) |
| `404 Not Found` | Database or entry not found |

### Example

=== "curl"

    ```bash
    curl -X POST "https://<server>:8714/v2.0/secrets" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -d '{
            "database_id": "E79BDEB2-1A58-4715-B74C-28A87A2AFD37",
            "entry_id": "D4FEC05E-7866-4424-A998-4D96FF8B183E",
            "protocol": "https",
            "expires_at": "2026-03-25T10:00:00.000Z",
            "access_max": 3,
            "notes": "Temporary access for the ops team"
        }'
    ```

=== "curl (with approval workflow)"

    ```bash
    curl -X POST "https://<server>:8714/v2.0/secrets" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -d '{
            "database_id": "E79BDEB2-1A58-4715-B74C-28A87A2AFD37",
            "entry_id": "D4FEC05E-7866-4424-A998-4D96FF8B183E",
            "protocol": "pd-server",
            "expires_at": "2026-03-19T11:00:00.000Z",
            "approval_required": true,
            "quorum_n": 2,
            "quorum_m": 3,
            "recipient_ids": ["USER-UUID-1", "USER-UUID-2"],
            "approver_ids": ["SUPERVISOR-UUID-1", "SUPERVISOR-UUID-2", "SUPERVISOR-UUID-3"],
            "notes": "Need emergency access to DB credentials"
        }'
    ```

---

## Get Secret

```
GET /v2.0/secrets/{id}
GET /v2.0/admin/secrets/{id}
```

Returns the **full representation** of a specific secret. In client scope, the caller must be the author of the secret.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string (UUID) | Yes | Secret unique identifier |

### Response

`200 OK`

```json
{
    "id": "B2C3D4E5-F6A7-8901-BCDE-F12345678901",
    "type": "entry",
    "status": "pending_approval",
    "protocol": "pd-server",
    "author": "3FA85F64-5717-4562-B3FC-2C963F66AFA6",
    "database_id": "E79BDEB2-1A58-4715-B74C-28A87A2AFD37",
    "database_name": "Production",
    "entry_id": "1CA4DF0E-2E59-4735-8FD7-3DF7DF43C638",
    "entry_path": "Infrastructure\\Servers\\DB Master",
    "entry_user": "root",
    "entry_type": "password",
    "created_at": "2026-03-18T11:00:00.000Z",
    "expires_at": "2026-03-19T11:00:00.000Z",
    "notes": "Need emergency access to DB credentials",
    "access_max": 1,
    "access_count": 0,
    "include_totp": true,
    "approval_required": true,
    "quorum_n": 2,
    "quorum_m": 3,
    "require_2fa": false,
    "recipient_ids": ["USER-UUID-1", "USER-UUID-2"],
    "approver_ids": ["SUPERVISOR-UUID-1", "SUPERVISOR-UUID-2", "SUPERVISOR-UUID-3"],
    "approved_by": [
        {
            "user_id": "SUPERVISOR-UUID-1",
            "timestamp": "2026-03-18T12:00:00.000Z"
        }
    ],
    "rejected_by": [],
    "open_uuid": "c7d8e389f66f6b86g8eb00fgg049332e",
    "approve_uuid": "d8e9f490g77g7c97h9fc11ghh150443f"
}
```

!!! note "The two UUID fields depend on who is asking"
    This example is the response the secret's **author** receives. An
    approver sees the same object with `open_uuid` absent, and a caller who
    is neither author, recipient nor approver — an administrator in the
    admin scope, for instance — sees it with both fields absent. See
    [Who receives the link tokens](#who-receives-the-link-tokens).

### Error Responses

| Status | Description |
|--------|-------------|
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Not the author (client scope) or session does not have admin scope |
| `404 Not Found` | Secret not found |

### Example

=== "curl"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/secrets/B2C3D4E5-F6A7-8901-BCDE-F12345678901" \
        -H "Authorization: Bearer <token>"
    ```

---

## Update Secret (Admin)

```
PATCH /v2.0/admin/secrets/{id}
```

Updates an existing secret. **Admin scope only.** Include only the fields you want to update.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string (UUID) | Yes | Secret unique identifier |

### Request Body

```json
{
    "expires_at": "2026-04-01T10:00:00.000Z",
    "access_max": 5,
    "notes": "Extended access per ticket #1234"
}
```

### Response

`200 OK`

Returns the full representation of the updated secret.

### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | Invalid fields |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions (requires Server Administrator role) |
| `404 Not Found` | Secret not found |

### Example

=== "curl"

    ```bash
    curl -X PATCH "https://<server>:8714/v2.0/admin/secrets/A1B2C3D4-E5F6-7890-ABCD-EF1234567890" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -d '{
            "expires_at": "2026-04-01T10:00:00.000Z",
            "access_max": 5
        }'
    ```

---

## Delete Secret

```
DELETE /v2.0/secrets/{id}
DELETE /v2.0/admin/secrets/{id}
```

Deletes a secret permanently. In client scope, the caller must be the author.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string (UUID) | Yes | Secret unique identifier |

### Response

`204 No Content`

No response body.

### Error Responses

| Status | Description |
|--------|-------------|
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Not the author (client scope) or insufficient permissions |
| `404 Not Found` | Secret not found |

### Example

=== "curl"

    ```bash
    curl -X DELETE "https://<server>:8714/v2.0/secrets/A1B2C3D4-E5F6-7890-ABCD-EF1234567890" \
        -H "Authorization: Bearer <token>"
    ```

---

## Approve Secret

```
POST /v2.0/secrets/{id}/approve
POST /v2.0/admin/secrets/{id}/approve
```

Approves a secret that is in `pending_approval` status. The caller must be listed in the secret's `approver_ids`. When the number of approvals reaches `quorum_n`, the secret transitions to `available` status.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string (UUID) | Yes | Secret unique identifier |

### Request Body (optional)

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `extends` | integer | No | Extend the expiration by this many minutes from now |

```json
{
    "extends": 60
}
```

### Response

`200 OK`

Returns the full representation of the secret with updated status and `approved_by` list.

### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | Secret is not in `pending_approval` status |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Caller is not a designated approver |
| `404 Not Found` | Secret not found |

### Example

=== "curl"

    ```bash
    curl -X POST "https://<server>:8714/v2.0/secrets/B2C3D4E5-F6A7-8901-BCDE-F12345678901/approve" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -d '{"extends": 60}'
    ```

---

## Reject Secret

```
POST /v2.0/secrets/{id}/reject
POST /v2.0/admin/secrets/{id}/reject
```

Rejects a secret that is in `pending_approval` status. The caller must be listed in the secret's `approver_ids`. The secret transitions to `rejected` status immediately.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string (UUID) | Yes | Secret unique identifier |

### Response

`200 OK`

Returns the full representation of the secret with `rejected` status.

### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | Secret is not in `pending_approval` status |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Caller is not a designated approver |
| `404 Not Found` | Secret not found |

### Example

=== "curl"

    ```bash
    curl -X POST "https://<server>:8714/v2.0/secrets/B2C3D4E5-F6A7-8901-BCDE-F12345678901/reject" \
        -H "Authorization: Bearer <token>"
    ```

---

## Revoke Secret

```
POST /v2.0/secrets/{id}/revoke
POST /v2.0/admin/secrets/{id}/revoke
```

Revokes a secret, making it permanently inaccessible. Only the **author** or a **server administrator** can revoke a secret. Cannot be undone.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string (UUID) | Yes | Secret unique identifier |

### Response

`200 OK`

Returns the full representation of the secret with `revoked` status.

### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | Secret is already revoked, consumed, or expired |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Not the author and not an admin |
| `404 Not Found` | Secret not found |

### Example

=== "curl"

    ```bash
    curl -X POST "https://<server>:8714/v2.0/secrets/A1B2C3D4-E5F6-7890-ABCD-EF1234567890/revoke" \
        -H "Authorization: Bearer <token>"
    ```
