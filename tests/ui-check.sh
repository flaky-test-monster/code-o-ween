#!/bin/bash
# Checks the manager UI's logic against the real CLI without clicking: builds a small harness
# app that bundles the CLI like Code-o-ween.app does, creates one disguise in temporary
# folders, runs tests/ui/checks.swift, and renders the main window and edit sheet to PNG.
# Usage: tests/ui-check.sh [SNAPSHOT_DIR]   (needs Command Line Tools and Visual Studio Code.app)
set -euo pipefail
source "$(dirname "$0")/lib.sh"
skip_unless_macos_with_vscode
{ command -v xcrun >/dev/null && xcrun --find swiftc >/dev/null 2>&1; } || { printf 'SKIP: Swift compiler not found\n'; exit 0; }
use_temp_roots
trap 'rm -rf -- "$test_root" "$data_root"' EXIT
snapshots="${1:-$test_root/snapshots}"
mkdir -p "$snapshots"

harness="$test_root/Harness.app/Contents"
mkdir -p "$harness/MacOS" "$harness/Resources/cli"
cp "$cli" "$harness/Resources/cli/code-o-ween"
cp -R "$package_dir/icons" "$harness/Resources/cli/icons"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string harness' -c 'Add :CFBundleIdentifier string local.code-o-ween.ui-check' "$harness/Info.plist" >/dev/null
sed 's/^@main$//' "$package_dir/ui/CodeOWeenApp.swift" >"$test_root/app.swift"
# Top-level code is only allowed in a file named main.swift.
cp "$package_dir/tests/ui/checks.swift" "$test_root/main.swift"
# macOS 14 for MainActor.assumeIsolated; the app itself targets 13, so its deprecations are expected.
xcrun swiftc -swift-version 6 -suppress-warnings -target "$(uname -m)-apple-macos14.0" -framework SwiftUI -framework AppKit \
  "$test_root/app.swift" "$test_root/main.swift" -o "$harness/MacOS/harness"

"$cli" create "UI Check" --emoji "👻" --color purple --folder "$test_root" --window-color off >/dev/null
# A bundle whose metadata claims the slug "--all" must be ignored and reported, never acted on.
mkdir -p "$CODE_O_WEEN_APP_ROOT/VS Code - Evil.app/Contents/Resources"
printf -- '--all' >"$CODE_O_WEEN_APP_ROOT/VS Code - Evil.app/Contents/Resources/code-o-ween.slug"
"$harness/MacOS/harness" "$snapshots" "$data_root/ui-check/user-data/User/settings.json"
[[ $# -gt 0 ]] || printf '(pass a folder to keep the snapshots)\n'
