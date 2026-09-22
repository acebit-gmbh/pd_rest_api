# Recycle Bin

*Server 20.0.0 and later.*

Every database keeps its own recycle bin: the place a deleted entry or folder goes when it is not destroyed outright. An item reaches the bin when it is deleted in the Windows client, or when a [Delete Entry](entries.md#delete-entry) or [Delete Folder](folders.md#delete-folder) call is made without `mode`, or with `mode=recycle`. The endpoints on this page show what is in the bin, put an item back, and destroy one or all of them.

| Method | Path | Description |
|--------|------|-------------|
| `GET` | [`/v2.0/databases/{db}/recyclebin`](#list-recycle-bin) | List the items in the bin the caller may see |
| `POST` | [`/v2.0/databases/{db}/recyclebin/{id}/restore`](#restore-item) | Put one item back where it was deleted from |
| `DELETE` | [`/v2.0/databases/{db}/recyclebin/{id}`](#delete-item) | Destroy one item |
| `DELETE` | [`/v2.0/databases/{db}/recyclebin`](#empty-recycle-bin) | Destroy what the caller can see in the bin and may delete |

These are client-scope endpoints, per database. They work the same in `client` and `admin` sessions. There is no `PATCH` and no `PUT`: an item in the bin is put back or destroyed, never edited.

!!! warning "Destroying an item cannot be undone"
    `DELETE` on this page is final. There is no second bin behind the bin, no undo, and no copy left anywhere for an administrator to recover. [Empty Recycle Bin](#empty-recycle-bin) destroys every item the caller can see and may delete in one call, a deleted folder with everything under it. Ask the user before you send either one.

---

## Detecting Support

Every [database object](databases.md#database-object) of a server that implements this page carries a read-only `recycle_bin` object:

```json
"recycle_bin": {
    "enabled": true,
    "keep": 1000,
    "can_manage": false
}
```

The presence of `recycle_bin` means the whole feature is there: these endpoints and the `mode` parameter on [Delete Entry](entries.md#delete-entry) and [Delete Folder](folders.md#delete-folder). When the object is absent the server is older than 20.0.0: do not call `/recyclebin` (it answers a plain `404`) and do not send `mode`. This is the same rule the [`icons`](icons.md#detecting-support) object follows, and the documented way to test for a feature -- never a version number, which the API does not report. The fields are described under [Databases](databases.md#recycle-bin-capability).

---

## Items in the Bin

An item in the bin **keeps the id it had**, and that id stays the item's own for as long as the bin holds it. It is not addressable through the entries and folders routes while it is there: `GET`, `PATCH`, `DELETE`, `/move`, `/children`, `/content` and `/otp` under `/databases/{db}/entries/{id}` and `/databases/{db}/folders/{id}` all answer `404`, exactly as they do for an id that never existed. `POST /secrets` and `POST /admin/secrets` answer `404` for such an `entry_id` as well. Address the item through the routes on this page instead; once it is restored, its own routes answer again, under the same id.

A deleted **folder** is one item. It travels into the bin with its sub-folders and its entries, is listed as a single row, and is restored or destroyed as a whole. The entries below it are not listed separately and are not addressable by their own ids.

**How many the bin keeps.** The database's `recycle_bin.keep` says how many items the bin holds. Once there are more, the oldest are dropped -- destroyed, with no further notice, and not counted as a deletion by anyone. A client that wants an item back should not leave it in the bin.

**When the bin is off.** An administrator can set the server to keep no recycle bin. `recycle_bin.enabled` is then `false`, `keep` is `0`, and a delete with `mode=recycle` -- or without `mode` -- destroys the item instead of binning it, which is what the Windows client does under the same setting. These endpoints still answer.

---

## Who Sees What

Two rules decide what a caller finds in a database's bin:

- **Your own deletions are always yours.** Every caller sees the items that caller deleted, whether or not `can_manage` is set. Acting on one is a separate question: putting an item back needs the right on the folder it returns to (see [Restore Item](#restore-item)), and destroying one needs the right to delete it (see [Delete Item](#delete-item)).
- **Other people's deletions need `can_manage`.** The database's [`recycle_bin.can_manage`](databases.md#recycle-bin-capability) says whether this caller may also see and act on items *other* people deleted. When it is `false`, those items are not listed, and their ids answer `404` on every route here -- the same answer as an id that is not in the bin at all.

`can_manage` is computed for the current caller and for that one database, so it can differ from one database to the next in the same session. Read it from the database object rather than deriving it from a role.

Every row says who deleted it, in `deleted_by`, which is what makes a bin worth listing for a caller with `can_manage`: without it, one person's deletions cannot be told from another's.

Restoring an item needs one right beyond seeing it: the right to change the folder the item returns to (see [Restore Item](#restore-item)).

---

## List Recycle Bin

```
GET /v2.0/databases/{db}/recyclebin
```

Returns a paginated list of the items in the database's recycle bin that the caller may see -- the caller's own deletions, and everybody's when [`can_manage`](#who-sees-what) is `true`.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `db` | string (UUID) | Yes | Database ID |

### Query Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `offset` | integer | No | Pagination offset (default: `0`) |
| `limit` | integer | No | Pagination limit (default: `100`, clamped to `1000`) |

### Response

`200 OK`

The standard [paginated envelope](overview.md#pagination), in the same shape [List Children](folders.md#list-children-navigation) returns -- without the `path` array, because an item in the bin has no place in the tree. Each row is the compact [entry](entries.md#compact-representation) or [folder](folders.md#compact-representation) representation plus `deleted_by`, and `type` tells the two apart: a folder has `type: "folder"`, an entry a type such as `"password"` or `"credit_card"`. Items the caller may not see are left out and are not counted in `total`.

| Field | Type | Description |
|-------|------|-------------|
| `data` | array | Items in the bin (folders and entries) |
| `total` | integer | Number of items the caller can see |
| `offset` | integer | Current pagination offset |
| `limit` | integer | Current pagination limit |

Beside the fields of a compact entry or folder, every row in `data` carries one more:

| Field | Type | Description |
|-------|------|-------------|
| `deleted_by` | string | the user id of whoever deleted the item - the same kind of value as an entry's `author`. There is no companion timestamp: the server does not record when an item was deleted |

```json
{
    "data": [
        {
            "type": "folder",
            "id": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
            "name": "Staging",
            "icon": "ico3.svg",
            "database_icon": null,
            "importance": "normal",
            "category": "",
            "tags": "",
            "has_second_pass": false,
            "updated_at": "2025-03-04T09:12:00.000Z",
            "deleted_by": "8c1d0f41-5b2a-4a6e-9f3d-2b7c8e5a1d04"
        },
        {
            "type": "password",
            "id": "c3d4e5f6-a7b8-9012-cdef-123456789012",
            "name": "Slack Workspace",
            "has_second_pass": false,
            "has_otp": false,
            "totp": {
                "state": "none"
            },
            "login": "admin@example.com",
            "url": "https://example.slack.com",
            "icon": "ico0.svg",
            "database_icon": null,
            "importance": "normal",
            "category": "",
            "tags": "",
            "updated_at": "2025-03-06T14:41:00.000Z",
            "expires_at": null,
            "deleted_by": "8c1d0f41-5b2a-4a6e-9f3d-2b7c8e5a1d04"
        }
    ],
    "total": 2,
    "offset": 0,
    "limit": 100
}
```

A row carries no password, no comments and no custom fields: it is the compact representation with `deleted_by` added, and the detail routes do not answer for an item in the bin. To read an item's fields again, [restore](#restore-item) it first.

### Error Responses

| Status | `error.code` | Meaning |
|:------:|:------------:|---------|
| `400` | `400` | Bad `offset` or `limit` |
| `401` | `401` | Not authenticated |
| `404` | `404` | Database not found or not accessible to you. Also the answer of a server older than 20.0.0 |
| `405` | `405` | Method other than `GET` or `DELETE` (`Allow: GET, DELETE`) |

### Examples

=== "curl"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/recyclebin?offset=0&limit=100" \
        -H "Authorization: Bearer <token>"
    ```

=== "PowerShell"

    ```powershell
    . .\PD-RestClient-v2.ps1
    $session = Connect-PDServer -Server "<server>" -Username "<user>" -Password "<password>"
    $db = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"

    (Get-PDRecycleBin -Session $session -DatabaseId $db).data | Format-Table type, name, id
    ```

---

## Restore Item

```
POST /v2.0/databases/{db}/recyclebin/{id}/restore
```

Puts one item back into the database. It returns to the folder it was deleted from; when that folder is no longer there, it returns to the database root. A folder returns with everything that went into the bin with it.

Restoring needs the right to change the folder the item returns to -- the `update` permission on that folder, the same right a `PATCH` on that folder needs. Without it the request answers `403` and the item stays in the bin. When the item was deleted from a folder that is gone, the right is weighed on the database root.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `db` | string (UUID) | Yes | Database ID |
| `id` | string (UUID) | Yes | Id of the item in the recycle bin |

### Request Body

None. Send no body, or `{}`.

### Response

`204 No Content`

No response body. The item is out of the bin: its own [entry](entries.md) or [folder](folders.md) routes answer again under the same id, and the next [List Recycle Bin](#list-recycle-bin) no longer shows it. Read the item, or the children of the folder it landed in, to learn where it went.

### Error Responses

| Status | `error.code` | Meaning |
|:------:|:------------:|---------|
| `401` | `401` | Not authenticated |
| `403` | `403` | You may not change the folder the item returns to |
| `404` | `404` | The id is not in this database's recycle bin, or it is an item you may not see; the database does not exist or is not accessible to you; a server older than 20.0.0 |
| `405` | `405` | Method other than `POST` (`Allow: POST`) |

### Examples

=== "curl"

    ```bash
    curl -X POST "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/recyclebin/c3d4e5f6-a7b8-9012-cdef-123456789012/restore" \
        -H "Authorization: Bearer <token>"
    ```

=== "PowerShell"

    ```powershell
    Restore-PDRecycleBinItem -Session $session -DatabaseId $db -ItemId "c3d4e5f6-a7b8-9012-cdef-123456789012"

    # The 204 does not say where the item landed - reload to find out.
    Get-PDEntry -Session $session -DatabaseId $db -EntryId "c3d4e5f6-a7b8-9012-cdef-123456789012"
    ```

---

## Delete Item

```
DELETE /v2.0/databases/{db}/recyclebin/{id}
```

Destroys one item in the recycle bin. A folder is destroyed with everything that went into the bin with it. This cannot be undone.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `db` | string (UUID) | Yes | Database ID |
| `id` | string (UUID) | Yes | Id of the item in the recycle bin |

### Response

`204 No Content`

No response body.

### Error Responses

| Status | `error.code` | Meaning |
|:------:|:------------:|---------|
| `401` | `401` | Not authenticated |
| `403` | `403` | You may not destroy this item |
| `404` | `404` | The id is not in this database's recycle bin, or it is an item you may not see; the database does not exist or is not accessible to you; a server older than 20.0.0 |
| `405` | `405` | Method other than `DELETE` on this path (`Allow: DELETE`) |

### Examples

=== "curl"

    ```bash
    curl -X DELETE "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/recyclebin/c3d4e5f6-a7b8-9012-cdef-123456789012" \
        -H "Authorization: Bearer <token>"
    ```

=== "PowerShell"

    ```powershell
    Remove-PDRecycleBinItem -Session $session -DatabaseId $db -ItemId "c3d4e5f6-a7b8-9012-cdef-123456789012"
    ```

---

## Empty Recycle Bin

```
DELETE /v2.0/databases/{db}/recyclebin
```

Destroys every item in the database's recycle bin that the caller can see **and may delete** -- the caller's own deletions, and everybody's when [`can_manage`](#who-sees-what) is `true`. An item the caller may not see, or may not delete, is left in the bin, and the call answers `204` all the same. This cannot be undone.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `db` | string (UUID) | Yes | Database ID |

### Response

`204 No Content`

No response body. An empty bin answers `204` as well, so the call is safe to repeat.

### Error Responses

| Status | `error.code` | Meaning |
|:------:|:------------:|---------|
| `401` | `401` | Not authenticated |
| `404` | `404` | Database not found or not accessible to you. Also the answer of a server older than 20.0.0 |
| `405` | `405` | Method other than `GET` or `DELETE` (`Allow: GET, DELETE`) |

### Examples

=== "curl"

    ```bash
    curl -X DELETE "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/recyclebin" \
        -H "Authorization: Bearer <token>"
    ```

=== "PowerShell"

    ```powershell
    Clear-PDRecycleBin -Session $session -DatabaseId $db
    ```

---

## Building a Recycle-Bin View

1. Read the database object and look for `recycle_bin`. No object, no view: leave the menu item out rather than showing one that answers `404`.
2. With `enabled: false`, say so where the user deletes something -- under that setting a deletion is final, whatever `mode` asks for -- and leave the view out.
3. List the bin with [List Recycle Bin](#list-recycle-bin) and page through it with `offset` and `limit`, as for any other list.
4. Offer **Restore** and **Delete** per row, and **Empty** for the whole view. Confirm the two destructive ones; neither can be undone.
5. `can_manage` `false` means the view shows only what this user deleted. Say that in the view, so an empty list does not read as an empty bin.
6. After a restore, reload the folder the item went back to, or the root when the old folder is gone -- the `204` does not say where it landed.
