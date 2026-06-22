#!/usr/bin/env bash
set -euo pipefail

APP_NAME="HighlightBar"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${PROJECT_DIR}/dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"
PLIST_PATH="${CONTENTS_DIR}/Info.plist"
ENTITLEMENTS="${PROJECT_DIR}/${APP_NAME}.entitlements"

# --- Configurable for releases (CI overrides; local defaults are placeholders) ---
# Code-signing identity. "-" = ad-hoc (fine for local runs); CI passes a
# "Developer ID Application: …" identity for a notarizable build.
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
BUNDLE_ID="${BUNDLE_ID:-com.local.highlightbar}"
MARKETING_VERSION="${MARKETING_VERSION:-1.0}"
BUILD_VERSION="${BUILD_VERSION:-1}"
# Sparkle update configuration. Replace with your real appcast URL and EdDSA
# public key (see the Phase 5 checklist) before shipping signed updates.
SU_FEED_URL="${SU_FEED_URL:-https://25mattm.github.io/Highlighter/appcast.xml}"
SU_PUBLIC_ED_KEY="${SU_PUBLIC_ED_KEY:-REPLACE_WITH_YOUR_SPARKLE_EDDSA_PUBLIC_KEY}"

echo "Building ${APP_NAME} (release)..."
swift build -c release --package-path "${PROJECT_DIR}"

BUILD_BIN="$(swift build -c release --package-path "${PROJECT_DIR}" --show-bin-path)/${APP_NAME}"

echo "Locating embedded Sparkle.framework..."
SPARKLE_FRAMEWORK="$(find "${PROJECT_DIR}/.build" -path "*Sparkle.xcframework/macos*/Sparkle.framework" -type d 2>/dev/null | head -n1 || true)"
if [ -z "${SPARKLE_FRAMEWORK}" ]; then
  echo "error: Sparkle.framework not found under .build — run 'swift package resolve' first." >&2
  exit 1
fi

echo "Creating app bundle at ${APP_DIR}..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}" "${FRAMEWORKS_DIR}"

cp "${BUILD_BIN}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

# Let the executable find the bundled Sparkle.framework at runtime.
install_name_tool -add_rpath "@executable_path/../Frameworks" "${MACOS_DIR}/${APP_NAME}" 2>/dev/null || true

echo "Embedding Sparkle.framework..."
ditto "${SPARKLE_FRAMEWORK}" "${FRAMEWORKS_DIR}/Sparkle.framework"

cat > "${PLIST_PATH}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${MARKETING_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD_VERSION}</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>SUFeedURL</key>
  <string>${SU_FEED_URL}</string>
  <key>SUPublicEDKey</key>
  <string>${SU_PUBLIC_ED_KEY}</string>
  <key>SUEnableAutomaticChecks</key>
  <false/>
</dict>
</plist>
EOF

if command -v codesign >/dev/null 2>&1; then
  echo "Signing (identity: ${CODESIGN_IDENTITY}) with Hardened Runtime..."
  # Strip extended attributes (Finder info / quarantine) that codesign rejects.
  xattr -cr "${APP_DIR}" 2>/dev/null || true
  # Hardened Runtime + secure timestamp are required for notarization and need a
  # real Developer ID (the app and the embedded Sparkle.framework then share one
  # Team ID, so Library Validation is satisfied). Local ad-hoc builds skip them
  # so the app stays runnable without Library Validation rejecting the
  # ad-hoc-signed framework.
  CODESIGN_FLAGS=(--force)
  if [ "${CODESIGN_IDENTITY}" != "-" ]; then
    CODESIGN_FLAGS+=(--options runtime --timestamp)
  fi

  SPARKLE_DEST="${FRAMEWORKS_DIR}/Sparkle.framework"
  # Sign nested Sparkle helpers inside-out, then the framework itself.
  for nested in \
    "Versions/Current/XPCServices/Downloader.xpc" \
    "Versions/Current/XPCServices/Installer.xpc" \
    "Versions/Current/Autoupdate" \
    "Versions/Current/Updater.app"; do
    if [ -e "${SPARKLE_DEST}/${nested}" ]; then
      codesign "${CODESIGN_FLAGS[@]}" --sign "${CODESIGN_IDENTITY}" "${SPARKLE_DEST}/${nested}"
    fi
  done
  codesign "${CODESIGN_FLAGS[@]}" --sign "${CODESIGN_IDENTITY}" "${SPARKLE_DEST}"

  # Strip any extended attributes once more, then sign the app last with the
  # Hardened Runtime entitlements.
  xattr -cr "${APP_DIR}" 2>/dev/null || true
  codesign "${CODESIGN_FLAGS[@]}" --entitlements "${ENTITLEMENTS}" --sign "${CODESIGN_IDENTITY}" "${APP_DIR}"

  echo "Verifying signature..."
  codesign --verify --deep --strict --verbose=1 "${APP_DIR}" || true
fi

echo
echo "Done."
echo "App bundle: ${APP_DIR}"
echo "Open it with:"
echo "open \"${APP_DIR}\""
