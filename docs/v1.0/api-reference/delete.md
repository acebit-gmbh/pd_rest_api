# Delete

## Delete Entries

Deletes one or more entries from a database.

| | |
|---|---|
| **Endpoint** | `DELETE /v1.0/delete` |
| **Auth required** | Yes |
| **Content-Type** | `application/json` |

### Query Parameters

| Parameter | Type | Required | Description |
|-----------|------|:--------:|-------------|
| `db` | string (UUID) | Yes | Database fingerprint |

### Request Body

| Field | Type | Required | Description |
|-------|------|:--------:|-------------|
| `reason` | string | Conditional | Reason for deletion. Required if the database has `reasondelete` set to `"1"`. |
| `entries` | array of strings | Yes | List of entry fingerprints (UUIDs) to delete |

### Request Examples

=== "curl"

    ```bash
    curl -k -X DELETE \
      "https://your-server:8714/v1.0/delete?db=DB_FINGERPRINT" \
      -H "access_token: YOUR_ACCESS_TOKEN" \
      -H "client_id: YOUR_CLIENT_ID" \
      -H "Content-Type: application/json" \
      -d '{
        "reason": "Credentials rotated",
        "entries": [
          "550e8400-e29b-41d4-a716-446655440000",
          "660e8400-e29b-41d4-a716-446655440001"
        ]
      }'
    ```

=== "PowerShell"

    ```powershell
    $deleteBody = @{
        reason  = "Credentials rotated"
        entries = @(
            "550e8400-e29b-41d4-a716-446655440000",
            "660e8400-e29b-41d4-a716-446655440001"
        )
    } | ConvertTo-Json

    Invoke-RestMethod `
      -Uri "https://your-server:8714/v1.0/delete?db=$dbFingerprint" `
      -Method DELETE `
      -Headers $headers `
      -Body $deleteBody `
      -ContentType "application/json"
    ```

=== "Python"

    ```python
    delete_data = {
        "reason": "Credentials rotated",
        "entries": [
            "550e8400-e29b-41d4-a716-446655440000",
            "660e8400-e29b-41d4-a716-446655440001"
        ]
    }

    requests.delete(
        f"https://your-server:8714/v1.0/delete?db={db_fingerprint}",
        headers={**headers, "Content-Type": "application/json"},
        json=delete_data,
        verify=False
    )
    ```

### Success Response

**Status:** `200 OK`

### Error Responses

| Code | Description |
|------|-------------|
| `401` | Access token is invalid or expired |
| `403` | Insufficient permissions to delete entries |
| `404` | Database or one or more entries not found |

### Notes

!!! warning "Deletion Reason"
    Check the `reasondelete` field in the [database listing](databases.md) response. If set to `"1"`, the `reason` field is mandatory in the delete request.

!!! tip "Bulk Deletion"
    You can delete multiple entries in a single request by including all their fingerprints in the `entries` array. See [Bulk Operations](../guides/bulk-operations.md) for more patterns.
