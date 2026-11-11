#!/bin/zsh
# Build Saff and install it on the iPhone connected by cable.
# Usage: ./scripts/install.sh        (re-run every 7 days with a free Apple ID; your logs are kept)
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM="${SAFF_TEAM:-$(cat scripts/team.txt 2>/dev/null || true)}"
if [[ -z "$TEAM" ]]; then
  echo "No team ID. Put your Apple Team ID in scripts/team.txt" >&2
  exit 1
fi

echo "› Generating Xcode project"
xcodegen generate --quiet

echo "› Finding iPhone"
DEVICE=$(xcrun devicectl list devices --json-output /dev/stdout 2>/dev/null | python3 -I -c '
import json, sys
data = json.loads(sys.stdin.read() or "{}")
for d in data.get("result", {}).get("devices", []):
    hw = d.get("hardwareProperties", {})
    if hw.get("platform") == "iOS" and d.get("connectionProperties", {}).get("pairingState") == "paired":
        print(hw.get("udid") or d.get("identifier")); break
')
if [[ -z "$DEVICE" ]]; then
  echo "No paired iPhone found. Plug it in, unlock it and tap Trust." >&2
  exit 1
fi
echo "  $DEVICE"

echo "› Building"
xcodebuild -project Saff.xcodeproj -scheme Saff -configuration Release \
  -destination "id=$DEVICE" -derivedDataPath build \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" \
  -quiet build

echo "› Installing"
xcrun devicectl device install app --device "$DEVICE" build/Build/Products/Release-iphoneos/Saff.app
xcrun devicectl device process launch --device "$DEVICE" com.ahmadmujahid.saff >/dev/null || true
echo "✓ Saff installed"
