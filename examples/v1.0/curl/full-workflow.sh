#!/bin/bash
#
# Password Depot REST API v1.0 - Complete Workflow Example
#
# Usage:
#   ./full-workflow.sh <SERVER> <USERNAME> <PASSWORD> [PORT]
#
# Example:
#   ./full-workflow.sh your-server.example.com admin my_password
#   ./full-workflow.sh 192.0.2.100 admin my_password 9000
#
# Requirements:
#   - curl
#   - jq (https://jqlang.github.io/jq/)

set -e

SERVER="${1:?Usage: $0 <SERVER> <USERNAME> <PASSWORD> [PORT]}"
USERNAME="${2:?Usage: $0 <SERVER> <USERNAME> <PASSWORD> [PORT]}"
PASSWORD="${3:?Usage: $0 <SERVER> <USERNAME> <PASSWORD> [PORT]}"
PORT="${4:-8714}"

BASE="https://${SERVER}:${PORT}/v1.0"

echo "============================================"
echo " Password Depot REST API - curl Workflow"
echo "============================================"

# ── 1. Login ──────────────────────────────────────────
echo -e "\n[1/6] Logging in..."

LOGIN=$(curl -k -s -X POST "${BASE}/login" \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${USERNAME}\",\"pass\":\"${PASSWORD}\"}")

TOKEN=$(echo "$LOGIN" | jq -r '.access_token')
CLIENT=$(echo "$LOGIN" | jq -r '.client_id')

if [ "$TOKEN" = "null" ] || [ -z "$TOKEN" ]; then
  echo "Login failed:"
  echo "$LOGIN" | jq .
  exit 1
fi

echo "  Logged in. Client ID: ${CLIENT}"

# Cleanup function to ensure logout
cleanup() {
  echo -e "\nLogging out..."
  curl -k -s -X POST "${BASE}/logout" -H "client_id: ${CLIENT}" > /dev/null
  echo "Done."
}
trap cleanup EXIT

# ── 2. List Databases ─────────────────────────────────
echo -e "\n[2/6] Listing databases..."

DBS=$(curl -k -s -X GET "${BASE}/list" \
  -H "access_token: ${TOKEN}" \
  -H "client_id: ${CLIENT}")

echo "$DBS" | jq -r '.databases[] | "  \(.name)  \(.fingerprint)"'

DB_FP=$(echo "$DBS" | jq -r '.databases[0].fingerprint')
DB_NAME=$(echo "$DBS" | jq -r '.databases[0].name')

if [ "$DB_FP" = "null" ]; then
  echo "No databases found."
  exit 0
fi

echo "  Using: ${DB_NAME}"

# ── 3. List Entries ───────────────────────────────────
echo -e "\n[3/6] Listing entries in root folder..."

ENTRIES=$(curl -k -s -X GET "${BASE}/list?db=${DB_FP}" \
  -H "access_token: ${TOKEN}" \
  -H "client_id: ${CLIENT}")

ENTRY_COUNT=$(echo "$ENTRIES" | jq '.entries | length')
echo "  Found ${ENTRY_COUNT} entries:"
echo "$ENTRIES" | jq -r '.entries[] | "  \(.name)\t\(.login)\t\(.url)"'

# ── 4. Create Entry ──────────────────────────────────
echo -e "\n[4/6] Creating a test entry..."

NEW_ENTRY=$(curl -k -s -X PUT "${BASE}/add?db=${DB_FP}" \
  -H "access_token: ${TOKEN}" \
  -H "client_id: ${CLIENT}" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"API Workflow Test - $(date '+%Y-%m-%d %H:%M')\",
    \"login\": \"workflow_test\",
    \"password\": \"test_password_$(date +%s)\",
    \"url\": \"https://test.example.com\"
  }")

echo "  Entry created."

# ── 5. Search ─────────────────────────────────────────
echo -e "\n[5/6] Searching for 'workflow_test'..."

SEARCH=$(curl -k -s -X GET \
  "${BASE}/search?db=${DB_FP}&query=workflow_test" \
  -H "access_token: ${TOKEN}" \
  -H "client_id: ${CLIENT}")

SEARCH_COUNT=$(echo "$SEARCH" | jq '.entries | length')
echo "  Found ${SEARCH_COUNT} matching entries:"
echo "$SEARCH" | jq -r '.entries[] | "  \(.name)\t\(.login)"'

# ── 6. Read Entry Details ─────────────────────────────
if [ "$SEARCH_COUNT" -gt 0 ]; then
  echo -e "\n[6/6] Reading first entry details..."
  ENTRY_FP=$(echo "$SEARCH" | jq -r '.entries[0].fingerprint')

  DETAIL=$(curl -k -s -X GET \
    "${BASE}/read?db=${DB_FP}&entry=${ENTRY_FP}" \
    -H "access_token: ${TOKEN}" \
    -H "client_id: ${CLIENT}")

  echo "$DETAIL" | jq .
fi

# Logout is handled by the trap
