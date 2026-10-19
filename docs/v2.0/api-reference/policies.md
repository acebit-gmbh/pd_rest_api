# Policies

*Server 20.0.0 and later.*

The server's policies are the settings the Server Manager shows on its *Policies* page and on the *Policies* tabs of Group Properties and User Properties: the sign-in methods, the second factor, the inactivity period, the network addresses, the account password rules, the API token rules and the others. The endpoints on this page read and change them, and show what a change would do before it is made, in an **admin-scoped session** (`"scope": "admin"` at login), under the same rules as the Server Manager: whoever may change a setting there may change it here, a change is checked and recorded in the audit trail the same way, and a change made here shows in the Server Manager and the other way round.

| Method | Path | Description |
|--------|------|-------------|
| `GET` | [`/v2.0/admin/server/policy`](#get-server-policy) | The server's policy document, optionally with the effective values |
| `PATCH` | [`/v2.0/admin/server/policy`](#update-server-policy) | Change settings of the server's policy document |
| `GET` | [`/v2.0/admin/groups/{id}/policy`](#get-group-policy) | A group's policy document, optionally with the effective values |
| `PATCH` | [`/v2.0/admin/groups/{id}/policy`](#update-group-policy) | Change settings of a group's policy document |
| `GET` | [`/v2.0/admin/users/{id}/policy`](#get-user-policy) | A user's policy document, optionally with the effective values |
| `PATCH` | [`/v2.0/admin/users/{id}/policy`](#update-user-policy) | Change settings of a user's policy document |
| `POST` | [`/v2.0/admin/server/policy/preview`](#preview-a-change) | What a change of the server's policy document would do, without making it |
| `POST` | [`/v2.0/admin/groups/{id}/policy/preview`](#preview-a-change) | What a change of a group's policy document would do, without making it |
| `POST` | [`/v2.0/admin/users/{id}/policy/preview`](#preview-a-change) | What a change of a user's policy document would do, without making it |
| `GET` | [`/v2.0/admin/policy-registry`](#get-policy-registry) | Every setting this server knows, with its type, range, scopes and default |
| `GET` | [`/v2.0/admin/policy-conflicts`](#get-policy-conflicts) | The settings on which a user's groups set different values |

Any other method on these paths answers `405` with an `Allow` header (`GET, PATCH` on the policy documents, `POST` on their previews, `GET` on the registry and the conflicts). After `policy`, only `preview` is a further path segment; any other answers `404`. Long-lived API tokens issued with the admin scope reach these endpoints under the same rules as the account they belong to.

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

## Preview a Change

```
POST /v2.0/admin/server/policy/preview
POST /v2.0/admin/groups/{id}/policy/preview
POST /v2.0/admin/users/{id}/policy/preview
```

Shows what a change of the level's policy document would do, without making it: which users would get a different value, or a different lock, for which setting, and the warnings the Server Manager shows before it saves a policy -- the users who would be left without a way to sign in first. The Server Manager asks for this preview before every policy save and shows it wherever a user is affected or a warning is found.

A preview takes the request of the matching `PATCH` -- the same `If-Match` header and the same body (see [Update Server Policy](#update-server-policy)) -- and is checked as that change would be: the same rights, the same settings and values and the same refusals, each answered with the status the change would get (see [Preview Refusals](#preview-refusals)). Nothing is changed. The answer describes the policies and the users as they are at that moment; it reserves nothing, and the change itself is checked again when it is sent.

Each user's value is resolved before and after the change from the server's document, the documents of the user's groups and the user's own document, as the [effective view](#effective-view) resolves it for a user.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|:--------:|-------------|
| `id` | string (UUID) | Yes | On the group and user paths: the group's or the user's unique identifier |

### Request Headers

| Header | Required | Description |
|--------|:--------:|-------------|
| `If-Match` | Yes | The revision the change would be made against, as for the change, such as `"17"` |

### Query Parameters

| Parameter | Type | Required | Description |
|-----------|------|:--------:|-------------|
| `offset` | integer | No | The number of rows to skip; `0` by default |
| `limit` | integer | No | The most rows to return, at least `1`; `100` by default, and a value above `1000` is taken as `1000` |
| `filter` | string | No | `flagged`: the rows of the warnings instead of the rows of the changed values |
| `stamp` | string | No | From the second page on: the `stamp` of the page before (see [Pages and the Stamp](#pages-and-the-stamp)) |

`offset` and `limit` are written in digits alone. Any other value of these parameters, and one of them named twice, answers `400`. Other query parameters are not read.

### Request Body

The body of the change, read in the same way: exactly the member `set`, naming at least one setting (see [Update Server Policy](#update-server-policy)).

### Response

`200 OK`, without an `ETag` header. The body is the preview reply:

```json
{
    "outcome": "previewed",
    "revision": 4,
    "errors": [],
    "stamp": "4.57.12",
    "preview": {
        "unchanged": false,
        "settings": [
            {
                "setting": "session.idle_timeout",
                "reach": "users",
                "applied": true,
                "resolved": true,
                "source_only": 0,
                "transitions": [
                    {
                        "before": {"state": "default", "value": 3600, "source": {"type": "server"}, "locked": false},
                        "after": {"state": "enforced", "value": 900, "source": {"type": "group", "id": "FEAE7AC9-58D1-4A76-82A6-2C7DB135CFDD"}, "locked": true},
                        "users": 2
                    }
                ]
            }
        ],
        "warnings": {
            "sign_in_lost": 0,
            "methods_empty": 0,
            "network_empty": 0,
            "platforms_empty": 0,
            "second_factor_empty": 0,
            "ages_crossed_new": 0,
            "ages_crossed_already": 0,
            "conflict_created": 0,
            "conflict_removed": 0
        },
        "conflicts": [],
        "users": 2,
        "disabled": 1,
        "hidden": 0,
        "filter": "changes",
        "offset": 0,
        "limit": 100,
        "total": 2,
        "rows": [
            {"user": "3D1C91F6-754D-427E-9D76-8CC20E8C326E", "disabled": false, "setting": "session.idle_timeout", "transition": 0, "warnings": []},
            {"user": "8B0E5A21-1F3C-4D7E-9A6B-2C4D6E8F0A1B", "disabled": true, "setting": "session.idle_timeout", "transition": 0, "warnings": []}
        ]
    }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `outcome` | string | `previewed` in a `200`; `refused` or `restart` in `error.policy` (see [Preview Refusals](#preview-refusals)) |
| `revision` | integer | The document's current revision; `0` where the preview was refused before the document was read |
| `errors` | array | As in the [reply object](#reply-object): the reasons of a refusal. In a `200` empty, or one `too_large` error where the page was shortened (see [Pages and the Stamp](#pages-and-the-stamp)) |
| `stamp` | string | With `previewed` and `restart`: the state the preview describes |
| `preview` | object | With `previewed`: the summary and one page of rows |
| `preview.unchanged` | boolean | `true` where the change names only what the document already holds, so that the change would save nothing; every list is then empty and every count `0` |
| `preview.settings` | array | Each setting the change would change, in the order of the setting ids (see [Changed Settings](#changed-settings)). A setting the body names with what the document already holds -- the same state and value, or `not_set` where nothing is declared -- is left out |
| `preview.warnings` | object | By warning (see [Warnings](#warnings)), the number of its rows |
| `preview.conflicts` | array | Each setting on which the change makes the groups of some users disagree, or stop disagreeing, in the order of the setting ids: `setting`; `groups`, the groups whose values disagree -- after the change, or before it where the change ends the disagreement; `created` and `removed`, for how many users the disagreement starts and ends (see [Get Policy Conflicts](#get-policy-conflicts)) |
| `preview.users` | integer | The users the caller may read who get a different value or lock, or a warning |
| `preview.disabled` | integer | How many of `users` are disabled |
| `preview.hidden` | integer | The users the caller may not read who get a different value or lock, or a warning |
| `preview.filter` | string | `changes`, or `flagged` for `filter=flagged` |
| `preview.offset`, `preview.limit` | integer | The page as applied |
| `preview.total` | integer | The rows of the filter, on all pages together |
| `preview.rows` | array | The rows of this page (see [Rows](#rows)) |

**Users the caller may not read.** A preview names only the users whose policies the caller may read (see [Who May Read and Change](#who-may-read-and-change)). The others are counted in `hidden`, never named, and no other count, transition, warning, conflict or row includes them -- so that, for example, the built-in administrator is only counted for every other caller, and super-administrators for a caller who is not one. The preview still judges them: a change that would leave no server administrator able to sign in is refused (`lockout`). A preview that counts any of them is recorded in the audit trail (see [Preview Refusals](#preview-refusals)).

### Changed Settings

Each entry of `settings`:

| Field | Type | Description |
|-------|------|-------------|
| `setting` | string | The setting id |
| `reach` | string | `users`: the value as it applies to each user the change reaches -- the user at a user level, the members of the group and of the groups within it at a group level, every user at the server level. `databases`: a setting whose registry `sides` include `data`, changed in the server's document -- one line for every database. `server`: a setting that is set for the server as a whole -- one line. A setting of both sides changed at the server level has a `users` entry and a `databases` entry |
| `applied` | boolean | Whether this server itself enforces the setting, as in the [effective view](#effective-view) |
| `resolved` | boolean | `false` for a setting this server cannot resolve, such as a declaration it cannot read being removed; it then has no transitions |
| `source_only` | integer | The users whose value and lock stay as they are while the level the value comes from, or its state, changes: counted, not listed |
| `transitions` | array | Each change of a value or a lock: `before` and `after`, and `users`, how many users meet it. Empty where nobody's value or lock changes. A `databases` or `server` line has at most one, with `users` `0` |

`before` and `after`:

| Field | Type | Description |
|-------|------|-------------|
| `state` | string | `not_set`, `default` or `enforced`: the state of the value that applies |
| `value` | value | The value that applies; absent where nothing restricts |
| `source` | object | Where it comes from, as in the effective view: a level, `{"type": "product"}` or `{"type": "groups"}`. `{"type": "user"}` without an `id` is the user's own document, whichever user it is, so that users alike share one transition |
| `locked` | boolean | A level of the user's chain enforces the setting -- unlike `locked` in the effective view, the user's own level counts as well |

### Warnings

| Warning | `setting` of its rows | Meaning |
|---------|-----------------------|---------|
| `sign_in_lost` | `""` | An administrator who can sign in to the Server Manager could not after the change, while another still could. The row's `clause` names the first rule the account fails: `disabled`, `method`, `second_factor`, `network` or `version` |
| `methods_empty` | `auth.methods.allowed` | The user's allowed sign-in methods become an empty set |
| `network_empty` | `auth.network.allowed` | The user's allowed network addresses become an empty list |
| `platforms_empty` | `session.platforms.allowed` | The user's allowed client platforms become an empty set |
| `second_factor_empty` | `auth.second_factor.required` | After the change a second factor is required of the user while no second-factor method (`auth.second_factor.methods`) is allowed, which was not so before -- whether the change brings the requirement or the empty set |
| `ages_crossed_new` | `account.password.min_age` or `database.master_password.min_age` | The user's minimum age of that password becomes larger than its maximum age |
| `ages_crossed_already` | as above | The minimum age was larger than the maximum before the change and stays so |
| `conflict_created` | the setting | The user's groups come to set different values for a setting that takes one value |
| `conflict_removed` | the setting | The user's groups no longer disagree on the setting |

- The users left without a way to sign in come first: `sign_in_lost`, then the empty sets. Only `sign_in_lost` judges the accounts themselves, as the Server Manager's sign-in does; the other warnings judge the policy values alone.
- A warning is looked for only where the change changes a setting it concerns: `sign_in_lost` where it changes a setting the Server Manager's sign-in checks (`auth.methods.allowed`, `auth.second_factor.required`, `auth.second_factor.methods`, `auth.second_factor.preferred`, `auth.network.allowed` or `session.client.min_version`); `methods_empty`, `network_empty` and `platforms_empty` where it changes that set (`auth.methods.allowed`, `auth.network.allowed`, `session.platforms.allowed`); `second_factor_empty` where it changes `auth.second_factor.required` or `auth.second_factor.methods`; the ages where it changes either age of a pair; a conflict where it changes the setting the groups disagree on. A setting the body names with what the document already holds is not changed.
- For `methods_empty`, `network_empty` and `platforms_empty`, "becomes empty" is the step from any other value, or from none, to an empty set the user's chain declares; a set that was already empty before raises none of them. `second_factor_empty` is raised also over a method set that was empty before, where the change makes the second factor required.
- The ages compare the values of the policy documents. A value that reaches a user's computer from another source (see `sources` in the [registry](#get-policy-registry)) is not part of the preview.
- No warning refuses the change. Only a change that would leave no server administrator able to sign in to the Server Manager is refused (`lockout`), as without a preview.

### Rows

With the default filter, a row for each setting and user whose value or lock changes, in the order of the setting ids and then of the user ids:

```json
{"user": "3D1C91F6-754D-427E-9D76-8CC20E8C326E", "disabled": false, "setting": "session.idle_timeout", "transition": 0, "warnings": []}
```

`transition` is the index of the user's transition in the `transitions` of the setting's `users` entry; `warnings` lists every warning the user meets, in the order of the table above.

With `filter=flagged`, a row for each warning and user, in the order of the warnings in the table above, then of the setting ids, then of the user ids:

```json
{"user": "3D1C91F6-754D-427E-9D76-8CC20E8C326E", "disabled": false, "setting": "auth.methods.allowed", "warning": "methods_empty", "warnings": ["methods_empty"]}
```

A `sign_in_lost` row also has `clause`. Disabled users are listed and marked with `disabled`: an account that is enabled again meets the policies at once. Rows carry user ids only; [`GET /admin/users/{id}`](users.md#get-user-admin) gives a user's name.

### Pages and the Stamp

The rows come in pages, like the lists of the API (see [Pagination](overview.md#pagination)). Every page carries the whole summary -- `settings`, `warnings`, `conflicts` and the counts --, so the first page tells everything but the ids of the users beyond it.

The preview is worked out anew for every page. `stamp` names the state of the policies and of the users and groups that the page describes; treat it as an opaque string and send it back as `stamp` when you ask for a further page, with the `If-Match` and the body of the first page. A further page is checked as the change would be first: a change that would now be refused gets that refusal, with its status, as on the first page; and where this document changed since the revision in `If-Match`, the answer is `412` with the code `stale` -- read the document again. Otherwise, where other policies, or the users and groups, changed since the page whose `stamp` was sent, the answer is `409` with the outcome `restart`, the new `stamp` and no rows. In every case, ask again from the first page. A page asked without `stamp` describes the current state.

A page that would be larger than the server answers holds fewer rows than asked, and `errors` carries a `too_large` error that says where the next page starts; the status is still `200`. A preview whose summary alone would be too large is refused with `409` and `too_large`.

### Preview Refusals

A refused preview uses the standard [error envelope](overview.md#error-format), with the preview reply under `error.policy` -- the outcome `refused` and its `errors`, or `restart` and the new `stamp`:

| Status | Description |
|--------|-------------|
| `400 Bad Request` | The body, `If-Match` or a query parameter is refused, or the change would be refused for a setting or a value; `error.policy.errors` names each |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Not an admin-scoped session; the caller may not change a setting the body names; the change would leave no server administrator able to sign in (`lockout`), or would need an approval nobody can give (`approval_unreachable`); or the server is a mirror |
| `404 Not Found` | A group or user that does not exist, or that the caller may not change any setting of, as for the change |
| `405 Method Not Allowed` | Another method than `POST`, with `Allow: POST` |
| `409 Conflict` | `restart`: other policies, or the users and groups, changed since the page whose `stamp` was sent (a change of this document answers `412`). Or `too_large`: the change would make the stored policies larger than the server holds, or the preview would be larger than the server answers |
| `412 Precondition Failed` | The document changed since the revision in `If-Match`: `error.policy.errors` carries the code `stale`, `error.policy.revision` the current revision and the response its `ETag`. It carries no document: read the document again |
| `413 Payload Too Large` | The body is larger than 64 KiB |
| `428 Precondition Required` | No `If-Match`, or `If-Match: *` |
| `503 Service Unavailable` | Nothing was changed, and the same request may succeed later: a directory synchronisation (Active Directory or Azure AD) is running, so the users and groups the preview needs cannot be looked up now (`directory_busy`; try again when it has finished), or the audit trail cannot record the preview at the moment (`audit_unavailable`, below) |

A preview that counts users the caller may not read (`hidden` above `0`) is recorded in the audit trail as a policy change preview, each page asked: with the account that asked for it -- for a long-lived API token, the token's account --, the REST API as the channel, the level, the change with the values before and after, `hidden` and the page (`stamp`, `offset` and `filter`). Where the audit trail cannot record such a preview, it is refused with `503` and the code `audit_unavailable`, without the count; while the audit trail cannot record at all, every preview is refused that way. Every other preview, answered or refused, is not recorded, and no preview raises an alert: it changes nothing.

**Client guidance:** preview a change with the `If-Match` and the body you are about to send, show the warnings before the changed values, and send the `PATCH` only when the user confirms. The preview reserves nothing: the change can still answer `412`, or be refused, when the policies or the users changed in between.

### Example

=== "curl"

    ```bash
    curl -i -X POST "https://<server>:8714/v2.0/admin/groups/FEAE7AC9-58D1-4A76-82A6-2C7DB135CFDD/policy/preview?limit=100" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -H 'If-Match: "4"' \
        -d '{"set": {"session.idle_timeout": {"state": "enforced", "value": 900}}}'
    ```

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

The client follows them where one of them is set for the user at any level -- the server, one of the user's groups or the user --, or where the server's client security policies were active when it was upgraded to Server 20.0.0. A permission, storage location, file tool, export channel or master-password rule of the list that is not set then gives its product default -- for the master-password rules at least 8 characters from 3 character groups, a history of 12 and a minimum age of one day --, while a lock, clipboard or program option that is not `enforced` leaves the user's own choice.

The other Password Depot apps do not apply these settings. Any app or integration can read the settings an app applies, as they apply to the signed-in user, with their sources and whether they are enforced, in the [client policy bundle](client-policy.md): `GET /me/policy`, and `policy` in the answer of a client-scope sign-in. No Password Depot app applies the bundle yet.

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

Every answer of the document routes that the policies decide carries one reply object: the body of a `200`, and `error.policy` of the others (see [Errors](#errors)). A preview carries the preview reply instead (see [Preview a Change](#preview-a-change)). A `404` and the answers given before the policies are asked carry none. The server writes it compact; the examples on this page are indented for reading.

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
| `too_large` | `409` | The stored policies would be larger than the server holds, or a preview larger than the server answers. In a `200` read: the effective view was shortened; in a `200` preview: the page was shortened |
| `stale` | `412` | A preview only: the document changed since the revision in `If-Match` |
| `directory_busy` | `503` | A directory synchronisation is running; try again when it has finished |
| `audit_unavailable` | `503` | The audit trail cannot record the change, or the preview; nothing was saved |
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
- `412 Precondition Failed` carries the current document in `error.policy.document` and its revision in the `ETag` header -- except for a preview, whose `412` carries the current revision alone (see [Preview Refusals](#preview-refusals)).
- For a preview, `error.policy` is the preview reply; its `409` can also be the outcome `restart`, whose `errors` is empty and whose `error.message` asks for the preview again from the first page.
- These answers use the standard error envelope without `error.policy`: `401`; the `403` for a session without the admin scope, and a mirror server's `403` for a `PATCH` or a preview; `404`, whose body is the one the group and user routes answer for an id that does not exist; `405`; `411`; the `413` for a request above the server's general size limit (see [HTTP status codes](overview.md#http-status-codes)); and a `500` when the server could not produce a reply. Branch on the HTTP status, and read `error.policy` only where it is present.
- The messages in `error.policy` are in English; match `code`, never the message.
- A mirror server answers every `PATCH`, and every preview, that carries a bearer token with `403` before the token is examined, as it does for every write (see [Mirror servers are read-only](overview.md#http-status-codes)).

!!! note "What is recorded"
    Every saved change is recorded in the audit trail as a policy change, with the values before and after, the account that made it -- for a long-lived API token, the token's account -- and the REST API as the channel. So is every change the server examines and refuses -- for its body, a body that could not be read included, its `If-Match`, its settings and values, or the caller's rights, a group or user that does not exist included -- and a change that could not be saved. A request refused before its policy is examined -- without a valid admin-scoped session, by a mirror server, or for a method the path does not take -- is not recorded as a policy change; neither is a change answered `412`, one that changes nothing, or a read. A preview is recorded, as a policy change preview, only where it counts users the caller may not read (see [Preview Refusals](#preview-refusals)); every other preview, answered or refused, is not: it changes nothing.
