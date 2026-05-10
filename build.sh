#!/usr/bin/env bash
# =============================================================================
# build.sh — Build Lumina Forge (arm64, unsigned) and copy to ~/Downloads
#
# Usage
# -----
#   bash build.sh              # Debug build
#   bash build.sh release      # Release build
#   bash build.sh clean        # Clean the build folder
#   bash build.sh clean release # Clean then Release build
#
# Output
# ------
#   ~/Downloads/Lumina Forge/Lumina Forge.app
#
# Requirements
# ------------
#   • macOS 26 Tahoe (beta) or later
#   • Xcode 17 or later (xcodebuild in PATH)
#   • No Apple Developer account required — builds are unsigned
# =============================================================================

set -euo pipefail

PROJ="Lumina Forge.xcodeproj"
SCHEME="Lumina Forge"
BUILD_DIR="$(pwd)/build"
DEST="$HOME/Downloads/Lumina Forge"

# ── Parse arguments ──────────────────────────────────────────────────────────
CONFIG="Debug"
DO_CLEAN=0

for arg in "$@"; do
  case "$arg" in
    release|Release) CONFIG="Release" ;;
    clean|Clean)     DO_CLEAN=1 ;;
  esac
done

# ── Clean ─────────────────────────────────────────────────────────────────────
if [[ $DO_CLEAN -eq 1 ]]; then
  echo "▸ Cleaning build folder…"
  xcodebuild clean \
    -project   "$PROJ" \
    -scheme    "$SCHEME" \
    -configuration "$CONFIG" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="-" \
    | grep -E "^(Build|error:|warning:|note:|✓|▸)" || true
  echo "✓ Clean done"
fi

# ── Build ─────────────────────────────────────────────────────────────────────
echo ""
echo "▸ Building Lumina Forge ($CONFIG, arm64, unsigned)…"
echo ""

xcodebuild build \
  -project       "$PROJ" \
  -scheme        "$SCHEME" \
  -configuration "$CONFIG" \
  -arch          arm64 \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="" \
  ENABLE_USER_SCRIPT_SANDBOXING=NO \
  | grep -E "^(Build|error:|warning:|note:|Compile|Link|Copy|PhaseScript)" || true

# ── Locate the built .app ─────────────────────────────────────────────────────
APP_PATH=$(find "$BUILD_DIR" -name "Lumina Forge.app" -not -path "*/Index.noindex/*" | head -1)

if [[ -z "$APP_PATH" ]]; then
  echo ""
  echo "❌  Build failed — Lumina Forge.app not found in $BUILD_DIR"
  exit 1
fi

# ── Copy to ~/Downloads/Lumina Forge/ ────────────────────────────────────────
echo ""
mkdir -p "$DEST"
rm -rf "$DEST/Lumina Forge.app"
cp -R "$APP_PATH" "$DEST/Lumina Forge.app"

echo "✅  Lumina Forge.app ($CONFIG) copied to:"
echo "    $DEST/Lumina Forge.app"
echo ""
echo "    To run:  open \"$DEST/Lumina Forge.app\""
