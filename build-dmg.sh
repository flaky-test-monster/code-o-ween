#!/bin/bash
# Builds the manager app with build-ui.sh into a staging folder (never ~/Applications) and
# packages it as a disk image: dist/Code-o-ween-VERSION.dmg, with an Applications shortcut
# next to the app.
#
# Environment:
#   CODE_O_WEEN_DIST_DIR           where the .dmg is written (default: dist/ next to this script)
#   CODE_O_WEEN_BUILD_ARCHS        passed on to build-ui.sh, e.g. "arm64 x86_64" for a universal app
#   CODE_O_WEEN_CODESIGN_IDENTITY  a Developer ID identity; without it the app stays ad-hoc signed
#                                  and Gatekeeper asks the user to open it with right-click → Open

set -euo pipefail
unset CDPATH

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ "$(uname -s)" == Darwin ]] || { printf 'build-dmg.sh needs macOS (hdiutil, codesign, swiftc).\n' >&2; exit 1; }

# The version is the CLI's; the Info.plist of the manager app carries the same number.
VERSION="$(sed -n 's/^VERSION="\([^"]*\)"$/\1/p' "$SCRIPT_DIR/code-o-ween" | head -1)"
[[ -n "$VERSION" ]] || { printf 'Could not read VERSION from code-o-ween.\n' >&2; exit 1; }

DIST_DIR="${CODE_O_WEEN_DIST_DIR:-$SCRIPT_DIR/dist}"
mkdir -p "$DIST_DIR"
DIST_DIR="$(cd -P "$DIST_DIR" && pwd)"
DMG_PATH="$DIST_DIR/Code-o-ween-$VERSION.dmg"
VOLUME_NAME="Code-o-ween $VERSION"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/code-o-ween-dmg.XXXXXX")"
trap 'rm -rf -- "$STAGE"' EXIT
APP_PATH="$STAGE/root/Code-o-ween.app"
mkdir -p "$STAGE/root"

# build-ui.sh installs to CODE_O_WEEN_MANAGER_APP; pointing it into the staging folder keeps
# ~/Applications untouched.
CODE_O_WEEN_MANAGER_APP="$APP_PATH" "$SCRIPT_DIR/build-ui.sh"

if [[ -n "${CODE_O_WEEN_CODESIGN_IDENTITY:-}" ]]; then
  /usr/bin/codesign --force --deep --options runtime --timestamp \
    --sign "$CODE_O_WEEN_CODESIGN_IDENTITY" "$APP_PATH"
fi
/usr/bin/codesign --verify --deep --strict "$APP_PATH"

ln -s /Applications "$STAGE/root/Applications"

rm -f "$DMG_PATH"
hdiutil create -quiet -volname "$VOLUME_NAME" -srcfolder "$STAGE/root" \
  -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG_PATH"

if [[ -n "${CODE_O_WEEN_CODESIGN_IDENTITY:-}" ]]; then
  /usr/bin/codesign --force --timestamp --sign "$CODE_O_WEEN_CODESIGN_IDENTITY" "$DMG_PATH"
  # Notarize and staple separately, once an App Store Connect key is set up:
  #   xcrun notarytool submit "$DMG_PATH" --keychain-profile NAME --wait
  #   xcrun stapler staple "$DMG_PATH"
fi

hdiutil verify -quiet "$DMG_PATH"
shasum -a 256 "$DMG_PATH" | tee "$DMG_PATH.sha256"
printf 'Built %s\n' "$DMG_PATH"
