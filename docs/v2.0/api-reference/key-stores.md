# Key Stores

*Server 20.0.0 and later.*

The server keeps its keys in two key stores: the **configuration key store** (`config`), which also holds the super administrator password -- the sign-in password of the built-in administrator --, and the **audit key store** (`audit`), which protects the audit trail. Each key store also opens with its own **recovery code**, which is shown once, to the person who writes it down, and then typed back to confirm that it was written down correctly. The endpoints on this page read the state of both key stores, confirm a recovery code, issue a new one, and change or reset the super administrator password, in an **admin-scoped session** (`"scope": "admin"` at login). They are the functions of **Tools > Recovery Keys > Recovery Codes** and of the super administrator password in the Server Manager, under the same rules, recorded in the audit trail the same way.

| Method | Path | Description |
|--------|------|-------------|
| `GET` | [`/v2.0/admin/key-stores`](#get-key-store-status) | The state of both key stores |
| `POST` | [`/v2.0/admin/key-stores/recovery-code/confirm`](#confirm-a-recovery-code) | Confirm a recovery code by typing it back |
| `POST` | [`/v2.0/admin/key-stores/recovery-code`](#issue-a-new-recovery-code) | Issue a new recovery code, proved by the current code or the super administrator password |
| `POST` | [`/v2.0/admin/key-stores/super-admin-password`](#change-or-reset-the-super-administrator-password) | Change the super administrator password, or reset it with the configuration key store's recovery code |

Path segments are case-sensitive, and one trailing slash is no segment. Any other path under `/v2.0/admin/key-stores` answers `404`; any other method answers `405` with an `Allow` header (`GET` on the status, `POST` on the others).

---

## Who May

- **The built-in administrator, or an account with the Security Officer role** (`security_officer` in [`roles`](users.md#roles-values)) -- the role itself: another role, another super administrator account included, is not enough. Every other caller is answered `403`; on the three `POST` endpoints the refusal is recorded in the audit trail.
- **An admin-scoped session.** A session without the admin scope is answered `403`.
- **Long-lived API tokens** with the admin scope read the [status](#get-key-store-status) only. The three `POST` endpoints answer a request with an API token `403` before its body is read, and record the refusal: a recovery code is meant to be shown to a person, and these changes are made in a signed-in session.

---

## Wrong Passwords and Codes

A wrong current password or recovery code is answered `403` and counted, both for the session and for the client's address, like a failed sign-in -- never against an account:

- After repeated wrong passwords or codes, on any of these endpoints together, **the session ends**: the request that reached the limit is still answered, its token then answers `401`, and a new sign-in is needed. A request of that session already on its way is answered `429`.
- The address counts towards the server's IP lockout, as failed sign-ins do; a blocked address is answered `429` with a `Retry-After` header on every request. The super administrators' cooldown after failed sign-ins (see [Authentication](authentication.md)) answers these endpoints `429` as well.
- A recovery code with a **typing error** -- one whose check characters do not match -- is answered `400` and is not counted: compare it with the code as it was written down.

---

## Get Key Store Status

```
GET /v2.0/admin/key-stores
```

Returns the state of both key stores: never a secret, and no audit record (a read).

### Response

`200 OK`:

```json
{
    "stores": [
        {
            "vault": "config",
            "open": true,
            "identity": "hNzaNvwX7nWfWt_KSyqkfw",
            "fingerprint": "3b60eea8b676521f",
            "generation": 7,
            "machine": "tpm",
            "slots": ["machine", "password", "recovery"],
            "recovery_confirmed": false
        },
        {
            "vault": "audit",
            "open": false
        }
    ]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `vault` | string | `config` or `audit` |
| `open` | boolean | Whether the server opened the key store. A key store that is not open has `vault` and `open` only |
| `identity` | string | The key store's identity, which stays the same for its whole life and is printed with its recovery code |
| `fingerprint` | string | The fingerprint of the key store's root, printed with its recovery code |
| `generation` | integer | The key store's generation; every change raises it |
| `machine` | string | What binds the key store to this computer: `tpm` or `dpapi-machine` (Windows DPAPI) |
| `slots` | array of strings | How the key store opens: `machine` (on this computer), `password` (with the super administrator password; the configuration key store only), `recovery` (with its recovery code) |
| `recovery_confirmed` | boolean | Whether the key store's current recovery code was typed back; while it is `false`, the server's dashboard warns |

All members of one key store are read from one generation.

### Error Responses

| Status | Description |
|--------|-------------|
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Not an admin-scoped session, or the caller is neither the built-in administrator nor a Security Officer |
| `429 Too Many Requests` | The address is blocked (see [Wrong Passwords and Codes](#wrong-passwords-and-codes)) |
| `503 Service Unavailable` | A key store changed while its state was read; read it again |

### Example

=== "curl"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/admin/key-stores" \
        -H "Authorization: Bearer <token>"
    ```

---

## Confirm a Recovery Code

```
POST /v2.0/admin/key-stores/recovery-code/confirm
```

Confirms that the recovery code written down opens its key store. The dashboard's warning for that key store ends.

### Request Body

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `vault` | string | Yes | `config` or `audit` |
| `code` | string | Yes | The recovery code, as written down |

```json
{
    "vault": "config",
    "code": "<recovery code>"
}
```

The body is strict JSON, and every member is taken as it was sent: nothing is trimmed and no letter case is changed.

### Response

`200 OK`:

```json
{
    "vault": "config",
    "recovery_confirmed": true,
    "changed": true,
    "identity": "hNzaNvwX7nWfWt_KSyqkfw",
    "generation": 8
}
```

`changed` is `false` when the code was confirmed before: nothing is written then, and the confirmation is still recorded.

### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | A malformed body; `vault` missing or not `config` or `audit`; a code with a typing error (not counted) |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | The caller may not (see [Who May](#who-may)), a long-lived API token, a code that does not open the key store (counted), or a mirror server |
| `409 Conflict` | A backup is running; confirm the code again when it has finished |
| `413 Payload Too Large` | A body larger than 65535 bytes |
| `429 Too Many Requests` | See [Wrong Passwords and Codes](#wrong-passwords-and-codes) |
| `500 Internal Server Error` | The key store could not be changed; nothing was changed |
| `503 Service Unavailable` | The key store is not open, the code could not be checked, or the audit trail cannot record the confirmation; nothing was changed |

---

## Issue a New Recovery Code

```
POST /v2.0/admin/key-stores/recovery-code
```

Issues a new recovery code for a key store. The previous code no longer opens it; copies of the key store made before, a backup's for example, still open with the previous code. The new code is unconfirmed until it is [typed back](#confirm-a-recovery-code).

### Request Body

The new code is proved either by the key store's current recovery code or by the super administrator password:

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `vault` | string | Yes | `config` or `audit` |
| `by` | string | Yes | `recovery-code` or `password` |
| `code` | string | With `recovery-code` | The key store's current recovery code |
| `current` | string | With `password` | The super administrator password |

```json
{
    "vault": "config",
    "by": "recovery-code",
    "code": "<current recovery code>"
}
```

The audit key store has no password of its own: `"by": "password"` with `"vault": "audit"` is the way in when the audit key store's own code is lost. The super administrator password then stands in for it, which joins the two key stores' separate keeping; the audit trail records it as a kind of its own and the server's Windows event log warns. Keep the new code apart from that password.

### Response

`200 OK`, with `Cache-Control: no-store`:

```json
{
    "vault": "config",
    "by": "recovery-code",
    "code": "<new recovery code>",
    "fingerprint": "3b60eea8b676521f",
    "identity": "hNzaNvwX7nWfWt_KSyqkfw",
    "generation": 9,
    "recovery_confirmed": false
}
```

The members come in this order; the answer is ASCII JSON. Show the code once, to the person who writes it down with the identity and the fingerprint, then have them type it back with [Confirm a Recovery Code](#confirm-a-recovery-code). Never log, store or cache the answer. If the answer is lost, the code it carried is lost as well: issue a new one with the same credential.

### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | A malformed body; `vault` or `by` missing or unknown; a code with a typing error (not counted) |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | The caller may not (see [Who May](#who-may)), a long-lived API token, a wrong current code or password (counted), or a mirror server |
| `409 Conflict` | A backup is running; issue the code again when it has finished |
| `413 Payload Too Large` | A body larger than 65535 bytes |
| `429 Too Many Requests` | See [Wrong Passwords and Codes](#wrong-passwords-and-codes) |
| `500 Internal Server Error` | The new code was saved, but the key file does not open with it, so it was not shown: issue a new code again (the server's system log says why); or the key store could not be changed |
| `503 Service Unavailable` | The key store is not open, the code or password could not be checked, or the audit trail cannot record the change; nothing was changed |

---

## Change or Reset the Super Administrator Password

```
POST /v2.0/admin/key-stores/super-admin-password
```

Changes the super administrator password -- the built-in administrator's sign-in password, which the configuration key store keeps -- with the current password, or resets it with the configuration key store's recovery code.

### Request Body

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `by` | string | Yes | `password` (a change) or `recovery-code` (a reset) |
| `current` | string | With `password` | The current super administrator password |
| `code` | string | With `recovery-code` | The configuration key store's recovery code |
| `new` | string | Yes | The new password |

```json
{
    "by": "password",
    "current": "<current password>",
    "new": "<new password>"
}
```

The new password is taken as it was sent. It may not be empty or `admin` in any letter case, and must be well-formed Unicode text. It must meet the server's [account password policies](users.md#password-rules) for the built-in administrator: the character groups and the minimum length always; the history and the minimum age only when the built-in administrator changes their own password with the current one. A Security Officer's change and every reset are an administrator's setting of the password.

### Response

`200 OK`:

```json
{
    "by": "recovery-code",
    "held": false,
    "recovery_confirmed": true
}
```

`recovery_confirmed` is present after a reset only: the recovery code it used is confirmed by it.

### Sessions After a Change

- The built-in administrator's REST sessions end, and so do their Server Manager and client sessions. When the built-in administrator changes their own password here, their own session ends as well: the `200` is still answered, and the next request needs a new sign-in with the new password.
- Long-lived API tokens of the built-in administrator are kept.
- The administrators receive the alert that the user was modified, as for a change in the Server Manager.

### Sign-Ins Refused With `4038`

A `standard` sign-in of the built-in administrator whose password does not meet the account password policies is answered `403` with `error.code` `4038` (see [Authentication](authentication.md)). Over REST, a Security Officer changes or resets the password with this endpoint; the built-in administrator's next sign-in with the new password is accepted.

### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | A malformed body; `by` missing or unknown; the new password empty, `admin`, not well-formed text or against the account password policies (the message names the rules); a reset code with a typing error (not counted) |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | The caller may not (see [Who May](#who-may)), a long-lived API token, a wrong current password or reset code (counted), or a mirror server |
| `409 Conflict` | A backup is running; change the password again when it has finished |
| `413 Payload Too Large` | A body larger than 65535 bytes |
| `429 Too Many Requests` | See [Wrong Passwords and Codes](#wrong-passwords-and-codes) |
| `500 Internal Server Error` | The password could not be changed |
| `503 Service Unavailable` | The configuration key store is not open, the current password could not be checked, or the audit trail cannot record the change; nothing was changed |

---

## Mirror Servers

Each server keeps its own key stores and its own super administrator password. A mirror server answers the [status](#get-key-store-status) from its own key stores. The three `POST` endpoints answer `403` on a mirror server before the token is examined, as every write there does (see [Mirror servers are read-only](overview.md#http-status-codes)): change a mirror's recovery codes and super administrator password with the Server Manager connected to that mirror, or with `pd_keys` on it.

---

## Audit Trail

Each confirmation, new recovery code and password change is recorded in the audit trail (`GET /admin/audit`) with the REST API as the channel (`rest`), the same records a change in the Server Manager writes:

| `kind` | Recorded for |
|--------|--------------|
| `907` | A new recovery code |
| `918` | A new recovery code of the audit key store issued with the super administrator password |
| `917` | A recovery code typed back |
| `915` | A change of the super administrator password |
| `916` | A reset of the super administrator password with the recovery code |

The record is written before the key store changes; a change the audit trail cannot record is not made (`503`). A change the key store then refuses is followed by a record of the same kind with the outcome `failed`, a refusal before it -- a wrong password or code, a malformed request -- has a `failed` record of its own, and a caller who may not has a `denied` one; a request with a long-lived API token is recorded as `denied` without a target. No record holds a recovery code or a password.

---

## Caching and Handling

Every answer of these endpoints, errors included, carries `Cache-Control: no-store` and `Pragma: no-cache`. Request bodies carry passwords and recovery codes, and the answer of [Issue a New Recovery Code](#issue-a-new-recovery-code) carries the new code: send them over HTTPS only, keep them in memory only, and never write them to a log, a file or a cache.

---

## Errors

Every refusal uses the standard [error envelope](overview.md#error-format); `error.code` is the HTTP status, and these endpoints use no sub-code. The messages are in English; branch on the HTTP status, never on the message.
