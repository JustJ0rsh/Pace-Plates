#!/usr/bin/env bash
#
# Compile and run the cross-platform Swift logic tests for Pace & Plates.
#
# Pace & Plates is a native iOS app, so most of it can only be built with Xcode
# on macOS. A subset of the app logic depends only on Foundation, though, and
# can be compiled and exercised with the open-source Swift toolchain on Linux.
#
# This runner compiles the wearable-vitals logic test in
# scripts/wearable_vitals_test_main.swift together with the real app source it
# depends on, then runs it. A non-zero exit means the logic regressed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO_ROOT}"

if ! command -v swiftc >/dev/null 2>&1; then
  if [ -x /opt/swift/usr/bin/swiftc ]; then
    export PATH="/opt/swift/usr/bin:${PATH}"
  else
    echo "error: swiftc not found. Run .cursor/install.sh to install the Swift toolchain." >&2
    exit 127
  fi
fi

OUT_BIN="$(mktemp /tmp/wearable_vitals_test-XXXXXX)"
trap 'rm -f "${OUT_BIN}"' EXIT

echo "==> swiftc $(swiftc --version | head -1)"
echo "==> Building wearable-vitals logic test"
swiftc -swift-version 5 \
  "WorkingOut/Models/WearableDevicePreference.swift" \
  "WorkingOut/Features/Home/Vitals/VitalMetric.swift" \
  "scripts/wearable_vitals_test_main.swift" \
  -o "${OUT_BIN}"

echo "==> Running wearable-vitals logic test"
"${OUT_BIN}"
echo "PASS: wearable-vitals logic test"
