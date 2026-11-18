#!/usr/bin/env bash
#
# Cloud Agent install script for Pace & Plates (WorkingOut).
#
# Pace & Plates is a native iOS/SwiftUI app. The full app target can only be
# built with Xcode on macOS, so the shipping app itself cannot be compiled on
# this Linux VM. What this script does provide is everything that IS
# cross-platform in the repo, so agents can still make and verify real changes:
#
#   * The Swift 6 Linux toolchain, so Foundation-only app logic can be compiled
#     and exercised (see scripts/run_swift_logic_tests.sh, which runs the
#     wearable-vitals logic test against the real app source files).
#   * The Python dependencies used by the App Store Connect utility scripts in
#     scripts/ (import_achievements.py, asc_sync_gamecenter_images.py).
#
# The script is idempotent: it is safe to run repeatedly and skips work that is
# already done.
set -euo pipefail

SWIFT_VERSION="6.3.3"
SWIFT_UBUNTU="ubuntu24.04"
SWIFT_URL_DIR="ubuntu2404"
SWIFT_ROOT="/opt/swift-${SWIFT_VERSION}"
SWIFT_LINK="/opt/swift"
SWIFT_BIN="${SWIFT_ROOT}/usr/bin/swift"

echo "==> Installing system dependencies for the Swift toolchain"
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  binutils \
  git \
  gnupg2 \
  libc6-dev \
  libcurl4-openssl-dev \
  libedit2 \
  libgcc-13-dev \
  libncurses-dev \
  libpython3-dev \
  libsqlite3-0 \
  libstdc++-13-dev \
  libxml2-dev \
  libz3-dev \
  pkg-config \
  tzdata \
  zip \
  unzip \
  zlib1g-dev \
  openssl

if [ -x "${SWIFT_BIN}" ] && "${SWIFT_BIN}" --version 2>/dev/null | grep -q "${SWIFT_VERSION}"; then
  echo "==> Swift ${SWIFT_VERSION} already installed at ${SWIFT_ROOT}; skipping download"
else
  echo "==> Downloading Swift ${SWIFT_VERSION} for ${SWIFT_UBUNTU}"
  TARBALL="$(mktemp /tmp/swift-XXXXXX.tar.gz)"
  curl -fSL -o "${TARBALL}" \
    "https://download.swift.org/swift-${SWIFT_VERSION}-release/${SWIFT_URL_DIR}/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE-${SWIFT_UBUNTU}.tar.gz"
  echo "==> Extracting Swift toolchain to ${SWIFT_ROOT}"
  sudo rm -rf "${SWIFT_ROOT}"
  sudo mkdir -p "${SWIFT_ROOT}"
  sudo tar xzf "${TARBALL}" -C "${SWIFT_ROOT}" --strip-components=1
  rm -f "${TARBALL}"
fi

echo "==> Linking ${SWIFT_LINK} -> ${SWIFT_ROOT}"
sudo ln -sfn "${SWIFT_ROOT}" "${SWIFT_LINK}"

echo "==> Adding Swift to PATH for future shells"
echo 'export PATH=/opt/swift/usr/bin:$PATH' | sudo tee /etc/profile.d/swift.sh >/dev/null
sudo chmod 0644 /etc/profile.d/swift.sh

export PATH="/opt/swift/usr/bin:${PATH}"
echo "==> Swift toolchain: $(swift --version | head -1)"

echo "==> Installing Python dependencies for App Store Connect scripts"
# Dedicated VM: install into the system interpreter so the documented
# `python3 scripts/<name>.py` invocations work verbatim.
python3 -m pip install --break-system-packages --no-input requests PyJWT cryptography

echo "==> Verifying Python script dependencies import"
python3 - <<'PY'
import importlib
for mod in ("requests", "jwt", "cryptography"):
    importlib.import_module(mod)
print("requests / PyJWT / cryptography import OK")
PY

echo "==> Compiling the Swift logic test to prime the toolchain"
"$(dirname "$0")/../scripts/run_swift_logic_tests.sh"

echo "==> Install complete"
