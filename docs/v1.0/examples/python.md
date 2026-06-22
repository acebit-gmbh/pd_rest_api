# Python Examples

Complete Python examples for all Password Depot REST API v1.0 endpoints.

!!! info "Prerequisites"
    - Python 3.7+
    - `requests` library: `pip install requests`
    - Replace `YOUR_SERVER` with your Password Depot Server address

!!! warning "SSL Verification"
    Examples use `verify=False` for self-signed certificates. For production, use `verify=True` (or omit it) with a valid CA-signed certificate, or point `verify` to your CA bundle file.

## Setup

```python
import requests
import json
import urllib3

# Suppress SSL warnings when using self-signed certificates
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

BASE_URL = "https://YOUR_SERVER:8714/v1.0"
VERIFY_SSL = False  # Set to True with a valid CA certificate
```

## Authentication

!!! warning "Legacy Servers (prior to v18.0.0)"
    The examples below pass login credentials as a JSON request body, which requires **v18.0.0 or later**. For older servers, credentials (`user`, `pass`, `tfacode`) must be passed as custom HTTP headers instead. See the [API Reference: Authentication](../api-reference/authentication.md) for legacy examples.

### Login

```python
def login(base_url, username, password, tfa_code=None):
    """Authenticate and return session headers."""
    payload = {"user": username, "pass": password}
    if tfa_code:
        payload["tfacode"] = tfa_code

    response = requests.post(
        f"{base_url}/login",
        json=payload,
        verify=VERIFY_SSL
    )
    response.raise_for_status()
    data = response.json()

    return {
        "access_token": data["access_token"],
        "client_id": data["client_id"]
    }


# Usage
headers = login(BASE_URL, "admin", "my_password")
print(f"Logged in. Client ID: {headers['client_id']}")
```

### Logout

```python
def logout(base_url, headers):
    """End the current session."""
    requests.post(
        f"{base_url}/logout",
        headers={"client_id": headers["client_id"]},
        verify=VERIFY_SSL
    )
    print("Logged out.")


# Usage
logout(BASE_URL, headers)
```

## Databases

### List All Databases

```python
def list_databases(base_url, headers):
    """Return all databases available to the user."""
    response = requests.get(
        f"{base_url}/list",
        headers=headers,
        verify=VERIFY_SSL
    )
    response.raise_for_status()
    return response.json()


# Usage
result = list_databases(BASE_URL, headers)
for db in result["databases"]:
    print(f"  {db['name']}  ({db['fingerprint']})")
```

## Entries

### List Entries

```python
def list_entries(base_url, headers, db_fingerprint, folder_fingerprint=None):
    """List entries in a database folder."""
    params = {"db": db_fingerprint}
    if folder_fingerprint:
        params["folder"] = folder_fingerprint

    response = requests.get(
        f"{base_url}/list",
        params=params,
        headers=headers,
        verify=VERIFY_SSL
    )
    response.raise_for_status()
    return response.json()


# Usage
db_fp = result["databases"][0]["fingerprint"]
entries = list_entries(BASE_URL, headers, db_fp)
for entry in entries.get("entries", []):
    print(f"  {entry['name']}  login={entry['login']}  url={entry['url']}")
```

### Read Entry Details

```python
def read_entry(base_url, headers, db_fingerprint, entry_fingerprint):
    """Read all attributes of an entry."""
    response = requests.get(
        f"{base_url}/read",
        params={"db": db_fingerprint, "entry": entry_fingerprint},
        headers=headers,
        verify=VERIFY_SSL
    )
    response.raise_for_status()
    return response.json()


# Usage
entry_fp = entries["entries"][0]["fingerprint"]
detail = read_entry(BASE_URL, headers, db_fp, entry_fp)
print(json.dumps(detail, indent=2))
```

### Create a New Entry

```python
def create_entry(base_url, headers, db_fingerprint, entry_data, parent=None):
    """Create a new entry in the database."""
    params = {"db": db_fingerprint}
    if parent:
        params["parent"] = parent

    response = requests.put(
        f"{base_url}/add",
        params=params,
        headers={**headers, "Content-Type": "application/json"},
        json=entry_data,
        verify=VERIFY_SSL
    )
    response.raise_for_status()
    return response.json()


# Usage
new_entry = create_entry(BASE_URL, headers, db_fp, {
    "name": "My Python Entry",
    "login": "pyuser@example.com",
    "password": "secure_password",
    "url": "https://example.com"
})
print(f"Created: {new_entry.get('name', 'OK')}")
```

### Modify an Entry

```python
def modify_entry(base_url, headers, db_fingerprint, entry_fingerprint, updates):
    """Update attributes of an existing entry."""
    response = requests.post(
        f"{base_url}/modify",
        params={"db": db_fingerprint, "entry": entry_fingerprint},
        headers={**headers, "Content-Type": "application/json"},
        json=updates,
        verify=VERIFY_SSL
    )
    response.raise_for_status()


# Usage
modify_entry(BASE_URL, headers, db_fp, entry_fp, {
    "name": "Updated Entry",
    "password": "new_password_456"
})
print("Entry updated.")
```

## Search

```python
def search_entries(base_url, headers, db_fingerprint, query, parent=None):
    """Search for entries matching a query."""
    params = {"db": db_fingerprint, "query": query}
    if parent:
        params["parent"] = parent

    response = requests.get(
        f"{base_url}/search",
        params=params,
        headers=headers,
        verify=VERIFY_SSL
    )
    response.raise_for_status()
    return response.json()


# Usage
results = search_entries(BASE_URL, headers, db_fp, "example")
for entry in results.get("entries", []):
    print(f"  {entry['name']}  login={entry['login']}")
```

## Delete

```python
def delete_entries(base_url, headers, db_fingerprint, entry_fingerprints, reason=""):
    """Delete one or more entries."""
    response = requests.delete(
        f"{base_url}/delete",
        params={"db": db_fingerprint},
        headers={**headers, "Content-Type": "application/json"},
        json={"reason": reason, "entries": entry_fingerprints},
        verify=VERIFY_SSL
    )
    response.raise_for_status()


# Usage
delete_entries(BASE_URL, headers, db_fp,
    ["entry-uuid-1", "entry-uuid-2"],
    reason="No longer needed"
)
print("Entries deleted.")
```

## Move

```python
def move_entries(base_url, headers, db_fingerprint, target_folder, entry_fingerprints):
    """Move entries to a target folder."""
    response = requests.post(
        f"{base_url}/move",
        params={"db": db_fingerprint},
        headers={**headers, "Content-Type": "application/json"},
        json={"target": target_folder, "entries": entry_fingerprints},
        verify=VERIFY_SSL
    )
    response.raise_for_status()


# Usage
move_entries(BASE_URL, headers, db_fp,
    "target-folder-uuid",
    ["entry-uuid-1", "entry-uuid-2"]
)
print("Entries moved.")
```

## Complete Workflow

```python
"""
Password Depot REST API - Complete Python Workflow
Usage: python workflow.py
"""
import requests
import json
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

SERVER = "YOUR_SERVER"
PORT = 8714
BASE_URL = f"https://{SERVER}:{PORT}/v1.0"
VERIFY_SSL = False

def main():
    print("=== Password Depot REST API - Python Workflow ===\n")

    # 1. Login
    print("--- Logging in...")
    response = requests.post(f"{BASE_URL}/login",
        json={"user": "admin", "pass": "my_password"},
        verify=VERIFY_SSL)
    response.raise_for_status()
    creds = response.json()
    headers = {
        "access_token": creds["access_token"],
        "client_id": creds["client_id"]
    }
    print(f"Logged in. Client ID: {creds['client_id']}")

    try:
        # 2. List databases
        print("\n--- Databases:")
        response = requests.get(f"{BASE_URL}/list",
            headers=headers, verify=VERIFY_SSL)
        dbs = response.json()
        for db in dbs["databases"]:
            print(f"  {db['name']}  ({db['fingerprint']})")

        # 3. List entries
        db_fp = dbs["databases"][0]["fingerprint"]
        print(f"\n--- Entries in '{dbs['databases'][0]['name']}':")
        response = requests.get(f"{BASE_URL}/list",
            params={"db": db_fp}, headers=headers, verify=VERIFY_SSL)
        entries = response.json()
        for entry in entries.get("entries", []):
            print(f"  {entry['name']}  login={entry['login']}  url={entry['url']}")

        # 4. Create entry
        print("\n--- Creating new entry...")
        response = requests.put(f"{BASE_URL}/add",
            params={"db": db_fp},
            headers={**headers, "Content-Type": "application/json"},
            json={
                "name": "Test Entry from Python",
                "login": "pyuser",
                "password": "py_test_123",
                "url": "https://test.example.com"
            },
            verify=VERIFY_SSL)
        print("Entry created.")

        # 5. Search
        print("\n--- Searching for 'pyuser'...")
        response = requests.get(f"{BASE_URL}/search",
            params={"db": db_fp, "query": "pyuser"},
            headers=headers, verify=VERIFY_SSL)
        results = response.json()
        for entry in results.get("entries", []):
            print(f"  {entry['name']}  login={entry['login']}")

    finally:
        # 6. Always logout
        print("\n--- Logging out...")
        requests.post(f"{BASE_URL}/logout",
            headers={"client_id": creds["client_id"]},
            verify=VERIFY_SSL)
        print("Done.")


if __name__ == "__main__":
    main()
```

## Standalone Client Library

A reusable Python client class is available at [`examples/python/pd_client.py`](https://github.com/acebit-gmbh/pd_rest_api/tree/main/examples/v1.0/python/pd_client.py). See the [standalone scripts section](../examples/python.md) for usage.
