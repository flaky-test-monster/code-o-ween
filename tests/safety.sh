#!/bin/bash
# Fast checks without side effects. Runs on macOS and Linux: it sources the CLI and exercises
# the pure-shell parts, including the generated launchers against fake executables.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
# shellcheck source=../code-o-ween
source "$cli"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
# These settings are read by the sourced CLI functions.
# shellcheck disable=SC2034
BIN_ROOT="$test_root/bin"
# shellcheck disable=SC2034
DATA_ROOT="$test_root/data"
APP_ROOT="$test_root/apps"
mkdir -p "$BIN_ROOT"

# --- Metadata, profile paths and shortcuts of a VS Code disguise ------------------------------
app="$test_root/Fake App.app"
mkdir -p "$app/Contents/Resources"
profile_path="$test_root/custom data/demo"
write_metadata "$app" profile "$profile_path"
write_metadata "$app" extensions isolated
[[ "$(profile_for_app "$app" demo)" == "$profile_path" ]]
[[ "$(read_metadata "$app" profile)" == "$profile_path" ]]
[[ "$(read_metadata "$app" missing fallback)" == fallback ]]
[[ "$(kind_for_app "$app")" == vscode ]]
[[ "$(family_for_app "$app")" == vscode ]]
[[ "$(label_for_app "$app")" == "Visual Studio Code" ]]
[[ "$(shortcut_for_app "$app" demo)" == code-demo ]]
write_shortcut demo "$app"
grep -Fq '# Managed by Code-o-ween: demo' "$BIN_ROOT/code-demo"
grep -Fq 'Contents/Resources/app/bin/code' "$BIN_ROOT/code-demo"
grep -Fq -- '--extensions-dir' "$BIN_ROOT/code-demo"
bash -n "$BIN_ROOT/code-demo"
assert_shortcut_owned demo code-demo
printf 'unrelated\n' >"$BIN_ROOT/code-other"
if (assert_shortcut_owned other code-other) 2>/dev/null; then exit 1; fi
ln -s "$BIN_ROOT/code-other" "$BIN_ROOT/code-link"
if (assert_shortcut_owned link code-link) 2>/dev/null; then exit 1; fi
[[ "$(<"$BIN_ROOT/code-other")" == unrelated ]]
# A changed profile path is read back, and unsafe profile paths are refused.
write_metadata "$app" profile "$test_root/new/demo"
[[ "$(profile_for_app "$app" demo)" == "$test_root/new/demo" ]]
printf '/\n' >"$app/Contents/Resources/code-o-ween.profile"
if (profile_for_app "$app" demo) 2>/dev/null; then exit 1; fi

# --- Generated launchers, executed against fake executables ---------------------------------
fake_bin="$test_root/fakebin"
mkdir -p "$fake_bin"
for executable in Code "Google Chrome" firefox Slack; do
  printf '#!/bin/bash\nprintf "%%s\\n" "$HOME" "$@"\n' >"$fake_bin/$executable"
  chmod +x "$fake_bin/$executable"
done
real_home="$test_root/realhome"
mkdir -p "$real_home/Documents"

write_launcher "$fake_bin/launch-code" Code "$test_root/data/code-demo" vscode isolated code-demo
bash -n "$fake_bin/launch-code"
grep -Fq '/"Code' "$fake_bin/launch-code"
expected="$real_home"$'\n'"--user-data-dir"$'\n'"$test_root/data/code-demo/user-data"$'\n'"--extensions-dir"$'\n'"$test_root/data/code-demo/extensions"$'\n'"--foo"
[[ "$(HOME="$real_home" "$fake_bin/launch-code" --foo)" == "$expected" ]]
[[ -d "$test_root/data/code-demo/user-data" ]]
# A settings folder the launcher had to create carries the ownership marker; an existing one is left alone.
[[ "$(<"$test_root/data/code-demo/.code-o-ween-profile")" == code-demo ]] || fail "launcher did not mark the folder it created"
# A recreated VS Code profile starts with update.mode pinned, so the copy cannot update itself.
grep -Fq '"update.mode": "none"' "$test_root/data/code-demo/user-data/User/settings.json" || fail "recreated profile not pinned"
# An existing folder the launcher does not own is refused, never claimed, never used.
mkdir -p "$test_root/data/theirs"
printf 'x' >"$test_root/data/theirs/README"
write_launcher "$fake_bin/launch-theirs" Code "$test_root/data/theirs" vscode shared theirs
expect_fail env HOME="$real_home" "$fake_bin/launch-theirs"
[[ ! -e "$test_root/data/theirs/.code-o-ween-profile" && ! -e "$test_root/data/theirs/user-data" ]] || fail "launcher used a folder it does not own"
# A symlinked profile is refused too, even with a matching marker behind it.
ln -s "$test_root/data/code-demo" "$test_root/data/code-link"
write_launcher "$fake_bin/launch-link" Code "$test_root/data/code-link" vscode shared code-demo
expect_fail env HOME="$real_home" "$fake_bin/launch-link"
# Without a slug (no guard requested) the launcher behaves as before.
write_launcher "$fake_bin/launch-code-shared" Code "$test_root/data/code-demo" vscode shared
if grep -Fq -- '--extensions-dir' "$fake_bin/launch-code-shared"; then exit 1; fi
# Electron's Node mode (used by the bundled CLI) bypasses the isolation arguments.
[[ "$(ELECTRON_RUN_AS_NODE=1 HOME=/nowhere "$fake_bin/launch-code" x)" == "/nowhere"$'\n'"x" ]]

write_launcher "$fake_bin/launch-chrome" "Google Chrome" "$test_root/data/chrome-demo" chromium
bash -n "$fake_bin/launch-chrome"
expected="$real_home"$'\n'"--user-data-dir=$test_root/data/chrome-demo/user-data"$'\n'"https://example.com"
[[ "$(HOME="$real_home" "$fake_bin/launch-chrome" https://example.com)" == "$expected" ]]

write_launcher "$fake_bin/launch-firefox" firefox "$test_root/data/firefox-demo" firefox
expected="$real_home"$'\n'"--profile"$'\n'"$test_root/data/firefox-demo/profile"
[[ "$(HOME="$real_home" "$fake_bin/launch-firefox")" == "$expected" ]]
[[ -d "$test_root/data/firefox-demo/profile" ]]

write_launcher "$fake_bin/launch-slack" Slack "$test_root/data/slack-demo" home
bash -n "$fake_bin/launch-slack"
expected="$test_root/data/slack-demo/home"$'\n'"--flag"$'\n'"one"
[[ "$(HOME="$real_home" "$fake_bin/launch-slack" --flag one)" == "$expected" ]]
[[ -L "$test_root/data/slack-demo/home/Documents" ]]
[[ "$(readlink "$test_root/data/slack-demo/home/Documents")" == "$real_home/Documents" ]]
[[ ! -e "$test_root/data/slack-demo/home/Library" && ! -e "$test_root/data/slack-demo/home/Pictures" ]]
# Running it again must not fail on the existing links.
[[ "$(HOME="$real_home" "$fake_bin/launch-slack" again)" == "$test_root/data/slack-demo/home"$'\n'"again" ]]
if (write_launcher "$fake_bin/launch-bad" Slack "$test_root/data/x" nonsense) 2>/dev/null; then exit 1; fi

# --- Shortcuts for apps without a bundled CLI -----------------------------------------------
chrome_app="$test_root/Chrome - Demo.app"
mkdir -p "$chrome_app/Contents/Resources"
write_metadata "$chrome_app" slug chrome-demo
write_metadata "$chrome_app" family chromium
write_metadata "$chrome_app" shortcut chrome-chrome-demo
[[ "$(shortcut_for_app "$chrome_app" chrome-demo)" == chrome-chrome-demo ]]
write_shortcut chrome-demo "$chrome_app"
bash -n "$BIN_ROOT/chrome-chrome-demo"
grep -Fq '# Managed by Code-o-ween: chrome-demo' "$BIN_ROOT/chrome-chrome-demo"
grep -Fq '/usr/bin/open -n -a' "$BIN_ROOT/chrome-chrome-demo"
grep -Fq 'Chrome\ -\ Demo.app --args "$@"' "$BIN_ROOT/chrome-chrome-demo"
if grep -Fq -- '--user-data-dir' "$BIN_ROOT/chrome-chrome-demo"; then exit 1; fi

# --- Recipes --------------------------------------------------------------------------------
[[ "$(kind_for_bundle_id com.google.Chrome)" == chrome ]]
[[ "$(kind_for_bundle_id com.microsoft.VSCodeInsiders)" == vscode-insiders ]]
[[ "$(kind_for_bundle_id md.obsidian)" == obsidian ]]
if kind_for_bundle_id com.example.unknown; then exit 1; fi
if kind_for_bundle_id ""; then exit 1; fi
(load_kind slack; [[ "$KIND_FAMILY" == home && "$KIND_SHORTCUT" == slack && "$KIND_PREFIX" == Slack ]])
(load_kind vscodium; [[ "$KIND_FAMILY" == vscode && "$KIND_CANDIDATES" == VSCodium.app ]])
if (load_kind nonsense) 2>/dev/null; then exit 1; fi
[[ "$(source_env_name vscode-insiders)" == CODE_O_WEEN_VSCODE_INSIDERS_APP ]]
(load_kind vscode; [[ "$(CODE_O_WEEN_VSCODE_APP=/x/Code.app default_source_app)" == /x/Code.app ]])
(load_kind vscode; [[ "$(VSCODE_APP=/y/Code.app default_source_app)" == /y/Code.app ]])
(load_kind edge; [[ "$(CODE_O_WEEN_EDGE_APP=/z/Edge.app default_source_app)" == /z/Edge.app ]])
if (load_kind generic; default_source_app) 2>/dev/null; then exit 1; fi
# Captured first: grep -q closing the pipe early would turn into SIGPIPE under pipefail.
porcelain="$(list_kinds --porcelain)"
[[ "$(printf '%s\n' "$porcelain" | wc -l | tr -d ' ')" == 14 ]]
# Field 3 says whether the app is installed on this machine, so it is not asserted here.
[[ "$(awk -F'\t' '$1=="chrome"{print $2"|"$4"|"$6}' <<<"$porcelain")" == "Google Chrome|no|broken" ]] || fail "chrome recipe row"
[[ "$(awk -F'\t' '$1=="vscode"{print $2"|"$4"|"$6}' <<<"$porcelain")" == "Visual Studio Code|yes|verified" ]] || fail "vscode recipe row"
[[ "$(awk -F'\t' '$1=="slack"{print $6}' <<<"$porcelain")" == "unverified" ]] || fail "slack recipe status"
grep -Fq 'not working' <<<"$(list_kinds)"
(load_kind edge; [[ "$KIND_STATUS" == broken ]]; expect_fail assert_kind_usable)
(load_kind vscode; [[ "$KIND_STATUS" == verified ]]; assert_kind_usable 2>/dev/null)
(load_kind firefox; [[ "$KIND_STATUS" == unverified ]]; assert_kind_usable 2>/dev/null)
grep -Fq 'private HOME' <<<"$(list_kinds)"
# The generic recipe takes its names from the bundle and recognizes VS Code-style apps.
tool_app="$test_root/Some Tool.app"
mkdir -p "$tool_app/Contents/Resources/app/bin"
printf '{}' >"$tool_app/Contents/Resources/app/product.json"
(configure_kind_for_source generic "$tool_app"
  [[ "$KIND_LABEL" == "Some Tool" && "$KIND_PREFIX" == "Some Tool" && "$KIND_SHORTCUT" == some-tool && "$KIND_FAMILY" == vscode ]])
plain_app="$test_root/Plain.app"
mkdir -p "$plain_app/Contents/Resources"
(configure_kind_for_source generic "$plain_app"; [[ "$KIND_FAMILY" == home && "$KIND_PREFIX" == Plain ]])
(configure_kind_for_source chrome "$plain_app"; [[ "$KIND_FAMILY" == chromium && "$KIND_PREFIX" == Chrome ]])
[[ "$(detect_kind "$plain_app")" == generic ]]

# --- Discovery of disguises in the app folder ---------------------------------------------
mkdir -p "$APP_ROOT/Chrome - Work.app/Contents/Resources"
write_metadata "$APP_ROOT/Chrome - Work.app" slug work
write_metadata "$APP_ROOT/Chrome - Work.app" name Work
write_metadata "$APP_ROOT/Chrome - Work.app" kind chrome
write_metadata "$APP_ROOT/Chrome - Work.app" label "Google Chrome"
write_metadata "$APP_ROOT/Chrome - Work.app" extensions none
mkdir -p "$APP_ROOT/VS Code - Old.app/Contents/Resources"
write_metadata "$APP_ROOT/VS Code - Old.app" slug old
[[ "$(app_for_slug work)" == "$APP_ROOT/Chrome - Work.app" ]]
[[ "$(find_instances | tr -cd '\0' | wc -c | tr -d ' ')" == 2 ]] || fail "two disguises expected"
# One command per disguise at a time.
(lock_slug "$test_root" demo; expect_fail lock_slug "$test_root" demo; unlock_slug; lock_slug "$test_root" demo; unlock_slug)
[[ ! -e "$test_root/.lock-demo" ]] || fail "lock not released"
# A symlinked app root is followed, so disguises created through it are found again.
ln -s "$APP_ROOT" "$test_root/apps-link"
(APP_ROOT="$test_root/apps-link"; [[ "$(app_for_slug work)" == "$test_root/apps-link/Chrome - Work.app" ]]) || fail "symlinked app root not followed"
# A slug that is not a slug is never looked up.
if app_for_slug -- "--all" 2>/dev/null || app_for_slug "--all" 2>/dev/null; then fail "invalid slug looked up"; fi
# Two bundles with one slug are an error, not a coin toss.
mkdir -p "$APP_ROOT/Chrome - Work Copy.app/Contents/Resources"
write_metadata "$APP_ROOT/Chrome - Work Copy.app" slug work
expect_fail app_for_slug work
rm -rf -- "$APP_ROOT/Chrome - Work Copy.app"
[[ "$(app_for_slug old)" == "$APP_ROOT/VS Code - Old.app" ]]
if app_for_slug missing; then exit 1; fi
# A bundle that records no kind or name is a VS Code disguise named after its bundle.
[[ "$(kind_for_app "$APP_ROOT/VS Code - Old.app")" == vscode ]]
[[ "$(name_for_app "$APP_ROOT/VS Code - Old.app")" == "VS Code - Old" ]]
listing="$(list_instances)"
[[ "$listing" == *"Work"*"Google Chrome"*"-"* && "$listing" == *"VS Code - Old"*"Visual Studio Code"* ]]

# --- Names, colors, folders -----------------------------------------------------------------
validate_name "Cauldron 2 🎃"
for bad in "" "--all" "-x" "a/b" "a:b" " padded" "padded " $'line\nbreak' $'esc\033[31m'; do
  expect_fail validate_name "$bad"
done
[[ "$(color_hex teal)" == "#007F88" && "$(color_hex navy)" == "#1A237E" ]] || fail "color table"
[[ "$(canonical_color TEAL)" == teal && "$(canonical_color "#12ab9f")" == "#12AB9F" && "$(color_hex "#12ab9f")" == "#12AB9F" ]] || fail "color normalization"
for bad in mauve "#12ab9" "#12ab9fz" "12ab9f" 'red;x' ""; do expect_fail canonical_color "$bad"; done
[[ "$(color_names | wc -l | tr -d ' ')" == 15 ]] || fail "color names"
mkdir -p "$test_root/pin me"
[[ "$(resolve_folder "$test_root/pin me")" == "$(cd -P "$test_root/pin me" && pwd)" ]] || fail "resolve folder"
# An exported CDPATH must not redirect a relative folder that also exists under CDPATH.
mkdir -p "$test_root/bin/pin me"
cdpath_result="$(cd "$test_root/bin" && CDPATH="$test_root" bash -c 'source "$1"; resolve_folder "pin me"' _ "$cli")"
[[ "$cdpath_result" == "$(cd -P "$test_root/bin/pin me" && pwd)" ]] || fail "CDPATH affected folder resolution: $cdpath_result"
expect_fail resolve_folder "$test_root/missing"
mkdir -p "$test_root/profile"
apply_pinned_folder "$test_root/profile" set "$test_root/pin me"
[[ "$(read_profile_setting "$test_root/profile" pinned-folder)" == "$test_root/pin me" ]] || fail "pin folder"
apply_pinned_folder "$test_root/profile" clear
[[ -z "$(read_profile_setting "$test_root/profile" pinned-folder)" ]] || fail "unpin folder"

# --- Options that only apply to VS Code-style apps ------------------------------------------
(folder_action=set window_tint=""; assert_vscode_only_options vscode "Visual Studio Code")
(folder_action=""; window_tint=on; assert_vscode_only_options vscode "Visual Studio Code")
# The sourced function reads these two.
# shellcheck disable=SC2034
(folder_action="set"; window_tint=""; expect_fail assert_vscode_only_options chromium "Google Chrome")
# shellcheck disable=SC2034
(folder_action=""; window_tint="on"; expect_fail assert_vscode_only_options home "Slack")

# --- Settings folders: socket length, home folder, and ownership ----------------------------
assert_socket_path_fits "/Users/someone/.code-o-ween/demo"
expect_fail assert_socket_path_fits "/Users/someone/Library/Application Support/Some Rather Long Folder Name/a-rather-long-name"
# The limit is in bytes: 60 two-byte characters are 94 characters but 154 bytes.
expect_fail assert_socket_path_fits "/Users/$(printf 'ö%.0s' $(seq 1 60))/d"
expect_fail assert_safe_profile_location "$HOME"
expect_fail assert_safe_profile_location "$(printf '%s' "$HOME" | tr '[:lower:]' '[:upper:]')"
expect_fail assert_safe_profile_location "$(dirname "$HOME")"
assert_safe_profile_location "$HOME/.code-o-ween/demo"
profile_is_ours "$test_root/not-there" demo || fail "missing profile should be claimable"
# The home guard compares physical locations: a symlink to the home folder is still the home folder.
ln -s "$HOME" "$test_root/home-link"
expect_fail assert_safe_profile_location "$test_root/home-link"
expect_fail assert_safe_profile_location "$test_root/home-link/.."          # an ancestor, through the link
expect_fail assert_safe_profile_location "$HOME/./.code-o-ween/.."           # the home folder, spelled around
assert_safe_profile_location "$test_root/home-link/not-yet-created/demo"     # inside home is fine
[[ "$(physical_path "$test_root/home-link/new/deeper")" == "$(cd -P "$HOME" && pwd)/new/deeper" ]] || fail "physical_path through a symlink"
# An unmarked folder is never adopted, even one that looks like a settings folder in the default root.
(
  HOME="$test_root/fakehome"
  mkdir -p "$HOME/.code-o-ween/unmarked/user-data" "$HOME/.code-o-ween/unmarked/extensions"
  expect_fail profile_is_ours "$HOME/.code-o-ween/unmarked" unmarked
  mkdir -p "$test_root/elsewhere/work/user-data"
  expect_fail profile_is_ours "$test_root/elsewhere/work" work
  expect_fail claim_profile "$test_root/elsewhere/work" work
  [[ -d "$test_root/elsewhere/work/user-data" ]] || fail "refused folder was touched"
)
mkdir -p "$test_root/repo/src"
printf 'code\n' >"$test_root/repo/README.md"
expect_fail profile_is_ours "$test_root/repo" repo
expect_fail claim_profile "$test_root/repo" repo
claim_profile "$test_root/fresh" fresh
[[ "$(<"$test_root/fresh/$PROFILE_MARKER")" == fresh ]] || fail "profile marker"
expect_fail profile_is_ours "$test_root/fresh" other
# An existing file is not a missing folder: it must never pass as claimable or deletable.
printf 'data' >"$test_root/afile"
expect_fail profile_is_ours "$test_root/afile" afile
expect_fail assert_profile_ours "$test_root/afile" afile delete
# Slugs read back from metadata must look like slugs before they become arguments.
{ is_slug cauldron && is_slug "my-app-2"; } || fail "valid slugs rejected"
for bad in "--all" "-x" "Cauldron" "a--b" "a b" "" "a/b"; do if is_slug "$bad"; then fail "is_slug accepted '$bad'"; fi; done
# A symbolic link is never a settings folder: rm -rf would delete the link and keep the data.
ln -s "$test_root/fresh" "$test_root/fresh-link"
expect_fail claim_profile "$test_root/fresh-link" fresh
expect_fail assert_profile_ours "$test_root/fresh-link" fresh delete
assert_profile_ours "$test_root/fresh" fresh delete

printf 'PASS: profile persistence and ownership, metadata, shortcut ownership, symlink rejection, launchers for every family, recipes, discovery across folders, names, colors, folders, socket path limit\n'
