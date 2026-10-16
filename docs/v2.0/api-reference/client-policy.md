# Policies for Clients

*Server 20.0.0 and later.*

The server resolves, for each user, the [policies](policies.md) set for the server, for the user's groups and for the user, and delivers the result to the user's own sessions as one JSON document, the **client policy bundle**: the people-side settings an app applies -- those of users, not of databases and folders -- and the account password rules, as far as a policy sets them, each with its value, where the value comes from and whether it is enforced. A client does not need the policy registry or the policy documents to read it, and it needs no admin scope.

The bundle is an API capability: the server issues it, and an app or an integration decides for itself what it does with it. No Password Depot app applies the bundle yet; see [Settings Clients Follow](policies.md#settings-clients-follow) for the settings Password Depot for Windows (Corporate Edition) follows by its own route.

| Where | What |
|-------|------|
| [`GET /v2.0/me/policy`](#get-own-policy-bundle) | The bundle of the signed-in user, issued for the session of the request |
| [`POST /v2.0/auth/login`](authentication.md#success-response) and [`POST /v2.0/auth/webauthn/complete`](authentication.md#webauthn) | The same bundle as the member `policy` of a successful client-scope sign-in |

!!! warning "Provisional for apps"
    The members described on this page are what the server sends. Until a Password Depot app applies the bundle, its shape can still gain members. Ignore members you do not know, and treat a member that is absent as not set. For a setting absent from `people`, that means its product default applies, not that nothing restricts it (see [Settings](#settings)).

---

## Get Own Policy Bundle

```
GET /v2.0/me/policy
```

Returns the bundle of the account the request is made for, issued for this request's session. Any authenticated session may read it -- client or admin scope, long-lived API tokens included --, and always for its own account only; there is no route that reads another user's bundle. It is answered on a mirror server too.

### Response

`200 OK`, with `Content-Type: application/json` and `Cache-Control: no-store`, and without an `ETag`: each answer is a new issue, with its own `issued` and `not_after`. The body is the [bundle](#the-bundle).

```json
{
    "type": "pd-policy-bundle",
    "v": 1,
    "server": "srv:e1aa5c3f90b24d7c8a1e6f0b3d2c9a47",
    "incarnation": "AQIDBAUGBwgJCgsMDQ4PEA",
    "serial": 48211,
    "user": "u:3D52A0C4-1B6E-4F7A-9C2D-5E8F10B2A7C1",
    "session": {"platform": "android", "declared": true, "client": "20.0.3"},
    "issued": 1790726400000,
    "not_after": 1791331200000,
    "people": {
        "client.clipboard.clear_after": {
            "v": 30, "merge": "min", "locked": false,
            "src": {"scope": "groups", "ids": ["g:51D0E2F3-6A7B-4C8D-9E0F-1A2B3C4D5E6F", "g:8C3B1A20-4D5E-4F60-8172-93A4B5C6D7E8"], "names": ["Finance", "Payroll"]},
            "by": "client", "on_unknown": "ignore"
        },
        "client.lock.idle_timeout": {
            "v": 300, "merge": "min", "locked": true,
            "src": {"scope": "user"},
            "by": "client", "on_unknown": "ignore",
            "bound": 600,
            "lock": {"scope": "group", "id": "g:51D0E2F3-6A7B-4C8D-9E0F-1A2B3C4D5E6F", "name": "Finance"}
        },
        "offline.max_age": {
            "v": 604800, "merge": "min", "locked": true,
            "src": {"scope": "server"},
            "by": "client", "on_unknown": "ignore"
        },
        "usage.clipboard.allowed": {
            "v": true, "merge": "and", "locked": false,
            "src": {"scope": "server"},
            "by": "client", "on_unknown": "ignore"
        }
    },
    "critical": []
}
```

The example is indented for reading. The server writes the bundle compactly, without white space, in the order shown, with the settings in ascending order of their ids; the `policy` member of a sign-in answer is written the same way. Each answer is an issue of its own, with its own `issued`, `not_after` and `session`, so do not expect two answers to carry the same bytes. Parse it as JSON and do not depend on the order. A client that keeps a copy keeps the body of `GET /me/policy` as it came.

### Error Responses

| Status | Description |
|--------|-------------|
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | As for every authenticated request, for example a client platform the server's **Allowed client platforms** policy does not allow (`4036` for Android) or a version below its **Minimum client version** policy (`4037`); see [Authentication](authentication.md#error-responses) |
| `404 Not Found` | A further path segment after `policy` |
| `405 Method Not Allowed` | Any method but `GET`, with `Allow: GET` |
| `500 Internal Server Error` | The server issues bundles but cannot issue this one at that moment -- a mirror server before its main server's configuration and policies have arrived is one such case; the message is the generic one with a reference, and the server log names the reason. It never means that no policy applies; see [When to Fetch It](#when-to-fetch-it) |

### Example

=== "curl"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/me/policy" \
        -H "Authorization: Bearer <token>"
    ```

=== "PowerShell"

    ```powershell
    $bundle = Invoke-RestMethod -Uri "https://<server>:8714/v2.0/me/policy" -Headers @{ Authorization = "Bearer $token" }
    Write-Host "Policy serial: $($bundle.serial)"
    ```

=== "Python"

    ```python
    bundle = requests.get(
        f"{BASE}/me/policy",
        headers={"Authorization": f"Bearer {token}"},
        verify=False,
    ).json()
    print(f"Policy serial: {bundle['serial']}")
    ```

---

## In the Sign-In Answer

A successful sign-in with the client scope -- `POST /auth/login` with every `auth` method, and `POST /auth/webauthn/complete` -- carries the bundle of the signed-in user for the session it opens, as the member `policy`, after the members described under [Success Response](authentication.md#success-response):

```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "policy": {"type":"pd-policy-bundle","v":1,"server":"srv:e1aa5c3f90b24d7c8a1e6f0b3d2c9a47","incarnation":"AQIDBAUGBwgJCgsMDQ4PEA","serial":48211,"user":"u:3D52A0C4-1B6E-4F7A-9C2D-5E8F10B2A7C1","session":{"platform":"web","declared":true,"client":"2.0.1"},"issued":1790726400000,"not_after":1791331200000,"people":{},"critical":[]}
}
```

- A sign-in with the admin scope never carries `policy`; such a session reads its account's bundle with `GET /me/policy`.
- Where the server cannot issue the bundle at that moment -- a mirror server before its main server's configuration and policies have arrived is one such case --, the sign-in still succeeds and its answer comes without `policy`; `GET /me/policy` then answers `500` for as long as it cannot.
- The answers that issue no token -- `401`, `403`, `429`, `459`, `460` and the others -- never carry it.

---

## The Bundle

| Member | Type | Description |
|--------|------|-------------|
| `type` | string | Always `pd-policy-bundle` |
| `v` | integer | The version of the bundle's shape: `1` |
| `server` | string | The server's id, `srv:` followed by 32 lower-case hexadecimal digits. It never changes for a server, and a mirror server names its main server's. Always present: where the server has no id, it issues no bundle (see [In the Sign-In Answer](#in-the-sign-in-answer)) |
| `incarnation` | string | The id of the server's policy store whose changes `serial` counts, 22 characters of base64url. A mirror server names its main server's. Always present: where the store has none, the server issues no bundle |
| `serial` | integer | The count of policy changes, as the server's policy store holds it: it moves with every change of a policy and with every change of the users and groups that can alter what applies to a user -- a membership added or removed, a user or a group disabled, enabled or deleted. Compare it, and `incarnation`, only for equality, never as a time or as a number of changes for this user: a pair that differs from your copy's means that something changed on the server since, not necessarily for this user. An equal pair does not promise an equal bundle -- a group's new name, for one, reaches `src` without moving `serial` --, so apply the newest bundle you hold as a whole (see [When to Fetch It](#when-to-fetch-it)) |
| `user` | string | `u:` followed by the user's id |
| `session` | object | The session the bundle was issued for; see [Session](#session) |
| `issued` | integer | When the server issued the bundle, in milliseconds since 1970-01-01 UTC |
| `not_after` | integer | Until when the bundle may be relied on, in milliseconds since 1970-01-01 UTC: `issued` plus the user's **Offline copies: access limit** policy (`offline.max_age`), seven days where nothing sets it |
| `people` | object | The settings, by setting id; see [Settings](#settings) |
| `critical` | array of strings | The ids of the settings a client that does not know them must not ignore when they are enforced. Always `[]` on this server version |

A member that is absent is not set; for a setting absent from `people`, see [Settings](#settings). The bundle carries no signature: take it from the server over HTTPS only, as every answer.

### Session

| Member | Type | Description |
|--------|------|-------------|
| `platform` | string | The platform the session counts as: `web`, `android`, `ios`, `macos`, `linux`, `windows` or `windows-corp`; `web` where nothing named a platform (see [Client Identity](authentication.md#client-identity-and-supported-clients)) |
| `declared` | boolean | `true` where the client named its platform: for a session token, at its sign-in, in `X-PD-Client` or the `client` object; for a long-lived API token, in the `X-PD-Client` of this request. `false` where the platform is the `web` given to a client that names none |
| `client` | string | The numeric core of the client version the session declared: the one to four dot-separated integers it declared, each without a leading zero, and no pre-release or build suffix (`20.0.3-beta.1+7` is `20.0.3`). Absent where the declared version does not read as a version under the **Minimum client version** policy (see [Minimum Client Version](authentication.md#minimum-client-version)), and where `declared` is `false` |

### Settings

`people` holds the people-side settings an app applies -- those the [registry](policies.md#get-policy-registry) lists as `live`, with `people` among their `sides` and with `enforced_by` `client` or `server+client` -- and the account password rules (`account.password.*`), so that an app can check a new password before it sends it. Settings that only the server applies, such as the sign-in methods, the network addresses or the session rules, are never in the bundle. Nor are the settings of databases and folders (`sides` `data` alone), even those an app applies and those set at the server's level: `secret.password.min_length` and the `history.*` settings, for example, are never in `people`, whatever sets them.

Of those, `people` holds only the settings that something sets for the user: the server, one of the user's groups or the user. A setting of that set that nothing sets is absent: no policy sets it for the user, and it resolves to its product default, which the bundle does not carry -- for the master-password rules, for one, at least 8 characters from 3 character groups (see [Settings Clients Follow](policies.md#settings-clients-follow)). An absent setting does not mean that nothing restricts it. Every setting present carries its value:

| Member | Type | Description |
|--------|------|-------------|
| `v` | value | The value that applies to the user, in the form of the setting's type (see [Values](policies.md#values)) |
| `merge` | string | How the values of several groups combine: `and`, `or`, `min`, `max`, `intersection`, `union`, `strict` or `priority` |
| `locked` | boolean | `true` where a level enforces the setting for the user -- the server, a group, or the user's own entry --; `false` where the value is a default |
| `src` | object | Where the value comes from; see [Sources](#sources) |
| `by` | string | Who acts on the setting by its kind: `client`, `server+client`, or `server` for the account password rules. It does not say whether this server itself enforces the setting; that is `applied` in the [registry](policies.md#get-policy-registry) |
| `on_unknown` | string | What a client that does not know the setting does when it is enforced; `ignore` |
| `bound` | value | Only where the setting is locked and a default below the lock made the value stricter: the enforced value |
| `lock` | object | With `bound`: where the enforced value comes from, in the form of `src` |

A value that is enforced and that no default below it tightened carries neither `bound` nor `lock`: its `src` is the level that enforces it.

### Sources

| `src` | Meaning |
|-------|---------|
| `{"scope": "server"}` | The server's policies |
| `{"scope": "group", "id": "g:<group id>", "name": "<group name>"}` | One of the user's groups |
| `{"scope": "groups", "ids": ["g:<group id>", ...], "names": ["<group name>", ...]}` | Several of the user's groups together; `names` in the order of `ids`, ascending by id |
| `{"scope": "user"}` | The user's own policies |

Where the groups decide, `src` names the groups that decided the value: under `and`, `or`, `min`, `max` and `strict` the groups whose entry is the value -- under `and` a `false` names the groups that said `false` and a `true` every group, under `or` the reverse, and under `min`, `max` and `strict` the group whose entry is the value, or each of them where several set that same value; under `intersection`, `union` and `priority` every group whose entry was combined. A `lock` names the groups that enforce. Only groups the user belongs to are named.

---

## When to Fetch It

The server does not tell a session that its policies changed. A client that uses the bundle takes the one in the sign-in answer, fetches `GET /me/policy` when it resumes a session, and fetches it again before `not_after`. A copy past its `not_after` no longer describes the server's policies. Every bundle is complete: the newest one you hold replaces every older one as a whole, whatever its `serial`.

To tell whether a server issues the bundle, test for the feature by the answer:

- the `policy` member in a client-scope sign-in answer, or `GET /me/policy` answering `200` with a body whose `type` is `pd-policy-bundle`: the server issues the bundle;
- `GET /me/policy` answering `404`: the server issues no bundle;
- `GET /me/policy` answering `500`: the server issues bundles but could not issue this one. Ask again later and keep the last bundle you hold while it is within its `not_after`. Never take a `500`, or a sign-in answer without `policy`, for "no policy applies".
