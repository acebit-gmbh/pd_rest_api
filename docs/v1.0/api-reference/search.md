# Search

## Search Entries

Search for entries matching a query string within a database.

| | |
|---|---|
| **Endpoint** | `GET /v1.0/search` |
| **Auth required** | Yes |

### Query Parameters

| Parameter | Type | Required | Description |
|-----------|------|:--------:|-------------|
| `db` | string (UUID) | Yes | Database fingerprint |
| `query` | string | Yes | Search term |
| `parent` | string (UUID) | No | Restrict search to a specific folder |

### Request Examples

=== "curl"

    ```bash
    # Search entire database
    curl -k -X GET \
      "https://your-server:8714/v1.0/search?db=DB_FINGERPRINT&query=example" \
      -H "access_token: YOUR_ACCESS_TOKEN" \
      -H "client_id: YOUR_CLIENT_ID"

    # Search within a specific folder
    curl -k -X GET \
      "https://your-server:8714/v1.0/search?db=DB_FINGERPRINT&query=example&parent=FOLDER_FP" \
      -H "access_token: YOUR_ACCESS_TOKEN" \
      -H "client_id: YOUR_CLIENT_ID"
    ```

=== "PowerShell"

    ```powershell
    # Search entire database
    $searchTerm = "example"
    $results = Invoke-RestMethod `
      -Uri "https://your-server:8714/v1.0/search?db=$dbFingerprint&query=$searchTerm" `
      -Headers $headers

    $results.entries | Format-Table name, login, url

    # Search within a specific folder
    $results = Invoke-RestMethod `
      -Uri "https://your-server:8714/v1.0/search?db=$dbFingerprint&query=$searchTerm&parent=$folderFp" `
      -Headers $headers
    ```

=== "Python"

    ```python
    # Search entire database
    response = requests.get(
        "https://your-server:8714/v1.0/search",
        params={"db": db_fingerprint, "query": "example"},
        headers=headers,
        verify=False
    )
    results = response.json()

    for entry in results.get("entries", []):
        print(f"{entry['name']} - {entry['login']} - {entry['url']}")
    ```

### Success Response

**Status:** `200 OK`

Returns results in the same format as the [entry list](entries.md#list-entries) endpoint:

```json
{
  "name": "Search Results",
  "parent": "",
  "entries": [
    {
      "name": "Example Entry",
      "fingerprint": "660e8400-e29b-41d4-a716-446655440001",
      "rights": "RMID",
      "itemclass": "0",
      "login": "user1",
      "url": "http://example.com",
      "date": "2021-07-05T10:39:50.000Z",
      "icon": "ico0.png",
      "hash": ""
    }
  ],
  "infoclasses": "000007FF",
  "reasondelete": "1"
}
```

### Error Responses

| Code | Description |
|------|-------------|
| `401` | Access token is invalid or expired |
| `404` | Database or parent folder not found |

### Tips

!!! tip "URL-encode the search term"
    If your search term contains special characters, make sure to URL-encode it. Most HTTP client libraries handle this automatically.

!!! tip "Search scope"
    Use the `parent` parameter to narrow search results to a specific folder. This can significantly improve search performance on large databases.
