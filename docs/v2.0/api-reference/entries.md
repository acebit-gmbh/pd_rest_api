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
| `login` | string or null | Yes | Login/username (only for `password` and `custom` types). Returns `null` if second-pass protected and no correct password provided. |
| `url` | string or null | Yes | Primary URL (only for `password` and `custom` types). Returns `null` if second-pass protected and no correct password provided. |
| `icon` | string | No | Icon filename (e.g., `"ico12.svg"`). Served at `/file/{icon}`. |
| `importance` | string | Yes | Importance level: `"low"`, `"normal"`, or `"high"` (default: `"normal"`) |
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
    Entries can be protected with an optional second password. When `has_second_pass` is `true`, retrieving the full representation (including `pass`, `comments`, and `custom_fields`) requires the `X-Second-Password` request header with the correct password. In compact representations, `login` and `url` return `null` when the entry is second-pass protected and no correct password is provided.

    Updating (`PATCH`) a protected entry now **requires** a correct `X-Second-Password`, which the server verifies; a missing or wrong value returns `403 Forbidden` with body `error.code` = `4031`. (Previously the current second password was not enforced on writes.) Changing the second password via `X-New-Second-Password` additionally requires the correct current `X-Second-Password`.

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
    used as the target of a shared secret.

    *Changed in Server 20.0.0.* Earlier releases resolved a deleted entry and
    returned it like a live one, password included.

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
| `importance` | string | No | `"low"`, `"normal"`, or `"high"` (default: `"normal"`) |
| `category` | string | No | Category label |
| `tags` | string | No | Tags (comma-separated) |
| `comments` | string | No | Comments/notes |
| `custom_fields` | array of objects | No | Custom fields, for `password` and `custom` types (see [Custom Field Object](#custom-field-object)) |
| `<type>` | object | No | Type-specific data sub-object keyed by type name (see [Type-Specific Fields](#type-specific-fields)) |
| `urls` | array of strings | No | Associated URLs |
| `expires_at` | string (ISO 8601) or null | No | Expiration date |

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

### Response

`201 Created`

Returns the compact representation of the created entry (without `pass`).

```json
{
    "type": "password",
    "id": "c3d4e5f6-a7b8-9012-cdef-123456789012",
    "name": "Slack Workspace",
    "has_second_pass": false,
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
| `400 Bad Request` | Invalid or missing required fields |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions |
| `404 Not Found` | Database or parent folder not found |

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

### Response

`200 OK`

Returns the compact representation of the updated entry.

```json
{
    "type": "password",
    "id": "c3d4e5f6-a7b8-9012-cdef-123456789012",
    "name": "Slack Workspace (Admin)",
    "has_second_pass": false,
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
| `400 Bad Request` | Invalid fields |
| `401 Unauthorized` | Missing or invalid authentication token |
| `403 Forbidden` | Insufficient permissions (body `error.code` = `403`), **or** a missing/incorrect `X-Second-Password` for a protected entry (body `error.code` = `4031`) |
| `404 Not Found` | Database or entry not found |

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
