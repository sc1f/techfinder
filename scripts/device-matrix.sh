#!/bin/bash
# Checks the layout on several iPhone screen sizes: builds once, then on a Simulator for each size runs
# the layout UI test (every control stays off the camera image, upright and sideways) and saves
# screenshots of the main states.
#
#   scripts/device-matrix.sh [output-dir]
#
# Uses the newest installed iOS runtime and creates any missing Simulators ("TF <device>"). Set DEVICES
# to a space-separated list of device type names to change the sizes checked.
set -euo pipefail

cd "$(dirname "$0")/.."
out="${1:-build/device-matrix}"
derived="build/DeviceMatrix"
bundle=com.scif.TechFinder
mkdir -p "$out"

# The smallest, a notched small screen, a Dynamic Island screen and the largest.
DEVICES="${DEVICES:-iPhone-SE-3rd-generation iPhone-13-mini iPhone-16-Pro iPhone-16-Pro-Max}"

runtime=$(xcrun simctl list runtimes --json | python3 -c '
import json, sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"] if r.get("platform") == "iOS" and r["isAvailable"]]
runtimes.sort(key=lambda r: [int(p) for p in r["version"].split(".")])
print(runtimes[-1]["identifier"])')
echo "Runtime: $runtime"

xcodebuild build-for-testing \
  -project TechFinder.xcodeproj -scheme TechFinder \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$derived" -quiet
app="$derived/Build/Products/Debug-iphonesimulator/TechFinder.app"

failed=0
for type in $DEVICES; do
  type_id="com.apple.CoreSimulator.SimDeviceType.$type"
  if ! xcrun simctl list devicetypes | grep -q "($type_id)"; then
    echo "::warning::No device type $type; skipping"
    continue
  fi
  name="TF $type"
  udid=$(xcrun simctl list devices available --json | python3 -c '
import json, sys
name, runtime = sys.argv[1:]
print(next((d["udid"] for d in json.load(sys.stdin)["devices"].get(runtime, []) if d["name"] == name), ""))' "$name" "$runtime")
  if [ -z "$udid" ]; then
    if ! udid=$(xcrun simctl create "$name" "$type_id" "$runtime" 2>/dev/null); then
      echo "::warning::$type doesn't run $runtime; skipping"
      continue
    fi
  fi
  echo "== $type ($udid)"
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null

  log="$out/$type-test.log"
  if xcodebuild test-without-building \
      -project TechFinder.xcodeproj -scheme TechFinder \
      -destination "id=$udid" -derivedDataPath "$derived" \
      -only-testing:TechFinderUITests/TechFinderUITests/testControlsStayOffTheImage >"$log" 2>&1; then
    echo "   layout test passed"
  else
    echo "::error::Layout test failed on $type"
    grep -E "error: -" "$log" || tail -20 "$log"
    failed=1
  fi

  xcrun simctl install "$udid" "$app"
  shoot() {
    local shot="$1"; shift
    xcrun simctl terminate "$udid" "$bundle" 2>/dev/null || true
    xcrun simctl launch "$udid" "$bundle" -TFFreshLibrary YES "$@" >/dev/null
    sleep 8
    xcrun simctl io "$udid" screenshot "$out/$type-$shot.png" >/dev/null 2>&1
  }
  shoot portrait
  shoot movements -TFImageCircle 90 -TFMovements YES -TFRise 8 -TFShift 4 -TFOverview NO
  shoot landscape -TFSimulateHold landscapeLeft
  xcrun simctl terminate "$udid" "$bundle" 2>/dev/null || true
  xcrun simctl shutdown "$udid" 2>/dev/null || true
done
exit $failed
