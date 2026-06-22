# Quick Start

This guide walks you through a complete CRUD workflow -- from authenticating to creating, reading, updating, and deleting a password entry -- using the v2.0 API.

## Prerequisites

- Password Depot Server with REST service enabled ([setup guide](setup.md))
- A valid user account on the server
- `curl` (with `jq` recommended), PowerShell, or Python installed

## Step 1: Login

Authenticate and obtain an access token.

**Request:**

```bash
curl -k -X POST "https://YOUR_SERVER:8714/v2.0/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"user":"admin","pass":"my_password"}'
```

**Response:**

```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

Save the token for all subsequent requests:

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

!!! tip
    All subsequent examples assume the `TOKEN` variable is set. Replace `$TOKEN` with your actual token if not using a variable.

## Step 2: List Databases

Retrieve all databases available to the authenticated user.

**Request:**

```bash
curl -k -X GET "https://YOUR_SERVER:8714/v2.0/databases" \
  -H "Authorization: Bearer $TOKEN"
```

**Response:**

```json
{
  "data": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "name": "Company Passwords.pswe",
      "description": "Main corporate password database",
      "updated_at": "2024-11-20T16:45:00.000Z"
    },
    {
      "id": "660e8400-e29b-41d4-a716-446655440001",
      "name": "IT Infrastructure.pswe",
      "description": "Infrastructure credentials",
      "updated_at": "2024-12-01T09:00:00.000Z"
    }
  ],
  "total": 2,
  "offset": 0,
  "limit": 100
}
```

Note the `id` of the database you want to work with. We will use `550e8400-e29b-41d4-a716-446655440000` in the following steps.

```bash
DB="550e8400-e29b-41d4-a716-446655440000"
```

## Step 3: Browse Root Contents

Retrieve all folders and entries at the root level of a database using the children endpoint.

**Request:**

```bash
curl -k -X GET "https://YOUR_SERVER:8714/v2.0/databases/$DB/children?offset=0&limit=100" \
  -H "Authorization: Bearer $TOKEN"
```

**Response:**

```json
{
  "name": "root",
  "parent": null,
  "has_second_pass": false,
  "data": [
    {
      "type": "folder",
      "id": "f1a2b3c4-d5e6-7890-abcd-ef1234567890",
      "name": "Servers",
      "icon": "ico3.svg",
      "importance": "normal",
      "category": "",
      "tags": "",
      "has_second_pass": false,
      "updated_at": "2024-02-05T16:30:00.000Z"
    },
    {
      "type": "password",
      "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "name": "GitHub Account",
      "has_second_pass": false,
      "login": "devteam",
      "url": "https://github.com",
      "icon": "ico12.svg",
      "importance": "normal",
      "category": "",
      "tags": "development,git",
      "updated_at": "2024-11-20T16:45:00.000Z",
      "expires_at": null
    },
    {
      "type": "password",
      "id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
      "name": "AWS Console",
      "has_second_pass": false,
      "login": "admin@company.com",
      "url": "https://console.aws.amazon.com",
      "icon": "ico5.svg",
      "importance": "normal",
      "category": "Infrastructure",
      "tags": "cloud,aws",
      "updated_at": "2024-12-01T09:00:00.000Z",
      "expires_at": null
    }
  ],
  "total": 3,
  "offset": 0,
  "limit": 100
}
```

## Step 4: Read an Entry

Retrieve full details of a specific entry, including the password.

**Request:**

```bash
ENTRY="a1b2c3d4-e5f6-7890-abcd-ef1234567890"

curl -k -X GET "https://YOUR_SERVER:8714/v2.0/databases/$DB/entries/$ENTRY" \
  -H "Authorization: Bearer $TOKEN"
```

**Response:**

```json
{
  "type": "password",
  "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
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

## Step 5: Create an Entry

Create a new password entry in the database.

**Request:**

```bash
curl -k -X POST "https://YOUR_SERVER:8714/v2.0/databases/$DB/entries" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Slack Workspace",
    "login": "admin@company.com",
    "pass": "Str0ng!P@ssword#2024",
    "url": "https://company.slack.com",
    "comments": "Company Slack admin account"
  }'
```

**Response:**

**Status:** `201 Created`

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

!!! note
    The response returns the compact representation with the server-assigned `id` and timestamps. The `pass` field is not included in creation responses.

## Step 6: Update an Entry

Update an existing entry with new values. Include only the fields you want to change.

**Request:**

```bash
ENTRY_UPDATE="c3d4e5f6-a7b8-9012-cdef-123456789012"

curl -k -X PATCH "https://YOUR_SERVER:8714/v2.0/databases/$DB/entries/$ENTRY_UPDATE" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Slack Workspace (Admin)",
    "pass": "N3wStr0ng!P@ss#2025",
    "comments": "Password rotated Jan 2025"
  }'
```

**Response:**

**Status:** `200 OK`

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

## Step 7: Delete an Entry

Remove an entry from the database.

**Request:**

```bash
curl -k -X DELETE "https://YOUR_SERVER:8714/v2.0/databases/$DB/entries/$ENTRY_UPDATE" \
  -H "Authorization: Bearer $TOKEN"
```

**Response:**

**Status:** `204 No Content`

No response body is returned on successful deletion.

## Step 8: Logout

End the session and invalidate the access token.

**Request:**

```bash
curl -k -X POST "https://YOUR_SERVER:8714/v2.0/auth/logout" \
  -H "Authorization: Bearer $TOKEN"
```

**Response:**

**Status:** `204 No Content`

## Complete Script

Here is the entire workflow as a single copy-paste script:

=== "curl (Bash)"

    ```bash
    #!/bin/bash
    SERVER="YOUR_SERVER"
    PORT="8714"
    BASE="https://${SERVER}:${PORT}/v2.0"

    # Step 1: Login
    LOGIN=$(curl -k -s -X POST "${BASE}/auth/login" \
      -H "Content-Type: application/json" \
      -d '{"user":"USERNAME","pass":"PASSWORD"}')

    TOKEN=$(echo "$LOGIN" | jq -r '.access_token')
    echo "Logged in. Token: ${TOKEN:0:20}..."

    AUTH="Authorization: Bearer ${TOKEN}"

    # Step 2: List databases
    DATABASES=$(curl -k -s -X GET "${BASE}/databases" -H "$AUTH")
    echo "Databases:"
    echo "$DATABASES" | jq '.data[] | {name, id}'

    DB=$(echo "$DATABASES" | jq -r '.data[0].id')

    # Step 3: Browse root contents
    CHILDREN=$(curl -k -s -X GET "${BASE}/databases/${DB}/children" -H "$AUTH")
    echo "Root contents:"
    echo "$CHILDREN" | jq '.data[] | {type, name}'

    # Step 4: Read first entry (any non-folder item)
    ENTRY_ID=$(echo "$CHILDREN" | jq -r '.data[] | select(.type != "folder") | .id' | head -1)
    DETAIL=$(curl -k -s -X GET "${BASE}/databases/${DB}/entries/${ENTRY_ID}" -H "$AUTH")
    echo "Entry detail:"
    echo "$DETAIL" | jq '{name, login, url, comments}'

    # Step 5: Create a new entry
    NEW=$(curl -k -s -X POST "${BASE}/databases/${DB}/entries" \
      -H "$AUTH" \
      -H "Content-Type: application/json" \
      -d '{
        "name": "Test Entry",
        "login": "testuser",
        "pass": "TestP@ss123",
        "url": "https://example.com"
      }')
    NEW_ID=$(echo "$NEW" | jq -r '.id')
    echo "Created entry: $NEW_ID"

    # Step 6: Update the entry
    curl -k -s -X PATCH "${BASE}/databases/${DB}/entries/${NEW_ID}" \
      -H "$AUTH" \
      -H "Content-Type: application/json" \
      -d '{
        "name": "Test Entry (Updated)",
        "pass": "UpdatedP@ss456"
      }' | jq .
    echo "Updated entry: $NEW_ID"

    # Step 7: Delete the entry
    curl -k -s -X DELETE "${BASE}/databases/${DB}/entries/${NEW_ID}" -H "$AUTH"
    echo "Deleted entry: $NEW_ID"

    # Step 8: Logout
    curl -k -s -X POST "${BASE}/auth/logout" -H "$AUTH"
    echo "Logged out."
    ```

=== "PowerShell"

    ```powershell
    $Server = "YOUR_SERVER"
    $Port = 8714
    $Base = "https://${Server}:${Port}/v2.0"

    # Step 1: Login
    $loginBody = @{ user = "USERNAME"; pass = "PASSWORD" } | ConvertTo-Json
    $login = Invoke-RestMethod -Uri "$Base/auth/login" -Method POST `
      -Body $loginBody -ContentType "application/json"

    $headers = @{ Authorization = "Bearer $($login.access_token)" }
    Write-Host "Logged in successfully."

    # Step 2: List databases
    $dbs = Invoke-RestMethod -Uri "$Base/databases" -Headers $headers
    $dbs.data | Format-Table name, id

    $dbId = $dbs.data[0].id

    # Step 3: Browse root contents
    $children = Invoke-RestMethod -Uri "$Base/databases/$dbId/children" -Headers $headers
    $children.data | Format-Table type, name

    # Step 4: Read first entry (any non-folder item)
    $entryId = ($children.data | Where-Object { $_.type -ne "folder" })[0].id
    $detail = Invoke-RestMethod -Uri "$Base/databases/$dbId/entries/$entryId" `
      -Headers $headers
    $detail | ConvertTo-Json -Depth 5

    # Step 5: Create a new entry
    $newBody = @{
        name  = "Test Entry"
        login = "testuser"
        pass  = "TestP@ss123"
        url   = "https://example.com"
    } | ConvertTo-Json

    $new = Invoke-RestMethod -Uri "$Base/databases/$dbId/entries" -Method POST `
      -Headers $headers -Body $newBody -ContentType "application/json"
    Write-Host "Created entry: $($new.id)"

    # Step 6: Update the entry
    $updateBody = @{
        name = "Test Entry (Updated)"
        pass = "UpdatedP@ss456"
    } | ConvertTo-Json

    Invoke-RestMethod -Uri "$Base/databases/$dbId/entries/$($new.id)" `
      -Method PATCH -Headers $headers -Body $updateBody -ContentType "application/json"
    Write-Host "Updated entry: $($new.id)"

    # Step 7: Delete the entry
    Invoke-RestMethod -Uri "$Base/databases/$dbId/entries/$($new.id)" `
      -Method DELETE -Headers $headers
    Write-Host "Deleted entry: $($new.id)"

    # Step 8: Logout
    Invoke-RestMethod -Uri "$Base/auth/logout" -Method POST -Headers $headers
    Write-Host "Logged out."
    ```

=== "Python"

    ```python
    import requests

    SERVER = "YOUR_SERVER"
    PORT = 8714
    BASE = f"https://{SERVER}:{PORT}/v2.0"

    # Step 1: Login
    resp = requests.post(
        f"{BASE}/auth/login",
        json={"user": "USERNAME", "pass": "PASSWORD"},
        verify=False,
    )
    token = resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {token}"}
    print("Logged in successfully.")

    # Step 2: List databases
    dbs = requests.get(f"{BASE}/databases", headers=headers, verify=False).json()
    for db in dbs["data"]:
        print(f"  {db['name']} ({db['id']})")

    db_id = dbs["data"][0]["id"]

    # Step 3: Browse root contents
    children = requests.get(
        f"{BASE}/databases/{db_id}/children", headers=headers, verify=False
    ).json()
    for item in children["data"]:
        print(f"  [{item['type']}] {item['name']}")

    # Step 4: Read first entry (any non-folder item)
    entry_id = next(e["id"] for e in children["data"] if e["type"] != "folder")
    detail = requests.get(
        f"{BASE}/databases/{db_id}/entries/{entry_id}",
        headers=headers,
        verify=False,
    ).json()
    print(f"Entry: {detail['name']} ({detail['login']})")

    # Step 5: Create a new entry
    new = requests.post(
        f"{BASE}/databases/{db_id}/entries",
        headers=headers,
        json={
            "name": "Test Entry",
            "login": "testuser",
            "pass": "TestP@ss123",
            "url": "https://example.com",
        },
        verify=False,
    ).json()
    print(f"Created entry: {new['id']}")

    # Step 6: Update the entry
    requests.patch(
        f"{BASE}/databases/{db_id}/entries/{new['id']}",
        headers=headers,
        json={
            "name": "Test Entry (Updated)",
            "pass": "UpdatedP@ss456",
        },
        verify=False,
    )
    print(f"Updated entry: {new['id']}")

    # Step 7: Delete the entry
    requests.delete(
        f"{BASE}/databases/{db_id}/entries/{new['id']}",
        headers=headers,
        verify=False,
    )
    print(f"Deleted entry: {new['id']}")

    # Step 8: Logout
    requests.post(f"{BASE}/auth/logout", headers=headers, verify=False)
    print("Logged out.")
    ```

## Next Steps

- [API Reference](../api-reference/overview.md) -- Explore all endpoints in detail
- [Authentication Guide](authentication.md) -- OIDC, 2FA, and advanced auth flows
- [Changelog](../changelog.md) -- What changed from v1.0 to v2.0
