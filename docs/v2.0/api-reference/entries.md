# Entries

Full CRUD reference for managing password entries within databases on the Password Depot Enterprise Server.

Entries are accessed by database ID and entry ID. To **browse** entries within a folder, use the [List Children](folders.md#list-children-navigation) endpoint -- there is no flat `GET /entries` listing endpoint. To **search** across all entries in a database, use the [Search](search.md) endpoint.

---

## Entry Object

The entry object uses different representations depending on context:

- **Children/list** responses return a **compact representation**: basic metadata without sensitive fields like `pass` or `comments`.
- **Detail** responses (`GET /v2.0/databases/{db}/entries/{id}`) return the **full representation** with all fields including `pass`, `comments`, `custom_fields`, and type-specific data.

### Compact Representation

Returned by list/children and search endpoints.

| Field | Type | Writable | Description |
|-------|------|:--------:|-------------|
| `type` | string | Yes | Entry type: `password`, `credit_card`, `license`, `identity`, `information`, `banking`, `document`, `rdp`, `putty`, `teamviewer`, `custom`, `passkey`. For folders: `folder`. |
| `id` | string (UUID) | No | Unique identifier (server-generated) |
| `name` | string | Yes | Entry display name |
| `has_second_pass` | boolean | No | Whether the entry is protected by a second password |
| `has_otp` | boolean | No | Whether a one-time code (TOTP) can be generated for this entry - see [Get One-Time Code](#get-one-time-code). For a link, whether the link's own TOTP settings produce one, as the Windows client shows. `false` when you may not read the entry. The seed is never returned. Absent on servers older than 20.0.0: treat a missing field as "not supported". |
| `totp` | object | No | State of the entry's one-time code: always an object, never `null`, never withheld. The compact form carries `state` only: `none` (no seed), `set` (a code can be computed; the same as `has_otp`), `invalid` (a seed is stored but produces no code), `unsupported` (type `encrypted_file` or `certificate`) or `hidden` (you may not read the entry). This read form is not writable; the write form, which shares the key, is described under [One-Time Code Settings](#one-time-code-settings). The presence of `totp` is how a client detects that the server accepts that write form. Absent on servers older than 20.0.0. |
| `login` | string | Yes | Login/username (only for `password` and `custom` types). |
| `url` | string | Yes | Primary URL (only for `password` and `custom` types). |
| `icon` | string | No | Icon filename (e.g., `"ico12.svg"`). Served at `/file/{icon}`. |
| `importance` | string | Yes | Importance level: `"low"`, `"normal"`, or `"high"` -- the same level the Windows, macOS, iOS and Android clients show (default: `"normal"`) |
| `category` | string | Yes | Category label |
| `tags` | string | Yes | Tags (comma-separated) |
| `updated_at` | string (ISO 8601) | No | Last modification timestamp |
| `expires_at` | string (ISO 8601) or null | No | Expiration date, or `null` if not set |

Timestamp fields (`updated_at`, `expires_at`) are true UTC instants with a trailing `Z` (RFC 3339); inbound `expires_at` is likewise interpreted as UTC.

### Full Representation

Returned by the detail endpoint. Includes all compact fields plus:

**Common fields** (all entry types):

| Field | Type | Writable | Description |
|-------|------|:--------:|-------------|
| `author` | string | No | Author of the entry (read-only) |
| `image_custom` | boolean | Yes | Whether a custom image is used instead of a standard icon |
| `image_index` | integer | Yes | Standard icon index number |
| `image_name` | string | Yes | Custom image filename (e.g., `"twitter.com"`) |
| `comments` | string | Yes | Comments/notes. May require `X-Second-Password` header. |
| `totp` | object | No | Full form of the one-time-code state (see [One-Time Code Settings](#one-time-code-settings)): `state` as in the compact form; `writable` (whether the entry's type accepts the write form: `password`, `credit_card`, `license`, `banking`, `custom`); and, when `state` is `set` or `invalid`, the stored `digits`, `period`, `algorithm` (`"SHA1"`, `"SHA256"`, `"SHA512"`, or `null` for a stored value the server does not know) and `conforming` (whether the stored seed and parameters would be accepted by the write form today). For `hidden`, only `state` is present. Stored values are echoed as they are - an `invalid` entry may report `digits` `12` or `period` `300`. Never the seed. |

**Password and custom types only:**

| Field | Type | Writable | Description |
|-------|------|:--------:|-------------|
| `login_id` | string | Yes | Associated HTML element ID or name for the login field (for browser form filling) |
| `pass` | string | Yes | Password. Requires `X-Second-Password` header if `has_second_pass` is `true`. |
| `pass_id` | string | Yes | Associated HTML element ID or name for the password field (for browser form filling) |
| `urls` | array of strings | Yes | Associated URLs |
| `is_link` | boolean | Yes | Whether this entry is a link to another entry |
| `linked_item` | string (UUID) or null | Yes | UUID of the linked entry, or `null` if not a link |
| `is_template` | boolean | Yes | Whether this entry is a template |
| `info_template` | string or null | Yes | Template identifier (only applicable for `custom` type entries) |
| `param_str` | string | Yes | Command line parameters string |
| `custom_fields` | array of objects | Yes | Custom fields. May require `X-Second-Password` header. See [Custom Field Object](#custom-field-object). |

**All other entry types:**

| Field | Type | Writable | Description |
|-------|------|:--------:|-------------|
| `<type>` | object | Yes | Type-specific data as a sub-object keyed by the entry type name. See [Type-Specific Fields](#type-specific-fields). |

### Type-Specific Fields

For entry types other than `password` and `custom`, type-specific attributes are returned as a sub-object keyed by the entry type name. This keeps the common entry schema clean and avoids namespace collisions (e.g., `document.name` for the filename vs. top-level `name` for the entry display name).

The sub-object is present only in the **full representation**. Clients can generically access type-specific data via `entry[entry.type]`.

#### Credit Card (`"credit_card"`)

| Field | Type | Writable | Description |
|-------|------|:--------:|-------------|
| `card` | string | Yes | Card brand: `visa`, `master_card`, `discover`, `american_express`, `diners_club`, `jcb` |
| `holder` | string | Yes | Cardholder name |
| `number` | string | Yes | Card number (e.g., `"4111 1111 1111 1111"`) |
| `valid_thru` | string | Yes | Expiration date in `MM/YYYY` format |
| `cvv` | string | Yes | CVV/CVC security code |
| `phone` | string | Yes | Card hotline phone number |
| `url` | string | Yes | Online banking/service URL |
| `online_user` | string | Yes | Online banking username |
| `online_pass` | string | Yes | Online banking password |
| `pin` | string | Yes | Card PIN |

```json
{
    "type": "credit_card",
    "name": "Corporate Visa",
    "credit_card": {
        "card": "visa",
        "holder": "John Doe",
        "number": "4111 1111 1111 1111",
        "valid_thru": "12/2027",
        "cvv": "123",
        "phone": "+49 800 123456",
        "url": "https://banking.example.com",
        "online_user": "john.doe",
        "online_pass": "s3cur3",
        "pin": "1234"
    }
}
```

#### License (`"license"`)

| Field | Type | Writable | Description |
|-------|------|:--------:|-------------|
| `product` | string | Yes | Product name |
| `version` | string | Yes | Product version |
| `reg_name` | string | Yes | Registration name |
| `key_1` | string | Yes | License key |
| `key_2` | string | Yes | Additional key |
| `url` | string | Yes | License management URL |
| `user` | string | Yes | License management username |
| `pass` | string | Yes | License management password |
| `purchase_date` | string (ISO 8601) or null | Yes | Purchase date |
| `order_number` | string | Yes | Order number |
| `reg_email` | string | Yes | Registration email |

```json
{
    "type": "license",
    "name": "JetBrains IntelliJ",
    "license": {
        "product": "IntelliJ IDEA Ultimate",
        "version": "2025.1",
        "reg_name": "Example Corp",
        "key_1": "XXXXX-XXXXX-XXXXX-XXXXX",
        "key_2": "",
        "url": "https://account.jetbrains.com",
        "user": "admin@example.com",
        "pass": "s3cur3",
        "purchase_date": "2025-01-15T00:00:00.000Z",
        "order_number": "ORD-2025-001",
        "reg_email": "admin@example.com"
    }
}
```

#### Identity (`"identity"`)

| Field | Type | Writable | Description |
|-------|------|:--------:|-------------|
| `account` | string | Yes | Account/username |
| `email` | string | Yes | Email address |
| `first_name` | string | Yes | First name |
| `last_name` | string | Yes | Last name |
| `company` | string | Yes | Company |
| `address_1` | string | Yes | Address line 1 |
| `address_2` | string | Yes | Address line 2 |
| `city` | string | Yes | City |
| `state` | string | Yes | State/province |
| `zip` | string | Yes | ZIP/postal code |
| `country` | string | Yes | Country |
| `phone` | string | Yes | Phone number |
| `website` | string | Yes | Website URL |
| `birth_date` | string (ISO 8601) or null | Yes | Date of birth |
| `mobile` | string | Yes | Mobile phone number |
| `fax` | string | Yes | Fax number |
| `house` | string | Yes | House number |

```json
{
    "type": "identity",
    "name": "John Doe",
    "identity": {
        "account": "john.doe",
        "email": "john@example.com",
        "first_name": "John",
        "last_name": "Doe",
        "company": "Example Corp",
        "address_1": "Musterstraße",
        "address_2": "",
        "city": "Musterstadt",
        "state": "Sample State",
        "zip": "12345",
        "country": "Germany",
        "phone": "+49 6151 123456",
        "website": "https://example.com",
        "birth_date": "1990-05-15T00:00:00.000Z",
        "mobile": "+49 170 1234567",
        "fax": "",
        "house": "42"
    }
}
```

#### Information (`"information"`)

| Field | Type | Writable | Description |
|-------|------|:--------:|-------------|
| `text` | string | Yes | Main text content |

```json
{
    "type": "information",
    "name": "Server Room Access Code",
    "information": {
        "text": "Door code: 4821#\nValid Mon-Fri 08:00-18:00"
    }
}
```

#### Banking (`"banking"`)

| Field | Type | Writable | Description |
|-------|------|:--------:|-------------|
| `url` | string | Yes | Online banking URL |
| `user` | string | Yes | Online banking username |
| `pass` | string | Yes | Online banking password |
| `holder` | string | Yes | Account owner name |
| `account_number` | string | Yes | Account number (legacy) |
| `bank_id` | string | Yes | Bank ID / routing number (legacy) |
| `bank_name` | string | Yes | Bank name |
| `bic` | string | Yes | BIC/SWIFT code |
| `iban` | string | Yes | IBAN |
| `card_number` | string | Yes | Debit card number |
| `phone` | string | Yes | Bank hotline phone number |
| `legitimation_id` | string | Yes | Legitimation ID |
| `pin` | string | Yes | Card PIN |

```json
{
    "type": "banking",
    "name": "Sparkasse Darmstadt",
    "banking": {
        "url": "https://banking.sparkasse.de",
        "user": "john.doe",
        "pass": "s3cur3",
        "holder": "John Doe",
        "account_number": "",
        "bank_id": "",
        "bank_name": "Sparkasse Darmstadt",
        "bic": "HELADEF1DAS",
        "iban": "DE89 3704 0044 0532 0130 00",
        "card_number": "6789 0123 4567 8901",
        "phone": "+49 6151 9876543",
        "legitimation_id": "LG-123456",
        "pin": "5678"
    }
}
```

#### Document (`"document"`)

| Field | Type | Writable | Description |
|-------|------|:--------:|-------------|
| `name` | string or null | Yes | Original filename of the uploaded document (e.g., `"report.pdf"`) |
| `type` | string or null | No | MIME type derived from the filename extension (e.g., `"application/pdf"`) |
| `size` | integer | No | Size of the stored content in bytes |

```json
{
    "type": "document",
    "name": "Q4 Report",
    "document": {
        "name": "q4_report.pdf",
        "type": "application/pdf",
        "size": 2458621
    }
}
```

!!! info "Document Entry Restrictions"
    - Document entries **cannot** have a second password (`has_second_pass` is always `false`).
    - Maximum document content size is **64 MB**.
    - When a document entry is deleted, its binary content is automatically deleted from the server.
    - Use the [Document Content](#get-document-content) endpoints to download or upload the binary content.

#### RDP (`"rdp"`)

| Field | Type | Writable | Description |
|-------|------|:--------:|-------------|
| `host` | string | Yes | Remote host address |
| `user` | string | Yes | Username |
| `pass` | string | Yes | Password |
| `cmd_line` | string | Yes | Command line parameters |

```json
{
    "type": "rdp",
    "name": "Production Server",
    "rdp": {
        "host": "192.0.2.50",
        "user": "administrator",
        "pass": "s3cur3",
        "cmd_line": "/w:1920 /h:1080"
    }
}
```

#### PuTTY (`"putty"`)

| Field | Type | Writable | Description |
|-------|------|:--------:|-------------|
| `host` | string | Yes | Remote host address |
| `port` | integer | Yes | Port number (default: `0`) |
| `protocol` | string | Yes | Protocol: `ssh`, `telnet`, `rlogin`, `raw` |
| `user` | string | Yes | Username |
| `pass` | string | Yes | Password |
| `key_file` | string | Yes | Path to a private key file |
| `key_pass` | string | Yes | Passphrase for the key file |
| `cmd_line` | string | Yes | Command line parameters |

```json
{
    "type": "putty",
    "name": "Dev Server SSH",
    "putty": {
        "host": "dev.example.com",
        "port": 22,
        "protocol": "ssh",
        "user": "deploy",
        "pass": "",
        "key_file": "C:\\Keys\\dev_rsa.ppk",
        "key_pass": "keyP@ss",
        "cmd_line": ""
    }
}
```

#### TeamViewer (`"teamviewer"`)

| Field | Type | Writable | Description |
|-------|------|:--------:|-------------|
| `partner_id` | string | Yes | Partner/device ID |
| `pass` | string | Yes | Password |
| `mode` | string | Yes | Connection mode: `remote_control`, `file_transfer`, `vpn` |

```json
{
    "type": "teamviewer",
    "name": "Office Desktop",
    "teamviewer": {
        "partner_id": "123 456 789",
        "pass": "s3cur3",
        "mode": "remote_control"
    }
}
```

#### Passkey (`"passkey"`)

| Field | Type | Writable | Description |
|-------|------|:--------:|-------------|
| `url` | string | Yes | Relying party URL |
| `user` | string | Yes | Username |
| `alg` | integer | Yes | COSE algorithm identifier (default: `-7` for ES256) |
| `sign_count` | integer | No | Signature counter (read-only) |
| `cred_id` | string | Yes | Credential ID |
| `rp_id` | string | Yes | Relying party ID |
| `rp_name` | string | Yes | Relying party display name |
| `user_id` | string | Yes | User handle |
| `key` | string | Yes | Public and private key data |

```json
{
    "type": "passkey",
    "name": "GitHub Passkey",
    "passkey": {
        "url": "https://github.com",
        "user": "john.doe",
        "alg": -7,
        "sign_count": 42,
        "cred_id": "dGVzdC1jcmVk...",
        "rp_id": "github.com",
        "rp_name": "GitHub",
        "user_id": "dXNlci1pZA...",
        "key": "MIIBkTCB..."
    }
}
```

!!! note "Unsupported Entry Types"
    Entry types `encrypted_file` and `certificate` are not exposed via the REST API as they are bound to a specific computer and relevant mainly for local databases.

### Custom Field Object

```json
{
    "name": "Recovery Email",
    "value": "recovery@company.com",
    "input_id": "field_1"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Field display name |
| `value` | string | Field value |
| `input_id` | string | Input identifier |

!!! info "Second Password Protection"
    Entries can be protected with an optional second password. When `has_second_pass` is `true`, retrieving the full representation (including `pass`, `comments`, and `custom_fields`) requires the `X-Second-Password` request header with the correct password. `login` and `url` are part of every representation and are not withheld for a protected entry.

    Reading an entry's [one-time code](#get-one-time-code) requires `X-Second-Password` in the same way - for a link, also the second password of the entry it points to. `has_second_pass` on a link describes the link itself, so handle `4031` on `/otp` whatever it says.

    Updating (`PATCH`) a protected entry **requires** a correct `X-Second-Password`, which the server verifies; a missing or wrong value returns `403 Forbidden` with body `error.code` = `4031`. Changing the second password via `X-New-Second-Password` additionally requires the correct current `X-Second-Password`. Writing the entry's [one-time-code settings](#one-time-code-settings) follows the same rule - the second password is checked before anything about `totp` is - but the seed itself is not encrypted with the second password.

    Both headers must be **Base64-encoded** (UTF-8 bytes → Base64). This ensures reliable transport of passwords containing non-ASCII characters (e.g., umlauts, accented letters).

    | Header | Description |
    |--------|-------------|
    | `X-Second-Password` | Base64-encoded current second password (required to read/modify protected fields; verified on update) |
    | `X-New-Second-Password` | Base64-encoded new second password (to set, change, or remove protection; when changing, the correct current `X-Second-Password` must also be sent) |

    To **remove** second password protection, send `X-Second-Password` with the current password and `X-New-Second-Password` with an empty string (both Base64-encoded).

!!! note "No Flat List Endpoint"
    Unlike other resources, entries do not have a flat `GET /databases/{db}/entries` listing endpoint. To browse entries, use the [List Children](folders.md#list-children-navigation) endpoint which returns both folders and entries within a given location. To search across all entries, use the [Search](search.md) endpoint.

---

## Get Entry

```
GET /v2.0/databases/{db}/entries/{id}
```

Returns the **full representation** of a specific entry, including the password, comments, custom fields, and the ancestor `path` for breadcrumb navigation (see [Path / Breadcrumb](folders.md#path--breadcrumb)). If the entry is protected by a second password, the `X-Second-Password` header is required.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `db` | string (UUID) | Yes | Database ID |
| `id` | string (UUID) | Yes | Entry unique identifier |

### Request Headers

| Header | Required | Description |
|--------|----------|-------------|
| `X-Second-Password` | Conditional | Base64-encoded. Required if the entry has a second password (`has_second_pass: true`) |

### Response

`200 OK`

```json
{
    "path": [
        {
            "id": "3BF225B7-48BC-4AA4-888D-605E61A0F2D4",
            "name": "Infrastructure"
        },
        {
            "id": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
            "name": "Servers"
        }
    ],
    "type": "password",
    "id": "e1a2b3c4-d5e6-7890-abcd-ef1234567890",
    "name": "GitHub Account",
    "has_second_pass": false,
    "has_otp": false,
    "totp": {
        "state": "none",
        "writable": true
    },
    "login": "devteam",
    "url": "https://github.com",
    "login_id": "",
    "pass": "s3cur3P@ssw0rd!",
    "pass_id": "",
    "author": "admin",
    "image_custom": false,
    "image_index": 12,
    "image_name": "",
    "custom_fields": [
        {
            "name": "Recovery Email",
            "value": "recovery@company.com",
            "input_id": "field_1"
        }
    ],
    "urls": [
        "https://github.com/settings"
    ],
    "comments": "Shared developer team account",
    "is_link": false,
    "linked_item": null,
    "is_template": false,
    "info_template": null,
    "param_str": "",
    "icon": "ico12.svg",
    "importance": "normal",
    "category": "",
    "tags": "development,git",
    "updated_at": "2024-11-20T16:45:00.000Z",
    "expires_at": "2025-06-01T00:00:00.000Z"
}
```

!!! warning "Sensitive Data"
    The full entry response includes the plaintext password and other sensitive fields. Ensure your transport layer is secured with HTTPS and handle response data carefully.

### Error Responses

| Status | Description |
|--------|-------------|
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions (body `error.code` = `403`), **or** a missing/incorrect `X-Second-Password` for a protected entry (body `error.code` = `4031`) |
| `404 Not Found` | Database or entry not found, **or** the entry is in the recycle bin |

!!! note "Deleted entries are not addressable"
    This API has no recycle bin: nothing lists it, no field names it, and a
    deleted entry is not part of the model. Addressing one by its fingerprint
    therefore returns `404 Not Found` - on this endpoint and on every other
    `/entries/{id}` and `/folders/{id}` route - and a deleted entry cannot be
    used as the target of a shared secret. Treat such an id like one that
    does not exist. A link whose target has been deleted is the exception:
    creating, reading or updating that link returns `403 Forbidden`.

    *Server 20.0.0 and later.*

!!! tip "Detecting a wrong second password"
    A wrong or missing second password returns `403` with the JSON body `error.code` = `4031` (`PD_ERRCODE_INVALID_SECOND_PASS`), distinct from a generic access-denied `403` (which keeps `error.code` = `403`). Detect the condition by checking `HTTP status == 403 && body.error.code == 4031` and re-prompt the user for the second password; on a generic `403`, do not re-prompt. Always match the numeric `error.code`, never the localized message.

### Examples

=== "curl"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/entries/e1a2b3c4-d5e6-7890-abcd-ef1234567890" \
        -H "Authorization: Bearer <token>"
    ```

=== "curl (with second password)"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/entries/e1a2b3c4-d5e6-7890-abcd-ef1234567890" \
        -H "Authorization: Bearer <token>" \
        -H "X-Second-Password: $(echo -n 'mySecretPass' | base64)"
    ```

---

## Create Entry

```
POST /v2.0/databases/{db}/entries
POST /v2.0/databases/{db}/entries?parent={folder_id}
```

Creates a new entry within a database. Use the `parent` query parameter to place the entry inside a folder; omit it to create at root level.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `db` | string (UUID) | Yes | Database ID |

### Query Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `parent` | string (UUID) | No | Parent folder ID. Omit to create at root level. |

### Request Headers

| Header | Required | Description |
|--------|----------|-------------|
| `X-New-Second-Password` | No | Base64-encoded. Set a second password on the new entry |

### Request Body

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `type` | string | No | Entry type (default: `"password"`). See [Entry Object](#entry-object) for valid types. |
| `name` | string | Yes | Entry display name |
| `login` | string | No | Login/username |
| `pass` | string | No | Password |
| `url` | string | No | Primary URL |
| `importance` | string | No | `"low"`, `"normal"`, or `"high"` -- the same level the Windows, macOS, iOS and Android clients show. Any other string is stored as `"normal"` (default: `"normal"`) |
| `category` | string | No | Category label |
| `tags` | string | No | Tags (comma-separated) |
| `comments` | string | No | Comments/notes |
| `custom_fields` | array of objects | No | Custom fields, for `password` and `custom` types (see [Custom Field Object](#custom-field-object)) |
| `<type>` | object | No | Type-specific data sub-object keyed by type name (see [Type-Specific Fields](#type-specific-fields)) |
| `urls` | array of strings | No | Associated URLs |
| `expires_at` | string (ISO 8601) or null | No | Expiration date |
| `totp` | object or null | No | One-time-code (TOTP) settings of the new entry, an object with the members `secret`, `algorithm`, `digits` and `period`. `secret` is **required** here and is write-only: it is never returned by any route. `algorithm` (`SHA1`, `SHA256` or `SHA512`), `digits` (`6` to `8`) and `period` (`15` to `120` seconds) default to `SHA1`, `6` and `30` when omitted. No other member is accepted, and `{}` is refused. `null` is accepted and does nothing, so a client may always send the key. Only `password`, `credit_card`, `license`, `banking` and `custom` entries can carry a code. Ignored by servers older than 20.0.0. See [One-Time Code Settings](#one-time-code-settings). |

```json
{
    "type": "password",
    "name": "Slack Workspace",
    "login": "admin@company.com",
    "pass": "Str0ng!P@ssword#2024",
    "url": "https://company.slack.com",
    "comments": "Company Slack admin account"
}
```

With a one-time code (the seed is the RFC 6238 test vector):

```json
{
    "type": "password",
    "name": "Slack Workspace",
    "login": "admin@company.com",
    "pass": "Str0ng!P@ssword#2024",
    "url": "https://company.slack.com",
    "totp": {
        "secret": "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ",
        "algorithm": "SHA1",
        "digits": 6,
        "period": 30
    }
}
```

### Response

`201 Created`

Returns the compact representation of the created entry (without `pass`). When the body carried a `totp` object, the entry reports `has_otp: true` and `totp.state` `set`; a `totp` object that is refused creates nothing.

```json
{
    "type": "password",
    "id": "c3d4e5f6-a7b8-9012-cdef-123456789012",
    "name": "Slack Workspace",
    "has_second_pass": false,
    "has_otp": false,
    "totp": {
        "state": "none"
    },
    "login": "admin@company.com",
    "url": "https://company.slack.com",
    "icon": "ico0.svg",
    "importance": "normal",
    "category": "",
    "tags": "",
    "updated_at": "2025-01-15T10:30:00.000Z",
    "expires_at": null
}
```

### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | Invalid or missing required fields (body `error.code` = `400`), **or** a refused `totp` object (`error.code` = `4001` to `4006`, see [One-Time Code Settings](#one-time-code-settings)) |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions |
| `404 Not Found` | Database or parent folder not found |
| `501 Not Implemented` | `totp` sent with `type` `encrypted_file` or `certificate` |

### Example

=== "curl"

    ```bash
    curl -X POST "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/entries?parent=f1a2b3c4-d5e6-7890-abcd-ef1234567890" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -d '{
            "type": "password",
            "name": "Slack Workspace",
            "login": "admin@company.com",
            "pass": "Str0ng!P@ssword#2024",
            "url": "https://company.slack.com"
        }'
    ```

=== "curl (with one-time code)"

    ```bash
    curl -X POST "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/entries?parent=f1a2b3c4-d5e6-7890-abcd-ef1234567890" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -d '{
            "type": "password",
            "name": "Slack Workspace",
            "login": "admin@company.com",
            "pass": "Str0ng!P@ssword#2024",
            "url": "https://company.slack.com",
            "totp": {
                "secret": "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ",
                "algorithm": "SHA1",
                "digits": 6,
                "period": 30
            }
        }'
    ```

---

## Update Entry

```
PATCH /v2.0/databases/{db}/entries/{id}
```

Updates an existing entry. Include only the fields you want to update.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `db` | string (UUID) | Yes | Database ID |
| `id` | string (UUID) | Yes | Entry unique identifier |

### Request Headers

| Header | Required | Description |
|--------|----------|-------------|
| `X-Second-Password` | Conditional | Base64-encoded. Required and verified if the entry has a second password (`has_second_pass: true`); a missing/incorrect value returns `403` with `error.code` = `4031` |
| `X-New-Second-Password` | No | Base64-encoded. Set, change, or remove the second password. When changing, the correct current `X-Second-Password` must also be sent |

### Request Body

Include only the fields you want to update.

```json
{
    "name": "Slack Workspace (Admin)",
    "pass": "N3wStr0ng!P@ss#2025",
    "comments": "Password rotated Jan 2025"
}
```

!!! warning
    To move an entry to a different folder, use the dedicated [Move Entry](#move-entry) endpoint.

#### One-time code (`totp`)

The `totp` key writes the entry's one-time-code (TOTP) settings. It has four forms; the admission rules, the entry types, the permissions and the sub-codes are described under [One-Time Code Settings](#one-time-code-settings).

| Body | Effect |
|------|--------|
| key absent | The one-time-code settings are untouched |
| `"totp": null` | Removes the seed and resets the parameters to `SHA1` / `6` / `30` (when a seed is stored; on an entry without one, nothing changes). The entry then reports `has_otp: false` and `totp.state` `none` |
| `"totp": {"secret": "...", "algorithm": "SHA1", "digits": 6, "period": 30}` | Sets a seed, or replaces the stored one, in a single call - no removal first. Send all four members whenever you send `secret` |
| `"totp": {"digits": 8}` - an object without `secret` | Changes only the members sent and keeps the stored seed. Refused with `400` / `4005` when the entry has no seed |

**Merge rule** - there is only one: the members that arrive are validated and applied, and the members that are absent keep their stored values. An absent `secret` keeps the stored seed and does **not** re-validate it, so the parameters of an entry whose seed was imported or set by another client can be corrected even when that seed would not be admitted today. `{}`, any member other than the four, or a member of the wrong JSON type answers `400` / `4005`. Because an omitted member keeps whatever is stored, send all four members whenever you send `secret`.

```json
{
    "totp": {
        "secret": "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ",
        "algorithm": "SHA1",
        "digits": 6,
        "period": 30
    }
}
```

!!! warning "Sending `null` removes the seed"
    The seed is never returned, so it cannot be read back before it is removed, and this API cannot restore it. Where the database keeps entry history, the version of the entry before the write - seed included - stays in that history, which native clients with read permission receive with the entry. Send `null` to remove the code and omit the key to leave it alone; a `secret` of `""` is not "remove" but an invalid seed (`400` / `4001`).

!!! note "A refused one-time-code write is never `409`"
    A refused `totp` answers `400` (`error.code` `4001` to `4006`), `403` (`403`, `4031` or `4033`) or `501` - never `409`. `409` on this route keeps its one meaning: the body tried to write a link's `custom_fields` or type sub-object through the link. A `totp` write on a link is allowed and changes the link's own settings.

### Response

`200 OK`

Returns the compact representation of the updated entry.

```json
{
    "type": "password",
    "id": "c3d4e5f6-a7b8-9012-cdef-123456789012",
    "name": "Slack Workspace (Admin)",
    "has_second_pass": false,
    "has_otp": false,
    "totp": {
        "state": "none"
    },
    "login": "admin@company.com",
    "url": "https://company.slack.com",
    "icon": "ico0.svg",
    "importance": "normal",
    "category": "",
    "tags": "",
    "updated_at": "2025-01-15T14:22:00.000Z",
    "expires_at": null
}
```

### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | Invalid fields (body `error.code` = `400`), **or** a refused `totp` write (`error.code` = `4001` to `4006`, see [One-Time Code Settings](#one-time-code-settings)) |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions, or a `totp` write on an entry that is sealed for you (body `error.code` = `403`); a missing/incorrect `X-Second-Password` for a protected entry (`4031`); a `totp` write without read permission on the entry (`4033`) |
| `404 Not Found` | Database or entry not found |
| `501 Not Implemented` | `totp` sent for an entry of type `encrypted_file` or `certificate` |

!!! tip "Detecting a wrong second password"
    Updating a second-password-protected entry requires a correct `X-Second-Password`; a wrong or missing one returns `403` with the JSON body `error.code` = `4031` (`PD_ERRCODE_INVALID_SECOND_PASS`), distinct from a generic access-denied `403` (which keeps `error.code` = `403`). Detect the condition by checking `HTTP status == 403 && body.error.code == 4031` and re-prompt the user for the second password; on a generic `403`, do not re-prompt. Always match the numeric `error.code`, never the localized message.

### Example

=== "curl"

    ```bash
    curl -X PATCH "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/entries/c3d4e5f6-a7b8-9012-cdef-123456789012" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "Slack Workspace (Admin)",
            "pass": "N3wStr0ng!P@ss#2025"
        }'
    ```

=== "curl (set or replace the one-time code)"

    ```bash
    curl -X PATCH "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/entries/c3d4e5f6-a7b8-9012-cdef-123456789012" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -d '{
            "totp": {
                "secret": "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ",
                "algorithm": "SHA1",
                "digits": 6,
                "period": 30
            }
        }'
    ```

=== "curl (remove the one-time code)"

    ```bash
    curl -X PATCH "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/entries/c3d4e5f6-a7b8-9012-cdef-123456789012" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -d '{
            "totp": null
        }'
    ```

---

## Delete Entry

```
DELETE /v2.0/databases/{db}/entries/{id}
```

Deletes an entry.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `db` | string (UUID) | Yes | Database ID |
| `id` | string (UUID) | Yes | Entry unique identifier |

### Response

`204 No Content`

No response body.

### Error Responses

| Status | Description |
|--------|-------------|
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions |
| `404 Not Found` | Database or entry not found |

### Example

=== "curl"

    ```bash
    curl -X DELETE "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/entries/c3d4e5f6-a7b8-9012-cdef-123456789012" \
        -H "Authorization: Bearer <token>"
    ```

---

## Move Entry

```
POST /v2.0/databases/{db}/entries/{id}/move
```

Moves an entry to a different folder within the same database.

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `db` | string (UUID) | Yes | Database ID |
| `id` | string (UUID) | Yes | Entry unique identifier |

### Request Body

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `target` | string (UUID) or null | Yes | Target folder ID. Set to `null` to move to root level. |

```json
{
    "target": "f2b3c4d5-e6f7-8901-bcde-f12345678901"
}
```

### Response

`200 OK`

Returns the compact representation of the moved entry.

```json
{
    "type": "password",
    "id": "e1a2b3c4-d5e6-7890-abcd-ef1234567890",
    "name": "GitHub Account",
    "has_second_pass": false,
    "has_otp": false,
    "totp": {
        "state": "none"
    },
    "login": "devteam",
    "url": "https://github.com",
    "icon": "ico12.svg",
    "importance": "normal",
    "category": "",
    "tags": "development,git",
    "updated_at": "2024-02-17T15:00:00.000Z",
    "expires_at": null
}
```

### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | Invalid target folder |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions |
| `404 Not Found` | Database, entry, or target folder not found |

### Examples

=== "curl"

    ```bash
    curl -X POST "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/entries/e1a2b3c4-d5e6-7890-abcd-ef1234567890/move" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -d '{
            "target": "f2b3c4d5-e6f7-8901-bcde-f12345678901"
        }'
    ```

=== "curl (move to root)"

    ```bash
    curl -X POST "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/entries/e1a2b3c4-d5e6-7890-abcd-ef1234567890/move" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -d '{
            "target": null
        }'
    ```

---

## Get One-Time Code

```
GET /v2.0/databases/{db}/entries/{id}/otp
```

Returns the entry's **current one-time code** (TOTP), computed on the server's clock from the TOTP settings stored with the entry. Use it to fill the one-time-code step of a login from the same entry that filled the user name and password. The seed itself is never returned.

The code is valid for the rest of the current period: `expires_in` is the number of whole seconds until it changes (`1` to `period`), so the time actually left is between `expires_in - 1` and `expires_in` seconds. Do not cache a code, and do not fill one with `expires_in` of `2` or less - wait `expires_in` seconds and fetch the next one.

The same rules apply as for [reading the entry](#get-entry): you need read permission, the entry must not be sealed for you, and a second-password-protected entry needs `X-Second-Password`. Long-lived API tokens cannot read one-time codes; log in to obtain a session. An entry whose [`has_otp`](#compact-representation) is `false` (`totp.state` other than `set`) has no code to return. To store, replace or remove the settings a code is computed from, see [One-Time Code Settings](#one-time-code-settings).

### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `db` | string (UUID) | Yes | Database ID |
| `id` | string (UUID) | Yes | Entry unique identifier |

### Request Headers

| Header | Required | Description |
|--------|----------|-------------|
| `X-Second-Password` | Conditional | Base64-encoded. Required if the entry has a second password (`has_second_pass: true`) - and, for a link, if the entry it points to has one |

### Response

`200 OK`

```json
{
    "code": "012345",
    "digits": 6,
    "period": 30,
    "expires_in": 12,
    "algorithm": "SHA1"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `code` | string | The current code. A string, because leading zeros are part of it |
| `digits` | integer | Length of the code, `4` to `16`. Codes of 10 or more digits are Password Depot's own and not RFC 4226 codes; every Password Depot client computes them the same way |
| `period` | integer | Seconds each code is valid |
| `expires_in` | integer | Whole seconds until the code changes, `1` to `period` |
| `algorithm` | string | `"SHA1"`, `"SHA256"` or `"SHA512"` |

### Error Responses

| Status | `error.code` | Meaning |
|:------:|:------------:|---------|
| `400` | `400` | `X-Second-Password` longer than 1024 characters |
| `401` | `401` | Not authenticated |
| `403` | `403` | No permission (on the entry or, for a link, on the entry it points to); sealed; long-lived API token; the entry uses an old form of second-password protection that the REST API cannot check |
| `403` | `4031` | Wrong or missing second password (for a link, also the linked entry's) |
| `404` | `404` | Database or entry not found, or the entry is in the recycle bin |
| `404` | `4041` | The entry has no one-time code (`PD_ERRCODE_NO_ONE_TIME_CODE`) |
| `405` | `405` | Method other than `GET` |
| `501` | `501` | Entry type `encrypted_file` or `certificate` |

!!! warning "Sensitive Data"
    A one-time code is a credential. Treat the response like the `pass` field: never log it, and discard it once it has been used.

!!! note "Links"
    For a link, the code comes from the link's **own** TOTP settings - the same code the Windows client shows for that link. The entry it points to must still be readable by you and must not be in the recycle bin.

!!! info "Audit"
    Every successful call is recorded as an entry access in the server's audit log, and "password accessed" alerts fire for it - for a link, alerts set on the link and on the entry it points to. A refused call is recorded as a failed entry access and written to the server log, but fires no alert.

!!! tip "Telling the errors apart"
    Match `error.code`, never the message. `403` with `4031` means prompt for the second password; a plain `403` means do not. `404` with `4041` means the entry exists but has no one-time code; a plain `404` means there is no such entry. A server older than 20.0.0 does not know this endpoint and answers a plain `404` - and omits `has_otp` from its entries, which is the better way to detect the feature.

### Examples

=== "curl"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/entries/e1a2b3c4-d5e6-7890-abcd-ef1234567890/otp" \
        -H "Authorization: Bearer <token>"
    ```

=== "curl (with second password)"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/entries/e1a2b3c4-d5e6-7890-abcd-ef1234567890/otp" \
        -H "Authorization: Bearer <token>" \
        -H "X-Second-Password: $(echo -n 'mySecretPass' | base64)"
    ```

---

## One-Time Code Settings

*Server 20.0.0 and later.*

Every REST consumer - the web client, the mobile apps, custom automation - can store a one-time-code (TOTP) seed with an entry, replace it, change its parameters or remove it. This is done through the `totp` key of [Create Entry](#create-entry) and [Update Entry](#update-entry); there is no separate route. The server never returns a stored seed: `GET /entries/{id}` reports the parameters, [Get One-Time Code](#get-one-time-code) returns the computed code, and that is everything a client can see. An editor can therefore show the stored `digits`, `period` and `algorithm`, but to change the seed it must ask the user for a whole new one.

### The `totp` object in responses

`totp` is part of every entry representation, compact and full, and is not on folders. It is always an object, never `null`, and never withheld: a caller who may not read the entry receives `{"state": "hidden"}`. Its presence is the way to detect that the server accepts the write form below. The server ignores request keys it does not know, so a client cannot find out by writing.

| Field | Present in | Type | Description |
|-------|------------|------|-------------|
| `state` | compact and full | string | `hidden`, `unsupported`, `set`, `invalid` or `none` - see the table below |
| `writable` | full | boolean | Whether the entry's type accepts the write form |
| `digits` | full, `set` or `invalid` | integer | Stored code length |
| `period` | full, `set` or `invalid` | integer | Stored period in seconds |
| `algorithm` | full, `set` or `invalid` | string or null | `"SHA1"`, `"SHA256"` or `"SHA512"`; `null` when the stored algorithm is one the server does not know |
| `conforming` | full, `set` or `invalid` | boolean | Whether the stored seed and parameters would pass the admission rules below today |

| `state` | Meaning |
|---------|---------|
| `hidden` | You may not read the entry. Nothing else is reported - `{"state": "hidden"}` - not even `writable` |
| `unsupported` | Entry type `encrypted_file` or `certificate` |
| `set` | A code can be computed. `has_otp` is `true` in exactly this state |
| `invalid` | A seed is stored but produces no code. The stored parameters are echoed as they are (for example `digits` `12` or `period` `300`) so that a repair UI can show them |
| `none` | No seed |

The states are listed in order of precedence: an entry you may not read is `hidden` whatever else is true. Treat a `state` you do not recognise as `hidden` - show no code and offer no editor.

```json
{
    "state": "set",
    "writable": true,
    "digits": 6,
    "period": 30,
    "algorithm": "SHA1",
    "conforming": true
}
```

### The `totp` key in requests

| Member | Type | Description |
|--------|------|-------------|
| `secret` | string | The seed, Base32 (RFC 4648). Write-only: never returned by any route. Required on `POST`; on `PATCH` an absent `secret` keeps the stored seed (see the [merge rule](#one-time-code-totp)) |
| `algorithm` | string | `SHA1`, `SHA256` or `SHA512`, case-insensitive. Default on `POST`: `SHA1`. An empty string is refused (`4002`), not read as `SHA1` |
| `digits` | integer | `6` to `8`. Default on `POST`: `6` |
| `period` | integer | `15` to `120` seconds. Default on `POST`: `30` |

Only these four members exist. `{}`, any other member, or a member of the wrong JSON type answers `400` / `4005`; so does an object without `secret` on `POST`, or on `PATCH` for an entry that has no seed. `null` removes the code on `PATCH` and does nothing on `POST`. The four forms of the key and the merge rule are under [Update Entry](#one-time-code-totp).

**Admission.** The seed is normalised first - letters are upper-cased, whitespace is dropped anywhere, `=` padding is dropped from the end - and must then be 16 to 128 Base32 characters (`A` to `Z`, `2` to `7`). Any other character is refused; nothing is silently dropped, because a swallowed typo would store a seed no authenticator app shares. The server stores the normalised form. After the sent and the stored values are merged, the server computes a code once; if that fails, the seed is refused as well. A refused write changes nothing, so an accepted write always leaves the entry with `has_otp: true` and `totp.state` `set`. On `PATCH`, only the members that arrive are validated - a stored seed is never re-judged by a parameter change. The first failing member, in the order `secret`, `algorithm`, `digits`, `period`, names the sub-code.

**Entry types.** `password`, `credit_card`, `license`, `banking` and `custom` can carry a one-time code written over REST - the types whose Windows editor has the one-time-code fields. Any other type answers `400` / `4006`; `encrypted_file` and `certificate` answer `501`, as they do on every route. The one exception is `null` on an entry that has no seed: there is nothing to remove, so it does nothing whatever the type; `null` over a stored seed is judged by the type like an object. The check uses the type the entry has **after** the request: the `type` of a `POST` body, or a `type` change sent in the same `PATCH`. An entry of another type that already has a seed - an `rdp` entry, for example - keeps showing it (`has_otp`, `totp` and `/otp` are unchanged), but its seed cannot be changed or removed over REST.

**Links.** A link may carry a one-time code. The write goes to the link's **own** settings - the ones `/otp` computes the link's code from - and the entry it points to is weighed as on every other write of a link. The `409` that guards a link's `custom_fields` and type sub-object does not apply to `totp`.

**Permissions and tokens.** A `totp` write needs the rights of any other entry write - create permission on the folder for `POST`, update permission on the entry for `PATCH` - and, on `PATCH`, read permission on the entry as well (`403` / `4033`): a caller who may update but not read an entry cannot destroy a seed they cannot see. An entry that is sealed for you answers a plain `403`. Long-lived API tokens write seeds exactly like a session; they still cannot read one, because no route returns a seed, and they still cannot read codes.

**Second password.** On `PATCH`, a protected entry needs the correct `X-Second-Password` (`403` / `4031`) before anything about `totp` is looked at; the seed itself is not encrypted with the second password. On `POST`, `totp` needs no `X-Second-Password`; `X-New-Second-Password` keeps its own rule (the `second_pass` permission).

**Audit and alerts.** A one-time-code write is recorded as an entry **modification** - a creation or an update - never as an entry access, and the alerts that fire are the ones for a password added or modified, never "password accessed". The audit message names the operation: on `PATCH`, that the entry's one-time code has been set, replaced, had its parameters changed, or been removed; on `POST`, that a new entry with a one-time code has been added. A refused write is recorded as a failed modification. No audit entry, server-log line, alert or error message ever contains the submitted seed.

### Order of checks

`PATCH /v2.0/databases/{db}/entries/{id}` with a `totp` key:

1. `404` when the database or entry does not exist, the id is a folder, or the entry is in the recycle bin; `403` without use permission
2. `403` without update permission
3. `400` when the body is not a JSON object
4. `403` / `4031` for a wrong or missing `X-Second-Password` on a protected entry
5. `403` when `X-New-Second-Password` is sent without the `second_pass` permission
6. Without a `totp` key nothing below applies; the request behaves as before 20.0.0
7. `400` / `4005` when `totp` is not `null` or an object of the four members
8. `403` / `4033` without read permission on the entry
9. `403` when the entry is sealed for you
10. `400` / `4006` or `501` for the entry's type (after a `type` change in the same body)
11. `400` / `4005` for an object without `secret` on an entry that has no seed
12. `400` / `4001` to `4004` from the admission rules and the code computation
13. Only now is the entry written, as one: the previous version goes to the history where the database keeps one, the body is applied, `updated_at` is bumped, and the write is audited

`POST /v2.0/databases/{db}/entries` with a `totp` key: the parent folder and create permission (`404`, `403`), then the body (`400`), then `X-New-Second-Password`, then `totp` in the same order - `4005` for the shape, `4006` / `501` for the type, `4005` for an object without `secret` (required here), `4001` to `4004`. There is no read or seal check on `POST`, because there is nothing to hide yet.

### Sub-codes

| Status | `error.code` | Constant | Meaning |
|:------:|:------------:|----------|---------|
| `400` | `4001` | `PD_ERRCODE_TOTP_SECRET` | `secret` is not strict Base32 of 16 to 128 characters after normalisation, or yields no code |
| `400` | `4002` | `PD_ERRCODE_TOTP_ALGORITHM` | `algorithm` is not `SHA1`, `SHA256` or `SHA512` |
| `400` | `4003` | `PD_ERRCODE_TOTP_DIGITS` | `digits` outside `6` to `8` |
| `400` | `4004` | `PD_ERRCODE_TOTP_PERIOD` | `period` outside `15` to `120` |
| `400` | `4005` | `PD_ERRCODE_TOTP_SHAPE` | Wrong shape: `{}`, a member other than the four, a wrong JSON type, or no `secret` where one is required |
| `400` | `4006` | `PD_ERRCODE_TOTP_ENTRY_TYPE` | The entry's type cannot carry a one-time code written over REST |
| `403` | `403` | - | No update or create permission, or the entry is sealed for you |
| `403` | `4031` | `PD_ERRCODE_INVALID_SECOND_PASS` | Wrong or missing second password (`PATCH`) |
| `403` | `4033` | `PD_ERRCODE_TOTP_READ_REQUIRED` | No read permission on the entry (`PATCH`) |
| `501` | `501` | - | Entry type `encrypted_file` or `certificate` |

`4001` to `4006` are the first sub-codes of the `400` family. A client that recognised a bad request by `error.code == 400` must match the HTTP status instead, as the [error format](overview.md#error-format) has always asked.

!!! warning "Shared links show the code"
    The HTTPS shared-link page (`/shared/<open_uuid>`, see [Secrets](secrets.md)) shows the shared entry's current one-time code, with a copy button, to anyone who opens the link - whenever the entry has a seed, whatever the secret's `include_totp` says. A seed stored through this API is therefore visible, as the code current at the moment the page is opened, on every anonymous HTTPS shared link of that entry for as long as the link can be opened. This behaviour is unchanged in 20.0.0.

!!! note "History and concurrent clients"
    - Where the database keeps entry history, every `totp` write - a removal included - first stores the previous version of the entry, seed included, in that history. Native clients with read permission receive the history with the entry.
    - `updated_at` is bumped by every accepted `totp` write, a parameter-only change included.
    - REST writes carry no lock and no `If-Match`. A native client that holds an older copy of the entry and saves it afterwards overwrites the seed written here, as it would any other field.

### Examples

=== "curl (change the parameters only)"

    ```bash
    curl -X PATCH "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/entries/c3d4e5f6-a7b8-9012-cdef-123456789012" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -d '{
            "totp": {
                "digits": 8,
                "period": 60
            }
        }'
    ```

=== "curl (with second password)"

    ```bash
    curl -X PATCH "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/entries/c3d4e5f6-a7b8-9012-cdef-123456789012" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/json" \
        -H "X-Second-Password: $(echo -n 'mySecretPass' | base64)" \
        -d '{
            "totp": {
                "secret": "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ",
                "algorithm": "SHA256",
                "digits": 6,
                "period": 30
            }
        }'
    ```

---

## Document Content

These endpoints manage the binary content (BLOB) of entries with `type: "document"`. The content is transferred as raw binary data, not JSON.

!!! warning "Document Entries Only"
    These endpoints are only available for entries where `type` is `"document"`. Calling them on other entry types returns `400 Bad Request`.

### Get Document Content

```
GET /v2.0/databases/{db}/entries/{id}/content
```

Downloads the binary content of a document entry.

#### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `db` | string (UUID) | Yes | Database ID |
| `id` | string (UUID) | Yes | Entry unique identifier |

#### Response

`200 OK`

The response body contains the raw binary content. The `Content-Type` header reflects the stored MIME type (e.g., `application/pdf`), and `Content-Disposition` includes the original filename.

| Response Header | Description |
|-----------------|-------------|
| `Content-Type` | MIME type of the document (e.g., `application/pdf`) |
| `Content-Disposition` | `attachment; filename="<content_name>"` |
| `Content-Length` | Size of the content in bytes |

#### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | Entry is not of type `document` |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions |
| `404 Not Found` | Database or entry not found, or no content uploaded yet |

#### Example

=== "curl"

    ```bash
    curl -X GET "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/entries/e1a2b3c4-d5e6-7890-abcd-ef1234567890/content" \
        -H "Authorization: Bearer <token>" \
        -o downloaded_file.pdf
    ```

---

### Upload Document Content

```
PUT /v2.0/databases/{db}/entries/{id}/content
```

Uploads or replaces the binary content of a document entry. The entire content is replaced on each call.

#### Path Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `db` | string (UUID) | Yes | Database ID |
| `id` | string (UUID) | Yes | Entry unique identifier |

#### Request Headers

| Header | Required | Description |
|--------|----------|-------------|
| `Content-Type` | Yes | MIME type of the uploaded file (e.g., `application/pdf`, `image/png`) |
| `Content-Disposition` | No | `attachment; filename="<filename>"` -- used to set `content_name` on the entry |

#### Request Body

Raw binary content of the file. Maximum size: **64 MB**.

#### Response

`200 OK`

Returns the compact representation of the entry. Note that the `document` sub-object with content metadata is only included in the full representation (use `GET /entries/{id}` to retrieve it).

```json
{
    "type": "document",
    "id": "e1a2b3c4-d5e6-7890-abcd-ef1234567890",
    "name": "Q4 Report",
    "has_second_pass": false,
    "has_otp": false,
    "totp": {
        "state": "none"
    },
    "icon": "ico0.svg",
    "importance": "normal",
    "category": "",
    "tags": "reports",
    "updated_at": "2025-03-10T12:00:00.000Z",
    "expires_at": null
}
```

#### Error Responses

| Status | Description |
|--------|-------------|
| `400 Bad Request` | Entry is not of type `document`, missing `Content-Type` header, or content exceeds 64 MB |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions |
| `404 Not Found` | Database or entry not found |

#### Example

=== "curl"

    ```bash
    curl -X PUT "https://<server>:8714/v2.0/databases/a1b2c3d4-e5f6-7890-abcd-ef1234567890/entries/e1a2b3c4-d5e6-7890-abcd-ef1234567890/content" \
        -H "Authorization: Bearer <token>" \
        -H "Content-Type: application/pdf" \
        -H "Content-Disposition: attachment; filename=\"q4_report.pdf\"" \
        --data-binary @q4_report.pdf
    ```

=== "Python"

    ```python
    with open("q4_report.pdf", "rb") as f:
        response = requests.put(
            f"{BASE}/databases/{db_id}/entries/{entry_id}/content",
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/pdf",
                "Content-Disposition": 'attachment; filename="q4_report.pdf"',
            },
            data=f,
            verify=False,
        )
    ```
