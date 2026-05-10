#!/usr/bin/env bash
# =============================================================================
# build-dmg.sh — Builds, signs, packages, and notarizes Lumina Forge as a DMG.
#
# Prerequisites
# -------------
#   • Xcode 17+ with Command Line Tools
#   • create-dmg  (brew install create-dmg)
#   • Notarization credentials stored in Keychain:
#       xcrun notarytool store-credentials "notarytool-credentials" \
#           --apple-id  "$APPLE_ID"   \
#           --team-id   "$TEAM_ID"    \
#           --password  "$APP_PASSWORD"
#
# Environment variables (all optional — skip signing/notarization if unset)
# -------------------------------------------------------------------------
#   CODE_SIGN_IDENTITY   Developer ID Application certificate name
#   DEVELOPMENT_TEAM     10-character Apple Team ID
#   APPLE_ID             Apple ID email used for notarization
#   NOTARIZE_TEAM_ID     Team ID for notarytool (may differ from DEVELOPMENT_TEAM)
#
# Usage
# -----
#   bash scripts/build-dmg.sh
#   # — or —
#   CODE_SIGN_IDENTITY="Developer ID Application: Your Name (XXXXXXXXXX)" \
#   DEVELOPMENT_TEAM="XXXXXXXXXX" \
#   APPLE_ID="you@example.com"    \
#   NOTARIZE_TEAM_ID="XXXXXXXXXX" \
#   bash scripts/build-dmg.sh
# =============================================================================

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
APP_NAME="Lumina Forge"
SCHEME="Lumina Forge"
BUNDLE_ID="com.luminaforge.app"
PROJECT="${APP_NAME}.xcodeproj"
CONFIG="Release"

BUILD_DIR="$(pwd)/build"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_PATH="${BUILD_DIR}/export"
APP_PATH="${EXPORT_PATH}/${APP_NAME}.app"
DMG_NAME="${APP_NAME}.dmg"
DMG_PATH="${BUILD_DIR}/${DMG_NAME}"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
    "${PROJECT}/project.pbxproj" 2>/dev/null || echo "1.0.0")

echo "▸ Building Lumina Forge ${VERSION}"
echo "▸ Archive → ${ARCHIVE_PATH}"
echo "▸ DMG     → ${DMG_PATH}"
echo ""

# ── 1. Clean ───────────────────────────────────────────────────────────────────
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# ── 2. Archive ─────────────────────────────────────────────────────────────────
echo "▸ Step 1/5  Archiving…"
xcodebuild archive \
  -project "${PROJECT}" \
  -scheme  "${SCHEME}"  \
  -configuration "${CONFIG}" \
  -archivePath "${ARCHIVE_PATH}" \
  -destination "generic/platform=macOS" \
  ${CODE_SIGN_IDENTITY:+CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY}"} \
  ${DEVELOPMENT_TEAM:+DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}"} \
  | xcbeautify 2>/dev/null || true   # xcbeautify is optional; fall through if absent

echo "✓ Archive complete"

# ── 3. Export ──────────────────────────────────────────────────────────────────
echo "▸ Step 2/5  Exporting…"
xcodebuild -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportPath  "${EXPORT_PATH}"  \
  -exportOptionsPlist ExportOptions.plist
echo "✓ Export complete"

# ── 4. Package DMG ─────────────────────────────────────────────────────────────
echo "▸ Step 3/5  Creating DMG…"

if ! command -v create-dmg &>/dev/null; then
  echo "⚠  create-dmg not found — install with:  brew install create-dmg"
  echo "   Falling back to hdiutil…"
  hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${APP_PATH}" \
    -ov -format UDZO \
    "${DMG_PATH}"
else
  create-dmg \
    --volname "${APP_NAME} ${VERSION}" \
    --volicon "${APP_PATH}/Contents/Resources/AppIcon.icns" \
    --window-pos    200 120 \
    --window-size   660 400 \
    --icon-size     160 \
    --icon "${APP_NAME}.app" 180 170 \
    --hide-extension "${APP_NAME}.app" \
    --app-drop-link 480 170 \
    --background "scripts/dmg-background.png" \
    "${DMG_PATH}" \
    "${APP_PATH}" \
  2>/dev/null || \
  create-dmg \
    --volname "${APP_NAME} ${VERSION}" \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 160 \
    --icon "${APP_NAME}.app" 180 170 \
    --hide-extension "${APP_NAME}.app" \
    --app-drop-link 480 170 \
    "${DMG_PATH}" \
    "${APP_PATH}"
fi
echo "✓ DMG created: ${DMG_PATH}"

# ── 5. Sign the DMG (optional) ────────────────────────────────────────────────
if [ -n "${CODE_SIGN_IDENTITY:-}" ]; then
  echo "▸ Step 4/5  Code-signing DMG…"
  codesign --sign "${CODE_SIGN_IDENTITY}" --timestamp "${DMG_PATH}"
  echo "✓ DMG signed"
else
  echo "⚠  Step 4/5  Skipped code-signing (CODE_SIGN_IDENTITY not set)"
fi

# ── 6. Notarize + Staple (optional) ────────────────────────────────────────────
if [ -n "${APPLE_ID:-}" ] && [ -n "${NOTARIZE_TEAM_ID:-}" ]; then
  echo "▸ Step 5/5  Notarizing (this may take a few minutes)…"
  xcrun notarytool submit "${DMG_PATH}" \
    --apple-id "${APPLE_ID}" \
    --team-id  "${NOTARIZE_TEAM_ID}" \
    --keychain-profile "notarytool-credentials" \
    --wait

  echo "▸ Stapling notarization ticket…"
  xcrun stapler staple "${DMG_PATH}"
  echo "✓ Notarized and stapled"
else
  echo "⚠  Step 5/5  Skipped notarization (set APPLE_ID and NOTARIZE_TEAM_ID)"
fi

# ── Done ───────────────────────────────────────────────────────────────────────
echo ""
echo "🎉  Lumina Forge ${VERSION} packaged:"
echo "    ${DMG_PATH}"
echo ""
echo "To install: open the DMG and drag Lumina Forge.app to /Applications."
