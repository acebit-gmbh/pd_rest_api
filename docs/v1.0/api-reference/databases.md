# Databases

## List Databases

Returns all databases available to the authenticated user, along with server password policy settings.

| | |
|---|---|
| **Endpoint** | `GET /v1.0/list` |
| **Auth required** | Yes |

### Required Headers

| Header | Description |
|--------|-------------|
| `access_token` | Access token from login |
| `client_id` | Client ID from login |

### Request Examples

=== "curl"

    ```bash
    curl -k -X GET "https://your-server:8714/v1.0/list" \
      -H "access_token: YOUR_ACCESS_TOKEN" \
      -H "client_id: YOUR_CLIENT_ID"
    ```

=== "PowerShell"

    ```powershell
    $headers = @{
        access_token = $login.access_token
        client_id    = $login.client_id
    }

    $result = Invoke-RestMethod `
      -Uri "https://your-server:8714/v1.0/list" `
      -Headers $headers

    # Display databases
    $result.databases | Format-Table name, fingerprint, date, rights
    ```

=== "Python"

    ```python
    headers = {
        "access_token": token,
        "client_id": client_id
    }

    response = requests.get(
        "https://your-server:8714/v1.0/list",
        headers=headers,
        verify=False
    )
    databases = response.json()
    ```

### Success Response

**Status:** `200 OK`

```json
{
  "databases": [
    {
      "name": "db_1.pswe",
      "fingerprint": "550e8400-e29b-41d4-a716-446655440000",
      "date": "2020-12-09T11:12:45.202Z",
      "rights": "RMIDCFAPE-Y-HL",
      "reasondelete": "1"
    },
    {
      "name": "db_2.pswe",
      "fingerprint": "660e8400-e29b-41d4-a716-446655440001",
      "date": "2023-01-15T08:30:00.000Z",
      "rights": "RM----------",
      "reasondelete": "0"
    }
  ],
  "infoclasses": "000007FF",
  "policyforce": "1",
  "policyminlength": "10",
  "policyincludeatleast": "0",
  "policymingroups": "3",
  "policyselectedgroups": "15"
}
```

### Response Fields

#### Database Object

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Database filename (e.g., `db_1.pswe`) |
| `fingerprint` | string (UUID) | Unique database identifier. Use this in subsequent API calls. |
| `date` | string (ISO 8601) | Last modification timestamp |
| `rights` | string | User's permission string for this database (see [permissions](overview.md#permission-strings)) |
| `reasondelete` | string | Whether a reason is required when deleting entries (`"1"` = yes, `"0"` = no) |

#### Password Policy Fields

These fields reflect the server's password policy configuration:

| Field | Type | Description |
|-------|------|-------------|
| `infoclasses` | string | Bitmask of available information classes (hex) |
| `policyforce` | string | Whether password policy is enforced (`"1"` = enforced) |
| `policyminlength` | string | Minimum password length |
| `policyincludeatleast` | string | Minimum number of required character types |
| `policymingroups` | string | Minimum number of character groups required |
| `policyselectedgroups` | string | Bitmask of selected character groups |

### Error Responses

| Code | Description |
|------|-------------|
| `401` | Access token is invalid or expired |
