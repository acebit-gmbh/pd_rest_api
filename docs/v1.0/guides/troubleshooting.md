# Troubleshooting

Common issues and solutions when working with the Password Depot REST API.

## Connection Issues

### Cannot Connect to Server

**Symptom:** Connection refused or timeout when accessing `https://server:8714/`

**Checklist:**

1. Verify the REST service is enabled in **Server Manager > Manage > Server Options > Connections > Supported Clients > Web Client**
2. Check that the server is running
3. Verify the correct port (default: `8714`, configurable in `pdserver.ini` via `PortREST`)
4. Check firewall rules -- port 8714 must be open for inbound HTTPS connections
5. Ensure you are using `https://` (not `http://`)

### SSL Certificate Errors

**Symptom:** `SSL certificate problem: unable to get local issuer certificate` or similar

**Cause:** Self-signed certificate or certificate mismatch.

**Solutions:**

=== "curl"

    ```bash
    # Skip certificate verification (development only)
    curl -k https://your-server:8714/v1.0/list

    # Or specify your CA bundle
    curl --cacert /path/to/ca-cert.pem https://your-server:8714/v1.0/list
    ```

=== "PowerShell 7+"

    ```powershell
    # Skip certificate verification
    Invoke-RestMethod -Uri "https://..." -SkipCertificateCheck
    ```

=== "PowerShell 5.1"

    ```powershell
    # Add this at the start of your script
    Add-Type @"
        using System.Net;
        using System.Security.Cryptography.X509Certificates;
        public class TrustAllCerts : ICertificatePolicy {
            public bool CheckValidationResult(
                ServicePoint sp, X509Certificate cert,
                WebRequest req, int problem) { return true; }
        }
    "@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCerts
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    ```

=== "Python"

    ```python
    import urllib3
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    # Skip verification
    requests.get("https://...", verify=False)

    # Or specify CA bundle
    requests.get("https://...", verify="/path/to/ca-cert.pem")
    ```

!!! warning
    Disabling SSL verification is acceptable for development and testing only. In production, always use a valid certificate and enable verification.

### Certificate Does Not Match Domain

**Symptom:** `SSL: CERTIFICATE_VERIFY_FAILED` even with a valid certificate

**Cause:** The certificate's `commonName` or `subjectAltName` does not match the hostname/IP you are connecting to.

**Solution:** Regenerate the certificate with the correct domain name and IP address using the **Create Certificate Wizard** in Server Manager, or obtain a certificate from a CA that covers your server's hostname.

## Authentication Issues

### 401 Unauthorized on Login

**Symptom:** Login returns `{"code": 401, "error": "..."}`

**Checklist:**

1. Verify username and password are correct
2. Ensure the user account is not locked or disabled
3. Check that the user has REST API access permissions
4. Verify the JSON body is correctly formatted:
   ```json
   {"user": "username", "pass": "password"}
   ```

### 401 Unauthorized on API Calls

**Symptom:** API calls return 401 after successful login

**Common causes:**

1. **Token expired** -- The `access_token` expires after 10 minutes of inactivity. Re-authenticate.
2. **Missing headers** -- Ensure both `access_token` and `client_id` are included in request headers.
3. **Wrong header names** -- Headers are case-sensitive: `access_token` and `client_id` (lowercase with underscore).

=== "curl"

    ```bash
    # Correct
    curl -H "access_token: abc123" -H "client_id: def456" ...

    # Wrong -- these will fail
    curl -H "Access-Token: abc123" ...
    curl -H "Authorization: Bearer abc123" ...
    ```

=== "PowerShell"

    ```powershell
    # Correct
    $headers = @{
        access_token = "abc123"
        client_id    = "def456"
    }

    # Wrong -- do not use Authorization header
    $headers = @{ Authorization = "Bearer abc123" }
    ```

### 403 Forbidden

**Symptom:** `{"code": 403, "error": "Forbidden"}`

**Cause:** The authenticated user does not have permission for the requested operation.

**Solution:** Check the `rights` field in database/entry responses. The user needs the appropriate permission character (e.g., `R` for read, `M` for modify, `I` for insert, `D` for delete). Contact your Password Depot administrator to adjust permissions.

## 2FA Issues

### 459 Response on Every Login

**Cause:** The user's 2FA secret was never confirmed. The QR code must be scanned and a valid code submitted to complete setup.

**Solution:** Follow the [Two-Factor Authentication Guide](two-factor-auth.md#scenario-1-first-time-2fa-setup-code-459) to complete the initial 2FA setup.

### Invalid 2FA Code

**Cause:** Code has expired (TOTP codes are valid for 30 seconds) or time synchronization issue.

**Solutions:**

1. Ensure the server and authenticator device have synchronized clocks
2. Generate a fresh code and submit immediately
3. If using automated TOTP generation, verify the secret is correct

## Request/Response Issues

### 400 Bad Request

**Symptom:** `{"code": 400, "error": "..."}`

**Common causes:**

1. **Unknown endpoint** -- Check the URL path
2. **Malformed JSON** -- Validate your JSON payload
3. **Missing required parameters** -- Check query parameters

```bash
# Validate JSON before sending
echo '{"user":"admin","pass":"test"}' | jq .
```

### 404 Not Found

**Symptom:** `{"code": 404, "error": "Not Found"}`

**Common causes:**

1. **Invalid fingerprint** -- Database, folder, or entry UUID does not exist
2. **Wrong database** -- The entry exists in a different database
3. **Deleted entry** -- The entry was deleted by another user/session

### Empty or Unexpected Response

**Checklist:**

1. Verify the `Content-Type: application/json` header is set on POST/PUT/DELETE requests
2. Ensure the request body is valid JSON
3. Check character encoding is UTF-8

## PowerShell-Specific Issues

### `Invoke-RestMethod` Returns HTML Instead of JSON

**Cause:** Typically happens when the server returns an error page instead of a JSON response.

**Solution:** Use `Invoke-WebRequest` instead to inspect the raw response:

```powershell
$response = Invoke-WebRequest -Uri "$BaseUri/list" `
    -Headers $headers

Write-Host "Status: $($response.StatusCode)"
Write-Host "Content-Type: $($response.Headers['Content-Type'])"
Write-Host "Body: $($response.Content)"
```

### `-SkipCertificateCheck` Not Recognized

**Cause:** Using Windows PowerShell 5.1, which does not support this parameter.

**Solution:** See the [PowerShell 5.1 SSL Workaround](../examples/powershell.md#windows-powershell-51-ssl-workaround) section, or upgrade to PowerShell 7+.

### JSON Serialization Issues

**Cause:** PowerShell may add extra properties or change types during serialization.

**Solution:** Use `-Depth` parameter with `ConvertTo-Json`:

```powershell
# Default depth is 2, which may truncate nested objects
$body = $complexObject | ConvertTo-Json -Depth 10
```

## curl-Specific Issues

### Special Characters in Passwords

**Cause:** Shell interprets special characters like `!`, `$`, `"`, `\`.

**Solution:** Use single quotes for the JSON body, or escape special characters:

```bash
# Use single quotes
curl -d '{"user":"admin","pass":"p@ss!word#123"}'

# Or escape with backslashes
curl -d "{\"user\":\"admin\",\"pass\":\"p@ss\\!word#123\"}"
```

## Getting Help

If you continue to experience issues:

1. Check the Password Depot Server logs for detailed error messages
2. Verify your server version is 18.0.0 or later
3. Contact AceBIT support at [password-depot.de](https://www.password-depot.de)
