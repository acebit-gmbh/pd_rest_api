# Entries

## List Entries

Browse entries within a database or folder.

| | |
|---|---|
| **Endpoint** | `GET /v1.0/list` |
| **Auth required** | Yes |

### Query Parameters

| Parameter | Type | Required | Description |
|-----------|------|:--------:|-------------|
| `db` | string (UUID) | Yes | Database fingerprint |
| `folder` | string (UUID) | No | Folder fingerprint. If omitted, lists the root folder. |

### Request Examples

=== "curl"

    ```bash
    # List root folder
    curl -k -X GET \
      "https://your-server:8714/v1.0/list?db=DB_FINGERPRINT" \
      -H "access_token: YOUR_ACCESS_TOKEN" \
      -H "client_id: YOUR_CLIENT_ID"

    # List specific folder
    curl -k -X GET \
      "https://your-server:8714/v1.0/list?db=DB_FINGERPRINT&folder=FOLDER_FINGERPRINT" \
      -H "access_token: YOUR_ACCESS_TOKEN" \
      -H "client_id: YOUR_CLIENT_ID"
    ```

=== "PowerShell"

    ```powershell
    # List root folder
    $entries = Invoke-RestMethod `
      -Uri "https://your-server:8714/v1.0/list?db=$dbFingerprint" `
      -Headers $headers

    $entries.entries | Format-Table name, login, url, fingerprint

    # List specific folder
    $folderEntries = Invoke-RestMethod `
      -Uri "https://your-server:8714/v1.0/list?db=$dbFingerprint&folder=$folderFingerprint" `
      -Headers $headers
    ```

=== "Python"

    ```python
    # List root folder
    response = requests.get(
        f"https://your-server:8714/v1.0/list?db={db_fingerprint}",
        headers=headers,
        verify=False
    )
    entries = response.json()

    # List specific folder
    response = requests.get(
        f"https://your-server:8714/v1.0/list?db={db_fingerprint}&folder={folder_fp}",
        headers=headers,
        verify=False
    )
    ```

### Success Response

**Status:** `200 OK`

```json
{
  "name": "New Group",
  "parent": "3103E6A5-250B-412F-AF6A-8846273E9B74",
  "entries": [
    {
      "name": "Example Entry",
      "fingerprint": "81AF2DA1-F2C4-4472-BAB3-FD950AF69FC6",
      "rights": "RMID",
      "itemclass": "0",
      "login": "user1",
      "url": "http://www.yahoo.com",
      "importance": "1",
      "date": "2010-07-05T10:39:50.000Z",
      "icon": "ico0.png",
      "hash": ""
    }
  ],
  "infoclasses": "000007FF",
  "reasondelete": "1"
}
```

### Response Fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Current folder name |
| `parent` | string (UUID) | Parent folder fingerprint (empty for root) |
| `entries` | array | List of entries in this folder |
| `infoclasses` | string | Bitmask of available information classes |
| `reasondelete` | string | Whether deletion reason is required |

### Entry Summary Object

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Entry display name |
| `fingerprint` | string (UUID) | Unique entry identifier |
| `rights` | string | User's permissions for this entry |
| `itemclass` | string | Entry type: `"-1"` = folder, `"0"` = password entry. The REST API v1.0 only operates on these two types. |
| `login` | string | Username/login stored in the entry |
| `url` | string | Associated URL |
| `importance` | string | Importance level (numeric) |
| `date` | string (ISO 8601) | Last modification timestamp |
| `icon` | string | Icon filename, available at `https://<server>:8714/file/<icon>` |
| `hash` | string | Whether a second password protects the item: `set` when one is configured, empty when not. **Since Server 20.0.0 this is a marker, not the hash itself** — see the note below |

!!! note "`hash` no longer carries the verifier"
    Before Server 20.0.0 this field contained the second-password hash
    itself. That value is an offline-crackable verifier and no client needs
    it — the second password is sent to the server, which checks it — so the
    field now reports only whether one is set:

    | Value | Meaning |
    |-------|---------|
    | `""` | no second password on this item |
    | `"set"` | a second password is required to read `pass` |

    Test it for emptiness, which is all the field was ever documented to
    mean. Writing the marker back in an update is a no-op: to change or
    clear a second password, send `secondpass` as before.

---

## Read Entry

Returns all attributes of a specific entry, including the password, custom fields, and TANs.

| | |
|---|---|
| **Endpoint** | `GET /v1.0/read` |
| **Auth required** | Yes |

### Query Parameters

| Parameter | Type | Required | Description |
|-----------|------|:--------:|-------------|
| `db` | string (UUID) | Yes | Database fingerprint |
| `entry` | string (UUID) | Yes | Entry fingerprint |

### Request Examples

=== "curl"

    ```bash
    curl -k -X GET \
      "https://your-server:8714/v1.0/read?db=DB_FINGERPRINT&entry=ENTRY_FINGERPRINT" \
      -H "access_token: YOUR_ACCESS_TOKEN" \
      -H "client_id: YOUR_CLIENT_ID"
    ```

=== "PowerShell"

    ```powershell
    $entry = Invoke-RestMethod `
      -Uri "https://your-server:8714/v1.0/read?db=$dbFingerprint&entry=$entryFingerprint" `
      -Headers $headers

    # Display all entry fields
    $entry | ConvertTo-Json -Depth 5
    ```

=== "Python"

    ```python
    response = requests.get(
        f"https://your-server:8714/v1.0/read",
        params={"db": db_fingerprint, "entry": entry_fingerprint},
        headers=headers,
        verify=False
    )
    entry = response.json()
    ```

### Success Response

**Status:** `200 OK`

```json
{
  "name": "Example Entry",
  "fingerprint": "81AF2DA1-F2C4-4472-BAB3-FD950AF69FC6",
  "itemclass": "0",
  "login": "user1",
  "pass": "secret_password",
  "url": "https://example.com",
  "importance": "1",
  "date": "2021-07-05T10:39:50.000Z",
  "comment": "Notes about this entry",
  "expirydate": "2025-12-31T23:59:59.000Z",
  "tags": "web,production",
  "author": "admin",
  "category": "Web Logins",
  "icon": "ico0.png",
  "hash": "",
  "secondpass": "",
  "template": "",
  "acm": "0",
  "paramstr": "",
  "loginid": "",
  "passid": "",
  "donotaddon": "0",
  "markassafe": "0",
  "safemode": "0",
  "istemplate": "0",
  "infotemplate": "",
  "usetabs": "0",
  "islink": "0",
  "linkeditem": "",
  "warnmsg": "",
  "warnlvl": "0",
  "warnverify": "",
  "serverrqrd": "0",
  "urls": ["https://alt.example.com", "https://backup.example.com"],
  "fields": [
    {"name": "CustomField1", "value": "custom_value"}
  ],
  "tans": [
    {"number": "1", "value": "123456", "used": "", "amount": "0", "ccode": "", "comment": ""}
  ],
  "history": []
}
```

### Entry Detail Fields

#### Core Fields

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Entry display name |
| `fingerprint` | string (UUID) | Unique entry identifier |
| `itemclass` | string | Entry type: `"-1"` = folder, `"0"` = password entry |
| `login` | string | Username/login |
| `pass` | string | Password (decrypted). Requires valid second password if `hash` is set. |
| `url` | string | Primary URL |
| `importance` | string | Importance level (numeric) |
| `date` | string (ISO 8601) | Last modification timestamp |
| `comment` | string | Notes/comments |
| `expirydate` | string (ISO 8601) | Expiration date (empty if not set) |
| `tags` | string | Comma-separated tags |
| `author` | string | Entry author/creator |
| `category` | string | Entry category |
| `icon` | string | Icon filename (available at `/file/<icon>`) |

#### Security Fields

| Field | Type | Description |
|-------|------|-------------|
| `hash` | string | Whether a second password protects the item: `set` when one is configured, empty when not. **Since Server 20.0.0 this is a marker, not the hash itself** — see the note below |
| `secondpass` | string | Second password (write-only, returned empty for security) |

#### Auto-Complete and Template Fields

| Field | Type | Description |
|-------|------|-------------|
| `template` | string | Auto-complete template |
| `acm` | string | Auto-complete mode (numeric) |
| `paramstr` | string | Additional parameters |
| `loginid` | string | HTML field ID for login auto-fill |
| `passid` | string | HTML field ID for password auto-fill |
| `donotaddon` | string | Disable browser addon for this entry (`"0"` or `"1"`) |
| `markassafe` | string | Mark URL as safe (`"0"` or `"1"`) |
| `safemode` | string | Safe mode enabled (`"0"` or `"1"`) |

#### Template and Linking Fields (since v17.0.0)

| Field | Type | Description |
|-------|------|-------------|
| `istemplate` | string | Entry is a template (`"0"` or `"1"`) |
| `infotemplate` | string | Custom template identifier |
| `usetabs` | string | Number of tabs used in the entry |
| `islink` | string | Entry is a link to another entry (`"0"` or `"1"`) |
| `linkeditem` | string | Fingerprint of the linked entry |

#### Warning Fields (since v16.0.0)

| Field | Type | Description |
|-------|------|-------------|
| `warnmsg` | string | Warning message displayed when accessing the entry |
| `warnlvl` | string | Warning severity level (numeric) |
| `warnverify` | string | Verification text the user must type to confirm |
| `serverrqrd` | string | Server connection required to access (`"0"` or `"1"`) |

#### Additional URLs

| Field | Type | Description |
|-------|------|-------------|
| `urls` | array of strings | Alternative URLs associated with the entry |

#### Custom Fields

| Field | Type | Description |
|-------|------|-------------|
| `fields` | array of objects | Custom fields defined for the entry |
| `fields[].name` | string | Custom field name |
| `fields[].value` | string | Custom field value |

#### TANs (Transaction Authentication Numbers)

| Field | Type | Description |
|-------|------|-------------|
| `tans` | array of objects | TAN list entries |
| `tans[].number` | string | TAN sequence number |
| `tans[].value` | string | TAN value |
| `tans[].used` | string (ISO 8601) | Date when the TAN was used (empty if unused) |
| `tans[].amount` | string | Monetary amount associated with the TAN |
| `tans[].ccode` | string | Currency code |
| `tans[].comment` | string | Comment about this TAN |

#### History (since v17.2.2)

| Field | Type | Description |
|-------|------|-------------|
| `history` | array of objects | Previous versions of the entry. Each object has the same structure as the entry itself. |

### Error Responses

| Code | Description |
|------|-------------|
| `401` | Access token is invalid or expired |
| `403` | Insufficient permissions to read this entry (or invalid second password) |
| `404` | Database or entry not found |

---

## Create Entry

Creates a new entry in the specified database and folder.

| | |
|---|---|
| **Endpoint** | `PUT /v1.0/add` |
| **Auth required** | Yes |
| **Content-Type** | `application/json` |

### Query Parameters

| Parameter | Type | Required | Description |
|-----------|------|:--------:|-------------|
| `db` | string (UUID) | Yes | Database fingerprint |
| `parent` | string (UUID) | No | Target folder fingerprint. Defaults to root folder. |

!!! info
    The server automatically generates the `fingerprint` and `icon` fields. Do not include them in the request.

### Request Examples

=== "curl"

    ```bash
    curl -k -X PUT \
      "https://your-server:8714/v1.0/add?db=DB_FINGERPRINT&parent=FOLDER_FINGERPRINT" \
      -H "access_token: YOUR_ACCESS_TOKEN" \
      -H "client_id: YOUR_CLIENT_ID" \
      -H "Content-Type: application/json" \
      -d '{
        "name": "My New Entry",
        "login": "user@example.com",
        "password": "secure_password",
        "url": "https://example.com"
      }'
    ```

=== "PowerShell"

    ```powershell
    $newEntry = @{
        name     = "My New Entry"
        login    = "user@example.com"
        password = "secure_password"
        url      = "https://example.com"
    } | ConvertTo-Json

    $created = Invoke-RestMethod `
      -Uri "https://your-server:8714/v1.0/add?db=$dbFingerprint&parent=$folderFingerprint" `
      -Method PUT `
      -Headers $headers `
      -Body $newEntry `
      -ContentType "application/json"
    ```

=== "Python"

    ```python
    new_entry = {
        "name": "My New Entry",
        "login": "user@example.com",
        "password": "secure_password",
        "url": "https://example.com"
    }

    response = requests.put(
        f"https://your-server:8714/v1.0/add?db={db_fingerprint}&parent={folder_fp}",
        headers={**headers, "Content-Type": "application/json"},
        json=new_entry,
        verify=False
    )
    ```

### Error Responses

| Code | Description |
|------|-------------|
| `401` | Access token is invalid or expired |
| `403` | Insufficient permissions to create entries |

---

## Modify Entry

Updates attributes of an existing entry.

| | |
|---|---|
| **Endpoint** | `POST /v1.0/modify` |
| **Auth required** | Yes |
| **Content-Type** | `application/json` |

### Query Parameters

| Parameter | Type | Required | Description |
|-----------|------|:--------:|-------------|
| `db` | string (UUID) | Yes | Database fingerprint |
| `entry` | string (UUID) | Yes | Entry fingerprint to modify |

### Request Body

Submit a JSON object with the attributes to update. Use the same structure as returned by the [read endpoint](#read-entry).

### Request Examples

=== "curl"

    ```bash
    curl -k -X POST \
      "https://your-server:8714/v1.0/modify?db=DB_FINGERPRINT&entry=ENTRY_FINGERPRINT" \
      -H "access_token: YOUR_ACCESS_TOKEN" \
      -H "client_id: YOUR_CLIENT_ID" \
      -H "Content-Type: application/json" \
      -d '{
        "name": "Updated Entry Name",
        "login": "new_user@example.com",
        "password": "new_secure_password"
      }'
    ```

=== "PowerShell"

    ```powershell
    $updates = @{
        name     = "Updated Entry Name"
        login    = "new_user@example.com"
        password = "new_secure_password"
    } | ConvertTo-Json

    Invoke-RestMethod `
      -Uri "https://your-server:8714/v1.0/modify?db=$dbFingerprint&entry=$entryFingerprint" `
      -Method POST `
      -Headers $headers `
      -Body $updates `
      -ContentType "application/json"
    ```

=== "Python"

    ```python
    updates = {
        "name": "Updated Entry Name",
        "login": "new_user@example.com",
        "password": "new_secure_password"
    }

    requests.post(
        f"https://your-server:8714/v1.0/modify",
        params={"db": db_fingerprint, "entry": entry_fingerprint},
        headers={**headers, "Content-Type": "application/json"},
        json=updates,
        verify=False
    )
    ```

### Error Responses

| Code | Description |
|------|-------------|
| `401` | Access token is invalid or expired |
| `403` | Insufficient permissions to modify this entry |
| `404` | Database or entry not found |
