"""
Password Depot REST API v1.0 - Python Client Library

A reusable client class for interacting with the Password Depot Enterprise
Server REST API.

Usage:
    from pd_client import PDClient

    client = PDClient("your-server")
    client.login("admin", "my_password")

    databases = client.list_databases()
    entries = client.list_entries(databases[0]["fingerprint"])

    client.logout()

    # Or use as context manager:
    with PDClient("your-server") as client:
        client.login("admin", "my_password")
        databases = client.list_databases()
"""

import requests
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


class PDClientError(Exception):
    """Exception raised for API errors."""

    def __init__(self, code, message):
        self.code = code
        self.message = message
        super().__init__(f"[{code}] {message}")


class TFASetupRequired(PDClientError):
    """Raised when 2FA setup is needed (code 459)."""

    def __init__(self, qr_url):
        self.qr_url = qr_url
        super().__init__(459, f"2FA setup required. QR code: {qr_url}")


class TFACodeRequired(PDClientError):
    """Raised when a 2FA code is needed (code 460)."""

    def __init__(self, message):
        super().__init__(460, message)


class PDClient:
    """Client for the Password Depot Enterprise Server REST API v1.0."""

    def __init__(self, server, port=8714, verify_ssl=False):
        """
        Initialize the client.

        Args:
            server: Hostname or IP address of the Password Depot Server.
            port: REST service port (default: 8714).
            verify_ssl: Whether to verify SSL certificates (default: False).
        """
        self.base_url = f"https://{server}:{port}/v1.0"
        self.verify_ssl = verify_ssl
        self.access_token = None
        self.client_id = None

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        if self.client_id:
            try:
                self.logout()
            except Exception:
                pass

    @property
    def _headers(self):
        """Return authentication headers."""
        if not self.access_token:
            raise PDClientError(401, "Not authenticated. Call login() first.")
        return {
            "access_token": self.access_token,
            "client_id": self.client_id,
        }

    def _handle_response(self, response):
        """Check response and raise appropriate exceptions."""
        if response.status_code == 200:
            try:
                return response.json()
            except ValueError:
                return None

        try:
            data = response.json()
        except ValueError:
            raise PDClientError(response.status_code, response.text)

        code = data.get("code", response.status_code)
        error = data.get("error", "Unknown error")

        if str(code) == "459":
            raise TFASetupRequired(error)
        if str(code) == "460":
            raise TFACodeRequired(error)

        raise PDClientError(code, error)

    def login(self, username, password, tfa_code=None):
        """
        Authenticate with the server.

        Args:
            username: User name.
            password: Password.
            tfa_code: Optional 6-digit 2FA code.

        Returns:
            dict with access_token and client_id.

        Raises:
            TFASetupRequired: If 2FA needs initial setup (code 459).
            TFACodeRequired: If a 2FA code is needed (code 460).
            PDClientError: On other errors.
        """
        payload = {"user": username, "pass": password}
        if tfa_code:
            payload["tfacode"] = tfa_code

        response = requests.post(
            f"{self.base_url}/login",
            json=payload,
            verify=self.verify_ssl,
        )

        data = self._handle_response(response)
        self.access_token = data["access_token"]
        self.client_id = data["client_id"]
        return data

    def login_oidc(self, idp, id_token):
        """
        Authenticate using OIDC/Azure identity provider.

        Args:
            idp: Identity Provider ID.
            id_token: OIDC/Azure token.

        Returns:
            dict with access_token and client_id.
        """
        response = requests.post(
            f"{self.base_url}/login",
            json={"idp": idp, "id_token": id_token},
            verify=self.verify_ssl,
        )

        data = self._handle_response(response)
        self.access_token = data["access_token"]
        self.client_id = data["client_id"]
        return data

    def logout(self):
        """End the current session."""
        response = requests.post(
            f"{self.base_url}/logout",
            headers={"client_id": self.client_id},
            verify=self.verify_ssl,
        )
        self.access_token = None
        self.client_id = None

    def list_databases(self):
        """
        List all databases available to the authenticated user.

        Returns:
            dict with 'databases' list and policy information.
        """
        response = requests.get(
            f"{self.base_url}/list",
            headers=self._headers,
            verify=self.verify_ssl,
        )
        return self._handle_response(response)

    def list_entries(self, db_fingerprint, folder_fingerprint=None):
        """
        List entries in a database folder.

        Args:
            db_fingerprint: Database UUID.
            folder_fingerprint: Optional folder UUID (default: root folder).

        Returns:
            dict with folder info and 'entries' list.
        """
        params = {"db": db_fingerprint}
        if folder_fingerprint:
            params["folder"] = folder_fingerprint

        response = requests.get(
            f"{self.base_url}/list",
            params=params,
            headers=self._headers,
            verify=self.verify_ssl,
        )
        return self._handle_response(response)

    def read_entry(self, db_fingerprint, entry_fingerprint):
        """
        Read all attributes of an entry.

        Args:
            db_fingerprint: Database UUID.
            entry_fingerprint: Entry UUID.

        Returns:
            dict with all entry fields.
        """
        response = requests.get(
            f"{self.base_url}/read",
            params={"db": db_fingerprint, "entry": entry_fingerprint},
            headers=self._headers,
            verify=self.verify_ssl,
        )
        return self._handle_response(response)

    def create_entry(self, db_fingerprint, entry_data, parent_fingerprint=None):
        """
        Create a new entry.

        Args:
            db_fingerprint: Database UUID.
            entry_data: dict with entry attributes (name, login, password, url, etc.).
            parent_fingerprint: Optional parent folder UUID (default: root).

        Returns:
            dict with created entry data.
        """
        params = {"db": db_fingerprint}
        if parent_fingerprint:
            params["parent"] = parent_fingerprint

        response = requests.put(
            f"{self.base_url}/add",
            params=params,
            headers={**self._headers, "Content-Type": "application/json"},
            json=entry_data,
            verify=self.verify_ssl,
        )
        return self._handle_response(response)

    def modify_entry(self, db_fingerprint, entry_fingerprint, updates):
        """
        Update attributes of an existing entry.

        Args:
            db_fingerprint: Database UUID.
            entry_fingerprint: Entry UUID.
            updates: dict with attributes to update.
        """
        response = requests.post(
            f"{self.base_url}/modify",
            params={"db": db_fingerprint, "entry": entry_fingerprint},
            headers={**self._headers, "Content-Type": "application/json"},
            json=updates,
            verify=self.verify_ssl,
        )
        return self._handle_response(response)

    def search(self, db_fingerprint, query, parent_fingerprint=None):
        """
        Search for entries matching a query.

        Args:
            db_fingerprint: Database UUID.
            query: Search string.
            parent_fingerprint: Optional folder UUID to restrict search.

        Returns:
            dict with 'entries' list.
        """
        params = {"db": db_fingerprint, "query": query}
        if parent_fingerprint:
            params["parent"] = parent_fingerprint

        response = requests.get(
            f"{self.base_url}/search",
            params=params,
            headers=self._headers,
            verify=self.verify_ssl,
        )
        return self._handle_response(response)

    def delete_entries(self, db_fingerprint, entry_fingerprints, reason=""):
        """
        Delete one or more entries.

        Args:
            db_fingerprint: Database UUID.
            entry_fingerprints: List of entry UUIDs to delete.
            reason: Optional reason for deletion.
        """
        response = requests.delete(
            f"{self.base_url}/delete",
            params={"db": db_fingerprint},
            headers={**self._headers, "Content-Type": "application/json"},
            json={"reason": reason, "entries": entry_fingerprints},
            verify=self.verify_ssl,
        )
        return self._handle_response(response)

    def move_entries(self, db_fingerprint, target_folder, entry_fingerprints):
        """
        Move entries to a target folder.

        Args:
            db_fingerprint: Database UUID.
            target_folder: Target folder UUID.
            entry_fingerprints: List of entry UUIDs to move.
        """
        response = requests.post(
            f"{self.base_url}/move",
            params={"db": db_fingerprint},
            headers={**self._headers, "Content-Type": "application/json"},
            json={"target": target_folder, "entries": entry_fingerprints},
            verify=self.verify_ssl,
        )
        return self._handle_response(response)


# ── Example usage ─────────────────────────────────────

if __name__ == "__main__":
    import sys

    if len(sys.argv) < 4:
        print(f"Usage: python {sys.argv[0]} <SERVER> <USERNAME> <PASSWORD> [PORT]")
        sys.exit(1)

    server = sys.argv[1]
    username = sys.argv[2]
    password = sys.argv[3]
    port = int(sys.argv[4]) if len(sys.argv) > 4 else 8714

    print("=== Password Depot REST API - Python Client ===\n")

    with PDClient(server, port) as client:
        # Login
        print("Logging in...")
        creds = client.login(username, password)
        print(f"  Client ID: {creds['client_id']}")

        # List databases
        print("\nDatabases:")
        result = client.list_databases()
        for db in result["databases"]:
            print(f"  {db['name']}  ({db['fingerprint']})")

        if not result["databases"]:
            print("  No databases found.")
            sys.exit(0)

        db_fp = result["databases"][0]["fingerprint"]

        # List entries
        print(f"\nEntries in '{result['databases'][0]['name']}':")
        entries = client.list_entries(db_fp)
        for entry in entries.get("entries", []):
            print(f"  {entry['name']}  login={entry['login']}  url={entry['url']}")

        # Create entry
        print("\nCreating test entry...")
        client.create_entry(db_fp, {
            "name": "Python API Test",
            "login": "pytest_user",
            "password": "test_password_123",
            "url": "https://test.example.com",
        })
        print("  Entry created.")

        # Search
        print("\nSearching for 'pytest_user'...")
        results = client.search(db_fp, "pytest_user")
        for entry in results.get("entries", []):
            print(f"  {entry['name']}  login={entry['login']}")

    print("\nDone.")
