# Changelog

All notable changes to the Password Depot REST API v2.0 are documented in this file.

The API version remains **v2.0**. Changes are listed by the Password Depot Enterprise Server release that introduced them, newest first. The API does not report the server version. Where a client needs to know whether a feature is available, test for the feature itself (for example, whether entry payloads carry `has_otp`) rather than for a version number.

---

## Server 20.0.0 (In Development)

!!! warning "In Development"
    Server 20.0.0 is under active development. Everything listed in this section is subject to change before the final release.

Server 20.0.0 keeps the v2.0 routes and fields listed under Server 19.x and makes the changes below. Entries marked **(Behavior Change)** can change the answer an existing client receives.

**At a glance -- changes that can affect an existing client:**

- REST API v1.0 is no longer served: `/v1.0/...` answers `410 Gone`
- request bodies must be valid JSON; send `{}` when a request has no body fields
- every request body must carry a `Content-Length`: a body sent with `Transfer-Encoding: chunked` answers `411 Length Required`
- `importance` strings map to the levels the desktop and mobile clients show
- a password change ends the account's REST sessions
- `open_uuid` and `approve_uuid` are optional in the secret representation
- `include_totp: false` on a shared secret is applied: the recipient no longer gets the entry's one-time code
- deleted entries and folders answer `404`
- writing a link's fields answers `409`
- `super_admin` in `roles` is not applied
- stricter passkey verification
- new one-time-code endpoint and `has_otp` field; new sub-codes `4012` and `4013` (`401`) and `4032` (`403`)
- one-time-code settings can be written: `totp` in `POST` and `PATCH` entry bodies, a `totp` object in every entry payload; new sub-codes `4001` to `4006` (`400`, the first of that family) and `4033` (`403`)
- database icons: new `/databases/{db}/icons` endpoints, an `icons` object on every database, a `database_icon` field on every entry and folder; new sub-codes `4007` and `4008` (`400`), `4034` (`403`), `4042` (`404`) and `4131` (`413`, the first of that family)
- `icon` follows `image_index` and is never `<name>.ico`; `image_custom`, `image_index` and `image_name` are validated when written (`400` / `4007`); documents show `ico133.svg`
- `/file/` serves the 135 standard icons only

### Breaking Changes

#### REST API v1.0 Removed (Behavior Change)

Server 20.0.0 serves REST API v2.0 only. A `GET`, `POST`, `PUT`, `PATCH` or `DELETE` request to a `/v1.0/` path (the prefix is matched case-insensitively) answers HTTP `410 Gone` with the v2.0 error object. The `410` is returned before any authentication takes place, and it is the same whether or not REST web-client support is enabled:

```json
{
  "error": {
    "code": 410,
    "message": "REST API v1.0 was removed in Password Depot Server 20.0.0. Use /v2.0/ instead."
  }
}
```

The nested `error` object is the only error shape the server produces; the flat v1.0 error body is gone. No route reads the v1.0 `access_token` / `client_id` request headers -- authenticate with `Authorization: Bearer <token>`.

Checks that run before routing still come first: an address under an IP lockout receives `429`, and `OPTIONS` preflight requests are answered with `204`. Paths containing `/file/`, `/temp/` or `/shared/` are not versioned and are routed before the version check, so they keep working and never answer `410`.

!!! warning "Behavior change for clients"
    Move every `/v1.0/` call to v2.0 before the server is upgraded. v2.0 is available from Server 19.1.0 (this documentation describes 19.2.0 and later), so the migration can be made and tested against a 19.2.x server first. See [New URL Structure](#new-url-structure) for the route mapping. Detect the removal by the HTTP status `410` (also carried in `error.code`), not by the message, which is localizable.

### New Features

#### One-Time Codes (TOTP)

- **`GET /databases/{db}/entries/{id}/otp`** returns the entry's current one-time code, computed on the server's UTC clock:
    - `code` -- a string, so leading zeros are kept
    - `digits`
    - `period`
    - `expires_in` -- seconds until the code changes
    - `algorithm` -- `SHA1`, `SHA256` or `SHA512`

    The same permission, seal and `X-Second-Password` rules apply as for reading the entry, including the checks on a link's target. There are two additional rules. Long-lived API tokens are refused with `403`, so use a login session token. An entry that uses an old form of second-password protection, which the REST API cannot check, also answers a plain `403`. For a link, the code comes from the link's own TOTP settings. The seed is never returned. A successful call is audited as an entry access and fires "password accessed" alerts. For a link, this includes alerts set on the entry it points to. A refused call is audited as a failed entry access and written to the server log; no alert fires for it.
- **`has_otp`** (boolean, read-only) is part of every entry representation, compact and full, next to `has_second_pass`. It says whether the entry's own TOTP settings can produce a one-time code. It is `false` when you may not read the entry. A `true` value does not bypass the checks above: `/otp` can still answer `403` or `403` / `4031`. Folders do not carry it.
- **`totp`** (object, read-only in responses) follows `has_otp` in every entry representation, compact and full. It is always an object, never `null`, and never withheld. `state` is `none`, `set` (the same as `has_otp: true`), `invalid` (a seed is stored but produces no code), `unsupported` (type `encrypted_file` or `certificate`) or `hidden` (you may not read the entry); the compact form carries `state` only. The full form adds `writable` and, for `set` and `invalid`, the stored `digits`, `period`, `algorithm` (`null` when the server does not know it) and `conforming`, echoed as stored so that a repair UI can show them. Never the seed. Folders do not carry it.
- **`totp` in `POST /databases/{db}/entries` and `PATCH /databases/{db}/entries/{id}` bodies** writes the entry's TOTP settings; there is no separate route, and every REST consumer, long-lived API tokens included, may use it. The value is `null` or an object with exactly the members `secret` (Base32, 16 to 128 characters after case folding, whitespace removal and trailing `=` stripping), `algorithm` (`SHA1`, `SHA256`, `SHA512`), `digits` (`6` to `8`) and `period` (`15` to `120`). The key absent leaves the settings alone. On `POST`, `secret` is required, the other members default to `SHA1` / `6` / `30`, and `null` does nothing. On `PATCH`, `null` removes the seed and resets the parameters (an entry without a seed is left unchanged), an object with `secret` sets or replaces the seed in one call, and an object without `secret` changes only the parameters. There is one merge rule: the members that arrive are validated and applied, the members that are absent keep their stored values, and an absent `secret` keeps the stored seed without re-validating it - so send all four members whenever you send `secret`. The server computes a code once before it writes anything; a refused write changes nothing, and an accepted one always leaves `has_otp: true`. Only `password`, `credit_card`, `license`, `banking` and `custom` entries accept the key (`400` / `4006` otherwise, `501` for `encrypted_file` and `certificate`); an `rdp` entry keeps showing a code it already has but cannot be edited over REST. A link's `totp` is the link's own, the one `/otp` computes from; the `409` link guard does not apply. On `PATCH`, the write additionally requires read permission on the entry (`403` / `4033`) and answers a plain `403` for an entry sealed for you; the second password, when the entry has one, is checked first (`403` / `4031`). A seed write is a modification, not an access: it is audited as an entry creation or update with an operation-specific message (`PATCH`: one-time code set, replaced, parameters changed, removed; `POST`: new entry with a one-time code added) and fires the "password added" or "password modified" alerts, never "password accessed". No audit entry, log line, alert or error message contains the seed. A refused `totp` never answers `409`. Removing a seed does not remove it from the entry's history where the database keeps one.

An entry without a one-time code answers `404` with `error.code` = `4041` (`PD_ERRCODE_NO_ONE_TIME_CODE`). A plain `404` means the database or entry does not exist, the id is a folder, or the entry is in the recycle bin. `4041` is returned only after every access check has passed. Until then, the usual answers come first: `403` for an entry you may not read, a sealed entry or an API token, `403` / `4031` for a missing or wrong second password, and `501` for an unsupported entry type. `has_otp: true` never leads to `4041`. Methods other than `GET` answer `405`.

A refused `totp` write answers `400` with `error.code` `4001` (`PD_ERRCODE_TOTP_SECRET`), `4002` (`PD_ERRCODE_TOTP_ALGORITHM`), `4003` (`PD_ERRCODE_TOTP_DIGITS`), `4004` (`PD_ERRCODE_TOTP_PERIOD`), `4005` (`PD_ERRCODE_TOTP_SHAPE`: `{}`, an unknown member, a wrong JSON type, or no `secret` where one is required) or `4006` (`PD_ERRCODE_TOTP_ENTRY_TYPE`); the first failing member in the order `secret`, `algorithm`, `digits`, `period` names the code. These are the first sub-codes of the `400` family. `403` / `4033` (`PD_ERRCODE_TOTP_READ_REQUIRED`) is new as well. See [One-Time Code Settings](api-reference/entries.md#one-time-code-settings).

**Client guidance:** detect the code read by the presence of `has_otp`, and the settings write by the presence of the `totp` key on any entry - the server ignores unknown request keys, so a write cannot be probed. Servers before 20.0.0 omit both and have no `/otp` route. Match `error.code`, never the message: prompt for the second password only on `4031`, never on a plain `403`. A client that recognised a bad request by `error.code == 400` must test the HTTP status instead. To leave a one-time code alone, omit the key; to remove it, send `null`, never `""`. Treat a `totp.state` you do not recognise as `hidden`.

#### Database Icons

- **`GET /databases/{db}/icons`** lists the icons stored in a database - what the Windows client calls custom icons - as `id`, `name` and `version`, without image data, in the standard paginated envelope. With `ids=3,7&include=data` it returns up to 32 icons **with** their images in one call, so a list view can draw a page of rows with one request. Removed icons are never listed. Images are added while the response stays within 2 MiB of decoded image data; later items come back with `state` `deferred`.
- **`GET /databases/{db}/icons/{icon_id}`** returns one icon with its image: `state`, `content_type` (`image/png`, or `image/bmp` for icons an older client stored), `width`, `height` and `data` (Base64). Icons are a property of the database, so no `X-Second-Password` is involved.
- **`POST /databases/{db}/icons`** uploads an icon as JSON - `{"name": "...", "data": "<Base64 PNG>"}`. PNG only, 1 to 64 pixels per side, at most 32768 bytes decoded; 64x64 is the native size of a Password Depot icon and what the Password Depot clients always send. The server keeps only the image chunks of the PNG, proves that the Windows client's decoder can read the result, and builds the 16x16 rendition that client needs, so the stored image is not byte-identical to the upload. `201` with `created` `true` for a new icon, `200` with `created` `false` when an identical icon of that name already exists. An existing icon with a different image is never touched: the upload is stored as `name (2)`. There is no `DELETE` and no replace.
- **`icons`** (object, read-only) is part of every database representation, client and admin scope, list and detail: `can_upload`, `accepted_types`, `max_bytes`, `max_side`, `max_count`, `batch_max`. Its presence is the capability marker for everything in this section. `can_upload` is `false` on a mirror server and when the database has no icon slot left. The admin-only `icons_count` is unrelated and also counts removed icons.
- **`database_icon`** (object or `null`, read-only) follows `icon` in every entry and folder representation, compact and full: `{"id", "name", "version"}` of the icon the item uses, in the item's own database, or `null`. It carries no image data. An item whose `image_name` no longer names an existing icon reports `null`.
- **Identifier, handle, change token.** `name` identifies an icon and is the value for `image_name`. `id` is a fetch handle of decimal digits, valid only inside its database - the one identifier of this API that is not a UUID. `version` changes whenever the stored image changes; responses are `no-store`, so cache images in memory by (database, `id`, `version`).
- **Permissions.** Whoever can open a database can list its icons, fetch them and upload to it - the desktop and mobile clients already receive every icon with the database, and an upload can never change or remove an existing icon. Long-lived API tokens may upload. Every upload attempt is audited, never with image data. A mirror server answers the upload, like every non-`GET` request, with `403`.
- **Isolation.** Every lookup goes through the database in the URL, or the item's own database. The same name in two databases is two icons, and an `id` from one database never returns another database's image.
- **Windows clients** store and read the same icons. A Windows client that has the database open sees an uploaded icon after it reopens the database.

A refused upload answers `400` / `4008` (`PD_ERRCODE_ICON_IMAGE`: `data` is not a usable PNG - JPEG, GIF, BMP, ICO, WebP, SVG and animated PNG included), `413` / `4131` (`PD_ERRCODE_ICON_TOO_LARGE`: too many bytes, too many pixels, or too large a stored record) or `403` / `4034` (`PD_ERRCODE_ICON_QUOTA`: 1024 icon slots or 8 MiB of icon data per database); a bad `name` or a body that is not a JSON object is a plain `400`. [Get Icon](api-reference/icons.md#get-icon) answers `404` / `4042` (`PD_ERRCODE_ICON_NOT_FOUND`) when the database has no usable icon with that id, and a plain `404` when the database itself is not there. `4131` is the first sub-code of the `413` family. A request over 1 MB is still refused with a plain `413` before the body is read - without CORS headers, so a browser sees a network error: check sizes before sending. See [Database Icons](api-reference/icons.md).

**Client guidance:** detect support by the `icons` object on the database, never by calling `/icons` or by uploading. Use the `name` the upload **returns**, not the one you sent. Cache images by `version`, and fetch the images of a page of rows in one `ids` call. Validate size and format before sending, and read the limits from `icons`. Draw `database_icon` when it is set, the standard `icon` otherwise, your own symbol last.

### Authentication and Sessions

#### Disabled Accounts Refused on Every Request (Behavior Change)

A token that belongs to a disabled account is refused on every route that requires a bearer token, including `POST /auth/logout`. Session tokens and long-lived API tokens both answer `401` with `error.code` `401` and the message "The user account is currently disabled." in the server's language. The server checks the account right after it verifies the token's signature. That is before it checks the token's expiry, its inactivity window and, for API tokens, whether the token is still registered. A refused request therefore does not extend the session's inactivity window.

`POST /auth/login` with `auth: "azure"` or `auth: "oidc"` now also answers `401` with the same message for a disabled account, as the standard and `auth: "sspi"` sign-ins already did. Super-administrator accounts are exempt from the token check and from these sign-in checks. Negotiate sign-in and passkey sign-in (`/auth/webauthn/*`) still refuse every disabled account, super-administrators included, each with its own message.

Disabling an account does not revoke any of its tokens. They are refused while the account is disabled. Once the account is re-enabled they are accepted again, unless they have expired, timed out or been revoked in the meantime.

!!! warning "Behavior change for clients"
    Treat a `401` on an authenticated route as "sign in again", and discard the token locally, because `POST /auth/logout` is refused as well. For a disabled account the new sign-in is refused too. Show `error.message` instead of retrying, and do not match on its text, which follows the server's language. Refused sign-ins count toward the address's failed-login limit, which answers `429`.

#### Sign-In Methods Follow the Server and Account Settings (Behavior Change)

`POST /v2.0/auth/login` honours the server-wide switch for each sign-in method, in both `client` and `admin` scope. For `sspi`, `azure` and `oidc` it also checks that the account's `auth_modes` include the method:

| `auth` | Server setting | Answer when the server setting is off | Answer when the account lacks the mode |
|--------|----------------|---------------------------------------|----------------------------------------|
| omitted / `standard` | Standard Authentication | `401` "This method of authentication is not supported..." | unchanged: `401` "Standard authentication is not enabled for this user." |
| `sspi` | Windows Domain Credentials | `401` "This method of authentication is not supported..." | `401` "This method of authentication is not supported..." |
| `azure` | Entra ID | `401` "This method of authentication is not supported..." | `401` "This method of authentication is not supported..." |
| `oidc` | OpenID Connect | `401` "This method of authentication is not supported..." | `401` "Logon failure: unknown user name or bad password." |

The server setting is checked first, before the user name, token or identity provider is looked at. These responses carry `error.code` `401`. `auth: "negotiate"` still requires Integrated Windows Authentication on the server and the `iwa` mode on the account.

!!! warning "Behavior change for clients"
    A sign-in method that works on one server may be switched off on another, or not allowed for one account. Handle the `401`, and do not infer the reason from the message, which is localizable.

#### OIDC Identities Matched Within Their Provider (Behavior Change)

With `POST /v2.0/auth/login` and `auth: "oidc"`, the server matches the user ID from the validated token only against accounts linked to the identity provider named in `idp`. The user ID is the provider's configured user-ID claim, `sub` by default. The comparison is case-sensitive. The login answers `401` with "The server cannot find the user account specified." when that user ID is linked only under a different provider, or only in a different letter case. The message does not include the user ID. The account must also allow OIDC authentication (see **Sign-In Methods Follow the Server and Account Settings**).

#### `401` for a Sign-In From an Address the Account Does Not Allow (Behavior Change)

An account restricted to one IP address or an address range can sign in over REST only from that address:

- **`POST /auth/login`** (every `auth` method, including Negotiate): the check runs after the credentials are accepted, and before the scope check and two-factor authentication. A refusal answers `401` with `error.code = 401` and a localized `error.message` (English: "IP is not authorized."). It counts as a failed login towards the IP lockout (`429`).
- **`POST /auth/webauthn/complete`**: the check runs after the passkey assertion is verified and after the admin-scope check, before a token is issued. A refusal answers `401` with `error.code = 401` and the same message. It counts towards the IP lockout (`429`).

The address compared is the connection's peer address, so behind a reverse proxy it is the proxy's address. An IPv4 client reported as `::ffff:a.b.c.d` is matched as `a.b.c.d`. The address is checked only when a token is issued. Later requests that carry a bearer token are not checked against it.

!!! warning "Behavior change for clients"
    A `401` from `POST /auth/login` or `POST /auth/webauthn/complete` is a refused sign-in; do not retry it automatically. Always match the numeric code, never the localized message.

#### Password Changes End the Account's REST Sessions (Behavior Change)

When a user's password is changed anywhere other than `POST /me/password`, all of that user's REST session tokens stop working immediately. The next request with any of them returns `401` ("Access token is invalid or expired."):

| Password change | The account's REST session tokens |
|-----------------|-----------------------------------|
| `POST /admin/users/{id}/password` | Invalidated -- including the caller's own session when an administrator uses it on their own account |
| Password changed or reset in the Server Manager | Invalidated |
| Password changed by the user in the Windows client | Invalidated |
| `POST /me/password` | Kept: after the `204`, the account's REST session tokens, including the calling session's, stay valid |

Long-lived API tokens are not affected by any password change.

!!! warning "Behavior change for clients"
    If a session that was working starts returning `401`, sign in again -- the password may have been changed elsewhere.

#### Client Address Recorded and Applied During Sign-In (Behavior Change)

The server takes the client's address from the connection at the start of every REST request, before authentication. Requests that carry no access token are therefore attributed to the address they come from:

- **Audit:** in `GET /admin/audit`, these records carry the client address in `actor.ip`: the sign-in, two-factor and lockout records written while handling `POST /auth/login`, the alert records fired by a passkey sign-in (`POST /auth/webauthn/complete`), and the records for the anonymous `/shared/` page.
- **IP lockout:** a wrong two-factor code on `POST /auth/login` (answered with `460`) counts towards the IP lockout for the client's address. Once the limit is reached, further requests from that address are answered with `429` and a `Retry-After` header.
- **Super-administrator cooldown:** after repeated failed sign-ins to a super-administrator account, password sign-ins to super-administrator accounts from that address are refused with `401` for a period.
- **Concurrent sessions:** the server can be set to refuse a second session. In that mode, a `POST /auth/login` sign-in with a password or identity token is not refused for this reason if it comes from the same address as the account's existing client session over the classic protocol (for example the Windows client). That session is ended instead. From any other address the sign-in is still refused with `401`.

!!! warning "Behavior change for clients"
    Clients behind one shared address (NAT, reverse proxy) share one lockout counter and one super-administrator cooldown, and count as the same address for the concurrent-session rule. Do not retry a rejected two-factor code automatically.

#### Error Codes 4012 and 4013 for E-mail Two-Factor Failures

When a user's effective two-factor mode is `email`, `POST /v2.0/auth/login` answers a server-side e-mail failure with HTTP `401`. The `error.message` is the same as before, and `error.code` carries a distinct sub-code:

| Condition | HTTP | `error.code` | Constant |
|-----------|:----:|:------------:|----------|
| The server cannot send e-mail: no SMTP server is configured, its e-mail sender stopped after repeated connection failures (until the service is restarted), or the code e-mail could not be handed to the sender | `401` | `4012` | `PD_ERRCODE_2FA_EMAIL_SEND_FAILED` |
| The account has no e-mail address | `401` | `4013` | `PD_ERRCODE_2FA_EMAIL_MISSING` |

If no SMTP server is configured or the e-mail sender has stopped, and the account also has no e-mail address, `4012` is returned. Either sub-code can also answer a request that already carries `tfacode`. With no SMTP server configured, such a login answers `4012` and does not issue the `460` code challenge. Invalid credentials still return `401` with `error.code = 401`. The 2FA challenges (`459`, `460`), the FIDO2 `409` and the second-password `403` / `4031` are unchanged.

Neither `4012` nor `4013` counts towards the IP lockout (`429`), on the REST API or on the classic client protocol. Both are reported only after the sign-in credentials (password, Windows sign-in or identity token) were accepted and, with `"scope": "admin"`, after the Server Manager access check. Each attempt is still logged and alerted as a failed login.

**Client guidance:** detect the conditions by `HTTP status == 401 && body.error.code == 4012` and `== 4013`. In both cases, advise contacting the administrator and do not retry automatically. This also applies when the request carried a `tfacode`: do not report it as a wrong code. Treat a plain `401` as before. Do not infer a reason from a sub-code you do not recognise: show a neutral sign-in failure, never "wrong password". Always match the numeric code, never the localized message. Servers before 20.0.0 send `error.code = 401` instead, and with no SMTP server configured they issue the `460` challenge to an account that has an e-mail address.

### Administration and Permissions

#### Admin Reads of Users, Groups and Databases Limited to What You Manage (Behavior Change)

Reading a single object in the admin section applies the same filter as the corresponding list. An object you cannot manage answers `404`, exactly like an id that does not exist: same status, `error.code` = `404` and the same message.

| Route | Readable by | Otherwise |
|-------|-------------|-----------|
| `GET /admin/users/{id}` | server administrators, super-administrators and user administrators: every user. Group administrators: users who are members of a group they administer, directly or through a nested group at any depth. | `404` "The server cannot find the user account specified." |
| `GET /admin/groups/{id}` | server administrators, super-administrators and user administrators: every group. Group administrators: the groups they administer and the groups nested within them at any depth. | `404` "The server cannot find the group specified." |
| `GET /admin/databases/{id}` | server administrators and super-administrators: every database. Database administrators: databases whose `db_admins` lists them. | `404` "The server cannot find the file specified." |

A group or database administrator needs the corresponding server role. Being listed in a group's administrators or in a database's `db_admins` is not enough on its own. Membership or nesting through a disabled group does not count. On each route, a caller who holds none of the roles in that row gets `404` for every id. Messages are shown with their English defaults and are localized by the server.

!!! warning "Behavior change for clients"
    A `404` from these routes means the object does not exist or is not one you manage. Do not treat it as proof that the object was deleted. Read the corresponding list (`GET /admin/users`, `GET /admin/groups`, `GET /admin/databases`) to find the objects available to you. Always match the status and numeric `error.code`, never the localized message.

The list routes, the other admin methods on these resources and the client-scope routes (`GET /users/{id}`, `GET /groups/{id}`, `GET /databases/{id}`) are unchanged.

#### Permission Rows Visible to Database Administrators and Their Issuer (Behavior Change)

`GET /admin/databases/{db}/permissions` returns every permission row only to callers who manage the database. These are server administrators, super-administrators, and users who hold the Database Administrator server role and are listed in the database's `db_admins`. Any other admin-scoped caller gets only the rows it issued, meaning rows whose `issuer_id` is the caller's own user ID. `total` counts only the rows the caller can see, and `offset` / `limit` page through that filtered set. A caller that issued no rows gets `200` with an empty `data` array and `total` of `0`.

`GET /admin/databases/{db}/permissions/{id}` returns `404` unless the caller manages the database or issued the row. This is the same response as for a permission ID that does not exist. A caller that created permission rows, for example to share entries with delegated rights, can list and read those rows as long as it uses an admin-scoped session.

#### Reading Alerts Requires a Server Administrator (Behavior Change)

`GET /admin/alerts` and `GET /admin/alerts/{id}` require a server administrator or super-administrator, as creating, updating and deleting alerts already did. Other admin-scope callers receive `403` with `error.code` `403` (default message: "This account does not have any of the server roles required for this operation."). An unknown alert id still answers `404`.

#### `super_admin` Role Is Not Applied Through REST (Behavior Change)

In `POST /admin/users` and `PATCH /admin/users/{id}`, `"super_admin"` is still accepted in `roles` without an error, but it is not applied. This matches the documented rule that `super_admin` is read-only and cannot be assigned through the API. A user created through REST is never a super-administrator, and a `PATCH` does not make an account one. A `PATCH` on a super-administrator account is refused with `403`, as before. The other roles in the array are applied as before.

Changing roles still requires the `server_admin` or `super_admin` role. For any other caller, a `roles` array that differs from the account's current roles returns `403`, and a listed `"super_admin"` counts as a difference. Super-administrators are managed in the Server Manager.

!!! warning "Behavior change for clients"
    No error signals the ignored role. Read the effective `roles` from the `201` response of `POST /admin/users`, or from `GET /admin/users/{id}` after a `PATCH` -- the `PATCH` response does not include `roles`.

#### `PATCH /admin/users/{id}` Applies All or Nothing (Behavior Change)

The server checks the whole request body before applying any of it. If one field is refused, nothing in the request is applied and the account stays as it was. Refusals include:

- `400` for an unknown authentication mode, two-factor mode or role, or a value of the wrong JSON type
- `403` from the `member_of` or `roles` permission checks

Like `POST /admin/users`, `PATCH` also answers `400` when the resulting `name` is empty, and `409` when another account already has that name. Both checks use the name the account would have after the request, even when the body does not contain `name`. Names are compared without regard to case, so a name held only by this account, in any letter case, is not a conflict. For all of these refusals `error.code` equals the HTTP status. Do not rely on the `error.message` text, which can be localized.

#### `403` / `4032` When the Licensed Number of Users Is Reached (Behavior Change)

When the server's licensed number of users is reached (the same limit the Server Manager applies; super-administrators do not count), an otherwise valid `POST /admin/users` creates no user and returns `403` with `error.code` = `4032` (`PD_ERRCODE_LICENSE_LIMIT`). `error.message` gives the number of users the server would have with the new account and the licensed number, in the server's language. The refusal is also written to the server log and to the request's admin audit record. Permission, validation and name-conflict errors (`403` with `error.code` `403`, `400`, `409`) are still returned first.

!!! warning "Behavior change for clients"
    Provisioning scripts must expect `403` / `4032` once the licensed number of users is reached, and must not retry it automatically. Tell it apart from a permission refusal by `error.code`, never by the message. The installed licences are shown in the Server Manager.

### Entries and Folders

#### Deleted Entries and Folders Answer `404` (Behavior Change)

An item in a database's recycle bin, or any item below a folder in the recycle bin, is not addressable through the REST API. Items reach the recycle bin when they are deleted in the Windows client. A `DELETE` made through this API removes the item permanently.

- When `{id}` names such an item, every `/databases/{db}/entries/{id}` route (`GET`, `PATCH`, `DELETE`, `/move`, `/content`, `/otp`) and every `/databases/{db}/folders/{id}` route (`GET`, `PATCH`, `DELETE`, `/children`, `/move`) answers `404`.
- `POST /secrets` and `POST /admin/secrets` answer `404` when `entry_id` names such an item.

The REST API has no recycle-bin view. Reading a link whose target is in the recycle bin (including `GET .../otp`), and creating or updating a link to such a target, answers `403` (see **Link Targets Weighed Like Direct Requests**).

!!! warning "Behavior change for clients"
    Handle the id of an item deleted in another client exactly like an unknown id: requests for it answer `404`, even though the item still exists in that database's recycle bin.

#### Setting a Second Password Requires the `second_pass` Permission (Behavior Change)

Sending `X-New-Second-Password` now also requires the `second_pass` permission:

- `POST /databases/{db}/entries` and `POST /databases/{db}/folders` -- whenever a non-empty `X-New-Second-Password` is sent. The permission is checked on the folder the item is created in (`parent`, or the database root when `parent` is omitted).
- `PATCH /databases/{db}/entries/{id}` and `PATCH /databases/{db}/folders/{id}` -- whenever the header is present and differs from `X-Second-Password`. That covers setting, changing and removing a second password. The permission is checked on the entry or folder being updated.

Without the permission, the request answers `403` with `error.code = 403`, not `4031`, and nothing is changed: the item is not created, or none of the body's fields are applied. On `PATCH`, the current second password is checked first: a wrong or missing `X-Second-Password` on a protected item still answers `403` / `4031`.

!!! warning "Behavior change for clients"
    Only re-prompt for a second password on `4031`. A plain `403` here means the user may not set second passwords in this folder or on this item. Send the request again without `X-New-Second-Password`, or tell the user.

#### Link Entries: Fields Cannot Be Written Through the Link (Behavior Change)

The custom and type-specific fields of a link belong to the entry it points to, and no REST write changes them through the link. `POST /databases/{db}/entries` and `PATCH /databases/{db}/entries/{id}` return `409` ("This entry is a link. Its fields belong to the entry it points to and cannot be changed here.") and apply nothing from the request body when both of these hold:

- the entry is a link after the request -- its current `is_link`, or the `is_link` in the body when present;
- the body contains `custom_fields` or the type sub-object (the key named after `type` in the body, or otherwise after the entry's current type).

`is_link`, `custom_fields` and the sub-object key are matched case-insensitively; `type` is read only under that exact name. In practice:

- Top-level properties such as `name`, and a bare `type`, are still accepted on a link.
- `is_link: false` together with `custom_fields` on a link is accepted: the entry is unlinked and receives the fields.
- `GET` on a link still returns the fields of the entry it points to.

!!! warning "Behavior change for clients"
    To change the fields shown through a link, update the entry named in `linked_item`. Do not send a link's `GET` response back unchanged in a `PATCH`.

#### Icon Fields Validated and `icon` Corrected (Behavior Change)

`image_custom`, `image_index` and `image_name` have always been writable on entries and folders, and `icon` has always been part of every representation. Server 20.0.0 makes the four agree with each other and with the other Password Depot clients:

- **`icon` follows `image_index`.** With `image_custom` `false` and `image_index` `0` to `134`, `icon` is `ico<image_index>.svg`. In every other case - a database icon, or an index outside that range - it is the standard icon of the item's type. Earlier servers returned the type's icon whatever `image_index` said.
- **`icon` is never `<name>.ico`.** Earlier servers returned `<image_name>.ico` for an item with `image_custom` `true` when a favicon file of that name happened to exist on the server. `icon` is now always `ico0.svg` to `ico134.svg`; the item's own image is named by the new `database_icon` field and fetched through [Database Icons](api-reference/icons.md).
- **Writes are validated.** A `POST` or `PATCH` whose `image_*` keys would change the item's icon to something unusable - `image_custom` `true` with an `image_name` that names no icon of this database, `image_custom` `false` together with a non-empty `image_name`, or `image_custom` `false` with an `image_index` outside `-1` to `134` - answers `400` with `error.code` `4007` (`PD_ERRCODE_ICON_ASSIGNMENT`). Earlier servers stored any value and answered `2xx`. Nothing is written on a refusal, not even a second-password change sent in the same request. A body that repeats the stored values is never refused, and a body without the three keys is not checked at all.
- **`image_index` of a database icon is the server's.** With `image_custom` `true` the server sets `image_index` itself, for the desktop clients; a value sent by the client is ignored.
- **A chosen standard icon `0` sticks.** Earlier servers replaced `image_index` `0` on a non-`password` entry with the type's icon on the next write, and removed a nameless custom icon in slot `0` the same way. `{"image_custom": false, "image_index": -1}` is now the explicit way to ask for the type's icon.

!!! warning "Behavior change for clients"
    A client that showed `/file/<icon>` keeps working, and now shows the selected standard icon instead of always the type's icon. A client that relied on `<host>.ico` favicons loses them until it draws `database_icon`; `icon` is the fallback it should already handle. A client that wrote `image_*` values without checking them must handle `400` / `4007` - match the status `400` and the code, never the message - and should take icon names from [List Icons](api-reference/icons.md#list-icons) or from the upload response. To leave an item's icon alone, omit all three keys.

See [Assigning an Icon](api-reference/entries.md#assigning-an-icon).

#### `/file/` Serves Standard Icons Only (Behavior Change)

The unauthenticated `/file/<name>` path serves the 135 standard icons `ico0.svg` to `ico134.svg` (the name in any letter case) and nothing else. It answers `GET` and `HEAD` only, always with `Content-Type: image/svg+xml` and a restrictive `Content-Security-Policy`; any other name answers `404`. Earlier servers also served other files of the server's icon folder under this path, such as the favicons behind a `<name>.ico` value of `icon`. Images of that kind are now reachable only as database icons, per database and with a bearer token. `/temp/` is unchanged.

!!! warning "Behavior change for clients"
    Request only the names that `icon` delivers. A `404` from `/file/` for any other name is final.

#### A Refused Write Leaves the Entry or Folder Unchanged (Behavior Change)

A `PATCH /databases/{db}/entries/{id}` or `PATCH /databases/{db}/folders/{id}` can be refused after the server has read the body -- with `400` when a field has the wrong JSON type (such as a string for `image_index`) or a `custom_fields` element is not an object, with `409` when `custom_fields` or a type-specific sub-object is sent for an entry that is, or in the same body becomes, a link, with `400` and a sub-code for a bad icon (`4007`) or a bad `totp` key (`4001` to `4006`), or with `403` when the body makes the entry a link to an entry you may not read or use.

Whatever the refusal, the item is exactly as the request found it: every field, its icon, its one-time-code settings, its author, its history -- no new history item, and none evicted to make room for one -- and its second password. A client can correct the body and retry against the item's previous values. The same now holds for a folder, whose body used to be applied key by key with nothing restored at all, so that a bad value in one key left the keys before it written.

Three refusals are new with this release, on `POST` and on `PATCH` alike: an entry may not be a link to itself, it may not be a link to another link, and it may not become a link while another link already points at it. All three answer `400`. They are judged on the entry the body would produce, not on what the body asks for, so a `PATCH` that says nothing about the link is judged on the link the entry already has; send `is_link: false`, or a `linked_item` that points at an entry which is not itself a link, to mend one.

A second-password change requested in the same call with `X-New-Second-Password` follows the same rule: it is applied only when the whole request succeeds. On an entry that is a link, setting one no longer re-encrypts the stored field values of the entry the link points at.

Two smaller corrections travel with this. `type` in a `PATCH` or `POST` body is now matched the way every other key is matched -- without regard to letter case, and on the last pair when a name is sent twice; earlier servers matched it exactly and took the first. And a write that the server applies but then cannot report -- it could not serialise the response, or the audit or alert call failed -- answers `200` or `201` with an empty body instead of `5xx`; the change has been made, and a reload shows it.

!!! warning "Behavior change for clients"
    Servers before 20.0.0 applied `X-New-Second-Password` before the body and kept it in effect when the body was rejected. From 20.0.0 a refused request leaves the item under its **previous** second password. An integration that reacted to a `4xx` by re-sending the corrected body with the new password in `X-Second-Password` now gets `403` / `4031` and must send the old one. A client that already read `4xx` as "nothing happened" needs no change; that reading is now correct. A body that sends `type` in a different letter case, or twice, may now reach a different entry type than it did before; send it once, and in lower case.

#### Importance Levels Corrected (Behavior Change)

`importance` on entries and folders uses the same scale as the Windows, macOS, iOS and Android clients: `"high"` is the level those clients show as **High**, `"low"` the level they show as **Low**, and `"normal"` is **Normal**. This applies to `importance` in every entry and folder representation and to the `importance` field in `POST` and `PATCH` requests. Servers before 20.0.0 mapped `"low"` and `"high"` the other way round; `"normal"` is unchanged.

!!! warning "Behavior change for clients"
    Clients that show and send the string as delivered need no change. Do not add an inversion of your own, or the level flips twice. An item whose importance was set to `"low"` or `"high"` through this API on an earlier server holds the opposite level and now reads back as that level, which is the level the desktop and mobile clients already show for it. The server does not migrate these values, because a database does not record which client set them.

No field names, strings or status codes change. Matching is case-insensitive, and any other string (or `null`) is stored as `"normal"`.

#### Seal Checked Against the Caller (Behavior Change)

These requests check the seals that apply to **you**. A seal you issued yourself does not block you:

- reading an entry (`GET /databases/{db}/entries/{id}`)
- reading, creating or updating a link (`GET /databases/{db}/entries/{id}`, `POST /databases/{db}/entries`, `PATCH /databases/{db}/entries/{id}`): the seal is checked on the entry the link points to, as well as on the link itself

This includes seals set on a parent folder and seals that apply to you through a group. Only active permission rows count. Rows that have expired or are not yet valid do not apply, and neither do seals that are broken or unset. The new one-time-code endpoint (`GET /databases/{db}/entries/{id}/otp`) uses the same check.

!!! warning "Behavior change for clients"
    Reading an entry that is sealed for you returns `403` with `error.code = 403`. The seal is checked before the second password, so a sealed entry never returns `4031`, even if it has a second password. Field names, strings and other status codes do not change.

#### Link Targets Weighed Like Direct Requests (Behavior Change)

Reading, creating or updating a **link** requires the following of the entry it points to (`linked_item`):

- read **and** use permission
- the entry is not sealed for you
- the entry is not a folder and not in the recycle bin

This applies to `GET /databases/{db}/entries/{id}` and `GET /databases/{db}/entries/{id}/otp` on a link, to `POST /databases/{db}/entries` with `is_link`, and to every `PATCH /databases/{db}/entries/{id}` of a link, including one that changes only other fields. Alerts set on the linked entry, or on a folder above it, also fire when it is read through a link.

Unchanged: when you read through a link and the linked entry has a second password, `X-Second-Password` must match that entry's second password, or the request returns `403` with `error.code` `4031`.

!!! warning "Behavior change for clients"
    A request on a link whose linked entry fails one of the conditions above returns `403` (`error.code` `403`). Links to entries you can read and use directly are unaffected.

### Shared Secrets

#### Server Shared-Secret Policy Applied When a Secret Is Created (Behavior Change)

`POST /secrets` and `POST /admin/secrets` apply the server's shared-secret policy, as set in the Server Manager, to every new secret. The policy is applied after the entry and permission checks and before the secret's `status` is set:

| Policy setting | Effect on the new secret |
|----------------|--------------------------|
| Channel for the secret's `protocol` (`https` or `pd-server`; `https` when omitted) not enabled | Refused: `403` "The server policy does not permit sharing over this channel." |
| Approval required | `approval_required` is set to `true`; the secret starts with `status` `pending_approval` |
| Minimum quorum (when the secret requires approval) | A `quorum_n` below the minimum is raised to it, and `quorum_m` is then raised to at least the new `quorum_n` |
| Second factor required | `require_2fa` is set to `true` for `pd-server` secrets; `https` secrets are not affected |
| Maximum number of opens | An `access_max` above the maximum is lowered to it; an `access_max` below `1` is set to it. An omitted `access_max` defaults to `1` |
| Maximum lifetime | `expires_at` is capped at the creation time plus the lifetime, and set to that when missing or `null`. The lifetime is applied exactly, including lifetimes shorter than a day. |

The channel refusal, the approval, quorum and second-factor settings, and exact lifetimes are new in Server 20.0.0; the caps on opens and lifetime were already applied. The policy only tightens a request: it never clears an `approval_required` or `require_2fa` that the creator asked for. Without a policy maximum, an `access_max` below `1` or a missing `expires_at` still returns `400`. The same policy applies to secrets created in the Windows client.

!!! warning "Behavior change for clients"
    Do not assume the request values were kept. Read the effective `status`, `approval_required`, `quorum_n`, `quorum_m`, `require_2fa`, `access_max` and `expires_at` from the `201` response, and handle `403` when the server does not allow the channel.

#### Creating a Secret Requires Read Permission (Behavior Change)

`POST /secrets` and `POST /admin/secrets` now require `read` permission on the entry named by `entry_id` (in the database named by `database_id`), in addition to `share`. A caller who holds `share` without `read` receives `403 Forbidden` (body `error.code` = `403`). Existing secrets are not affected.

#### Link Tokens Returned Only to Those They Are For (Behavior Change)

In the full secret representation, the link tokens depend on who is asking:

| Field | Returned to | Omitted for |
|-------|-------------|-------------|
| `open_uuid` | the secret's author, and users whose own ID is in `recipient_ids` | everyone else |
| `approve_uuid` | the secret's author, and users whose own ID is in `approver_ids` | everyone else |

Membership of a listed group does not count. The rule depends on the caller's role in the secret, not on the scope. Administrators using `/admin/secrets` receive a token only if they are the author or are listed for it. The rule applies to every response that carries the full representation:

- create, in client and admin scope
- `GET` by id, in client and admin scope
- `PATCH` by id (admin scope only)
- the `approve`, `reject` and `revoke` responses, in client and admin scope

In client scope, `GET` by id and `revoke` are available only to the author, so those responses always carry both tokens.

The list representation carries neither token, as before. No other field is affected by this change.

!!! warning "Behavior change for clients"
    Treat `open_uuid` and `approve_uuid` as optional. A missing field means the token is not for this caller; it is not an error. The author receives both in the `201` response of the create call.

#### Deleting a Secret in Admin Scope Requires a Server Administrator or the Author (Behavior Change)

`DELETE /admin/secrets/{id}` returns `403` (`error.code = 403`) unless the caller is a server administrator, a super-administrator or the secret's author. This is the same rule as `POST /admin/secrets/{id}/revoke`. A secret that does not exist still returns `404`. `DELETE /secrets/{id}` in client scope still requires the author.

!!! warning "Behavior change for clients"
    Handle `403` on this call. Detect it by the status and `error.code`, not by the message text, which is localized. No field names, response bodies or other status codes change.

#### Fix: `include_totp` Applied to Shared Links (Behavior Change)

`include_totp` on a shared secret decides whether the recipient gets the shared entry's one-time code. The default is `true`, also when the field is omitted on `POST /secrets` and `POST /admin/secrets`:

| `include_totp` | `https` secret | `pd-server` secret |
|----------------|----------------|--------------------|
| `true` | The shared-link page (`/shared/<open_uuid>`) shows the code that is current at the moment the page is opened, with a copy button. The page does not refresh the code and never shows the seed. | The TOTP seed travels with the entry, so the recipient's client computes the codes itself. |
| `false` | The page shows no one-time code. | The entry is delivered without its TOTP seed, the history it carries included. |

Servers before 20.0.0 accepted and echoed the value but neither kept it across a restart nor applied it: every shared link behaved as `true`, and a secret created with `false` reported `true` again after the next restart. Server 20.0.0 applies the value each time a secret is opened and keeps it across restarts. The fix matters more now that a seed can be written with one REST call (see [One-Time Codes (TOTP)](#one-time-codes-totp)): "write a seed, then share the entry" handed out the code, or over `pd-server` the seed, even when the creator had asked for `false`.

The page shows a code only when the entry can produce one -- the condition behind `has_otp`. An entry whose stored TOTP settings are invalid (`totp.state` `invalid`), or whose type is `encrypted_file` or `certificate` (`totp.state` `unsupported`), shows its other fields without a code. `PATCH /admin/secrets/{id}` accepts `include_totp` as before; an omitted value keeps the stored one. The server's shared-secret policy does not change the value, and secrets created in the Windows client carry `true`.

!!! warning "Behavior change for clients"
    A client that sent `include_totp: false` and relied on the code still showing must send `true` or omit the field. A client that sends `false` for every secret now shares entries without their one-time code. A secret that was created with `false` on an earlier server reports `true` after the upgrade (earlier servers never kept the value): read `include_totp` of the secrets that can still be opened, and set it to `false` with `PATCH /admin/secrets/{id}` where the creator had asked for that. No field names, status codes or response shapes change.

### Passkeys (WebAuthn)

#### Passkey Responses Verified Against the Relying Party (Behavior Change)

`POST /auth/webauthn/complete` (sign-in) and `POST /me/passkeys/complete` (registration) check every WebAuthn response against the server's relying party ID (RP ID). The begin endpoints return that ID as `publicKey.rpId` for sign-in and `publicKey.rp.id` for registration. A response is accepted only if all of these hold:

- `clientDataJSON.origin` is present, and its host equals the RP ID or is a subdomain of it.
- `authenticatorData.rpIdHash` is the SHA-256 hash of the RP ID.
- The user-present (UP) flag is set.
- The user-verified (UV) flag is set when the server's user-verification setting for that ceremony is **required**, which is the default. With any other setting (`preferred`, `discouraged`, or none), UV is not required.
- The response does not report a credential as backed up without being backup-eligible (BS = 1 with BE = 0).

On `/auth/webauthn/complete`, a failed check returns the generic passkey sign-in failure: `401`, with `error.code` `401`. It counts toward the IP address lockout like any other failed sign-in. On `/me/passkeys/complete`, a failed check returns `400`, and `error.message` describes the check that failed. That text is for display and logging only and may be localized, so do not parse it. The options returned by the `begin` endpoints are unchanged.

!!! warning "Behavior change for clients"
    Run both ceremonies from an origin whose host is the server's RP ID or a subdomain of it. Pass the options from the `begin` endpoint to the browser unchanged, including the user-verification requirement: `publicKey.userVerification` for sign-in, `publicKey.authenticatorSelection.userVerification` for registration.

#### Passkey Key Types and Algorithms (Behavior Change)

Passkey registration (`POST /me/passkeys/complete`) accepts only these credential public keys:

- EC2 keys on P-256 or P-384, with `x` and `y` each exactly the curve width: 32 bytes for P-256, 48 bytes for P-384
- RSA keys, with both `n` and `e` present

Other key types and curves, such as P-521, secp256k1 or Ed25519, answer `400`. Signatures are verified only for COSE algorithms `-7` (ES256), `-35` (ES384) and `-257` (RS256). This covers `packed` attestation statements (self or `x5c`) and sign-in assertions; any other algorithm is refused.

The labels of a COSE key may appear in any order. Attestation formats `none`, `packed` and `tpm` are accepted as before. For `tpm`, the key in `pubArea` must be P-256, P-384 or RSA and must match the credential key. The algorithms advertised in the registration options (ES256, ES384, RS256) are unchanged.

#### Passkey `sign_count` Is the Authenticator's Counter; Names Kept Across Restarts (Behavior Change)

`sign_count` holds the signature counter that the authenticator reported the last time the server verified a sign-in with the passkey. It appears only in the full passkey representation: the `201` response of `POST /me/passkeys/complete` and the `200` response of `PATCH /me/passkeys/{id}`. List responses (`GET /me/passkeys`) use the compact representation and do not include it. It is not a count of sign-ins:

- It is `0` for a newly registered passkey. It is also `0` for a passkey registered on an earlier server version, until its first sign-in on Server 20.0.0.
- It stays `0` for synced passkeys whose authenticators always report zero.
- It is the value the authenticator reports. Between sign-ins it can go up by more than one or stay the same.

A passkey's `name`, whether given at registration or set with `PATCH /me/passkeys/{id}`, is kept across server restarts. `sign_count` is stored with the passkey too. A sign-in does not make the server save on its own, though, so after a restart `sign_count` and `last_used_at` can show values from before the most recent sign-ins.

!!! warning "Behavior change for clients"
    Do not display or use `sign_count` as a usage counter. Use `last_used_at` to show when a passkey was last used.

### Requests and Errors

#### Request Bodies Must Be Valid JSON (Behavior Change)

Every v2.0 endpoint that reads a JSON request body now refuses a body it cannot parse as a JSON object. The following answer `400` (`error.code = 400`, "Malformed JSON request body.") before anything is changed:

- a JSON object that is truncated or contains a syntax error
- a body that contains only whitespace
- an empty body (`Content-Length: 0`)

This applies to:

- the `POST` and `PATCH` routes for databases, users, groups, alerts, permissions, secrets, entries and folders
- the entry and folder `/move` routes
- `PATCH /me`, `POST /me/password` and `POST /admin/users/{id}/password`
- `POST /auth/webauthn/begin` and `POST /auth/webauthn/complete`
- `POST /me/passkeys/complete` and `PATCH /me/passkeys/{id}`

`POST /auth/login` and `POST /secrets/{id}/approve` (and `POST /admin/secrets/{id}/approve`) do not reject an empty body as malformed: an HTTP Negotiate retry of the login sends none, and the approval body is optional. A non-empty body on these endpoints must still be valid JSON. On `POST /auth/login`, `POST /auth/webauthn/begin` and `POST /auth/webauthn/complete`, a `400` for a malformed body does not count as a failed sign-in.

The message text can be localized; check the status and `error.code`, not the message.

!!! warning "Behavior change for clients"
    Always send a JSON object as the request body, and send `{}` when a request has no body fields -- for example a `PATCH` on an entry or folder that only sets `X-New-Second-Password`. A request that answers `400` has to be corrected before it is retried.

#### Chunked Request Bodies Answer `411 Length Required` (Behavior Change)

Every request body must state its size in a `Content-Length` header. A request that carries a `Transfer-Encoding` header - of any value, and whether or not it also sends a `Content-Length`; `chunked` is the one clients send - is refused with HTTP `411 Length Required` and `error.code` `411`:

```json
{
  "error": {
    "code": 411,
    "message": "Send the request body with a Content-Length header. Chunked transfer encoding is not accepted."
  }
}
```

The refusal happens while the request headers are being read: the body is never read, the check runs before authentication, and the connection is closed afterwards. It applies to every method and every path, including a path that would otherwise answer `404` or `410`, a mirror server's `403` and an address under an IP lockout. A request that carries both a `Transfer-Encoding` and a `Content-Length` answers `411`, not `413`, even when the length alone would have been over the limit: the length is not trusted, because it does not describe what would be read. Servers before 20.0.0 read a chunked body on any route into memory with no size limit at all - the `Content-Length` caps (1 MB for JSON bodies, 64 MB for document content) never saw one.

Like the header-stage `413`, this answer is produced before the headers a normal response carries are added. The payload is the JSON error object above, but it is sent with `Content-Type: text/html; charset=utf-8` and without CORS or `Cache-Control` headers. A browser reports a network error rather than a status, and a generated client that picks its deserializer from `Content-Type` will not parse it. Match the HTTP status.

A request that sends *neither* header is unaffected: the server never reads a body whose size was not announced, so there is nothing to refuse. A `POST` or `PUT` that puts body bytes on the wire without announcing them still receives the HTTP layer's own bare `411`, whose body is announced in the response headers but never sent before the connection closes, so most clients report a truncated response rather than the status - unchanged from Server 19.x. A request that announces no length and sends no bytes is not refused either, but an endpoint that needs a body then fails it with `500`: always send a `Content-Length`, `0` included.

!!! warning "Behavior change for clients"
    No Password Depot client is affected: the web client, the Android client and the PowerShell example client all send bodies of known length. Third-party integrations that stream their request bodies are. **.NET `HttpClient` is the common case** - `PostAsJsonAsync`, `JsonContent` and `StreamContent` over a non-seekable stream send `Transfer-Encoding: chunked` by default, on ordinary JSON calls as well as on uploads. Buffer the body so its length is known (`StringContent`, `ByteArrayContent`, `await content.LoadIntoBufferAsync()`, or a seekable stream); setting `request.Headers.TransferEncodingChunked = false` does **not** help, as the request still goes out chunked. The same applies to `curl -T -`, an explicit `-H "Transfer-Encoding: chunked"`, `Invoke-WebRequest -TransferEncoding chunked`, Python `requests` with a generator body and Node streams without a length. A **reverse proxy in streaming mode** (nginx `proxy_request_buffering off`, some cloud load balancers) passes the client's own framing through, so an upload that arrived with a `Content-Length` still has one; a body whose length the proxy does not know - a streaming client, or an HTTP/2 front end - becomes chunked upstream and now receives `411`. Leaving request buffering on (the nginx default) makes the proxy state a length whatever the client did.

### Shared-Link Page

#### Shared-Link Page: Copy Confirmation for RDP, PuTTY and TeamViewer Entries

This applies to the shared-link page (`/shared/...`) for RDP, PuTTY and TeamViewer entries. The tooltip of the Computer / Host / Partner ID row has its own element id, `tooltip-url`, matching the row's input id `url`. Copying that row shows the confirmation next to it, and copying the login shows it next to the login.

### Fixes

#### One-Time Codes Counted in UTC

The server counts every one-time code on its clock in true UTC:

- `GET /databases/{db}/entries/{id}/otp` (both `code` and `expires_in`)
- the TOTP code on the shared-link page
- the authenticator-app (TOTP) codes checked at two-factor login

Standard authenticator apps count on the same UTC time base. With a correctly set server clock, codes stay in step with those apps across daylight saving time changes, including the hour that repeats when daylight saving time ends. No fields, formats or status codes change.

#### Default Icon of Document Entries

A `document` entry without an icon of its own reports `icon` `ico133.svg`, the document icon every other Password Depot client shows. Earlier servers reported `ico132.svg`, the icon of encrypted-file entries.

### Documentation Corrections

These correct the documentation only; the server's behavior is described as it has been.

- **`PUT /databases/{db}/entries/{id}/content` over 64 MB answers `413`, not `400`.** The server refuses a `Content-Length` above the limit before it reads the body. `400` is left for an entry that is not a `document`. The OpenAPI document and the test suite already said `413`. A chunked body no longer reaches that size check at all: any `Transfer-Encoding` header is now refused with `411` while the request headers are read, see [Chunked Request Bodies Answer `411 Length Required`](#chunked-request-bodies-answer-411-length-required-behavior-change).
- **`Content-Type` is not required on that upload, and is not stored.** The server does not read it. The type reported by `document.type`, and sent as `Content-Type` by `GET .../content`, is derived from the extension of the file name.
- **The file name field is `document.name`.** The reference called it `content_name` in two places; v2.0 has no such field. `Content-Disposition` on the upload sets `document.name`, and the download sends it back.
- **v2.0 responses have no `rights` string.** The overview described a permission string such as `"RMIDCFAPE-Y-HL"` on database and entry responses. That field belongs to REST API v1.0; v2.0 expresses permissions only as token arrays in the [permission rules](api-reference/permissions.md#rights-values).
- **`410`, `413` and `501` were missing from the status tables** of the overview: `410` for `/v1.0/` paths on Server 20.0.0, `413` for oversized request bodies, `501` for the entry types `encrypted_file` and `certificate`.
- **Mirror servers.** The overview now says that a mirror server answers every request other than `GET` that carries a bearer token with `403`, `POST /auth/logout` included. This is not new in Server 20.0.0; it was not documented.
- **The JSON examples** of entries and folders showed an `icon` that the server of the time would not have returned for them (it ignored `image_index`). With the change above they are now what Server 20.0.0 returns.

---

## Server 19.x -- v2.0 Released

REST API v2.0 was introduced in Password Depot Enterprise Server **19.1.0**. This section describes v2.0 as served by Server 19.2.x. Servers before 20.0.0 serve v1.0 alongside v2.0.

### Breaking Changes from v1.0

#### New URL Structure

API endpoints have been redesigned from verb-based commands to RESTful noun-based resource URLs with standard HTTP methods.

| v1.0 (Verb-based) | v2.0 (Noun-based) | Method |
|--------------------|--------------------| -------|
| `POST /login` | `POST /auth/login` | POST |
| `POST /logout` | `POST /auth/logout` | POST |
| `GET /oidc` | `GET /auth/oidc` | GET |
| `GET /list` | `GET /databases` | GET |
| `GET /list?db=...` | `GET /databases/{db}/children`, `GET /databases/{db}/folders/{id}/children` | GET |
| `GET /read?db=...&entry=...` | `GET /databases/{db}/entries/{id}`, `GET /databases/{db}/folders/{id}` | GET |
| `PUT /add` | `POST /databases/{db}/entries`, `POST /databases/{db}/folders` | POST |
| `POST /modify` | `PATCH /databases/{db}/entries/{id}`, `PATCH /databases/{db}/folders/{id}` | PATCH |
| `DELETE /delete` | `DELETE /databases/{db}/entries/{id}`, `DELETE /databases/{db}/folders/{id}` (one item per request) | DELETE |
| `POST /move` | `POST /databases/{db}/entries/{id}/move`, `POST /databases/{db}/folders/{id}/move` (one item per request) | POST |
| `GET /search` | `GET /databases/{db}/search` | GET |

`GET /databases/{db}/entries` without an id is not a listing and answers `404`. On Server 19.2.x both API versions are served side by side. Server 20.0.0 answers `GET`, `POST`, `PUT`, `PATCH` and `DELETE` requests to `/v1.0/` with `410 Gone` (see **REST API v1.0 Removed**).

#### Standard Bearer Token Authentication

Custom `access_token` and `client_id` headers have been replaced with the industry-standard `Authorization: Bearer <token>` header.

| Aspect | v1.0 | v2.0 |
|--------|------|------|
| Login response | `{"access_token": "...", "client_id": "..."}` | `{"access_token": "..."}` |
| Auth headers | `access_token: ...` + `client_id: ...` | `Authorization: Bearer ...` |
| Header count | 2 custom headers per request | 1 standard header per request |

#### Negotiate Authentication (Windows SSO)

New `"auth": "negotiate"` login method enables passwordless authentication via HTTP Negotiate (SPNEGO/Kerberos). The client's Windows process identity is used directly -- no username or password is sent in the request body. This is ideal for Group Managed Service Accounts (gMSA), scheduled tasks, and CI/CD pipelines in Windows domain environments.

#### Long-Lived Tokens for Service Accounts

The Password Depot Server Manager can generate **long-lived access tokens** for a user account, in client or admin scope, with an expiry date 1 to 730 days ahead (180 by default). Unlike session tokens, which lapse after 10 minutes without activity, they do not expire on inactivity, which makes them suitable for automation. A token is refused with `401` once it has expired or has been revoked or deleted in the Server Manager. Only a Super Administrator can generate, revoke or delete them. The token stops working at 00:00 on its expiry date. An admin-scope token is refused with `403` if its account has no Server Manager access, and a client-scope token for a Super Administrator account is refused with `401` ("The admin account cannot login from the client."). `POST /auth/logout` with such a token answers `200` with `"revoked": false` and `"token_type": "api_token"`, and neither revokes the token nor ends the account's session.

#### Native JSON Types

String-encoded values have been replaced with native JSON types throughout all responses and request bodies.

| Field type | v1.0 | v2.0 |
|------------|------|------|
| Booleans | `"1"` / `"0"` | `true` / `false` |
| Integers | `"42"` | `42` |
| Null values | `""` or date before 1901 | `null` |

Most timestamps that were never set are `null` (for example `expires_at` on entries and secrets, and `valid_from` / `valid_until` on permissions). Three fields carry the value `"1899-12-30T00:00:00.000Z"` instead: users `last_login`, and passkeys `created_at` and `last_used_at`. Treat that value as "never".

#### Folders as a Separate Resource

Folders are no longer marked by the `itemclass` field (`"-1"` in v1.0). They have their own endpoints to read, create, update, move and delete a folder, including `GET /databases/{db}/folders/{id}` for a single folder. There is no separate folder list. The `children` endpoints return folders and entries together, so tell them apart by `type`: folders have `"type": "folder"`.

| Operation | v1.0 | v2.0 |
|-----------|------|------|
| List folders | `GET /list?db=...` (filter by `itemclass`) | `GET /databases/{db}/children` or `GET /databases/{db}/folders/{id}/children` (listed together with entries, `"type": "folder"`) |
| Create folder | `PUT /add` with `itemclass: "-1"` | `POST /databases/{db}/folders` |
| Update folder | `POST /modify` | `PATCH /databases/{db}/folders/{id}` |
| Move folder | `POST /move` | `POST /databases/{db}/folders/{id}/move` |
| Delete folder | `DELETE /delete` | `DELETE /databases/{db}/folders/{id}` |

#### Standardized Error Format

The error response format has been restructured with a nested `error` object. `error.code` is a JSON number; in v1.0 `code` was a string.

**v1.0:**
```json
{
  "error": "Entry not found",
  "code": "404"
}
```

**v2.0:**
```json
{
  "error": {
    "code": 404,
    "message": "Entry not found"
  }
}
```

### New Features

#### Server Administration Endpoints

v2.0 adds comprehensive server administration capabilities that were not available in v1.0. They are served in the **admin scope** (log in with `"scope": "admin"`):

- **Users** -- Full CRUD management of server users (`GET/POST /admin/users`, `GET/PATCH/DELETE /admin/users/{id}`, `POST /admin/users/{id}/password`)
- **Groups** -- Full CRUD management of user groups (`GET/POST /admin/groups`, `GET/PATCH/DELETE /admin/groups/{id}`)
- **Permissions** -- Granular access control per database with database-level and entry-level rights, allow/deny model, validity periods, and seal workflow (`GET/POST /admin/databases/{db}/permissions`, `GET/PATCH/DELETE /admin/databases/{db}/permissions/{id}`)

In client scope, `/users` and `/groups` are a read-only directory (see **Client-Scope User and Group Directory**).

#### User Profile and Self-Service

- `GET /me` -- Retrieve the authenticated user's own profile (works in both client and admin scope)
- `PATCH /me` -- Update own profile; only `display_name`, `department` and `phone` are accepted (any other field returns `400`); returns the updated profile
- `POST /me/password` -- Change own password (requires current password verification)
- `GET /me/passkeys`, `POST /me/passkeys/begin`, `POST /me/passkeys/complete`, `PATCH/DELETE /me/passkeys/{id}` -- List, register, rename and delete own passkeys

#### Client-Scope User and Group Directory

Users and groups can be read outside the admin section, in a read-only compact representation. Any authenticated session can use these routes, and admin-scope sessions get the same compact form. Client applications can use them to look up users and groups by ID and name, for example when working with shared secrets. Full user and group management stays under `/admin/users` and `/admin/groups`.

- `GET /users`, `GET /users/{id}` -- List/get users (compact: `id`, `name`, `display_name`, `department`, `email`, `disabled`, `updated_at`)
- `GET /groups`, `GET /groups/{id}` -- List/get groups (compact: `id`, `name`, `description`, `department`, `email`, `disabled`, `updated_at`)

Lists are paginated with `offset` and `limit` and return `data`, `total`, `offset` and `limit`. An unknown ID, or any extra path segment after the ID, returns `404`. These routes accept only `GET`: `POST`, `PUT`, `PATCH` and `DELETE` return `405` with an `Allow: GET` header.

#### Alerts Management

New endpoints for managing server alert rules with full event type support, email notification recipients, and optional scoping to specific databases, users, or entries:

- `GET /admin/alerts` -- List all configured alerts
- `POST /admin/alerts` -- Create a new alert
- `GET /admin/alerts/{id}` -- Get alert details (including recipients and scope filters)
- `PATCH /admin/alerts/{id}` -- Update an alert
- `DELETE /admin/alerts/{id}` -- Delete an alert

#### Secrets (Shared Links) Management

New endpoints for sharing password entries with other users via secure links. Available in both client and admin scopes with an approval workflow:

- `GET/POST /secrets` -- List own secrets / create a shared secret (client scope)
- `GET/DELETE /secrets/{id}` -- Get or delete own secret
- `POST /secrets/{id}/approve` -- Approve a secret (designated approvers)
- `POST /secrets/{id}/reject` -- Reject a secret (designated approvers)
- `POST /secrets/{id}/revoke` -- Revoke own secret (author)
- `GET/POST/PATCH/DELETE /admin/secrets[/{id}]` -- Manage all secrets on the server (admin scope; see the [Secrets reference](api-reference/secrets.md) for the role each method requires)
- `POST /admin/secrets/{id}/approve`, `POST /admin/secrets/{id}/reject`, `POST /admin/secrets/{id}/revoke` -- Approval workflow in admin scope (approve and reject: designated approvers; revoke: the author or a server administrator)

Supports HTTPS (anonymous browser access) and `pd-server://` (binary client) protocols, configurable quorum-based approval, 2FA requirement, and access count limits.

#### Document Content Endpoints

One of the most requested features from customers: **document entries now support binary content retrieval and upload via the REST API**, a capability that was not available in v1.0. Entries of type `document` can store files up to 64 MB, and the content is managed via dedicated sub-resource endpoints:

- `GET /databases/{db}/entries/{id}/content` -- Download document content
- `PUT /databases/{db}/entries/{id}/content` -- Upload or replace document content (max 64 MB)

#### Type-Specific Fields

In the full representation (`GET /databases/{db}/entries/{id}`), entry types other than `password` and `custom` carry their type-specific attributes in a sub-object keyed by the entry type name (e.g., `"document": {"name": "report.pdf", "type": "application/pdf", "size": 2458621}`). `POST` and `PATCH` accept the same sub-object under the same key. This keeps the common entry schema clean and supports future type extensions without schema conflicts. Supported type sub-objects: `credit_card`, `license`, `identity`, `information`, `banking`, `document`, `rdp`, `putty`, `teamviewer`, `passkey`. The v1.0 `fields` array is replaced by `custom_fields`, which is only present for `password` and `custom` entry types, and by the type sub-object for all other types. Entry types `encrypted_file` and `certificate` are not supported by the REST API: they are left out of `GET /databases/{db}/children` and `GET /databases/{db}/search`, and reading one returns `501 Not Implemented`.

#### Database Management

Databases support full CRUD operations in the **admin scope**:

- `POST /admin/databases` -- Create a new database
- `PATCH /admin/databases/{id}` -- Update database settings
- `DELETE /admin/databases/{id}` -- Delete a database

In client scope, the database resource itself is read-only: `/databases` and `/databases/{id}` accept only `GET` and answer any other method with `405 Method Not Allowed`. Folders and entries inside a database keep their own write endpoints.

#### Pagination on All List Endpoints

All list endpoints support pagination through the `offset` and `limit` query parameters and return a standardized response envelope:

```json
{
  "data": [...],
  "total": 125,
  "offset": 0,
  "limit": 100
}
```

The exception is `GET /admin/audit`. It streams newline-delimited JSON (`application/x-ndjson`) with an optional `limit` and `X-Audit-*` response headers instead of the envelope.

#### Additional Error Code

- `409 Conflict` -- Returned when a request conflicts with the current state of a resource. Examples:
    - creating a user (`POST /admin/users`) or group (`POST /admin/groups`) with a name that is already taken
    - moving an entry or folder (`POST /databases/{db}/entries/{id}/move`, `POST /databases/{db}/folders/{id}/move`) to the folder it is already in, or moving a folder into itself or one of its own subfolders
    - renaming a passkey (`PATCH /me/passkeys/{id}`) to a name that another of your passkeys already has (an empty name returns `400`)
    - changing the password (`POST /me/password`, `POST /admin/users/{id}/password`) of an account whose `auth_modes` does not include `standard`
    - `POST /auth/login` for an account whose second factor is FIDO2, which is not available over REST

### Security & Bug Fixes

#### No-Cache Response Headers

API responses include `Cache-Control: no-store` and `Pragma: no-cache`. This covers all `/v2.0` endpoints, `/file` and `/temp` downloads, OPTIONS preflight responses and JSON error responses. The exceptions are the rejections the server sends while it is still reading the request headers, before the request is processed: a `413 Payload Too Large`, and on Server 20.0.0 and later a `411 Length Required`. The shared-link HTML page (`GET /shared/...`) sends `Cache-Control: no-cache, no-store` instead, plus the same `Pragma: no-cache`. API responses can carry plaintext secrets (entry passwords, shared-secret values, second-password-decrypted fields), so they must never be written to a shared or browser disk cache. No status codes or body fields change.

#### UTC Timestamps Corrected (Behavior Change)

Entity timestamp fields are UTC instants with a trailing `Z` (RFC 3339). Before 19.2.0, these fields carried the server's **local** wall-clock time with a `Z` suffix; since 19.2.0 the `Z` value is the true UTC instant.

!!! warning "Behavior change for clients"
    Clients that parsed the old values as UTC see times shift by the server's UTC offset -- this is the intended correction. For example, on a server at UTC+2, a 14:00 local timestamp changed from `...T14:00:00Z` (wrong) to `...T12:00:00Z` (correct).

Affected fields:

- users `updated_at` and `last_login`
- groups `updated_at`
- databases `updated_at`
- folders `updated_at`
- entries `updated_at` and `expires_at`
- alerts `updated_at`
- secrets `created_at`, `expires_at`, and `timestamp` in the `approved_by` / `rejected_by` arrays
- passkeys `created_at` and `last_used_at`
- permissions `valid_from` and `valid_until`

The request fields `expires_at` (entries, secrets) and `valid_from` / `valid_until` (permissions) are read as UTC instants: a value without an offset is taken as UTC, a value with an offset is converted, and `null` clears the field. A value that is not a valid ISO 8601 string returns `400`.

The server keeps these times in its own local time. An instant inside the hour that repeats when daylight saving time ends on the server is therefore returned as the later of the two instants that share that wall-clock time, both when it is emitted and when a written value is read back.

Entries and secrets `expires_at` and permissions `valid_from` / `valid_until` are `null` when not set. The other fields are always present; one that was never set -- for example `last_login` of a user who has never signed in, or a passkey's `last_used_at` -- is `"1899-12-30T00:00:00.000Z"`.

The date-only fields `license.purchase_date` and `identity.birth_date` are not converted: they are returned as `YYYY-MM-DDT00:00:00.000Z` (or `null`), and an inbound value that is not an ISO 8601 date is stored as empty rather than refused. No field names change.

#### Search Filters Unsupported Entry Types

`GET /databases/{db}/search` no longer returns entries whose type is unsupported by the REST/web surface -- i.e. the desktop-only legacy types `encrypted_file` and `certificate`. This brings `/search` into parity with `GET /children`, which already excludes them. The result array, the `total`/result count, and pagination all reflect the filtered set. Previously such entries appeared in results but returned `501 Not Implemented` when opened.

#### Second Password Enforced on Update

`PATCH /databases/{db}/entries/{id}` and `PATCH /databases/{db}/folders/{id}` now **require** a correct `X-Second-Password` header when the target item is second-password protected (`has_second_pass=true`); otherwise the server responds `403 Forbidden`. This also applies to the change-second-password flow: when sending `X-New-Second-Password`, the client must additionally send the correct current `X-Second-Password`. Items without a second password are unaffected.

#### Error Code 4031 for Wrong Second Password

A wrong or missing `X-Second-Password` on a protected entry or folder returns HTTP `403` with the JSON body `error.code = 4031` (`PD_ERRCODE_INVALID_SECOND_PASS`). This applies to `GET` or `PATCH` on `/databases/{db}/entries/{id}` and `/databases/{db}/folders/{id}`. A generic access-denied or sealed `403` keeps `error.code = 403`.

More generally, `error.code` may carry an application sub-code (`>= 1000`) that differs from the HTTP status. The HTTP status remains the authority for the response class, while `error.code` can convey a finer machine-readable reason.

**Client guidance:** on `HTTP status == 403 && body.error.code == 4031`, re-prompt for the second password. On a generic `403`, do not re-prompt. Always match the numeric code, never the localized message.

### Documentation Corrections

#### OIDC Login Token Contract (Clarification)

`POST /v2.0/auth/login` with `auth: "oidc"` sends `{ auth, idp, id_token }`, where `idp` is the ID of a configured OIDC provider. The `id_token` field **must** carry either (a) a signed OIDC `id_token` JWT whose `aud` contains the `client_id` configured for that provider, or (b) an OAuth access token (opaque or JWT) obtained for that same client and usable as a Bearer credential at the provider's `userinfo_endpoint`. It **must not** carry a bare authorization `code`.

The REST server performs **no** authorization-code exchange. It validates the supplied value directly: first as an ID token (signature against the provider's JWKS, `exp`/`nbf`, `aud`), and otherwise as a Bearer token at the `userinfo_endpoint`. It never POSTs to the `token_endpoint`. A provider configured for authorization-code flow only (`response_type` `code` with no `id_token`, e.g. a Google-style preset) is supported only if the relying party exchanges the code for a token itself before calling REST login. The recommended client configuration is to request `response_type=id_token`. An invalid, expired or forged token, a bare code, an unknown `idp`, or no matching local user returns HTTP `401`. This is a clarification only -- no behavior change.

#### `/children` Response Envelope Correction (Doc Fix)

The response envelope of `GET /databases/{db}/children` and `GET /databases/{db}/folders/{id}/children` contains only `path`, `data`, `total`, `offset` and `limit`. The previously documented top-level fields `name`, `parent` and `has_second_pass` are **not** part of the response, and no released server has ever emitted them. They have been removed from the documentation. (Each item inside `data` still has its own `has_second_pass`; only the top-level envelope fields were wrong.)
