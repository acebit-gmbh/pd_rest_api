# Move

## Move Entries

Moves one or more entries to a target folder within the same database.

| | |
|---|---|
| **Endpoint** | `POST /v1.0/move` |
| **Auth required** | Yes |
| **Content-Type** | `application/json` |

### Query Parameters

| Parameter | Type | Required | Description |
|-----------|------|:--------:|-------------|
| `db` | string (UUID) | Yes | Database fingerprint |

### Request Body

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `target` | string (UUID) | Yes | Target folder fingerprint |
| `entries` | array of strings | Yes | List of entry fingerprints (UUIDs) to move |

### Request Examples

=== "curl"

    ```bash
    curl -k -X POST \
      "https://your-server:8714/v1.0/move?db=DB_FINGERPRINT" \
      -H "access_token: YOUR_ACCESS_TOKEN" \
      -H "client_id: YOUR_CLIENT_ID" \
      -H "Content-Type: application/json" \
      -d '{
        "target": "770e8400-e29b-41d4-a716-446655440002",
        "entries": [
          "550e8400-e29b-41d4-a716-446655440000",
          "660e8400-e29b-41d4-a716-446655440001"
        ]
      }'
    ```

=== "PowerShell"

    ```powershell
    $moveBody = @{
        target  = "770e8400-e29b-41d4-a716-446655440002"
        entries = @(
            "550e8400-e29b-41d4-a716-446655440000",
            "660e8400-e29b-41d4-a716-446655440001"
        )
    } | ConvertTo-Json

    Invoke-RestMethod `
      -Uri "https://your-server:8714/v1.0/move?db=$dbFingerprint" `
      -Method POST `
      -Headers $headers `
      -Body $moveBody `
      -ContentType "application/json"
    ```

=== "Python"

    ```python
    move_data = {
        "target": "770e8400-e29b-41d4-a716-446655440002",
        "entries": [
            "550e8400-e29b-41d4-a716-446655440000",
            "660e8400-e29b-41d4-a716-446655440001"
        ]
    }

    requests.post(
        f"https://your-server:8714/v1.0/move?db={db_fingerprint}",
        headers={**headers, "Content-Type": "application/json"},
        json=move_data,
        verify=False
    )
    ```

### Success Response

**Status:** `200 OK`

### Error Responses

| Code | Description |
|------|-------------|
| `401` | Access token is invalid or expired |
| `403` | Insufficient permissions to move entries |
| `404` | Database, target folder, or entries not found |

### Notes

!!! tip "Finding Folder Fingerprints"
    Folder fingerprints can be found in the [entry list](entries.md#list-entries) response. Entries with sub-entries are folders. Use the `parent` field to navigate the folder hierarchy.

!!! tip "Bulk Move"
    You can move multiple entries to the same target folder in a single request. See [Bulk Operations](../guides/bulk-operations.md) for patterns.
