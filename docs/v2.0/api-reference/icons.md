# Database Icons

*Server 20.0.0 and later.*

Every database carries its own collection of icons next to the 135 standard icons that ship with Password Depot. A database icon is what the Windows client calls a custom icon: a small image, stored inside the database, that any entry or folder of that database can show. The endpoints on this page list the icons of a database, return their images and upload new ones. Assigning an icon to an entry or folder is part of the entry or folder write and is described under [Assigning an Icon](entries.md#assigning-an-icon).

| Method | Path | Description |
|--------|------|-------------|
| `GET` | [`/v2.0/databases/{db}/icons`](#list-icons) | List the icons of a database, or fetch several images in one call |
| `GET` | [`/v2.0/databases/{db}/icons/{icon_id}`](#get-icon) | One icon with its image |
| `POST` | [`/v2.0/databases/{db}/icons`](#upload-icon) | Upload a new icon |

The endpoints work the same in `client` and `admin` sessions. There is no `PATCH`, no `PUT` and no `DELETE`: an icon that exists is never changed or removed through this API.

!!! warning "An upload is database-wide"
    An uploaded icon is not attached to the entry you are editing. It becomes part of the database: every user who can open the database sees its name and its image, in every client, and it counts toward the database's icon quota. It cannot be deleted through this API. Do not put anything confidential into an icon or its name.

---

## Detecting Support

Every [database object](databases.md#database-object) of a server that implements this page carries a read-only `icons` object:

```json
"icons": {
    "can_upload": true,
    "accepted_types": ["image/png"],
    "max_bytes": 32768,
    "max_side": 64,
    "max_count": 1024,
    "batch_max": 32
}
```

The presence of `icons` means the whole feature is there: these endpoints, the [`database_icon`](entries.md#compact-representation) field on entries and folders, the validated `image_*` writes and the corrected `icon` field. When the object is absent the server is older than 20.0.0: do not call `/icons` (it answers a plain `404`), do not probe by uploading, and treat `icon` as the legacy value. The fields are described under [Databases](databases.md#icons-capability).

---

## Icon Object

| Field | Type | Present | Description |
|-------|------|---------|-------------|
| `id` | string | always | Fetch handle: a string of decimal digits, valid only inside this database. Opaque - not a UUID and not a value for `image_name` |
| `name` | string | always | The icon's identifier, unique within the database, compared case-insensitively. This is the value for `image_name` |
| `version` | string | always | Opaque change token. It changes whenever the stored image changes |
| `state` | string | [Get Icon](#get-icon), and [List Icons](#list-icons) with `include=data` | `ok`, `unusable` (the stored image cannot be served; show the fallback and remember that for this `id` and `version`) or `deferred` (the response's byte budget was reached; fetch this icon with [Get Icon](#get-icon)) |
| `content_type` | string | `state` `ok` | `image/png`, or `image/bmp` for icons that an older client stored. Accept exactly these two values |
| `width`, `height` | integer | `state` `ok` | Size in pixels, read from the image header. Can be larger than `max_side` - see *Served images* below |
| `data` | string | `state` `ok` | The image, Base64 (RFC 4648, standard alphabet, no line breaks, no `data:` prefix) |
| `created` | boolean | [Upload Icon](#upload-icon) response | `true` when the upload stored a new icon, `false` when an identical icon of that name was already there |

**Identifier.** An icon has three values with three jobs. `name` identifies the icon and is what an entry or folder refers to in `image_name`. `id` is only a handle for fetching the image; it is the one exception to the rule that [resource identifiers](overview.md#resource-identifiers) are UUIDs, and it can be assigned to a different icon after an administrator has removed all icons of the database - which is why it always travels with `version`. `version` tells a client whether the image it has cached is still the stored one. Treat a `state` you do not recognise as `unusable`.

**Served images.** `max_side` and `max_bytes` limit what an upload may contain, not what these endpoints return. The desktop clients store icons in sizes of their own, and those are served in their stored size, up to 512 pixels per side and 1 MiB of image data; a stored image beyond that, or one that is neither PNG nor BMP, reports `state` `unusable` ([Get Icon](#get-icon): `404` / `4042`). Scale the image to the size you draw it in.

**Caching.** Responses carry `Cache-Control: no-store` like every other API response, so the browser cache does not help. Cache images in memory under the key (server, database id, `id`, `version`) and fetch only what is missing; entry and folder rows give you `id` and `version` without any image data.

---

## List Icons

```
GET /v2.0/databases/{db}/icons
GET /v2.0/databases/{db}/icons?ids={id,id,...}&include=data
```

Without `ids`, returns a paginated list of the database's icons **without** image data - what an icon picker needs to show names. With `ids` and `include=data`, returns up to `batch_max` icons with their images in one call - what a list view needs to draw the rows it has just loaded.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `db` | string (UUID) | Yes | Database ID |

### Query Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `offset` | integer | No | Pagination offset (default: `0`). Ignored when `ids` is given |
| `limit` | integer | No | Pagination limit (default: `100`, clamped to `1000`). Ignored when `ids` is given |
| `ids` | string | No | Comma-separated icon ids, `1` to `batch_max` (`32`) of them, each 1 to 6 decimal digits. The count is taken before duplicates are collapsed, so more than `32` ids answers `400` even when some repeat. A malformed value answers `400` |
| `include` | string | No | `data` adds `state` and the image fields to every item. Requires `ids` (`400` otherwise): there is no paged listing of images |

### Response

`200 OK`

The standard [paginated envelope](overview.md#pagination), ordered by the icons' position in the database. With `ids`, the icons come back in the order the ids were given, so a client can match them up positionally.

```json
{
    "data": [
        {
            "id": "3",
            "name": "example.com",
            "version": "9c1e5f2a-10f4-2b1"
        }
    ],
    "total": 1,
    "offset": 0,
    "limit": 100
}
```

With `ids=3,7&include=data`:

```json
{
    "data": [
        {
            "id": "3",
            "name": "example.com",
            "version": "9c1e5f2a-10f4-2b1",
            "state": "ok",
            "content_type": "image/png",
            "width": 64,
            "height": 64,
            "data": "iVBORw0KGgo..."
        },
        {
            "id": "7",
            "name": "logo.png",
            "version": "01ab22f0-2c000-400",
            "state": "deferred"
        }
    ],
    "total": 2,
    "offset": 0,
    "limit": 2
}
```

**Removed icons.** Icons that were removed in another client, and icons without image data, are never listed and do not count in `total`. A requested id that is unknown, removed or empty is left out without an error: treat a requested id that does not come back as gone.

**Byte budget.** Images are added until the decoded image bytes of the response reach 2 MiB; the image that reaches the limit is still returned whole, so one response can exceed the budget by at most one image, and the items after it come back with `state` `deferred` and no image. Icons uploaded through this API are at most `max_bytes` each, so 32 of them always fit; `deferred` concerns large icons stored by older clients.

### Error Responses

| Status | `error.code` | Meaning |
|:------:|:------------:|---------|
| `400` | `400` | Bad `offset`, `limit` or `ids`; more than `batch_max` ids; `include` other than `data`, or `include=data` without `ids` |
| `401` | `401` | Not authenticated |
| `404` | `404` | Database not found or not accessible to you. Also the answer of a server older than 20.0.0, and of any further path segment that is not an icon id |
| `405` | `405` | Method other than `GET` or `POST` (`Allow: GET, POST`) |

### Examples

=== "curl (list)"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/icons?offset=0&limit=100" \
        -H "Authorization: Bearer <token>"
    ```

=== "curl (images of several icons)"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/icons?ids=3,7&include=data" \
        -H "Authorization: Bearer <token>"
    ```

=== "PowerShell"

    ```powershell
    . .\PD-RestClient-v2.ps1
    $session = Connect-PDServer -Server "<server>" -Username "<user>" -Password "<password>"
    $db = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"

    # Names only
    (Get-PDDatabaseIcon -Session $session -DatabaseId $db).data | Format-Table id, name, version

    # Images of the icons 3 and 7
    $icons = Get-PDDatabaseIcon -Session $session -DatabaseId $db -Ids "3","7" -IncludeData
    ```

---

## Get Icon

```
GET /v2.0/databases/{db}/icons/{icon_id}
```

Returns one icon with its image. Icons are a property of the database, so no `X-Second-Password` is involved, whatever entry uses the icon.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `db` | string (UUID) | Yes | Database ID |
| `icon_id` | string | Yes | The icon's `id`: 1 to 6 decimal digits |

### Response

`200 OK`

```json
{
    "id": "3",
    "name": "example.com",
    "version": "9c1e5f2a-10f4-2b1",
    "state": "ok",
    "content_type": "image/png",
    "width": 64,
    "height": 64,
    "data": "iVBORw0KGgo..."
}
```

Store the image under the `version` that this response carries. When it differs from the `version` on the entry or folder row that made you ask, the row is stale: read your rows again, once per `id` and `version`.

### Error Responses

| Status | `error.code` | Meaning |
|:------:|:------------:|---------|
| `401` | `401` | Not authenticated |
| `404` | `4042` | No usable icon with that id in **this** database: the id is unknown, the icon was removed, it has no image, or the stored image cannot be served (`PD_ERRCODE_ICON_NOT_FOUND`). Show the item's standard [`icon`](entries.md#compact-representation) and do not ask again in this session |
| `404` | `404` | Database not found or not accessible to you; a server older than 20.0.0; an `icon_id` that is not 1 to 6 digits; any further path segment |
| `405` | `405` | Method other than `GET` (`Allow: GET`) |

### Examples

=== "curl"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/icons/3" \
        -H "Authorization: Bearer <token>"
    ```

=== "PowerShell"

    ```powershell
    # Writes the decoded image to a file and returns the icon object
    Get-PDDatabaseIcon -Session $session -DatabaseId $db -Id "3" -OutFile ".\example.com.png"
    ```

---

## Upload Icon

```
POST /v2.0/databases/{db}/icons
```

Stores a new icon in the database. The request is JSON like every other request of this API; the image travels as Base64 inside it. There is no multipart or binary upload.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `db` | string (UUID) | Yes | Database ID |

### Request Body

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `name` | string | Yes | Name of the icon. Trimmed by the server; then 1 to 100 characters and at most 240 bytes in UTF-8. Control characters (U+0000 to U+001F, U+007F to U+009F), U+FFFE, U+FFFF and unpaired surrogates are refused. Dots, spaces, parentheses, `&`, `/` and non-ASCII letters are fine |
| `data` | string | Yes | The image: a PNG, as strict Base64 (RFC 4648, no line breaks, no `data:` prefix), at most `43692` characters |

Any other key is ignored. The whole request body may be at most `65536` bytes.

```json
{
    "name": "example.com",
    "data": "iVBORw0KGgo..."
}
```

**Formats and limits.** The image must be a PNG of 1 to `max_side` (`64`) pixels per side and of 67 to `max_bytes` (`32768`) bytes once decoded from Base64. 64x64 is the native size of a Password Depot icon, and it is what the Password Depot clients always send: the picture scaled to fit a transparent 64x64 canvas. The server looks at the bytes, not at a declared type. JPEG, GIF, BMP, ICO, WebP, SVG and animated PNG are refused - convert before you upload. Check the size before sending: read the limits from the database's [`icons`](databases.md#icons-capability) object, not from this page.

**Normalisation.** The server keeps the image data and drops everything else: of the PNG's chunks only `IHDR`, `PLTE`, `tRNS`, `IDAT` and `IEND` are stored, so text, EXIF data, colour profiles and the like never reach the database. It then decodes the result once with the decoder the Windows client uses, and builds the 16x16 rendition that client needs. The image that [Get Icon](#get-icon) returns is therefore not byte-identical to the one you uploaded, and its `version` is computed by the server from what it stored.

**Name collisions.** The `name` you send is a wish, the `name` in the response is the fact - use that one in `image_name`:

- No icon of that name: the icon is stored (`201`, `created` `true`).
- An icon of that name was removed earlier: it is brought back in place with the new image, under the same `id` (`201`, `created` `true`). Entries and folders that still refer to that name show the new image.
- An icon of that name holds exactly the same image: nothing is written (`200`, `created` `false`). Repeating an upload is therefore safe.
- An icon of that name holds a **different** image: it is left alone, and yours is stored under a free name such as `example.com (2)` (`201`, `created` `true`).

**Removed icons.** This API cannot remove or replace an icon. Icons are removed in the Windows client or by an administrator; the slot of a removed icon stays reserved, so it still counts toward `max_count`.

**Permissions and tokens.** Listing and fetching need nothing beyond access to the database: whoever can open the database sees all of its icon names and images, exactly as the desktop and mobile clients receive them with the database. Uploading is open to the same callers - in a client session everyone with the database-level `use` right, in an admin session everyone who manages the database - because an upload can never change or remove an existing icon and is bounded by the quotas. The verdict for the current caller is published as `icons.can_upload`. Long-lived API tokens may upload, as they may write entries. Assigning an icon needs no right of its own; it is part of the entry or folder write.

**Mirror servers.** A mirror server answers every request that is not a `GET` with a plain `403`, so the two `GET` endpoints work there and the upload does not; `icons.can_upload` is `false`.

**Isolation.** An icon belongs to exactly one database. Every lookup goes through the database named in the URL, after the access check. The same name in two databases means two independent icons, and the `id` of an icon in one database, sent to another, addresses that database's own icon or answers `404` / `4042` - never the first database's image.

**Audit.** Every upload attempt that gets past the permission check is recorded in the server's audit log and written to the server log, whatever its outcome. Neither ever contains image data.

**Windows clients.** The icon is stored in the same place and form the Windows client uses. A Windows client that has the database open at the time of the upload sees the new icon, and entries that use it, after it reopens the database.

### Response

`201 Created` when an icon was stored, `200 OK` when an identical icon of that name already existed.

```json
{
    "id": "7",
    "name": "example.com",
    "version": "9c1e5f2a-10f4-2b1",
    "created": true
}
```

### Order of checks

1. `401` without a valid token; a plain `403` on a mirror server
2. `404` when the database does not exist or is not accessible to you
3. `405` for a method other than `GET` or `POST`
4. `403` when you may not upload to this database
5. `400` when the body is missing or is not a JSON object (a form-encoded body counts as missing); `413` / `4131` when the body is larger than `65536` bytes
6. `400` when `name` is missing, not a string, empty after trimming, too long, or contains a refused character
7. `400` / `4008` when `data` is missing, not a string, not strict Base64, or decodes to fewer than 67 bytes; `413` / `4131` when it is longer than `43692` characters (checked before decoding) or decodes to more than `max_bytes`
8. `400` / `4008` when the bytes are not a well-formed, non-animated PNG. This is a structural check of signature and chunks; no image decoder has run yet. `413` / `4131` when the header declares a width or height above `max_side`
9. The chunks other than `IHDR`, `PLTE`, `tRNS`, `IDAT` and `IEND` are dropped
10. `400` / `4008` when what is left cannot be decoded, or decodes to a size other than the header declares
11. The 16x16 rendition is built
12. The name collision rule is applied; `403` / `4034` when a new icon would exceed `max_count` (removed icons included) or 8 MiB of stored icon data in this database - bringing back a removed name needs no new slot; `413` / `4131` when the stored record, with its final name, would exceed 65535 bytes
13. Only now is the icon stored, in one step, and the outcome audited: `201`, or `200` for an identical icon

A refused or failed upload leaves nothing behind: no new icon, no half-written icon, no changed icon.

### Sub-codes

| Status | `error.code` | Constant | Meaning |
|:------:|:------------:|----------|---------|
| `400` | `4007` | `PD_ERRCODE_ICON_ASSIGNMENT` | Entry or folder `POST` / `PATCH`: `image_custom`, `image_index` and `image_name` do not name a usable icon. Nothing was written. Reload the icon list and let the user pick again. See [Assigning an Icon](entries.md#assigning-an-icon) |
| `400` | `4008` | `PD_ERRCODE_ICON_IMAGE` | Upload: `data` is not a usable PNG. Pick or convert another image |
| `403` | `4034` | `PD_ERRCODE_ICON_QUOTA` | Upload: the database cannot hold another icon. Use an existing one |
| `404` | `4042` | `PD_ERRCODE_ICON_NOT_FOUND` | Get Icon: no usable icon with that id in this database. Show the standard `icon` |
| `413` | `4131` | `PD_ERRCODE_ICON_TOO_LARGE` | Upload: too many bytes, too many pixels, or too large a stored record. Scale down and retry |

A plain `400`, `401`, `403`, `404` or `405` carries its own status in `error.code`. None of these endpoints answers `409`. `4131` is the first sub-code of the `413` family: match the HTTP status `413`, whatever the code.

!!! warning "A request over 1 MB is cut off before it is read"
    Like every JSON endpoint, this one refuses a request whose `Content-Length` exceeds 1 MB with a plain `413` (`error.code` `413`) before the body is read. That response is sent before the CORS headers are added, and the connection is closed, so a browser reports a network error instead of a status. Validate the size before sending, and treat a network error during an upload as "too large or connection lost".

### If the entry save fails

Uploading an icon and assigning it are two requests. When the upload succeeds and the entry or folder write then fails, the icon stays stored and unassigned. That is harmless - it shows up in every client's icon list and counts toward the quota - and nothing cleans it up, because this API has no delete. Retry the entry write with the same `image_name`. Sending the same upload again is safe as well: it answers `200` with the same icon.

!!! tip "Scripts: normalise first, then upload"
    Whatever the source image is, scale it to fit a transparent 64x64 canvas and save it as PNG before you upload; a 64x64 PNG is almost always far below `max_bytes`. If the encoded PNG is still larger than `max_bytes`, do not send it. `Add-PDDatabaseIcon -Resize` in the example client `examples/v2.0/PD-RestClient-v2.ps1` does exactly that with `System.Drawing`.

### Examples

=== "curl"

    ```bash
    curl -X POST "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/icons" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"example.com\", \"data\": \"$(base64 -w0 example-64.png)\"}"
    ```

=== "PowerShell"

    ```powershell
    # Scales the picture into a transparent 64x64 PNG, uploads it, and assigns it.
    # Use the name the server returns, not the one you sent.
    $icon = Add-PDDatabaseIcon -Session $session -DatabaseId $db -Name "example.com" -Path ".\logo.jpg" -Resize
    Set-PDEntryIcon -Session $session -DatabaseId $db -EntryId $entryId -Name $icon.name
    ```

---

## Showing an Item's Icon

Every entry and folder row carries two fields for this, in every representation:

- `database_icon` - `null`, or `{"id", "name", "version"}` of the database icon the item uses
- `icon` - the file name of a standard icon, always `ico0.svg` to `ico134.svg`; for an item with a database icon this is the standard icon of the item's type, and it is the documented fallback

Draw the item in this order, and stop at the first step that works:

1. `database_icon` is not `null`: the image of that icon, from your cache or from [List Icons](#list-icons) with `ids` and `include=data`. Show the standard icon while the image loads, so the layout does not move
2. The standard icon named by `icon` - from your own bundled copy of the 135 standard icons, or from [`/file/{icon}`](overview.md#entry-icons)
3. Your client's own symbol for the item's `type`

A list view collects the `database_icon.id` values of the rows it has just loaded that it has no image for under their `version`, and asks for them in batches of `batch_max`.
