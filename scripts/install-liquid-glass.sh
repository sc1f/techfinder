#!/bin/bash
# Installs the Liquid Glass build of TechFinder on a connected iPhone using a free Apple ID.
#
# GitHub Actions builds the app with the latest Xcode (iOS 26+ SDK) but can't sign it for your phone.
# This script downloads that unsigned build, signs it with your Personal Team certificate and
# provisioning profile, and installs it with devicectl.
#
# Requirements: gh (signed in), Xcode with your Apple ID added, the iPhone connected and unlocked.
# Free-team installs expire after 7 days; run the script again to refresh.
#
# Usage: scripts/install-liquid-glass.sh [run-id]
#   TEAM_ID=XXXXXXXXXX   override the team (defaults to your Personal Team)
#   APP_ZIP=path.zip     sign and install a zipped TechFinder.app instead of downloading from CI
set -euo pipefail

BUNDLE_ID="com.scif.TechFinder"
ARTIFACT="TechFinder-iphoneos-unsigned"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

say() { printf '\033[1m%s\033[0m\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

# --- Connected iPhone ---------------------------------------------------------
xcrun devicectl list devices --json-output "$WORK/devices.json" >/dev/null 2>&1 || fail "devicectl could not list devices"
read -r DEVICE_ID DEVICE_UDID DEVICE_NAME < <(python3 - "$WORK/devices.json" <<'PY'
import json, sys
devices = json.load(open(sys.argv[1]))["result"]["devices"]
for d in devices:
    hw, props, conn = d.get("hardwareProperties", {}), d.get("deviceProperties", {}), d.get("connectionProperties", {})
    if hw.get("platform") == "iOS" and hw.get("deviceType") == "iPhone" and conn.get("pairingState") == "paired":
        print(d["identifier"], hw.get("udid", ""), props.get("name", "iPhone").replace(" ", "_"))
        break
PY
) || true
[ -n "${DEVICE_ID:-}" ] || fail "no paired iPhone found. Connect it, unlock it and tap Trust."
say "iPhone: ${DEVICE_NAME//_/ } ($DEVICE_UDID)"

# --- Unsigned build from GitHub Actions ------------------------------------------
cd "$ROOT"
if [ -n "${APP_ZIP:-}" ]; then
  ditto -x -k "$APP_ZIP" "$WORK"
else
RUN_ID="${1:-$(gh run list --workflow ios.yml --branch main --status success --limit 10 --json databaseId --jq '.[].databaseId' \
  | while read -r id; do
      if gh api "repos/{owner}/{repo}/actions/runs/$id/artifacts" --jq '.artifacts[].name' 2>/dev/null | grep -qx "$ARTIFACT"; then
        echo "$id"; break
      fi
    done)}"
[ -n "$RUN_ID" ] || fail "no successful CI run with the $ARTIFACT artifact yet"
say "Downloading build from CI run $RUN_ID"
gh run download "$RUN_ID" --name "$ARTIFACT" --dir "$WORK/artifact"
ditto -x -k "$WORK/artifact/TechFinder-unsigned.zip" "$WORK"
fi
APP="$WORK/TechFinder.app"
[ -d "$APP" ] || fail "artifact did not contain TechFinder.app"

# --- Provisioning profile ------------------------------------------------------
find_profile() {
  python3 - "$BUNDLE_ID" "$DEVICE_UDID" "${TEAM_ID:-}" <<'PY'
import glob, os, plistlib, subprocess, sys, datetime
bundle, udid, team = sys.argv[1:4]
dirs = ["~/Library/Developer/Xcode/UserData/Provisioning Profiles", "~/Library/MobileDevice/Provisioning Profiles"]
best = None
for d in dirs:
    for path in glob.glob(os.path.join(os.path.expanduser(d), "*.mobileprovision")):
        try:
            data = subprocess.run(["security", "cms", "-D", "-i", path], capture_output=True, check=True).stdout
            p = plistlib.loads(data)
        except Exception:
            continue
        app_id = p.get("Entitlements", {}).get("application-identifier", "")
        prefix = p.get("TeamIdentifier", [""])[0]
        if app_id != f"{prefix}.{bundle}" or (team and prefix != team):
            continue
        if udid not in p.get("ProvisionedDevices", []):
            continue
        expires = p["ExpirationDate"].replace(tzinfo=datetime.timezone.utc)
        if expires < datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=1):
            continue
        if best is None or expires > best[1]:
            best = (path, expires, prefix)
if best:
    print(f"{best[0]}\t{best[2]}")
PY
}

IFS=$'\t' read -r PROFILE TEAM < <(find_profile) || true
if [ -z "${PROFILE:-}" ]; then
  say "No valid profile for this iPhone; asking Xcode to create one"
  TEAM="${TEAM_ID:-$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null \
    | awk -F' = ' '/isFreeProvisioningTeam = 1/{free=1} /teamID/{gsub(/[;" ]/,"",$2); if(free){print $2; exit}}')}"
  [ -n "$TEAM" ] || fail "no team found. Add your Apple ID in Xcode › Settings › Accounts, or set TEAM_ID."
  xcodebuild -project TechFinder.xcodeproj -scheme TechFinder -configuration Debug \
    -destination "id=$DEVICE_UDID" -derivedDataPath "$WORK/profile-build" \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic build >"$WORK/profile-build.log" 2>&1 \
    || { tail -20 "$WORK/profile-build.log"; fail "Xcode could not create a provisioning profile"; }
  IFS=$'\t' read -r PROFILE TEAM < <(find_profile) || true
  [ -n "${PROFILE:-}" ] || fail "still no provisioning profile for $BUNDLE_ID on this iPhone"
fi
say "Profile: $(basename "$PROFILE") (team $TEAM)"

# --- Signing identity ------------------------------------------------------------
# Use a keychain certificate that the profile allows.
IDENTITY="$(python3 - "$PROFILE" <<'PY'
import hashlib, plistlib, subprocess, sys
profile = plistlib.loads(subprocess.run(["security", "cms", "-D", "-i", sys.argv[1]], capture_output=True, check=True).stdout)
allowed = {hashlib.sha1(cert).hexdigest().upper() for cert in profile.get("DeveloperCertificates", [])}
identities = subprocess.run(["security", "find-identity", "-v", "-p", "codesigning"], capture_output=True, text=True).stdout
for line in identities.splitlines():
    parts = line.split()
    if len(parts) > 1 and parts[1].upper() in allowed:
        print(parts[1])
        break
PY
)"
[ -n "$IDENTITY" ] || fail "no certificate in your keychain matches the profile. Build once from Xcode to create it."

# --- Sign ---------------------------------------------------------------------------
cp "$PROFILE" "$APP/embedded.mobileprovision"
cat >"$WORK/entitlements.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>application-identifier</key><string>$TEAM.$BUNDLE_ID</string>
  <key>com.apple.developer.team-identifier</key><string>$TEAM</string>
  <key>get-task-allow</key><true/>
</dict>
</plist>
EOF
if [ -d "$APP/Frameworks" ]; then
  find "$APP/Frameworks" -maxdepth 1 \( -name "*.framework" -o -name "*.dylib" \) -exec \
    codesign --force --sign "$IDENTITY" --timestamp=none {} \;
fi
codesign --force --sign "$IDENTITY" --entitlements "$WORK/entitlements.plist" --generate-entitlement-der \
  --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
say "Signed"

# --- Install and launch ----------------------------------------------------------------
xcrun devicectl device install app --device "$DEVICE_ID" "$APP" >/dev/null
say "Installed on ${DEVICE_NAME//_/ }"
if xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID" >/dev/null 2>&1; then
  say "Launched"
else
  echo "Installed. Unlock the iPhone and open TechFinder."
fi
