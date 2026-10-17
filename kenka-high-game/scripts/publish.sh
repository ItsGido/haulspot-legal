#!/usr/bin/env bash
# Builds the place and publishes it to Roblox with the Open Cloud Place Publishing API.
#
# One-time setup (Creator Hub):
#   1. Create the experience (or open it in Studio once and publish) and note its Universe ID and Place ID
#      (Creator Hub > Creations > the experience > the "..." menu > Copy Universe ID / open the place for its Place ID).
#   2. Create an API key: Creator Hub > Open Cloud > API Keys > Create API Key.
#      Access permissions: "universe-places" with "Write", restricted to this experience.
#   3. Export them before running:
#        export ROBLOX_API_KEY=...        # never commit this
#        export ROBLOX_UNIVERSE_ID=1234567890
#        export ROBLOX_PLACE_ID=9876543210
#
# Usage:
#   scripts/publish.sh            # publishes (live servers update on restart)
#   scripts/publish.sh --saved    # saves a new version without publishing it
set -euo pipefail
cd "$(dirname "$0")/.."

: "${ROBLOX_API_KEY:?Set ROBLOX_API_KEY (see the comments at the top of this script)}"
: "${ROBLOX_UNIVERSE_ID:?Set ROBLOX_UNIVERSE_ID}"
: "${ROBLOX_PLACE_ID:?Set ROBLOX_PLACE_ID}"

VERSION_TYPE="Published"
if [ "${1:-}" = "--saved" ]; then
  VERSION_TYPE="Saved"
fi

echo "== Checking before publishing"
scripts/check.sh

echo "== Uploading build/KenkaHigh.rbxl as a ${VERSION_TYPE} version"
response=$(curl -sS --fail-with-body -X POST \
  "https://apis.roblox.com/universes/v1/${ROBLOX_UNIVERSE_ID}/places/${ROBLOX_PLACE_ID}/versions?versionType=${VERSION_TYPE}" \
  -H "x-api-key: ${ROBLOX_API_KEY}" \
  -H "Content-Type: application/octet-stream" \
  --data-binary @build/KenkaHigh.rbxl)
echo "$response"
echo "Done. Version info above."
