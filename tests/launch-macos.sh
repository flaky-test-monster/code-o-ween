#!/bin/bash
# End-to-end check on macOS: creates a disguise in temporary locations, launches it through
# Launch Services, verifies it runs with its own bundle identifier, profile, and Keychain item,
# then removes it with its data. Briefly opens a VS Code window.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
skip_unless_macos_with_vscode
use_temp_roots
suffix="$(random_suffix)"
name="Launch Test $suffix" slug="launch-test-$suffix"
bundle_id="local.code-o-ween.$slug"
keychain_service="Code-o-ween $slug Safe Storage"
app="$CODE_O_WEEN_APP_ROOT/VS Code - $name.app"
profile="$data_root/$slug"

is_running() { [[ "$(/bin/ps -axo command=)" == *"$app/Contents/MacOS/"* ]]; }
quit_app() {
  /usr/bin/osascript -e "tell application id \"$bundle_id\" to quit" >/dev/null 2>&1 || true
  wait_for 30 bash -c '! [[ "$(/bin/ps -axo command=)" == *"$1/Contents/MacOS/"* ]]' _ "$app" || true
}
cleanup() {
  quit_app
  /usr/bin/pkill -f "$app/Contents/MacOS/" 2>/dev/null || true
  /usr/bin/security delete-generic-password -s "$keychain_service" >/dev/null 2>&1 || true
  rm -rf -- "$test_root" "$data_root"
}
trap cleanup EXIT

keychain_item_exists() { /usr/bin/security find-generic-password -s "$keychain_service" >/dev/null 2>&1; }
socket_exists() { compgen -G "$profile/user-data/*-main.sock" >/dev/null; }
registered() { [[ "$(/usr/bin/lsappinfo list)" == *"bundleID=\"$bundle_id\""* ]]; }
prompt_open() { /usr/bin/pgrep -x SecurityAgent >/dev/null; }
# An unrelated Keychain prompt that is already open must not fail (or mask) the check below.
prompt_before=false
if prompt_open; then prompt_before=true; fi

mkdir -p "$test_root/project folder"
"$cli" create "$name" --emoji "🎃" --color orange --extensions isolated --folder "$test_root/project folder" >/dev/null
/usr/bin/codesign --verify --deep --strict "$app"
"$CODE_O_WEEN_BIN_ROOT/code-$slug" --version >/dev/null
dyld_output="$(DYLD_PRINT_LIBRARIES=1 ELECTRON_RUN_AS_NODE=1 "$app/Contents/MacOS/Code" -e 0 2>&1)"
[[ "$dyld_output" != *dyld* ]] || fail "DYLD_* variables are honored (hardened runtime missing)"

"$cli" open "$name"
wait_for 60 socket_exists || fail "instance did not start"
wait_for 30 registered || fail "instance is not registered with Launch Services as $bundle_id"
wait_for 60 keychain_item_exists || fail "the disguise did not create its own Keychain item"
if [[ "$prompt_before" == false ]] && prompt_open; then fail "a Keychain prompt appeared"; fi
[[ "$(/bin/ps -axo command=)" == *"$app/Contents/MacOS/Code "*"$test_root/project folder"* ]] || fail "the pinned folder was not opened"
[[ -d "$profile/extensions" ]] || fail "isolated extensions directory missing"
# Opening a running disguise hands it the pinned folder instead of only activating it.
"$cli" open "$name" || fail "could not open the running instance again"
sleep 2
is_running || fail "opening the running instance again stopped it"
"$cli" update "$name" --no-folder >/dev/null || fail "could not unpin while running"
expect_fail "$cli" update "$name" --color purple
expect_fail "$cli" remove "$name" --yes
is_running || fail "instance stopped unexpectedly"

quit_app
is_running && fail "instance did not quit"
"$cli" remove "$name" --delete-data --yes >/dev/null
keychain_item_exists && fail "Keychain item was not deleted"
[[ ! -e "$app" && ! -e "$profile" ]] || fail "remove left files behind"

printf 'PASS: launch via Launch Services, hardened runtime, own Keychain item without prompt, pinned folder, profile isolation, running guards, removal with data\n'
