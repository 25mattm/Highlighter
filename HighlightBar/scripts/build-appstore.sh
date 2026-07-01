#!/usr/bin/env bash
set -euo pipefail

# Builds the Mac App Store configuration: sandboxed, no Sparkle, no auto-update
# UI, no keyboard tracking (see Features.swift / Package.swift, HB_APPSTORE=1).
#
# Local default: an ad-hoc-signed sandboxed .app you can run to smoke-test.
# Release: pass APP_SIGN_IDENTITY (+ optional PROVISION_PROFILE) to sign for the
# store, and PKG_SIGN_IDENTITY to wrap it in a signed installer .pkg ready for
# Transporter / `xcrun altool --upload-app`.

APP_NAME="HighlightBar"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# Build output. Defaults to a temp dir outside the home/Documents tree — macOS
# stamps com.apple.provenance onto home-folder executables, breaking the code
# signature right after signing (so the .pkg would embed a broken app). Override
# with HB_DIST_DIR.
DIST_DIR="${HB_DIST_DIR:-/private/tmp/HighlightBar/dist-appstore}"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
PLIST_PATH="${CONTENTS_DIR}/Info.plist"
ENTITLEMENTS="${PROJECT_DIR}/${APP_NAME}-appstore.entitlements"
SCRATCH="${PROJECT_DIR}/.build-appstore"

# --- Configurable for releases (CI overrides; local defaults are placeholders) ---
# App-bundle signing identity. "-" = ad-hoc (local smoke test only — NOT
# acceptable to the store). CI passes "Apple Distribution: …".
APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:--}"
# Installer signing identity for the .pkg, e.g. "3rd Party Mac Developer
# Installer: …". When empty, the .pkg step is skipped (local .app only).
PKG_SIGN_IDENTITY="${PKG_SIGN_IDENTITY:-}"
# Mac App Store provisioning profile to embed (required by the real store build).
PROVISION_PROFILE="${PROVISION_PROFILE:-}"
BUNDLE_ID="${BUNDLE_ID:-com.matthewmullett.highlightbar}"
MARKETING_VERSION="${MARKETING_VERSION:-1.0}"
BUILD_VERSION="${BUILD_VERSION:-1}"

# Resolve APP_SIGN_IDENTITY / PKG_SIGN_IDENTITY = "auto" from the Keychain by
# their friendly prefix, so you never have to paste the full Team-ID strings.
resolve_identity() { security find-identity -v 2>/dev/null | grep -m1 -F "$1" | sed -E 's/.*"(.*)".*/\1/'; }
if [ "${APP_SIGN_IDENTITY}" = "auto" ]; then
  APP_SIGN_IDENTITY="$(resolve_identity 'Apple Distribution')"
  [ -n "${APP_SIGN_IDENTITY}" ] || { echo "error: no 'Apple Distribution' identity in your Keychain" >&2; exit 1; }
fi
if [ "${PKG_SIGN_IDENTITY}" = "auto" ]; then
  PKG_SIGN_IDENTITY="$(resolve_identity '3rd Party Mac Developer Installer')"
  [ -n "${PKG_SIGN_IDENTITY}" ] || { echo "error: no Mac Installer Distribution identity in your Keychain" >&2; exit 1; }
fi

echo "Building ${APP_NAME} (App Store config, HB_APPSTORE=1)..."
HB_APPSTORE=1 swift build -c release --package-path "${PROJECT_DIR}" --scratch-path "${SCRATCH}"
BUILD_BIN="$(HB_APPSTORE=1 swift build -c release --package-path "${PROJECT_DIR}" --scratch-path "${SCRATCH}" --show-bin-path)/${APP_NAME}"

echo "Creating app bundle at ${APP_DIR}..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BUILD_BIN}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

# Bundle the app icon (shared with the direct build).
if [ -f "${PROJECT_DIR}/AppIcon.icns" ]; then
  cp "${PROJECT_DIR}/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

# Bundle the privacy manifest (declares no data collection + UserDefaults reason).
if [ -f "${PROJECT_DIR}/PrivacyInfo.xcprivacy" ]; then
  cp "${PROJECT_DIR}/PrivacyInfo.xcprivacy" "${RESOURCES_DIR}/PrivacyInfo.xcprivacy"
fi

# Compile the asset-catalog icon (App Store review prefers CFBundleIconName).
# Info.plist declares CFBundleIconName, so a store build (non-ad-hoc identity)
# must not ship without the Assets.car — failures are fatal there.
if command -v actool >/dev/null 2>&1 && [ -d "${PROJECT_DIR}/Assets.xcassets" ]; then
  if ! actool "${PROJECT_DIR}/Assets.xcassets" --compile "${RESOURCES_DIR}" \
      --platform macosx --minimum-deployment-target 13.0 \
      --app-icon AppIcon --output-partial-info-plist /tmp/hb-actool.plist >/dev/null; then
    echo "warning: actool failed — Assets.car missing" >&2
    [ "${APP_SIGN_IDENTITY}" = "-" ] || exit 1
  fi
elif [ "${APP_SIGN_IDENTITY}" != "-" ]; then
  echo "error: actool or Assets.xcassets unavailable — required for a store build" >&2
  exit 1
fi

# Info.plist intentionally omits Sparkle's SUFeedURL / SUPublicEDKey: the App
# Store build has no updater. LSApplicationCategoryType is set so the bundle
# matches the store category.
cat > "${PLIST_PATH}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
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
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>ITSAppUsesNonExemptEncryption</key>
  <false/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
EOF

# Embed the Mac App Store provisioning profile when supplied (required by the
# real store build; absent for the local ad-hoc smoke test).
if [ -n "${PROVISION_PROFILE}" ]; then
  echo "Embedding provisioning profile..."
  cp "${PROVISION_PROFILE}" "${CONTENTS_DIR}/embedded.provisionprofile"
fi

# The App Store / TestFlight requires the app to be signed WITH the
# application-identifier + team-identifier entitlements that match the embedded
# provisioning profile (otherwise Transporter rejects it — error 90886).
# Extract them from the profile and add them to a COPY of the entitlements file,
# so every key in that file (sandbox, user-selected files, future additions)
# reaches the store build.
SIGN_ENTITLEMENTS="${ENTITLEMENTS}"
if [ -n "${PROVISION_PROFILE}" ]; then
  _pp="$(mktemp)"
  if security cms -D -i "${PROVISION_PROFILE}" -o "${_pp}" 2>/dev/null; then
    _appid="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "${_pp}" 2>/dev/null || true)"
    _team="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.team-identifier' "${_pp}" 2>/dev/null || true)"
    if [ -n "${_appid}" ] && [ -n "${_team}" ]; then
      SIGN_ENTITLEMENTS="$(mktemp)"
      cp "${ENTITLEMENTS}" "${SIGN_ENTITLEMENTS}"
      /usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string ${_appid}" "${SIGN_ENTITLEMENTS}"
      /usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string ${_team}" "${SIGN_ENTITLEMENTS}"
    fi
  fi
  rm -f "${_pp}"
fi

if command -v codesign >/dev/null 2>&1; then
  echo "Signing app (identity: ${APP_SIGN_IDENTITY}) with the App Sandbox..."
  # Strip extended attributes codesign rejects. App Store builds use the sandbox
  # entitlement; they do NOT use Hardened Runtime (--options runtime) — that is
  # for Developer ID / notarization, which the store does not use.
  # Clean-and-retry: Finder/Spotlight/QuickLook can race detritus onto the
  # bundle between cleaning and signing.
  for attempt in 1 2 3 4 5; do
    xattr -cr "${APP_DIR}" 2>/dev/null || true
    find "${APP_DIR}" \( -name '._*' -o -name '.DS_Store' \) -delete 2>/dev/null || true
    if codesign --force --sign "${APP_SIGN_IDENTITY}" --entitlements "${SIGN_ENTITLEMENTS}" "${APP_DIR}"; then
      break
    fi
    [ "${attempt}" = 5 ] && { echo "error: codesign failed after ${attempt} attempts" >&2; exit 1; }
    echo "codesign hit filesystem detritus; cleaning and retrying (${attempt})..."
    sleep 1
  done
  echo "Verifying signature..."
  codesign --verify --strict --verbose=1 "${APP_DIR}" || true
fi

# Wrap the signed .app in an installer .pkg for App Store Connect when an
# installer identity is supplied.
if [ -n "${PKG_SIGN_IDENTITY}" ]; then
  PKG_PATH="${DIST_DIR}/${APP_NAME}.pkg"
  echo "Building signed installer ${PKG_PATH}..."
  productbuild --component "${APP_DIR}" /Applications \
    --sign "${PKG_SIGN_IDENTITY}" "${PKG_PATH}"
  echo "Installer package: ${PKG_PATH}"
  echo "Upload with: xcrun altool --upload-app -t macos -f \"${PKG_PATH}\" --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>"
fi

echo
echo "Done."
echo "App bundle: ${APP_DIR}"
if [ "${APP_SIGN_IDENTITY}" = "-" ]; then
  echo "NOTE: ad-hoc signed (local smoke test only). Set APP_SIGN_IDENTITY + PKG_SIGN_IDENTITY for a store build."
fi
