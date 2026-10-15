# Policies

*Server 20.0.0 and later.*

The server's policies are the settings the Server Manager shows on its *Policies* page and on the *Policies* tabs of Group Properties and User Properties: the sign-in methods, the second factor, the inactivity period, the network addresses, the account password rules, the API token rules and the others. The endpoints on this page read and change them in an **admin-scoped session** (`"scope": "admin"` at login), under the same rules as the Server Manager: whoever may change a setting there may change it here, a change is checked and recorded in the audit trail the same way, and a change made here shows in the Server Manager and the other way round.

| Method | Path | Description |
|--------|------|-------------|
| `GET` | [`/v2.0/admin/server/policy`](#get-server-policy) | The server's policy document, optionally with the effective values |
| `PATCH` | [`/v2.0/admin/server/policy`](#update-server-policy) | Change settings of the server's policy document |
| `GET` | [`/v2.0/admin/groups/{id}/policy`](#get-group-policy) | A group's policy document, optionally with the effective values |
| `PATCH` | [`/v2.0/admin/groups/{id}/policy`](#update-group-policy) | Change settings of a group's policy document |
| `GET` | [`/v2.0/admin/users/{id}/policy`](#get-user-policy) | A user's policy document, optionally with the effective values |
| `PATCH` | [`/v2.0/admin/users/{id}/policy`](#update-user-policy) | Change settings of a user's policy document |
| `GET` | [`/v2.0/admin/policy-registry`](#get-policy-registry) | Every setting this server knows, with its type, range, scopes and default |
| `GET` | [`/v2.0/admin/policy-conflicts`](#get-policy-conflicts) | The settings on which a user's groups set different values |

Any other method on these paths answers `405` with an `Allow` header (`GET, PATCH` on the policy documents, `GET` on the registry and the conflicts), and a further path segment answers `404`. Long-lived API tokens issued with the admin scope reach these endpoints under the same rules as the account they belong to.

---

## Policy Documents

The server keeps one policy document for the server and one for each group and each user that sets anything. A document declares settings; every setting it does not declare is **not set** at that level. Each declaration has a state and a value:

| State | Meaning |
|-------|---------|
| `default` | The value applies at this level and below, unless a lower level sets its own |
| `enforced` | The value applies at this level and below; a lower level can only make it stricter, never looser |
| `not_set` | Used in a change only: removes the level's declaration of the setting |

The value that applies to a user is resolved from the server's document, the documents of the user's groups and the user's own document, as the Server Manager's *Effective policy...* shows it. Which settings exist, what type each value has and at which levels each can be set is listed by the [registry](#get-policy-registry).

### Document Object

```json
{
    "scope": {"type": "server"},
    "revision": 17,
    "set": {
        "auth.second_factor.required": {"state": "enforced", "value": true},
        "session.idle_timeout": {"state": "default", "value": 1800}
    },
    "opaque": []
}
```

| Field | Type | Description |
|-------|------|-------------|
| `scope` | object | The level: `{"type": "server"}`, `{"type": "group", "id": "<group id>"}` or `{"type": "user", "id": "<user id>"}` |
| `revision` | integer | The document's revision; `0` while the level declares nothing |
| `set` | object | The declarations this server can read, by setting id, ascending: each `{"state": "default" or "enforced", "value": <value>}` |
| `opaque` | array of strings | Ids of declarations this server cannot read (a setting it does not know, or a value of a form it does not know). They are kept as they are and can only be removed (`not_set`) |

The document shows only what the caller may change (see [Who May Read and Change](#who-may-read-and-change)); server administrators and security officers see the whole server document.

### Values

A value has the JSON form of the setting's `type` in the registry:

| `type` | JSON value |
|--------|------------|
| `boolean` | `true` or `false` |
| `integer` | integer |
| `duration` | integer, seconds |
| `size` | integer, bytes |
| `date` | integer, milliseconds since 1970-01-01 UTC |
| `word` | string, one word of the setting's list |
| `text` | string |
| `version` | string of one to four numbers separated by dots, such as `"20.1.3"` |
| `set` | array of words of the setting's list, each once, in ascending order of their UTF-8 bytes; `[]` is the empty set, a value of its own |
| `address_list` | array of strings: IPv4 and IPv6 addresses, prefixes such as `10.0.0.0/8` and ranges such as `192.168.1.10-192.168.1.50`, in any order; the server stores them in its own order |
| `principal_list` | array of strings, each `"u:<user id>"` or `"g:<group id>"`, each once, in ascending order |

A number row has a range (`range_min`, `range_max`); where the row also has `unlimited`, that number means "no limit". Settings of the other types in the registry cannot be set through these endpoints (`setting_not_writable`).

---

## Who May Read and Change

| Role | May change | May read |
|------|------------|----------|
| `server_admin`, `super_admin` | Every setting, at every level | Every document |
| `security_officer` | The `auth.*`, `session.*` and `account.*` settings, at every level | The whole server document; elsewhere what it may change |
| `user_admin`, `group_admin` | Every setting of the groups and users they administer; never the server document | What they may change |

- A user's document can only be changed by a caller who holds every server role the user holds. The caller's own roles decide as well, as above.
- A document can be read by whoever may change at least one of its settings, and then shows only those settings -- except the server document, which server administrators and security officers read whole.
- A long-lived API token with the admin scope reads and changes policies under these same rules, those of its account; its changes are recorded in the audit trail like any other.
- A group or a user that does not exist, that the caller does not administer, or whose policies the caller may neither read nor change answers `404`, exactly like a group or user id that does not exist on [`GET /admin/groups/{id}`](groups.md#get-group-admin) and [`GET /admin/users/{id}`](users.md#get-user-admin). The server document answers `403` to a caller who may read none of it.

---

## Revisions, `ETag` and `If-Match`

Every read and every successful change carries the document's revision, in the body (`revision`) and in a strong `ETag` header: the decimal revision in quotes, such as `ETag: "17"`. A change must name the revision it was made against in `If-Match`, exactly as the `ETag` gave it:

```
If-Match: "17"
```

- If the document has changed since, nothing is changed and the answer is `412 Precondition Failed`, with the current document in `error.policy` and its `ETag`. Look at the current values and decide again; never resend the same change blindly.
- The caller's rights and the settings and values of a change are checked first: a change refused for them answers that refusal, whatever revision it names.
- A change without `If-Match`, or with `If-Match: *`, answers `428 Precondition Required`. A weak tag (`W/"17"`), a list of tags, or anything other than one quoted revision answers `400`.
- If the answer to a change is lost, read the document again: its revision and values tell whether the change was made.

Compare revisions only for equality. `If-Match` is allowed in CORS preflight requests and `ETag` is exposed to browser scripts.

---

## Get Server Policy

```
GET /v2.0/admin/server/policy
```

Returns the server's policy document.

### Query Parameters

| Parameter | Type | Required | Description |
|-----------|------|:--------:|-------------|
| `view` | string | No | `effective`: also return the [effective values](#effective-view). Any other value answers `400` |

### Response

`200 OK`, with `ETag: "<revision>"`. The body is the [reply object](#reply-object):

```json
{
    "outcome": "read",
    "revision": 17,
    "document": {
        "scope": {"type": "server"},
        "revision": 17,
        "set": {
            "auth.second_factor.required": {"state": "enforced", "value": true},
            "session.idle_timeout": {"state": "default", "value": 1800}
        },
        "opaque": []
    },
    "errors": []
}
```

### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | `view` is not `effective` |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Not an admin-scoped session, or the caller may read no part of the server document |

### Example

=== "curl"

    ```bash
    curl -i -X GET "https://<server>:8714/v2.0/admin/server/policy?view=effective" \
        -H "Authorization: Bearer <token>"
    ```

---

## Update Server Policy

```
PATCH /v2.0/admin/server/policy
```

Changes settings of the server's policy document. Settings the body does not name stay as they are. The change applies all or nothing: if one setting is refused, nothing is changed.

### Request Headers

| Header | Required | Description |
|--------|:--------:|-------------|
| `If-Match` | Yes | The revision the change was made against, as the `ETag` of a read gave it, such as `"17"` |

### Request Body

The body is a JSON object with exactly one member, `set`, which names at least one setting:

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `set` | object | Yes | By setting id, the change of that setting: `{"state": "default" or "enforced", "value": <value>}` to declare it, or `{"state": "not_set"}` to remove the level's declaration |

```json
{
    "set": {
        "session.idle_timeout": {"state": "enforced", "value": 3600},
        "auth.second_factor.required": {"state": "not_set"}
    }
}
```

The body is ordinary JSON: white space and every standard escape are accepted, and the settings may come in any order. A number must be an integer within plus or minus 2^53 (`1e3` reads as `1000`, `1.5` is refused). A member name given twice in one object, any member besides `set`, a change with a member besides `state` and `value`, a `set` value whose words are not each once in ascending order, and a body above 64 KiB are refused. The value of each setting is checked against the registry: its type, its range, its words and the levels at which it can be set.

Some changes are refused for what they would cause, as in the Server Manager:

- a change that would leave no server administrator able to sign in to the Server Manager (`lockout`);
- a change that would need an approval nobody can give (`approval_unreachable`);
- a minimum age of an account password above its maximum age at the same level (`invalid_relation`).

### Response

`200 OK`, with the `ETag` of the document's new revision. The [reply object](#reply-object) carries the outcome `saved` and the document as it now is, or `unchanged` when the change names only what the document already holds -- then nothing is saved and the revision stays:

```json
{
    "outcome": "saved",
    "revision": 18,
    "document": {
        "scope": {"type": "server"},
        "revision": 18,
        "set": {
            "session.idle_timeout": {"state": "enforced", "value": 3600}
        },
        "opaque": []
    },
    "errors": []
}
```

A saved change is recorded in the audit trail, with the values before and after, and raises the alert `server_policy_modified` (see [Alerts](alerts.md#alert-types)), as a change made in the Server Manager does.

### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | The body, `If-Match` or a value is refused; `error.policy.errors` names each setting and why |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Not an admin-scoped session; the caller may not change a setting it names; the change would leave no administrator able to sign in, or would need an approval nobody can give; or the server is a mirror |
| `409 Conflict` | The change would make the stored policies larger than the server holds |
| `412 Precondition Failed` | The document changed since the revision in `If-Match`; `error.policy` carries the current document and the response its `ETag` |
| `413 Payload Too Large` | The body is larger than 64 KiB |
| `428 Precondition Required` | No `If-Match`, or `If-Match: *` |
| `500 Internal Server Error` | The change could not be saved; nothing was changed |
| `503 Service Unavailable` | Nothing was changed, and the same request may succeed later: the audit trail cannot record the change at the moment, or a directory synchronisation (Active Directory or Azure AD) is running and the users and groups the change needs cannot be looked up |

See [Errors](#errors) for the body of these answers.

### Example

=== "curl"

    ```bash
    curl -i -X PATCH "https://<server>:8714/v2.0/admin/server/policy" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -H 'If-Match: "17"' \
        -d '{"set": {"session.idle_timeout": {"state": "enforced", "value": 3600}}}'
    ```

---

## Get Group Policy

```
GET /v2.0/admin/groups/{id}/policy
```

Returns a group's policy document, as [Get Server Policy](#get-server-policy) does for the server: the same query parameter, the same response with `"scope": {"type": "group", "id": "<group id>"}`.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|:--------:|-------------|
| `id` | string (UUID) | Yes | Group unique identifier |

### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | `view` is not `effective` |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Not an admin-scoped session |
| `404 Not Found` | No such group, or not one whose policies the caller may read: "The server cannot find the group specified." |

### Example

=== "curl"

    ```bash
    curl -i -X GET "https://<server>:8714/v2.0/admin/groups/FEAE7AC9-58D1-4A76-82A6-2C7DB135CFDD/policy" \
        -H "Authorization: Bearer <token>"
    ```

---

## Update Group Policy

```
PATCH /v2.0/admin/groups/{id}/policy
```

Changes settings of a group's policy document, as [Update Server Policy](#update-server-policy) does for the server: the same headers, body, response and error responses, with these differences:

- a group that does not exist, or one the caller may not change any setting of, answers `404` "The server cannot find the group specified.", as on [Get Group Policy](#get-group-policy);
- a saved change is recorded in the audit trail and raises no alert.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|:--------:|-------------|
| `id` | string (UUID) | Yes | Group unique identifier |

### Example

=== "curl"

    ```bash
    curl -i -X PATCH "https://<server>:8714/v2.0/admin/groups/FEAE7AC9-58D1-4A76-82A6-2C7DB135CFDD/policy" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -H 'If-Match: "0"' \
        -d '{"set": {"auth.second_factor.preferred": {"state": "default", "value": "email"}}}'
    ```

---

## Get User Policy

```
GET /v2.0/admin/users/{id}/policy
```

Returns a user's policy document, as [Get Server Policy](#get-server-policy) does for the server, with `"scope": {"type": "user", "id": "<user id>"}`. With `view=effective` the effective values are the ones that apply to this user, each with its [trail](#effective-view).

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|:--------:|-------------|
| `id` | string (UUID) | Yes | User unique identifier |

### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | `view` is not `effective` |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Not an admin-scoped session |
| `404 Not Found` | No such user, or not one whose policies the caller may read -- also a user who holds a server role the caller does not hold: "The server cannot find the user account specified." |

---

## Update User Policy

```
PATCH /v2.0/admin/users/{id}/policy
```

Changes settings of a user's policy document, as [Update Server Policy](#update-server-policy) does for the server, with these differences:

- a user that does not exist, or one the caller may not change any setting of -- also one who holds a server role the caller does not hold --, answers `404` "The server cannot find the user account specified.", as on [Get User Policy](#get-user-policy);
- a saved change is recorded in the audit trail and raises no alert.

The user representation's `two_factor_mode` (see [Users](users.md#two_factor_mode-values)) reads and writes two of the user's own entries in this document, **Require a second factor** (`auth.second_factor.required`) and **Preferred second factor** (`auth.second_factor.preferred`); this route shows and changes them like every other setting.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|:--------:|-------------|
| `id` | string (UUID) | Yes | User unique identifier |

---

## Effective View

With `view=effective`, a read also returns `effective`: for each setting that can be set at the level and that the caller may change there (every one at the server level, for server administrators and security officers), what applies at that level and why.

```json
"effective": {
    "session.idle_timeout": {
        "state": "enforced",
        "value": 1800,
        "source": {"type": "user", "id": "3D1C91F6-754D-427E-9D76-8CC20E8C326E"},
        "locked": true,
        "applied": true,
        "lock_source": {"type": "server"},
        "bound": 3600,
        "trail": [
            {"source": {"type": "product"}, "state": "default", "value": 3600, "decision": "product_default"},
            {"source": {"type": "server"}, "state": "enforced", "value": 3600, "decision": "applied"},
            {"source": {"type": "groups"}, "state": "not_set", "decision": "not_set"},
            {"source": {"type": "user", "id": "3D1C91F6-754D-427E-9D76-8CC20E8C326E"}, "state": "default", "value": 1800, "decision": "within_bound"}
        ]
    }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `state` | string | The state at the level read |
| `value` | value | The value that applies; absent where nothing restricts (no product default and nothing set) |
| `source` | object | Where the value comes from: a scope, `{"type": "product"}` (the product default) or `{"type": "groups"}` (the user's groups together) |
| `locked` | boolean | A level above enforces the setting |
| `applied` | boolean | Whether this server itself enforces the setting; `false` means the server stores the setting but does not act on it -- a client may still follow it (see [Settings Clients Follow](#settings-clients-follow)) |
| `lock_source` | object | With `locked`: the level that enforces it |
| `bound` | value | With `locked`: the enforced value, where the value that applies is stricter than it |
| `trail` | array | User level only: each level's entry in order -- `source`, `state`, `value` where it has one, and `decision`: `product_default`, `applied`, `within_bound` (below an enforced value, stricter, taken), `limited` (below an enforced value, combined with it), `ignored` (below an enforced value, not stricter), `not_set`, `invalid`, `unknown_word`, `merged` (a group's entry taken into the groups' value), `conflict` (the user's groups disagree) |

A setting this server cannot resolve has `state`, `locked` (always `false`) and `applied` only. At the server level the reply also carries `also_set_at`: by setting id, the groups and users that declare it too, each `{"scope": ..., "state": ..., "value": ...}`.

A reply the server would have to make too large comes without `also_set_at` and the trails, or without `effective`, and with an error of the code `too_large` in `errors` that says so; the status is still `200`.

---

## Settings Clients Follow

`applied` says whether the server itself enforces a setting. A setting with `applied` `false` can still be followed by a client: Password Depot for Windows (Corporate Edition) receives, at each connection, the client security policies the server builds for its user from the policies that apply to that user -- the server's, the user's groups' and the user's own values -- and follows these settings:

- the storage locations, the file tools and the installation on a USB drive: `client.storage.allowed`, `client.file_tools.allowed`, `client.portable_install.allowed`;
- printing, the export channels, the clipboard, revealing one-time-code secrets, assigning second passwords and offline copies: `usage.print.allowed`, `usage.export.channels`, `usage.clipboard.allowed`, `usage.totp_secret.reveal`, `secret.compartment.assign.allowed`, `offline.allowed`;
- the master-password rules of its databases: `database.master_password.min_length`, `database.master_password.min_classes`, `database.master_password.history`, `database.master_password.min_age`;
- the lock and clipboard options and the program options: `client.lock.*`, `client.clipboard.clear_after`, `client.view.password_column`, `client.startup.*`, `client.backup.*`, `client.remote.delete_local_copy`, `client.update.*`, `client.network.ip_version`, `client.sign_in.*` -- these only where the value that applies is `enforced`; otherwise the user's own choice stays.

The client follows them where one of them is set for the user at any level -- the server, one of the user's groups or the user --, or where the server's client security policies were active when it was upgraded to Server 20.0.0. A permission, storage location, file tool, export channel or master-password rule of the list that is not set then gives its product default -- for the master-password rules at least 8 characters from 3 character groups, a history of 12 and a minimum age of one day --, while a lock, clipboard or program option that is not `enforced` leaves the user's own choice. Other Password Depot apps do not read these settings from the server.

---

## Get Policy Registry

```
GET /v2.0/admin/policy-registry
```

Returns every policy setting this server knows, in the order of the setting ids. Readable in every admin-scoped session; on a mirror too.

### Response

`200 OK`

```json
{
    "level": 1,
    "settings": [
        {
            "id": "session.idle_timeout",
            "type": "duration",
            "range_min": 600,
            "range_max": 600000,
            "unlimited": 9007199254740992,
            "sides": ["people"],
            "scopes": ["server", "group", "user"],
            "sources": [],
            "merge": "min",
            "stricter": "lower",
            "enforced_by": "server",
            "declared": false,
            "critical": false,
            "on_unknown": "ignore",
            "exempt_roles": [],
            "default": "3600",
            "category": "sign_in",
            "since": 1,
            "status": "live",
            "applied": true
        }
    ]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `level` | integer | The registry level of this server; a later server can know more settings and words |
| `settings[].id` | string | The setting id, the name used in a document's `set` |
| `type` | string | The value type (see [Values](#values)) |
| `range_min`, `range_max` | integer | The bounds of a number, or of the members of a list, where the setting has them |
| `unlimited` | integer | Where present, the number that means "no limit" |
| `sides` | array | `people` (servers, groups, users) and/or `data` (databases and folders) |
| `scopes` | array | The levels at which the setting can be set |
| `sources` | array | Origins of values that are not levels, where the setting has any |
| `merge` | string | How several entries of one level combine: `and`, `or`, `min`, `max`, `intersection`, `union`, `strict`, `priority` |
| `stricter` | string | The direction in which a lower level may tighten an enforced value: `lower`, `higher`, `false`, `true`, `subset`, `superset`; absent where it has none |
| `enforced_by` | string | Who acts on the setting: `server`, `client`, `server+client`, `crypto` |
| `condition` | string | Where present, the condition under which the setting is enforced |
| `declared` | boolean | The server checks the setting against what the client declares about itself |
| `critical`, `on_unknown` | boolean, string | What a client that does not know the setting must do when it is enforced |
| `exempt_roles` | array | Roles the setting does not bind |
| `default` | string | The product default as the registry writes it: a number or a word as it is, a set as its words separated by commas, a text as a JSON string, and where the data side and the people side start from different values, one value per side as `data:<value>,people:<value>` (for example `data:false,people:true`); absent where there is none |
| `category` | string | The group the Server Manager shows the setting under |
| `since`, `retired` | integer | The registry level that added the setting, and where present the level that retired it |
| `status`, `migrate_to` | string | `live` or another status, and where present the setting that replaces it |
| `applied` | boolean | Whether this server itself enforces the setting (see [Settings Clients Follow](#settings-clients-follow)) |

Members a row does not have are left out, and a later server can add members: ignore the ones you do not know. The registry carries ids and words, no labels: the names in bold on these pages are the Server Manager's.

### Error Responses

| Status | Description |
|--------|-------------|
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Not an admin-scoped session |

---

## Get Policy Conflicts

```
GET /v2.0/admin/policy-conflicts
```

Returns the settings that take a single value and on which some user's groups set different values. For such a user none of the group values applies: the server's value applies, or the product default, unless the user has a value of their own; an enforced server value applies in any case. The Server Manager's dashboard shows the same as a notice.

Readable by server administrators and security officers. Not paginated: each conflicting setting is listed once, in the order of the setting ids, with every group that takes part.

### Response

`200 OK`

```json
{
    "judged": true,
    "conflicts": [
        {
            "setting": "auth.second_factor.preferred",
            "groups": [
                "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
                "FEAE7AC9-58D1-4A76-82A6-2C7DB135CFDD"
            ],
            "users": 4
        }
    ]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `judged` | boolean | `false` where the server could not judge now -- on a mirror, or while a directory synchronisation (Active Directory or Azure AD) is running; `conflicts` is then empty. Ask again later |
| `conflicts[].setting` | string | The setting id |
| `conflicts[].groups` | array of strings | The groups whose values disagree for at least one user |
| `conflicts[].users` | integer | How many users the disagreement affects |

### Error Responses

| Status | Description |
|--------|-------------|
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Not an admin-scoped session, or the caller may not read the server's policies |

---

## Reply Object

Every answer of the document routes that the policies decide carries one reply object: the body of a `200`, and `error.policy` of the others (see [Errors](#errors)). A `404` and the answers given before the policies are asked carry none. The server writes it compact; the examples on this page are indented for reading.

| Field | Type | Description |
|-------|------|-------------|
| `outcome` | string | `read`, `saved`, `unchanged`, `stale` (the revision in `If-Match` is not the current one), `refused` or `failed` |
| `revision` | integer | The document's revision: the current one, or after a saved change the new one. In a `refused` reply it is `0` and names no revision; read the document again for its `ETag` |
| `document` | object | The [document](#document-object), where the reply carries one: after a read, a change and a `stale` refusal |
| `errors` | array | Each `{"setting": <id, or "" for the request as a whole>, "code": <word>, "message": <text>}`; empty where there is nothing to report |
| `effective`, `also_set_at` | object | With `view=effective` (see [Effective View](#effective-view)) |

### Error Codes

`errors[].code` gives the reason; the status follows from it.

| `code` | Status | Meaning |
|--------|:------:|---------|
| `invalid_request` | `400` | The request itself: the body, `If-Match`, the query parameter `view`. With `428` and `413` as well, for a missing `If-Match` and a body above 64 KiB |
| `setting_not_writable` | `400` | The setting cannot be set by this server (not complete, retired, or of a type it cannot check) |
| `not_applicable` | `400` | The setting cannot be set at this level |
| `invalid_value` | `400` | The value does not fit the setting: its type, range or words, or a principal list that names a user or group that does not exist |
| `remove_only` | `400` | The setting is unknown to this server, or its stored declaration cannot be read; it can only be removed |
| `invalid_relation` | `400` | The minimum age of an account password would be above its maximum age at the same level |
| `forbidden` | `403` | The caller may not change this setting at this level; for the request as a whole (`"setting": ""`), may not read or change this document -- `404` for a group or a user |
| `lockout` | `403` | No server administrator could sign in to the Server Manager after the change |
| `approval_unreachable` | `403` | The change would leave an approval that nobody can give |
| `too_large` | `409` | The stored policies would be larger than the server holds. In a `200` read: the effective view was shortened |
| `directory_busy` | `503` | A directory synchronisation is running; try again when it has finished |
| `audit_unavailable` | `503` | The audit trail cannot record the change; nothing was saved |
| `save_failed` | `500` | The change could not be saved; nothing was changed |

A refusal names every error at once. When its errors have different statuses, the answer is `403` if any is, else `400`, else the others in the order `409`, `503`, `500`. Treat a code you do not know by its status.

---

## Errors

The answers the policies decide -- `400`, a `403` for a policy refusal, `409`, `412`, `413` for a body above 64 KiB, `428`, `500` for `save_failed` and `503` -- use the standard [error envelope](overview.md#error-format), with the reply object under `error.policy`:

```json
{
    "error": {
        "code": 400,
        "message": "The value must be at least 600.",
        "policy": {
            "outcome": "refused",
            "revision": 0,
            "errors": [
                {"setting": "session.idle_timeout", "code": "invalid_value", "message": "The value must be at least 600."}
            ]
        }
    }
}
```

- `error.code` is the HTTP status; these endpoints use no sub-code. `error.message` is the message of the first error.
- `412 Precondition Failed` carries the current document in `error.policy.document` and its revision in the `ETag` header.
- These answers use the standard error envelope without `error.policy`: `401`; the `403` for a session without the admin scope, and a mirror server's `403` for a `PATCH`; `404`, whose body is the one the group and user routes answer for an id that does not exist; `405`; `411`; the `413` for a request above the server's general size limit (see [HTTP status codes](overview.md#http-status-codes)); and a `500` when the server could not produce a reply. Branch on the HTTP status, and read `error.policy` only where it is present.
- The messages in `error.policy` are in English; match `code`, never the message.
- A mirror server answers every `PATCH` that carries a bearer token with `403` before the token is examined, as it does for every write (see [Mirror servers are read-only](overview.md#http-status-codes)).

!!! note "What is recorded"
    Every saved change is recorded in the audit trail as a policy change, with the values before and after, the account that made it -- for a long-lived API token, the token's account -- and the REST API as the channel. So is every change the server examines and refuses -- for its body, a body that could not be read included, its `If-Match`, its settings and values, or the caller's rights, a group or user that does not exist included -- and a change that could not be saved. A request refused before its policy is examined -- without a valid admin-scoped session, by a mirror server, or for a method the path does not take -- is not recorded as a policy change; neither is a change answered `412`, one that changes nothing, or a read.
