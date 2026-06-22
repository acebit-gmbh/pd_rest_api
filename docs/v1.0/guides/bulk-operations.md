# Bulk Operations

This guide covers patterns for performing operations on multiple entries efficiently.

## Bulk Delete

The delete endpoint natively supports multiple entries in a single request:

=== "curl"

    ```bash
    curl -k -X DELETE "https://YOUR_SERVER:8714/v1.0/delete?db=${DB_FP}" \
      -H "access_token: ${TOKEN}" \
      -H "client_id: ${CLIENT}" \
      -H "Content-Type: application/json" \
      -d '{
        "reason": "Quarterly credential rotation",
        "entries": [
          "uuid-1",
          "uuid-2",
          "uuid-3"
        ]
      }'
    ```

=== "PowerShell"

    ```powershell
    # Collect fingerprints to delete
    $toDelete = $entries.entries |
        Where-Object { $_.name -like "*old*" } |
        ForEach-Object { $_.fingerprint }

    if ($toDelete.Count -gt 0) {
        $deleteBody = @{
            reason  = "Quarterly credential rotation"
            entries = @($toDelete)
        } | ConvertTo-Json

        Invoke-RestMethod `
            -Uri "$BaseUri/delete?db=$dbFingerprint" `
            -Method DELETE `
            -Headers $headers `
            -Body $deleteBody `
            -ContentType "application/json"

        Write-Host "Deleted $($toDelete.Count) entries."
    }
    ```

=== "Python"

    ```python
    # Collect fingerprints to delete
    to_delete = [
        e["fingerprint"] for e in entries.get("entries", [])
        if "old" in e["name"].lower()
    ]

    if to_delete:
        requests.delete(
            f"{BASE_URL}/delete",
            params={"db": db_fp},
            headers={**headers, "Content-Type": "application/json"},
            json={"reason": "Quarterly rotation", "entries": to_delete},
            verify=False
        )
        print(f"Deleted {len(to_delete)} entries.")
    ```

## Bulk Move

Move multiple entries to a target folder in a single request:

=== "PowerShell"

    ```powershell
    # Move all entries matching a pattern to a specific folder
    $toMove = $entries.entries |
        Where-Object { $_.url -like "*example.com*" } |
        ForEach-Object { $_.fingerprint }

    if ($toMove.Count -gt 0) {
        $moveBody = @{
            target  = $targetFolderFingerprint
            entries = @($toMove)
        } | ConvertTo-Json

        Invoke-RestMethod `
            -Uri "$BaseUri/move?db=$dbFingerprint" `
            -Method POST `
            -Headers $headers `
            -Body $moveBody `
            -ContentType "application/json"

        Write-Host "Moved $($toMove.Count) entries."
    }
    ```

=== "Python"

    ```python
    to_move = [
        e["fingerprint"] for e in entries.get("entries", [])
        if "example.com" in e.get("url", "")
    ]

    if to_move:
        requests.post(
            f"{BASE_URL}/move",
            params={"db": db_fp},
            headers={**headers, "Content-Type": "application/json"},
            json={"target": target_folder_fp, "entries": to_move},
            verify=False
        )
        print(f"Moved {len(to_move)} entries.")
    ```

## Bulk Create

The API creates one entry per request, so bulk creation requires multiple calls:

=== "PowerShell"

    ```powershell
    $entriesToCreate = @(
        @{ name = "Server 1"; login = "admin"; password = "pass1"; url = "https://srv1.local" },
        @{ name = "Server 2"; login = "admin"; password = "pass2"; url = "https://srv2.local" },
        @{ name = "Server 3"; login = "admin"; password = "pass3"; url = "https://srv3.local" }
    )

    foreach ($entry in $entriesToCreate) {
        $body = $entry | ConvertTo-Json
        Invoke-RestMethod `
            -Uri "$BaseUri/add?db=$dbFingerprint&parent=$folderFingerprint" `
            -Method PUT `
            -Headers $headers `
            -Body $body `
            -ContentType "application/json"

        Write-Host "Created: $($entry.name)"
    }
    ```

=== "Python"

    ```python
    entries_to_create = [
        {"name": "Server 1", "login": "admin", "password": "pass1", "url": "https://srv1.local"},
        {"name": "Server 2", "login": "admin", "password": "pass2", "url": "https://srv2.local"},
        {"name": "Server 3", "login": "admin", "password": "pass3", "url": "https://srv3.local"},
    ]

    for entry in entries_to_create:
        requests.put(
            f"{BASE_URL}/add",
            params={"db": db_fp, "parent": folder_fp},
            headers={**headers, "Content-Type": "application/json"},
            json=entry,
            verify=False
        )
        print(f"Created: {entry['name']}")
    ```

## Bulk Modify

Similarly, modify requires one request per entry:

=== "PowerShell"

    ```powershell
    # Rotate passwords for all entries in a folder
    $entries = Invoke-RestMethod `
        -Uri "$BaseUri/list?db=$dbFingerprint&folder=$folderFingerprint" `
        -Headers $headers

    foreach ($entry in $entries.entries) {
        $newPassword = -join ((65..90) + (97..122) + (48..57) |
            Get-Random -Count 20 | ForEach-Object { [char]$_ })

        $updates = @{ password = $newPassword } | ConvertTo-Json

        Invoke-RestMethod `
            -Uri "$BaseUri/modify?db=$dbFingerprint&entry=$($entry.fingerprint)" `
            -Method POST `
            -Headers $headers `
            -Body $updates `
            -ContentType "application/json"

        Write-Host "Rotated password for: $($entry.name)"
    }
    ```

## Import from CSV

A common use case is importing entries from a CSV file:

=== "PowerShell"

    ```powershell
    # CSV format: Name,Login,Password,URL
    $csvEntries = Import-Csv -Path "entries.csv"

    foreach ($row in $csvEntries) {
        $body = @{
            name     = $row.Name
            login    = $row.Login
            password = $row.Password
            url      = $row.URL
        } | ConvertTo-Json

        Invoke-RestMethod `
            -Uri "$BaseUri/add?db=$dbFingerprint" `
            -Method PUT `
            -Headers $headers `
            -Body $body `
            -ContentType "application/json"

        Write-Host "Imported: $($row.Name)"
    }

    Write-Host "Imported $($csvEntries.Count) entries."
    ```

=== "Python"

    ```python
    import csv

    with open("entries.csv", newline="") as f:
        reader = csv.DictReader(f)
        count = 0
        for row in reader:
            requests.put(
                f"{BASE_URL}/add",
                params={"db": db_fp},
                headers={**headers, "Content-Type": "application/json"},
                json={
                    "name": row["Name"],
                    "login": row["Login"],
                    "password": row["Password"],
                    "url": row["URL"]
                },
                verify=False
            )
            count += 1
            print(f"Imported: {row['Name']}")

    print(f"Imported {count} entries.")
    ```

## Token Refresh During Long Operations

!!! warning "Token Timeout"
    Remember that the access token expires after **10 minutes of inactivity**. For long-running bulk operations, implement token refresh logic.

=== "PowerShell"

    ```powershell
    $lastRequest = Get-Date

    function Invoke-PDRequest {
        param([string]$Uri, [string]$Method = "GET", [string]$Body)

        # Refresh token if more than 8 minutes since last request
        if (((Get-Date) - $script:lastRequest).TotalMinutes -gt 8) {
            Write-Host "Refreshing token..."
            $script:login = Invoke-RestMethod -Uri "$BaseUri/login" -Method POST `
                -Body (@{ user = $Username; pass = $Password } | ConvertTo-Json) `
                -ContentType "application/json"
            $script:headers = @{
                access_token = $script:login.access_token
                client_id    = $script:login.client_id
            }
        }

        $script:lastRequest = Get-Date

        $params = @{
            Uri     = $Uri
            Method  = $Method
            Headers = $script:headers
        }
        if ($Body) {
            $params.Body = $Body
            $params.ContentType = "application/json"
        }

        return Invoke-RestMethod @params
    }
    ```
