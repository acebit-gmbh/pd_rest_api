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
| `auth_modes` | array of strings | Yes | The sign-in methods the user may use (see values below). From Server 20.0.0 the methods the server's policies allow the user; writing it sets the account type and the user's own policy entry (see [`account_type` Values](#account_type-values)). |
| `account_type` | string | No | *Server 20.0.0 and later.* The account type: `password_depot`, `ad`, `azure_ad` or `oidc` (see values below). A value sent is ignored; writing `auth_modes` sets the type. |
| `display_name` | string | Yes | Display name |
| `department` | string | Yes | Department |
| `email` | string | Yes | Email address. **Required** when the user's effective 2FA mode is `email` (see `two_factor_mode` below). |
| `phone` | string | Yes | Phone number |
| `two_factor_mode` | string | Yes | The user's own two-factor setting (see values below). `"default"` when the user has none and follows the settings of the server (and, from Server 20.0.0, of the user's groups). |
| `sam` | string | Yes | SAM account name (e.g., `"DOMAIN\\username"`) |
| `upn` | string | Yes | User Principal Name (e.g., `"user@domain.local"`) |
| `dn` | string | Yes | Distinguished Name (LDAP DN) |
| `objectId` | string | Yes | Active Directory object ID (GUID) |
| `idp_user_id` | string | Yes | *Server 20.0.0 and later.* The user's ID at the identity provider of an `oidc` or `azure_ad` account -- the value of the provider's user-ID claim, or the user's Entra Object ID for Azure AD and for an Entra ID provider that uses `oid`. `""` when unset. See [Directory Binding](#directory-binding). |
| `idp` | string | Yes | *Server 20.0.0 and later.* Where `idp_user_id` belongs: the `id` of the OpenID Connect provider (`oidc`), or the Entra tenant ID of a tenant registered on the server (`azure_ad`, optional). `""` when unset. See [Directory Binding](#directory-binding). |
| `disabled` | boolean | Yes | Whether the account is disabled |
| `must_change_pass` | boolean | Yes | User must change password on next login. From Server 20.0.0, `GET /me` also answers `true` while the account's password is older than the server's **Account password: maximum age** policy, in a session that a password sign-in opened (see [Password Rules](#password-rules)); the stored flag is not changed by it. |
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

### `account_type` Values

*Server 20.0.0 and later.* The directory the account belongs to. Each type has its usual sign-in methods:

| Value | Account | Usual methods |
|-------|---------|---------------|
| `"password_depot"` | Password Depot account | `standard`, `webauthn` |
| `"ad"` | Active Directory account | `sspi`, `iwa`, `webauthn` |
| `"azure_ad"` | Azure AD account | `azure`, `webauthn` |
| `"oidc"` | OpenID Connect account | `oidc`, `webauthn` |

An `oidc` or `azure_ad` account is bound to the identity that signs in to it by `idp` and `idp_user_id`, which do not change the account type; see [Directory Binding](#directory-binding).

!!! note "Server policies (Server 20.0.0 and later)"
    The sign-in methods are the server's **Allowed sign-in methods** policy (`auth.methods.allowed`), which the Server Manager shows on the user's *Policies* tab. A user without an entry of their own in it may use the usual methods of their account type, as far as the values set for the server and the user's groups allow; a user with an entry of their own may use the methods it names, as far as a value enforced for the server or a group allows. A server upgraded from an earlier version gave each user whose `auth_modes` were not the usual methods of their account type an entry of their own with exactly those methods.

    Reading `auth_modes` answers the methods the user may use to sign in to a client (`POST /auth/login` and the passkey sign-in) under those values, the account type included, so it can name fewer methods than the user's own entry. `GET /me` answers the same for the caller.

    Writing `auth_modes` sets the account type from the directory methods it names -- `sspi` makes an `ad` account, otherwise `azure` an `azure_ad` account, otherwise `oidc` an `oidc` account, otherwise it is a `password_depot` account (`iwa` and `webauthn` name no type) -- and sets the user's own entry to exactly the methods named where they differ from the usual methods of that type; where they are the usual methods, it removes the user's own entry. The write is recorded in the audit trail as a policy change. It answers `403` when the caller may not change the user's sign-in policies -- the caller must hold every server role the user holds -- or when it would leave no administrator able to sign in to the Server Manager, and `409` when the user's policies changed at the same time. On `PATCH` it is made after the whole request has been checked and before the account is changed, together with a `two_factor_mode` of the same request, so a refused write leaves the account and the user's policies as they were; on `POST` a refused write creates no user. The user's whole policy document, this entry included, can also be read and changed with [`GET` and `PATCH /v2.0/admin/users/{id}/policy`](policies.md#get-user-policy).

### Directory Binding

*Server 20.0.0 and later.* `idp` and `idp_user_id` bind an OpenID Connect or Azure AD account to the identity that signs in to it. They are written with `POST /admin/users` and `PATCH /admin/users/{id}`, and read in the full representation: `GET /admin/users/{id}`, the `201` response of `POST /admin/users` and `GET /me`, where every account carries both, `""` when unset. The list, the compact form and the `PATCH` response do not carry them, and `PATCH /me` refuses them.

| `account_type` | `idp` | `idp_user_id` |
|----------------|-------|---------------|
| `oidc` | The provider's `id` from [`GET /auth/oidc`](authentication.md#oidc-providers), the value a sign-in sends as `idp`. Required together with `idp_user_id`. | The value of the provider's user-ID claim in the user's token (see [`oidc`](authentication.md#oidc)): for an Entra ID provider that uses `oid`, the user's Entra Object ID. Required together with `idp`. |
| `azure_ad` | Optional: the Entra tenant ID of a tenant registered on the server. | The user's Entra Object ID. Required where `idp` is set. |

- **Sign-in.** An `oidc` sign-in uses the account whose `idp` is the provider named at sign-in and whose `idp_user_id` is the user ID in the token, compared case-sensitively. An `azure` sign-in uses the Azure AD account whose `idp_user_id` is the token's `oid`, in any letter case; `idp` is not compared. The account must also be allowed the sign-in method (see [`account_type` Values](#account_type-values)).
- **Type.** A non-empty value needs an account whose type is `oidc` or `azure_ad`. `idp` and `idp_user_id` never set the type: where the account does not have it yet, send the type's usual methods in `auth_modes` in the same request, `["oidc", "webauthn"]` or `["azure", "webauthn"]` (see [`account_type` Values](#account_type-values)); any other set gives the user an entry of their own in **Allowed sign-in methods**. An empty string or `null` removes a value, on every account type. A member that is not sent keeps its value.
- **Form.** A value must not begin or end with white space, must not contain control characters, and must be at most 255 characters long. An Entra Object ID -- `idp_user_id` of an `azure_ad` account, or of an `oidc` account whose provider is an Entra ID provider that uses `oid` -- must be a GUID (`8-4-4-4-12` hexadecimal digits, without braces); it is accepted in any letter case and stored in lower case. Every other user ID is stored exactly as sent. `idp` is stored in the provider's or the tenant's own spelling.
- **One account per identity.** Another account that already holds the identity answers `409` with `error.code` `4091` (`PD_ERRCODE_IDENTITY_LINKED`): for `oidc`, an account of any type with the same `idp` and the same `idp_user_id`; for `azure_ad`, another account that can sign in with `azure` (an Azure AD account) with the same `idp_user_id` in any letter case, whatever its `idp`. The message names no account. The same Entra Object ID can be bound to one `oidc` and one `azure_ad` account.
- **`azure` on another type.** An `azure` sign-in looks for the Object ID among the Azure AD accounts. A `PATCH` whose `auth_modes` hold `"azure"` but give the account another type than `azure_ad` -- `["sspi", "azure"]` makes an `ad` account -- therefore answers `400` while the account keeps a GUID in `idp_user_id`, and nothing in the request is applied. Make the account an `azure_ad` one, leave `"azure"` out, or send `idp_user_id` empty in the same request. An Active Directory account that the server's Azure AD synchronization also maintains is not affected.
- **Checked first.** The binding is checked when the request carries `idp` or `idp_user_id`, and when a `PATCH` changes the type of an account that keeps a binding -- then the identity it keeps is checked under the new type, for one account per identity only -- always before anything is written: a refused request creates no user and changes nothing. Whoever may make the request may set the binding; no further role is needed.
- **Sessions.** A `PATCH` that changes or removes a binding the account had ends the account's sessions: its REST session tokens stop working (`401`), and its connections from the Windows client and the Server Manager are closed. Setting a binding on an account that had none ends nothing, and neither does sending the stored Entra Object ID in another letter case. Long-lived API tokens and trusted devices are kept.
- **Audit trail.** A change of the binding is recorded with the user's update, naming the new or the removed `idp` and `idp_user_id`.

!!! tip "Take the IDs from the directory"
    Copy `idp_user_id` from the directory, never from display data: for Entra ID the user's Object ID (the Microsoft Graph `id`, the token's `oid`), for another provider the value of the claim the provider uses as the user ID, normally `sub`. The claim is set per provider in the Server Manager (see [`oidc`](authentication.md#oidc)); a claim that never changes, such as `oid` or `sub`, keeps the binding stable, an e-mail address or a UPN does not. A value that belongs to another person binds the account to that person, and under an Entra ID provider with directory synchronization an account whose `idp_user_id` is not a user's Object ID in that directory is treated like a user removed from it.

### `two_factor_mode` Values

| Value | Description |
|-------|-------------|
| `"default"` | No setting of the user's own: the server's settings apply (from Server 20.0.0 the policies set for the server and the user's groups) |
| `"disabled"` | No second factor for this user (useful for service accounts); from Server 20.0.0, unless a group or the server enforces **Require a second factor** for the user |
| `"totp"` | TOTP (authenticator app). User must register a secret first. |
| `"email"` | Email-based one-time codes. **Requires `email` field to be set.** |
| `"fido2"` | FIDO2 / WebAuthn. User must register a FIDO2 credential first. |

!!! warning "Service accounts and 2FA"
    If the second factor that applies to a new user is `"email"` and you create the user without an `email` address, login will fail at runtime with `401` and `error.code` `4013`. For service / automation accounts (gMSA, CI pipelines, API tokens), set `"two_factor_mode": "disabled"` at creation to opt out explicitly.

!!! note "Server policies (Server 20.0.0 and later)"
    `two_factor_mode` is the user's own entry in the server's second-factor policies, which the Server Manager shows on the user's *Policies* tab: `disabled` is the user's **Require a second factor** set to off, a method is the user's **Preferred second factor**, and `default` means the user has neither. Reading the field derives it from those entries; a requirement set for the user, and the values set for the server or the user's groups, do not change it, so it does not tell which second factor a login asks.

    Writing the field changes those entries: a method sets the user's **Preferred second factor** and removes the user's own "not required", never a requirement set for the user; `disabled` sets the user's **Require a second factor** to off; `default` removes the user's preference and the user's own "not required". The write is recorded in the audit trail as a policy change. It answers `403` when the caller may not change the user's sign-in policies -- the caller must hold every server role the user holds -- or when it would leave no administrator able to sign in to the Server Manager, and `409` when the user's policies changed at the same time. The values set for the server and the user's groups apply beside these entries, and an enforced one wins. See [Which Second Factor Is Asked](authentication.md#which-second-factor-is-asked). From Server 20.0.0 the user's whole policy document, these entries included, can also be read and changed with [`GET` and `PATCH /v2.0/admin/users/{id}/policy`](policies.md#get-user-policy).

!!! note "Email requirement"
    When a user's effective 2FA mode resolves to `email`, the server requires a non-empty `email` field. Setting `two_factor_mode` to `email` without an email address is permitted at the API level but the user will not be able to log in until an email is added (`401`, `error.code` `4013`).

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
| `"audit_reader"` | Audit reader -- read and export the audit trail |
| `"security_officer"` | Security officer -- read and export the audit trail; from Server 20.0.0 also read the server's policies and change its sign-in, session and account policies (`auth.*`, `session.*`, `account.*`) at every level (see [Policies](policies.md#who-may-read-and-change)) |
| `"backup_operator"` | Backup operator -- Server Manager access without access to database content |

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

The policies that apply to the user are not part of the profile: from Server 20.0.0 they are read with [`GET /me/policy`](client-policy.md#get-own-policy-bundle).

### Response

`200 OK`

```json
{
    "id": "3D1C91F6-754D-427E-9D76-8CC20E8C326E",
    "name": "jdoe",
    "auth_modes": ["sspi", "iwa"],
    "account_type": "ad",
    "display_name": "John Doe",
    "department": "Engineering",
    "email": "jdoe@example.com",
    "phone": null,
    "sam": "DOMAIN\\jdoe",
    "upn": "jdoe@domain.local",
    "dn": "CN=John Doe,CN=Users,DC=domain,DC=local",
    "objectId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "idp_user_id": "",
    "idp": "",
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

    Any other field in the request body (including `name`, `email`, `roles`, `member_of`, `auth_modes`, `account_type`, `two_factor_mode`, `disabled`, `sam`, `upn`, `dn`, `idp`, `idp_user_id`, etc.) causes `400 Bad Request`.

    For password changes use [`POST /v2.0/me/password`](#change-own-password). For passkey management use the [`/me/passkeys/...`](#passkeys-webauthn) endpoints. Changes to username, email, roles, groups, directory binding, or 2FA settings remain admin-only via [`PATCH /v2.0/admin/users/{id}`](#update-user).

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
| `400 Bad Request` | Missing or empty `current_password` / `new_password` field, or the new password breaks the server's password rules (see [Password Rules](#password-rules)) |
| `401 Unauthorized` | Missing/invalid authentication token |
| `403 Forbidden` | Incorrect `current_password`, **or** the user is a super administrator, **or** the per-user `cannot_change_pass` flag is set. The response `error.message` distinguishes the cases. |
| `409 Conflict` | User does not use `standard` authentication (password change is not applicable) |

!!! warning "Super-administrator accounts"
    The built-in super-administrator password **cannot** be changed via the REST API. Use the Password Depot Server Manager (native admin application) instead. This is a deliberate restriction -- super-admin credentials are infrastructure-critical and managed outside the REST surface.

!!! warning "`cannot_change_pass` flag"
    If the account has `cannot_change_pass: true` (set by an administrator), this endpoint returns `403`. The user must ask their administrator to either clear the flag or rotate the password via `POST /admin/users/{id}/password`.

!!! note
    - Only users whose `auth_modes` include `"standard"` can change their password here. Users authenticating via OIDC, SSPI, IWA, or WebAuthn manage their password through the respective identity provider.
    - The new password must pass the server's password rules: from Server 20.0.0 the account password policies that apply to the account, the minimum age since the last change included; earlier servers apply the master-password rules of the client security policies where they are active. See [Password Rules](#password-rules).
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

## Password Rules

Every route that sets an account's password -- [Change Own Password](#change-own-password), [Create User](#create-user-admin) with `new_password` and [Change Password](#change-password-admin) -- checks the new password against the server's account password policies (Server 20.0.0 and later) that apply to the account whose password is set, set in the Server Manager under *Policies* for the server, a group or the user, with the groups the same request gives it: for a new user the groups in its `member_of`, for a change of a user's groups and password in one step in the Server Manager the new groups. They are the only rules the server applies: the master-password rules of the client security policies, which earlier servers apply to account passwords where they are active, do not judge an account password on Server 20.0.0.

None of the policies is set on a new installation, and a policy that is not set refuses nothing. On a server upgraded from an earlier version whose client security policies were active, the first start of Server 20.0.0 sets **Account password: minimum length** and **Account password: minimum character groups** at the server level, enforced, from the length and the number of character groups their master-password rules required.

| Policy | Effect on a new password |
|--------|--------------------------|
| **Account password: character groups** (`account.password.classes`) | It must hold a character of every listed group: `lowercase`, `uppercase`, `digits`, `symbols`. |
| **Account password: minimum character groups** (`account.password.min_classes`) | It must hold characters of at least this many of the four groups (1 to 4). |
| **Account password: minimum length** (`account.password.min_length`) | It must have at least this many characters (0 to 256). |
| **Account password: history** (`account.password.history`) | When the account changes its own password, it must differ from the account's last passwords, this many of them, the current one included (0 to 24). |
| **Account password: minimum age** (`account.password.min_age`) | The account may change its own password again only once this time has passed since the last change (up to 365 days). |
| **Account password: maximum age** (`account.password.max_age`) | Once this time has passed since the last change (1 to 730 days), the account must change its password. |

- **Characters.** A character is one Unicode code point, so a pair of UTF-16 surrogates counts once. Its group is its Unicode category: uppercase and titlecase letters are `uppercase`, lowercase letters `lowercase`, decimal digits `digits`, punctuation and symbols `symbols` -- over ASCII the same groups as the client security policies. A letter without case, a mark, a space or a control character counts towards the length and belongs to no group.
- **History.** When an account's password is set, the server keeps the password it replaces as an Argon2id hash, never the password itself, where the history policy that applies to the account asks for it, and keeps only as many previous passwords as that policy needs: its number less one, since the number includes the current password. Where no history policy applies, it keeps none. Every route that sets a password keeps the one it replaces, the administrators' routes included. The new password is compared with them only when the account changes its own password, on the same routes as the minimum age below; an administrator setting another account's password is not compared with the history. When the policy that applies to an account comes to need fewer -- it is lowered or removed, or the account moves to other groups --, the previous passwords it no longer needs are removed at the next automatic save of the server's configuration. Passwords replaced before the history policy applied to the account are not known; the password that is current when the policy starts to apply is kept once it is replaced.
- **Minimum age.** It binds the account's own change only: `POST /me/password`, `POST /admin/users/{id}/password` on the caller's own account, a change in the Windows client, and an administrator setting their own password in the Server Manager. An administrator setting another account's password is not held to it, and neither is a change once the maximum age has passed or while the account must change its password (`must_change_pass`). It counts from the last time the password was set, by any route; a password not set since the server was upgraded to 20.0.0 is not held to it.
- **Maximum age.** It counts from the last change of the password by any route; for a password last set before Server 20.0.0, from the first start of Server 20.0.0. An expired password still signs in: `POST /auth/login` answers as before, and `GET /me` answers `must_change_pass: true` until the password is changed, without the stored flag being set (the `/admin/users` reads show the stored flag). This holds in a session that a password sign-in (`auth: "standard"`) opened, for an account that may change its password itself -- not with `cannot_change_pass`, and not for a super-administrator; a session opened with another `auth` method or with a passkey, and a long-lived API token, read the stored flag. The Windows client is asked to change the password at such a sign-in, as for an account that must change it; a Server Manager sign-in is not.

A refused password answers `400` with `error.code` `400`: `error.message` starts with a line in the server's language saying that the password does not meet the security policy, as a refusal by the client security policies of earlier servers does, and names each rule the password breaks on a line of its own -- the setting, the scope that set it and the rule's value, for example "The policy setting account.password.min_length, as set at the server, requires at least 12 characters; the password has 8.". The lines are separated by CR LF. Nothing is changed by a refused request; `POST /admin/users` creates no user.

---

## Client Endpoints

These endpoints are available in both `client` and `admin` sessions. They return a compact representation suitable for user lookups (e.g., when assigning permissions or sharing secrets). No admin-specific fields (roles, auth_modes, account_type, AD attributes, directory binding, group memberships) are included.

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

A user's policies -- the settings of the *Policies* tab in the Server Manager's User Properties -- are read and changed with `GET` and `PATCH /v2.0/admin/users/{id}/policy` (*Server 20.0.0 and later*); see [Policies](policies.md#get-user-policy).

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
            "account_type": "password_depot",
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
            "account_type": "ad",
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
| `new_password` | string | Conditional | Initial password (plaintext). **Required** when the methods of `auth_modes` contain `"standard"`, as the usual methods of a `password_depot` account do when `auth_modes` is omitted. Optional for users that will only authenticate via OIDC, SSPI, IWA, or WebAuthn. |
| `auth_modes` | array of strings | No | The sign-in methods (see [`account_type` Values](#account_type-values)). Omitted, the user is a `password_depot` account without an entry of its own (Server 20.0.0 and later; earlier servers default to `["standard"]`). |
| `display_name` | string | No | Display name |
| `department` | string | No | Department |
| `email` | string | Conditional | Email address. **Required** if the effective 2FA mode for this user is `email` (see `two_factor_mode`). |
| `phone` | string | No | Phone number |
| `two_factor_mode` | string | No | The user's own 2FA setting: `"default"` (none of the user's own), `"disabled"`, `"totp"`, `"email"`, `"fido2"`. See the [User Object](#user-object) reference. For service accounts, set `"disabled"` to opt out. |
| `sam` | string | No | SAM account name |
| `upn` | string | No | User Principal Name |
| `dn` | string | No | Distinguished Name |
| `objectId` | string | No | Active Directory object ID (GUID) |
| `idp_user_id` | string | No | *Server 20.0.0 and later.* The user's ID at the identity provider of an `oidc` or `azure_ad` account; needs `auth_modes` with `"oidc"` or `"azure"`. See [Directory Binding](#directory-binding). |
| `idp` | string | Conditional | *Server 20.0.0 and later.* The OpenID Connect provider's `id`, **required** with `idp_user_id` on an `oidc` account; or the Entra tenant ID of a registered tenant, optional on an `azure_ad` account. See [Directory Binding](#directory-binding). |
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
    `new_password` is sent as **plaintext** in the JSON body -- the server hashes and stores it. Always call this endpoint over HTTPS. The new password must pass the server's password rules for the new user, with the groups in `member_of` (see [Password Rules](#password-rules)); where no rule is set, the server only rejects empty strings.

!!! tip "Service account recipe"
    Automation / service accounts (CI pipelines, cron jobs, gMSA) usually don't have an email address. If the second factor that applies to a new user is `"email"`, the account cannot sign in (`401`, `error.code` `4013`) at first login. Opt out explicitly:

    ```json
    {
        "name": "svc_ci",
        "new_password": "<long random>",
        "auth_modes": ["standard"],
        "two_factor_mode": "disabled",
        "display_name": "CI Service Account"
    }
    ```

!!! tip "Entra ID / OpenID Connect account recipe"
    *Server 20.0.0 and later.* An account that signs in through an OpenID Connect provider needs no password. Send the usual methods of its type in `auth_modes`, the provider's `id` from [`GET /auth/oidc`](authentication.md#oidc-providers) as `idp`, and the user's ID at the provider as `idp_user_id` -- for an Entra ID provider the user's Object ID:

    ```json
    {
        "name": "jdoe",
        "auth_modes": ["oidc", "webauthn"],
        "idp": "B5A1E2C4-3F6D-4E8A-9C0B-1D2E3F4A5B6C",
        "idp_user_id": "4f1c2d3e-5a6b-4c7d-8e9f-0a1b2c3d4e5f",
        "display_name": "John Doe",
        "email": "jdoe@example.com"
    }
    ```

    The user can then sign in with `auth: "oidc"` and this `idp`. Read the binding back with [`GET /admin/users/{id}`](#get-user-admin); see [Directory Binding](#directory-binding) for the rules and for an Azure AD account.

!!! note "Response never includes the password"
    The response object for `POST /admin/users` never echoes the `new_password` field back. The password is hashed immediately and only the hash is retained server-side.

#### Response

`201 Created`

```json
{
    "id": "56E4205C-0D50-47E9-90B8-B751EF19A165",
    "name": "jsmith",
    "auth_modes": ["standard"],
    "account_type": "password_depot",
    "display_name": "Jane Smith",
    "department": "Engineering",
    "email": "jsmith@example.com",
    "phone": null,
    "sam": null,
    "upn": null,
    "dn": null,
    "objectId": null,
    "idp_user_id": "",
    "idp": "",
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
| `400 Bad Request` | Invalid or missing required fields. Includes: missing `new_password` for a standard-auth user, empty `new_password`, or a password that breaks the server's password rules (see [Password Rules](#password-rules)); from Server 20.0.0 also a refused `idp` or `idp_user_id` -- a value of the wrong form, a binding on an account whose type is neither `oidc` nor `azure_ad`, an incomplete pair, or a provider or tenant the server does not have (see [Directory Binding](#directory-binding)); no user is created then. |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | `error.code` `403`: the session is not admin-scoped, the account has neither the `server_admin` nor the `user_admin` role, or it may not set the requested `roles` (requires `server_admin`) or `member_of`. `error.code` `4032` (`PD_ERRCODE_LICENSE_LIMIT`): the server's licensed number of users is reached. From Server 20.0.0 also `error.code` `403` when the `two_factor_mode` or `auth_modes` write is refused (see [`two_factor_mode` Values](#two_factor_mode-values) and [`account_type` Values](#account_type-values)); no user is created then |
| `409 Conflict` | A user with this username already exists, or (Server 20.0.0 and later) the user's policies changed while `two_factor_mode` or `auth_modes` was written. `error.code` `4091` (`PD_ERRCODE_IDENTITY_LINKED`, Server 20.0.0 and later): another account already holds the identity in `idp` and `idp_user_id` (see [Directory Binding](#directory-binding)); no user is created then |

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
    "account_type": "ad",
    "display_name": "John Doe",
    "department": "Engineering",
    "email": "jdoe@example.com",
    "phone": null,
    "sam": "DOMAIN\\jdoe",
    "upn": "jdoe@domain.local",
    "dn": "CN=John Doe,CN=Users,DC=domain,DC=local",
    "objectId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "idp_user_id": "",
    "idp": "",
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

!!! warning "A binding change ends the user's sessions"
    *Server 20.0.0 and later.* When the request changes or removes the `idp` and `idp_user_id` the user had, the user's sessions end: their REST session tokens stop working and their connections from the Windows client and the Server Manager are closed. Long-lived API tokens and trusted devices are kept. See [Directory Binding](#directory-binding).

#### Response

`200 OK`

The response carries the fields every user representation has. It does not carry the detail fields -- `sam`, `upn`, `dn`, `objectId`, `idp_user_id`, `idp`, `disabled`, `must_change_pass`, `cannot_change_pass`, `roles`, `member_of`, `last_login` and `passkeys`; read them with [`GET /admin/users/{id}`](#get-user-admin).

```json
{
    "id": "3D1C91F6-754D-427E-9D76-8CC20E8C326E",
    "name": "jdoe",
    "auth_modes": ["sspi", "iwa", "webauthn"],
    "account_type": "ad",
    "two_factor_mode": "default",
    "display_name": "John A. Doe",
    "department": "R&D",
    "email": "jdoe@example.com",
    "phone": "",
    "updated_at": "2024-11-21T10:15:00.000Z"
}
```

#### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | Invalid fields; from Server 20.0.0 also a refused `idp` or `idp_user_id`, or `auth_modes` that give `"azure"` to an account of another type than `azure_ad` while it keeps a GUID in `idp_user_id` (see [Directory Binding](#directory-binding)). Nothing in the request is applied |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions, or attempted to modify `roles` without `server_admin` role, or (Server 20.0.0 and later) the `two_factor_mode` or `auth_modes` write is refused (see [`two_factor_mode` Values](#two_factor_mode-values) and [`account_type` Values](#account_type-values)) |
| `404 Not Found` | User or referenced group not found |
| `409 Conflict` | Username conflict, or (Server 20.0.0 and later) the user's policies changed while `two_factor_mode` or `auth_modes` was written. `error.code` `4091` (`PD_ERRCODE_IDENTITY_LINKED`, Server 20.0.0 and later): another account already holds the identity in `idp` and `idp_user_id` (see [Directory Binding](#directory-binding)) |

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
    `new_password` is sent as **plaintext** -- the server hashes it and only stores the hash. Always call this endpoint over HTTPS. The new password must pass the server's password rules for the user whose password is set (see [Password Rules](#password-rules)). The minimum age since the last change does not apply, unless the caller sets their own password.

!!! warning "Self-service"
    For your own password prefer [`POST /v2.0/me/password`](#change-own-password), which requires the current password. Used on your own account, this endpoint also ends your own REST sessions.

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
| `400 Bad Request` | `new_password` field is missing, empty, or breaks the server's password rules (see [Password Rules](#password-rules)) |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions, or target user is a super admin account |
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

Passkeys can be used as a passwordless login method via the [`webauthn`](authentication.md#webauthn) auth flow. From Server 20.0.0 the server's **Allowed sign-in methods** policy must allow *Passkeys (WebAuthn)* (`webauthn`) for the user, so that `webauthn` is among the user's `auth_modes`, as it is for every account type wherever the policies allow it; earlier servers need WebAuthn enabled in the server options and the `webauthn` mode in the user's `auth_modes`.

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
| `400 Bad Request` | Passkeys are not allowed for the caller: from Server 20.0.0 the server's **Allowed sign-in methods** policy does not include `webauthn` for the user; earlier servers have WebAuthn switched off in the server options |
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
