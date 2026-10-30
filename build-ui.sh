#!/bin/bash

set -euo pipefail

# A CDPATH in the environment would make `cd` resolve relative paths against other folders.
unset CDPATH

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="${CODE_O_WEEN_MANAGER_APP:-$HOME/Applications/Code-o-ween.app}"
BUNDLE_ID="local.code-o-ween.manager"
mkdir -p "$(dirname "$APP_PATH")"

# Only ever replace (and later delete) a previous build of this app: APP_PATH is overridable
# and would otherwise point the build at any bundle.
assert_ours() {
  local path="$1" existing_id
  [[ -e "$path" ]] || return 0
  existing_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$path/Contents/Info.plist" 2>/dev/null || true)"
  [[ "$existing_id" != "$BUNDLE_ID" ]] || return 0
  printf 'Refusing to replace %s: it is not the Code-o-ween manager.\n' "$path" >&2
  exit 1
}
assert_ours "$APP_PATH"
BUILD_ROOT="$(mktemp -d "$(dirname "$APP_PATH")/.code-o-ween-build.XXXXXX")"
TEMP_APP="$BUILD_ROOT/Code-o-ween.app"
BACKUP_PATH=""

cleanup() {
  if [[ -n "$BACKUP_PATH" && -e "$BACKUP_PATH" && ! -e "$APP_PATH" ]]; then
    mv "$BACKUP_PATH" "$APP_PATH" || { printf 'Recovery copy retained: %s\n' "$BACKUP_PATH" >&2; return 1; }
  fi
  rm -rf -- "$BUILD_ROOT"
}
trap cleanup EXIT

# The version is the CLI's, so the two never drift apart.
VERSION="$(sed -n 's/^VERSION="\([^"]*\)"$/\1/p' "$SCRIPT_DIR/code-o-ween" | head -1)"
[[ -n "$VERSION" ]] || { printf 'Could not read VERSION from code-o-ween.\n' >&2; exit 1; }

command -v xcrun >/dev/null || { printf 'xcrun is required to build the manager UI.\n' >&2; exit 1; }
xcrun --find swiftc >/dev/null || { printf 'Swift compiler not found. Install Apple Command Line Tools.\n' >&2; exit 1; }

mkdir -p "$TEMP_APP/Contents/MacOS" "$TEMP_APP/Contents/Resources/cli/icons" "$(dirname "$APP_PATH")"

# One slice per architecture, joined with lipo when there is more than one. The default is
# the current machine; build-dmg.sh asks for "arm64 x86_64" so one app runs on every Mac.
read -r -a BUILD_ARCHS <<<"${CODE_O_WEEN_BUILD_ARCHS:-$(uname -m)}"
SLICES=()
for arch in "${BUILD_ARCHS[@]}"; do
  xcrun swiftc -parse-as-library -O \
    -target "$arch-apple-macos13.0" \
    -framework SwiftUI -framework AppKit \
    "$SCRIPT_DIR/ui/CodeOWeenApp.swift" \
    -o "$BUILD_ROOT/Code-o-ween-$arch"
  SLICES+=("$BUILD_ROOT/Code-o-ween-$arch")
done
if [[ ${#SLICES[@]} -eq 1 ]]; then
  mv "${SLICES[0]}" "$TEMP_APP/Contents/MacOS/Code-o-ween"
else
  xcrun lipo -create "${SLICES[@]}" -output "$TEMP_APP/Contents/MacOS/Code-o-ween"
fi

cp "$SCRIPT_DIR/code-o-ween" "$TEMP_APP/Contents/Resources/cli/code-o-ween"
cp -R "$SCRIPT_DIR/icons/." "$TEMP_APP/Contents/Resources/cli/icons/"
cp "$SCRIPT_DIR/icons/code-o-ween.icns" "$TEMP_APP/Contents/Resources/AppIcon.icns"
chmod +x "$TEMP_APP/Contents/Resources/cli/code-o-ween"

cat >"$TEMP_APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleDisplayName</key><string>Code-o-ween</string>
  <key>CFBundleExecutable</key><string>Code-o-ween</string>
  <key>CFBundleIconFile</key><string>AppIcon.icns</string>
  <key>CFBundleIdentifier</key><string>local.code-o-ween.manager</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Code-o-ween</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

/usr/bin/codesign --force --deep --sign - "$TEMP_APP" >/dev/null 2>&1

assert_ours "$APP_PATH"
if [[ -e "$APP_PATH" ]]; then
  BACKUP_PATH="$BUILD_ROOT/previous.app"
  mv "$APP_PATH" "$BACKUP_PATH"
fi
mv "$TEMP_APP" "$APP_PATH"

printf 'Installed manager UI at %s\n' "$APP_PATH"
