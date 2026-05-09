#!/usr/bin/env bash
#
# build-and-install.sh — Build Claudy (Release), replace /Applications/Claudy.app,
# re-sign ad-hoc, and optionally relaunch.
#
# Usage:
#   scripts/build-and-install.sh           # build + install, do not relaunch
#   scripts/build-and-install.sh --launch  # build + install + relaunch
#   scripts/build-and-install.sh -l        # same as --launch
#
set -euo pipefail

# --- Args ---------------------------------------------------------------------
LAUNCH=0
for arg in "$@"; do
    case "$arg" in
        --launch|-l) LAUNCH=1 ;;
        -h|--help)
            sed -n '2,12p' "$0"
            exit 0
            ;;
        *)
            echo "[err] unknown argument: $arg" >&2
            exit 2
            ;;
    esac
done

# --- Resolve repo root --------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if [ ! -d "$REPO_ROOT/notchi" ]; then
    # Fallback to known location.
    REPO_ROOT="$HOME/Documents/Dev/Claudy"
fi

PROJECT_DIR="$REPO_ROOT/notchi"
PROJECT_FILE="$PROJECT_DIR/Claudy.xcodeproj"
SCHEME="Claudy"
CONFIG="Release"
DERIVED="/tmp/claudy-build"
BUILT_APP="$DERIVED/Build/Products/Release/Claudy.app"
INSTALL_PATH="/Applications/Claudy.app"

if [ ! -d "$PROJECT_FILE" ]; then
    echo "[err] cannot find $PROJECT_FILE" >&2
    exit 1
fi

# --- 1. Strip xattrs that break codesign --------------------------------------
echo "==> Stripping com.apple.FinderInfo / fileprovider xattrs from repo tree"
find "$REPO_ROOT" -exec xattr -d com.apple.FinderInfo {} \; 2>/dev/null || true
find "$REPO_ROOT" -exec xattr -d 'com.apple.fileprovider.fpfs#P' {} \; 2>/dev/null || true

# --- 2. cd into project -------------------------------------------------------
echo "==> Entering $PROJECT_DIR"
cd "$PROJECT_DIR"

# --- 3. xcodebuild ------------------------------------------------------------
echo "==> Building: xcodebuild -scheme $SCHEME -configuration $CONFIG"
xcodebuild \
    -project "Claudy.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED"

if [ ! -d "$BUILT_APP" ]; then
    echo "[err] expected build product not found at $BUILT_APP" >&2
    exit 1
fi

# --- 4. Quit running Claudy ---------------------------------------------------
echo "==> Quitting any running Claudy instance"
osascript -e 'tell application "Claudy" to quit' >/dev/null 2>&1 || true
sleep 1

# --- 5. Replace /Applications/Claudy.app --------------------------------------
echo "==> Installing to $INSTALL_PATH"
rm -rf "$INSTALL_PATH"
cp -R "$BUILT_APP" "$INSTALL_PATH"

# --- 6. Re-sign ad-hoc (Sparkle first, then app) ------------------------------
SPARKLE="$INSTALL_PATH/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE" ]; then
    echo "==> Re-signing Sparkle.framework (ad-hoc)"
    codesign --force --deep --sign - "$SPARKLE"
else
    echo "[warn] Sparkle.framework not found at $SPARKLE; skipping"
fi

echo "==> Re-signing Claudy.app (ad-hoc)"
codesign --force --deep --sign - "$INSTALL_PATH"

# --- 7. Optional relaunch -----------------------------------------------------
LAUNCHED_LINE=""
if [ "$LAUNCH" -eq 1 ]; then
    echo "==> Launching Claudy"
    open "$INSTALL_PATH"
    LAUNCHED_LINE="[ok] launched"
fi

# --- 8. Summary ---------------------------------------------------------------
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INSTALL_PATH/Contents/Info.plist" 2>/dev/null || echo unknown)"
BUILD_NUM="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INSTALL_PATH/Contents/Info.plist" 2>/dev/null || echo unknown)"

echo
echo "[ok] installed Claudy"
echo "     path:    $INSTALL_PATH"
echo "     version: $VERSION ($BUILD_NUM)"
if [ -n "$LAUNCHED_LINE" ]; then
    echo "     $LAUNCHED_LINE"
fi
