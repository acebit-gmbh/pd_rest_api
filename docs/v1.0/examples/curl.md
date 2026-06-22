# curl Examples

Complete curl examples for all Password Depot REST API v1.0 endpoints.

!!! info "Prerequisites"
    - `curl` installed (included on most systems)
    - `jq` recommended for parsing JSON responses ([download](https://jqlang.github.io/jq/))
    - Replace `YOUR_SERVER` with your Password Depot Server address

!!! tip "Self-Signed Certificates"
    The `-k` flag skips SSL certificate verification. Remove it if you have a valid CA-signed certificate.

## Authentication

!!! warning "Legacy Servers (prior to v18.0.0)"
    The examples below pass login credentials as a JSON request body, which requires **v18.0.0 or later**. For older servers, credentials (`user`, `pass`, `tfacode`) must be passed as custom HTTP headers instead. See the [API Reference: Authentication](../api-reference/authentication.md) for legacy examples.

### Login

```bash
# Standard login
curl -k -s -X POST "https://YOUR_SERVER:8714/v1.0/login" \
  -H "Content-Type: application/json" \
  -d '{"user":"admin","pass":"my_password"}'
```

**Save credentials for reuse:**
```bash
LOGIN=$(curl -k -s -X POST "https://YOUR_SERVER:8714/v1.0/login" \
  -H "Content-Type: application/json" \
  -d '{"user":"admin","pass":"my_password"}')

TOKEN=$(echo "$LOGIN" | jq -r '.access_token')
CLIENT=$(echo "$LOGIN" | jq -r '.client_id')

echo "Token:  $TOKEN"
echo "Client: $CLIENT"
```

### Login with 2FA

```bash
curl -k -s -X POST "https://YOUR_SERVER:8714/v1.0/login" \
  -H "Content-Type: application/json" \
  -d '{"user":"admin","pass":"my_password","tfacode":"123456"}'
```

### Logout

```bash
curl -k -s -X POST "https://YOUR_SERVER:8714/v1.0/logout" \
  -H "client_id: ${CLIENT}"
```

## Databases

### List All Databases

```bash
curl -k -s -X GET "https://YOUR_SERVER:8714/v1.0/list" \
  -H "access_token: ${TOKEN}" \
  -H "client_id: ${CLIENT}" | jq '.databases[] | {name, fingerprint}'
```

## Entries

### List Entries in Root Folder

```bash
DB_FP="your-database-fingerprint"

curl -k -s -X GET "https://YOUR_SERVER:8714/v1.0/list?db=${DB_FP}" \
  -H "access_token: ${TOKEN}" \
  -H "client_id: ${CLIENT}" | jq '.entries[] | {name, login, url}'
```

### List Entries in a Specific Folder

```bash
FOLDER_FP="your-folder-fingerprint"

curl -k -s -X GET \
  "https://YOUR_SERVER:8714/v1.0/list?db=${DB_FP}&folder=${FOLDER_FP}" \
  -H "access_token: ${TOKEN}" \
  -H "client_id: ${CLIENT}"
```

### Read Entry Details

```bash
ENTRY_FP="your-entry-fingerprint"

curl -k -s -X GET \
  "https://YOUR_SERVER:8714/v1.0/read?db=${DB_FP}&entry=${ENTRY_FP}" \
  -H "access_token: ${TOKEN}" \
  -H "client_id: ${CLIENT}" | jq .
```

### Create a New Entry

```bash
# Create in root folder
curl -k -s -X PUT "https://YOUR_SERVER:8714/v1.0/add?db=${DB_FP}" \
  -H "access_token: ${TOKEN}" \
  -H "client_id: ${CLIENT}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "My New Entry",
    "login": "user@example.com",
    "password": "secure_password_123",
    "url": "https://example.com"
  }'

# Create in a specific folder
curl -k -s -X PUT \
  "https://YOUR_SERVER:8714/v1.0/add?db=${DB_FP}&parent=${FOLDER_FP}" \
  -H "access_token: ${TOKEN}" \
  -H "client_id: ${CLIENT}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Another Entry",
    "login": "admin",
    "password": "another_password",
    "url": "https://service.example.com"
  }'
```

### Modify an Entry

```bash
curl -k -s -X POST \
  "https://YOUR_SERVER:8714/v1.0/modify?db=${DB_FP}&entry=${ENTRY_FP}" \
  -H "access_token: ${TOKEN}" \
  -H "client_id: ${CLIENT}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Updated Entry Name",
    "password": "new_password_456"
  }'
```

## Search

### Search Entire Database

```bash
curl -k -s -X GET \
  "https://YOUR_SERVER:8714/v1.0/search?db=${DB_FP}&query=example" \
  -H "access_token: ${TOKEN}" \
  -H "client_id: ${CLIENT}" | jq '.entries[] | {name, login, url}'
```

### Search Within a Folder

```bash
curl -k -s -X GET \
  "https://YOUR_SERVER:8714/v1.0/search?db=${DB_FP}&query=admin&parent=${FOLDER_FP}" \
  -H "access_token: ${TOKEN}" \
  -H "client_id: ${CLIENT}"
```

## Delete

### Delete Entries

```bash
curl -k -s -X DELETE "https://YOUR_SERVER:8714/v1.0/delete?db=${DB_FP}" \
  -H "access_token: ${TOKEN}" \
  -H "client_id: ${CLIENT}" \
  -H "Content-Type: application/json" \
  -d '{
    "reason": "Credentials rotated",
    "entries": ["entry-uuid-1", "entry-uuid-2"]
  }'
```

## Move

### Move Entries to Another Folder

```bash
TARGET_FOLDER="target-folder-fingerprint"

curl -k -s -X POST "https://YOUR_SERVER:8714/v1.0/move?db=${DB_FP}" \
  -H "access_token: ${TOKEN}" \
  -H "client_id: ${CLIENT}" \
  -H "Content-Type: application/json" \
  -d "{
    \"target\": \"${TARGET_FOLDER}\",
    \"entries\": [\"entry-uuid-1\", \"entry-uuid-2\"]
  }"
```

## Complete Workflow Script

A full end-to-end script that logs in, lists databases, browses entries, creates an entry, and logs out:

```bash
#!/bin/bash
set -e

SERVER="YOUR_SERVER"
PORT="8714"
BASE="https://${SERVER}:${PORT}/v1.0"

echo "=== Password Depot REST API - curl Workflow ==="

# 1. Login
echo -e "\n--- Logging in..."
LOGIN=$(curl -k -s -X POST "${BASE}/login" \
  -H "Content-Type: application/json" \
  -d '{"user":"admin","pass":"my_password"}')

TOKEN=$(echo "$LOGIN" | jq -r '.access_token')
CLIENT=$(echo "$LOGIN" | jq -r '.client_id')
echo "Logged in. Client ID: ${CLIENT}"

# 2. List databases
echo -e "\n--- Databases:"
DBS=$(curl -k -s -X GET "${BASE}/list" \
  -H "access_token: ${TOKEN}" \
  -H "client_id: ${CLIENT}")
echo "$DBS" | jq '.databases[] | {name, fingerprint}'

# 3. Get first database fingerprint
DB_FP=$(echo "$DBS" | jq -r '.databases[0].fingerprint')
echo "Using database: ${DB_FP}"

# 4. List entries
echo -e "\n--- Entries in root folder:"
ENTRIES=$(curl -k -s -X GET "${BASE}/list?db=${DB_FP}" \
  -H "access_token: ${TOKEN}" \
  -H "client_id: ${CLIENT}")
echo "$ENTRIES" | jq '.entries[] | {name, login, url}'

# 5. Create a new entry
echo -e "\n--- Creating new entry..."
NEW=$(curl -k -s -X PUT "${BASE}/add?db=${DB_FP}" \
  -H "access_token: ${TOKEN}" \
  -H "client_id: ${CLIENT}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test Entry from curl",
    "login": "testuser",
    "password": "test123",
    "url": "https://test.example.com"
  }')
echo "Created: $(echo "$NEW" | jq -r '.name // "OK"')"

# 6. Search for the new entry
echo -e "\n--- Searching for 'testuser'..."
SEARCH=$(curl -k -s -X GET \
  "${BASE}/search?db=${DB_FP}&query=testuser" \
  -H "access_token: ${TOKEN}" \
  -H "client_id: ${CLIENT}")
echo "$SEARCH" | jq '.entries[] | {name, login}'

# 7. Logout
echo -e "\n--- Logging out..."
curl -k -s -X POST "${BASE}/logout" -H "client_id: ${CLIENT}"
echo "Done."
```
