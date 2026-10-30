#!/bin/bash
# Creates, updates, refreshes, and removes disguises in temporary folders without launching them.
# Needs Visual Studio Code.app (cloned with APFS, so this takes about a minute).
set -euo pipefail
source "$(dirname "$0")/lib.sh"
skip_unless_macos_with_vscode
use_temp_roots
suffix="$(random_suffix)"
name="Rebuild Test $suffix" slug="rebuild-test-$suffix"
other="Other Test $suffix" other_slug="other-test-$suffix"
cleanup() {
  local s
  for s in "$slug" "$other_slug"; do
    /usr/bin/security delete-generic-password -s "Code-o-ween $s Safe Storage" >/dev/null 2>&1 || true
  done
  rm -rf -- "$test_root" "$data_root"
}
trap cleanup EXIT

app="$CODE_O_WEEN_APP_ROOT/VS Code - $name.app"
profile="$data_root/$slug"
meta() { cat "$app/Contents/Resources/code-o-ween.$1"; }
mkdir -p "$test_root/project"

# Guards that stop before any copying.
expect_fail "$cli" create --all
expect_fail "$cli" create "Bad" --source "$test_root"
mkdir -p "$data_root/taken/src"
printf 'not ours\n' >"$data_root/taken/notes.txt"
expect_fail "$cli" create Taken
[[ -f "$data_root/taken/notes.txt" ]] || fail "foreign folder touched"
fake="$test_root/Fake Code.app"
mkdir -p "$fake/Contents/MacOS" "$fake/Contents/Resources/app/bin"
printf '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>Code</string></dict></plist>' >"$fake/Contents/Info.plist"
printf '#!/bin/sh\n' >"$fake/Contents/MacOS/Code"
cp "$fake/Contents/MacOS/Code" "$fake/Contents/Resources/app/bin/code"
chmod +x "$fake/Contents/MacOS/Code" "$fake/Contents/Resources/app/bin/code"
expect_fail "$cli" create Unsigned --source "$fake"
expect_fail "$cli" create Unsigned --source "$fake" --trust-source

# Create: metadata, signing, profile marker, tint.
"$cli" create "$name" --emoji "🎃" --color orange --extensions isolated --folder "$test_root/project" >/dev/null
[[ "$(meta icon-kind)/$(meta emoji)/$(meta extensions)/$(meta color)" == "emoji/🎃/isolated/orange" ]] || fail "create metadata"
/usr/bin/codesign --verify --deep --strict "$app" || fail "signature"
signature="$(/usr/bin/codesign -dv "$app/Contents/MacOS/Code" 2>&1)"
[[ "$signature" == *"(adhoc,runtime)"* ]] || fail "hardened runtime missing"
[[ "$signature" == *"Identifier=local.code-o-ween.$slug.code"* ]] || fail "per-disguise identifier"
[[ "$(cat "$profile/.code-o-ween-profile")" == "$slug" ]] || fail "profile marker"
[[ "$(cat "$profile/window-tint")" == on ]] || fail "new disguise not tinted"
grep -Fq '"titleBar.activeBackground": "#BF4F00"' "$profile/user-data/User/settings.json" || fail "tint not applied"
grep -Fq '"window.title": "🎃 ${dirty}' "$profile/user-data/User/settings.json" || fail "emoji not added to the window title"
grep -Fq '"update.mode": "none"' "$profile/user-data/User/settings.json" || fail "disguise may update itself"
# A settings file that cannot be edited fails the create and leaves nothing behind: a disguise is
# never installed without update.mode pinned.
broken_slug="broken-$suffix"
mkdir -p "$data_root/$broken_slug/user-data/User"
printf '%s' "$broken_slug" >"$data_root/$broken_slug/.code-o-ween-profile"
ln -s "$data_root/nowhere" "$data_root/$broken_slug/user-data/User/settings.json"
if output="$("$cli" create "Broken $suffix" --emoji "💀" 2>&1)"; then fail "create succeeded with an uneditable settings file"; fi
[[ "$output" == *"could not update the settings"* ]] || fail "settings failure message: $output"
[[ ! -e "$CODE_O_WEEN_APP_ROOT/VS Code - Broken $suffix.app" ]] || fail "uninstallable disguise was left behind"
[[ ! -e "$CODE_O_WEEN_BIN_ROOT/code-$broken_slug" ]] || fail "shortcut written for a failed create"
# update writes only into a settings folder it owns: tampered metadata pointing at someone's
# folder that happens to end in the slug is refused, on the direct path as well.
profile_meta="$app/Contents/Resources/code-o-ween.profile"
real_profile="$(cat "$profile_meta")"
mkdir -p "$test_root/project/$slug"
printf 'theirs' >"$test_root/project/$slug/notes.txt"
printf '%s' "$test_root/project/$slug" >"$profile_meta"
expect_fail "$cli" update "$name" --window-color off
expect_fail "$cli" update "$name" --no-folder
[[ "$(cat "$test_root/project/$slug/notes.txt")" == theirs && ! -e "$test_root/project/$slug/window-tint" ]] || fail "update wrote into a folder it does not own"
printf '%s' "$real_profile" >"$profile_meta"

# A combined folder and tint change applies the folder only after the tint edit succeeded.
settings_file="$profile/user-data/User/settings.json"
pin_before="$(cat "$profile/pinned-folder" 2>/dev/null || true)"
mv "$settings_file" "$settings_file.bak"
ln -s "$data_root/nowhere" "$settings_file"
expect_fail "$cli" update "$name" --folder "$test_root" --window-color on
[[ "$(cat "$profile/pinned-folder" 2>/dev/null || true)" == "$pin_before" ]] || fail "folder changed although the tint edit failed"
rm -f "$settings_file"
mv "$settings_file.bak" "$settings_file"

# refresh accepts fresh trust for one disguise, never for all of them.
"$cli" refresh "$slug" --trust-source >/dev/null
expect_fail "$cli" refresh --all --trust-source

# A settings folder that went missing is recreated with its marker by a direct update, so the
# other commands keep accepting it, and with update.mode pinned, so the copy cannot update itself.
mv "$profile" "$profile.away"
"$cli" update "$name" --window-color off >/dev/null
[[ "$(cat "$profile/.code-o-ween-profile")" == "$slug" ]] || fail "recreated profile has no marker"
grep -Fq '"update.mode": "none"' "$profile/user-data/User/settings.json" || fail "recreated profile not pinned"
# A disguise being worked on by another command cannot be rebuilt or removed in parallel.
mkdir "$CODE_O_WEEN_APP_ROOT/.lock-$slug"
expect_fail "$cli" refresh "$slug"
expect_fail "$cli" remove "$name" --yes
rmdir "$CODE_O_WEEN_APP_ROOT/.lock-$slug"
[[ -e "$app" ]] || fail "locked disguise was removed"
rm -rf "$profile"
mv "$profile.away" "$profile"

# A symlinked settings folder is refused rather than having only the link deleted.
mv "$profile" "$profile.real"
ln -s "$profile.real" "$profile"
expect_fail "$cli" remove "$name" --delete-data --yes
[[ -e "$app" && -d "$profile.real" && -f "$profile.real/.code-o-ween-profile" ]] || fail "refusing a symlinked profile destroyed something"
rm "$profile"
mv "$profile.real" "$profile"

# A broken recipe is refused even behind --app generic.
if [[ -d "/Applications/Google Chrome.app" ]]; then
  apps_before="$(find "$CODE_O_WEEN_APP_ROOT" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"
  if output="$("$cli" create "Browse $suffix" --app generic --source "/Applications/Google Chrome.app" 2>&1)"; then fail "broken bundle accepted behind --app generic"; fi
  [[ "$output" == *"do not work yet"* ]] || fail "generic override refusal message: $output"
  [[ "$(find "$CODE_O_WEEN_APP_ROOT" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" == "$apps_before" ]] || fail "generic override left an app behind"
fi

# install.sh: a relative install folder still yields working links, and install == bin is refused.
# The manager build is pointed into the test folder so the real ~/Applications is never touched.
(cd "$test_root" && CODE_O_WEEN_INSTALL_DIR=rel-install CODE_O_WEEN_BIN_ROOT="$test_root/ibin" \
  CODE_O_WEEN_MANAGER_APP="$test_root/Manager.app" "$package_dir/install.sh" >/dev/null 2>&1) || fail "install.sh with a relative folder failed"
[[ -x "$test_root/ibin/code-o-ween" && "$("$test_root/ibin/code-o-ween" --version)" == Code-o-ween* ]] || fail "relative install produced a broken command link"
expect_fail env CODE_O_WEEN_INSTALL_DIR="$test_root/same" CODE_O_WEEN_BIN_ROOT="$test_root/same" \
  CODE_O_WEEN_MANAGER_APP="$test_root/Manager2.app" "$package_dir/install.sh"
[[ ! -e "$test_root/same/code-o-ween" ]] || fail "install into the command folder went ahead"

# Chromium recipes are refused before anything is copied.
if output="$("$cli" create "Browse $suffix" --app chrome 2>&1)"; then fail "chrome recipe accepted"; fi
[[ "$output" == *"do not work yet"* ]] || fail "chrome refusal message: $output"
[[ ! -e "$CODE_O_WEEN_APP_ROOT/Chrome - Browse $suffix.app" ]] || fail "chrome refusal left an app behind"
expect_fail "$cli" create "$name"

# A second disguise, with a custom color and a built-in icon (drawn, since no ICNS exists for it),
# gets a different code hash (separate Keychain access).
"$cli" create "$other" --color "#12ab9f" --window-color off >/dev/null
other_app="$CODE_O_WEEN_APP_ROOT/VS Code - $other.app"
[[ "$(cat "$other_app/Contents/Resources/code-o-ween.color")" == "#12AB9F" ]] || fail "custom color not normalized"
[[ -s "$other_app/Contents/Resources/code-o-ween.icns" ]] || fail "no icon for a custom color"
if cmp -s "$other_app/Contents/Resources/code-o-ween.icns" "$package_dir/icons/teal.icns"; then fail "custom color used a bundled icon"; fi
cdhash() { /usr/bin/codesign -dvvv "$1/Contents/MacOS/Code" 2>&1 | grep CDHash=; }
[[ "$(cdhash "$app")" != "$(cdhash "$other_app")" ]] || fail "disguises share a code hash"
# An untinted disguise still gets update.mode pinned, and nothing else.
other_settings="$data_root/$other_slug/user-data/User/settings.json"
grep -Fq '"update.mode": "none"' "$other_settings" || fail "untinted disguise may update itself"
if grep -Fq 'titleBar' "$other_settings"; then fail "untinted disguise got a tint"; fi

# Update and refresh keep everything they don't change.
"$cli" update "$name" --color purple >/dev/null
[[ "$(meta icon-kind)/$(meta emoji)/$(meta extensions)/$(meta color)" == "emoji/🎃/isolated/purple" ]] || fail "update lost metadata"
[[ "$(cat "$profile/pinned-folder")" == "$(cd -P "$test_root/project" && pwd)" ]] || fail "update lost pinned folder"
"$cli" update "$name" --built-in-icon >/dev/null
if grep -Fq 'window.title' "$profile/user-data/User/settings.json"; then fail "emoji title kept after switching to the built-in icon"; fi
"$cli" update "$name" --emoji "🎃" >/dev/null
before="$(cdhash "$app")"
"$cli" refresh "$slug" >/dev/null
[[ "$(cdhash "$app")" == "$before" ]] || fail "refresh changed the code hash (would re-prompt for Keychain access)"
"$cli" update "$name" --window-color off >/dev/null
if grep -Fq titleBar "$profile/user-data/User/settings.json"; then fail "tint not cleared"; fi

# Disguises from before window tints existed are not tinted by a refresh.
rm -f "$profile/window-tint"
printf '{ "titleBar.activeBackground": "#123456" }' >"$profile/user-data/User/settings.json"
"$cli" refresh "$slug" >/dev/null
grep -Fq '#123456' "$profile/user-data/User/settings.json" || fail "refresh changed an untinted disguise's settings"

# refresh --all keeps going after a failure and reports it.
printf 'mauve' >"$other_app/Contents/Resources/code-o-ween.color"
if output="$("$cli" refresh --all 2>&1)"; then fail "refresh --all hid a failure"; fi
[[ "$output" == *"Rebuilt: $app"* && "$output" == *"could not refresh"* ]] || fail "refresh --all output: $output"

# Remove refuses to delete a folder it does not own (for example tampered metadata pointing at
# a project), then deletes only what it owns.
printf 'teal' >"$other_app/Contents/Resources/code-o-ween.color"
foreign="$test_root/code/$slug"
mkdir -p "$foreign/src"
printf 'keep me\n' >"$foreign/README.md"
printf '%s' "$foreign" >"$app/Contents/Resources/code-o-ween.profile"
expect_fail "$cli" remove "$name" --delete-data --yes
[[ -d "$app" && -f "$foreign/README.md" ]] || fail "removed despite refusal"
printf '%s' "$profile" >"$app/Contents/Resources/code-o-ween.profile"
"$cli" remove "$name" --delete-data --yes >/dev/null
[[ ! -e "$app" && ! -e "$profile" && ! -e "$CODE_O_WEEN_BIN_ROOT/code-$slug" ]] || fail "remove left files behind"

printf 'PASS: create/update/refresh/remove metadata, custom colors, emoji title, signing, profile ownership, source verification, tint migration, refresh --all failures\n'
