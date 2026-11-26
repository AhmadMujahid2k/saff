#!/bin/zsh
# Delete Saff's cached provisioning profiles that expire within 3 days, so the next
# `xcodebuild -allowProvisioningUpdates` fetches fresh 7-day ones. Without this, Xcode
# keeps reusing a profile until it expires, and a reinstall doesn't extend the app's life.
setopt nullglob
for f in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/"*.mobileprovision; do
  plist=$(security cms -D -i "$f" 2>/dev/null) || continue
  name=$(plutil -extract Name raw - <<< "$plist" 2>/dev/null) || continue
  [[ "$name" == *com.ahmadmujahid.saff* ]] || continue
  expires=$(plutil -extract ExpirationDate raw - <<< "$plist")
  exp_s=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$expires" +%s 2>/dev/null) || continue
  if (( exp_s - $(date +%s) < 3 * 24 * 3600 )); then
    rm -f "$f" && echo "  renewing profile: $name (expires $expires)"
  fi
done
