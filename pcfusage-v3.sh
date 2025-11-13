#!/bin/bash
# ---------------------------------------------------------------------------
# Cloud Foundry Application Usage Reporter (v3 API)
# Gathers org/space/app/process metadata using CF v3 API
# Usage:
#   ./pcfusage-v3.sh <org_name> [--debug]
# ---------------------------------------------------------------------------

set -euo pipefail

ORG_NAME="${1:-}"
DEBUG="${2:-}"

if [ -z "$ORG_NAME" ]; then
  echo "Usage: $0 <org_name> [--debug]"
  exit 1
fi

if [ "$DEBUG" == "--debug" ]; then
  echo "🔍 Debug mode enabled"
fi

OUTFILE="pcfusage_${ORG_NAME}_$(date +%Y%m%d%H%M%S).csv"
echo "Org,Space,App,Process Type,Instances,Memory(MB),Disk(MB),State,Buildpacks,Routes" > "$OUTFILE"

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

function debug() {
  if [ "$DEBUG" == "--debug" ]; then
    echo "DEBUG: $*" >&2
  fi
}

function cf_curl_safe() {
  local endpoint="$1"
  debug "Calling: cf curl ${endpoint}"
  cf curl "${endpoint}" 2>/dev/null || echo "{}"
}

# ---------------------------------------------------------------------------
# Environment checks
# ---------------------------------------------------------------------------

for cmd in cf jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "❌ $cmd not found in PATH"; exit 1; }
done

if ! cf target >/dev/null 2>&1; then
  echo "❌ Not logged in to Cloud Foundry. Run 'cf login' first."
  exit 1
fi

# ---------------------------------------------------------------------------
# Get Org GUID
# ---------------------------------------------------------------------------

debug "Fetching org GUID for ${ORG_NAME}"
ORG_GUID=$(cf_curl_safe "/v3/organizations?names=${ORG_NAME}" | jq -r '.resources[0].guid // empty')

if [ -z "$ORG_GUID" ]; then
  echo "❌ Organization '${ORG_NAME}' not found."
  echo "Available orgs:"
  cf curl /v3/organizations | jq -r '.resources[].name'
  exit 1
fi
echo "✅ Organization: ${ORG_NAME} (${ORG_GUID})"

# ---------------------------------------------------------------------------
# List Spaces in Org
# ---------------------------------------------------------------------------

SPACES_JSON=$(cf_curl_safe "/v3/spaces?organization_guids=${ORG_GUID}")
SPACE_COUNT=$(echo "$SPACES_JSON" | jq -r '.pagination.total_results // 0')
echo "📦 Found ${SPACE_COUNT} space(s) in org '${ORG_NAME}'"

if [ "$SPACE_COUNT" -eq 0 ]; then
  echo "⚠️ No spaces found in org '${ORG_NAME}'"
  exit 0
fi

for SPACE_GUID in $(echo "$SPACES_JSON" | jq -r '.resources[].guid'); do
  SPACE_NAME=$(echo "$SPACES_JSON" | jq -r --arg guid "$SPACE_GUID" '.resources[] | select(.guid==$guid) | .name')
  echo "➡️  Processing space: ${SPACE_NAME} (${SPACE_GUID})"

  # -------------------------------------------------------------------------
  # List Apps in Space
  # -------------------------------------------------------------------------
  APPS_JSON=$(cf_curl_safe "/v3/apps?space_guids=${SPACE_GUID}")
  APP_COUNT=$(echo "$APPS_JSON" | jq -r '.pagination.total_results // 0')

  if [ "$APP_COUNT" -eq 0 ]; then
    echo "   ⚠️  No apps found in space '${SPACE_NAME}'"
    continue
  fi
  echo "   📱 Found ${APP_COUNT} app(s) in space '${SPACE_NAME}'"

  for APP_GUID in $(echo "$APPS_JSON" | jq -r '.resources[]?.guid'); do
    APP_NAME=$(echo "$APPS_JSON" | jq -r --arg guid "$APP_GUID" '.resources[] | select(.guid==$guid) | .name')
    APP_STATE=$(echo "$APPS_JSON" | jq -r --arg guid "$APP_GUID" '.resources[] | select(.guid==$guid) | .state')

    # Buildpacks
    BUILDPACKS=$(cf_curl_safe "/v3/apps/${APP_GUID}" | jq -r '.lifecycle.buildpacks // [] | join(";")')

    # Routes
    ROUTES=$(cf_curl_safe "/v3/routes?app_guids=${APP_GUID}" | jq -r '[.resources[].url] // [] | join(";")')

    # Processes (memory/disk/instances)
    PROCESSES_JSON=$(cf_curl_safe "/v3/processes?app_guids=${APP_GUID}")
    PROC_COUNT=$(echo "$PROCESSES_JSON" | jq -r '.pagination.total_results // 0')

    if [ "$PROC_COUNT" -eq 0 ]; then
      echo "      ⚠️  No processes for app '${APP_NAME}'"
      continue
    fi

    for row in $(echo "$PROCESSES_JSON" | jq -r '.resources[]? | @base64'); do
      _jq() { echo "$row" | base64 --decode | jq -r "$1"; }
      TYPE=$(_jq '.type')
      INSTANCES=$(_jq '.instances')
      MEM=$(_jq '.memory_in_mb')
      DISK=$(_jq '.disk_in_mb')
      echo "${ORG_NAME},${SPACE_NAME},${APP_NAME},${TYPE},${INSTANCES},${MEM},${DISK},${APP_STATE},${BUILDPACKS},${ROUTES}" >> "$OUTFILE"
    done
  done
done

echo
echo "✅ Report generated: ${OUTFILE}"
if [ "$DEBUG" == "--debug" ]; then
  echo "🔍 CSV preview:"
  head -n 10 "$OUTFILE"
fi

