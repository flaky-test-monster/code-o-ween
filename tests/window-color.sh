#!/bin/bash
# Checks the settings.json editor behind the window tint and emoji title against tricky JSONC files.
# Needs Visual Studio Code.app (its bundled Node runs the editor); no disguise is created.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
skip_unless_macos_with_vscode
# shellcheck source=../code-o-ween
source "$cli"
# default_source_app reads the loaded recipe.
load_kind vscode
vscode="$(default_source_app)"

test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
profile="$test_root/profile"
settings="$profile/user-data/User/settings.json"
tint() { apply_window_settings "$vscode" "$profile" "$1" "${2:-}" keep "" 2>/dev/null; }
title() { apply_window_settings "$vscode" "$profile" keep "" "$1" "${2:-}" 2>/dev/null; }
pin_updates() { apply_window_settings "$vscode" "$profile" keep "" keep "" set 2>/dev/null; }
valid_json() { ELECTRON_RUN_AS_NODE=1 "$vscode/Contents/MacOS/Code" -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$settings"; }
# For fixtures that keep comments: strips them (and trailing commas) the way VS Code tolerates, then parses.
valid_jsonc() { ELECTRON_RUN_AS_NODE=1 "$vscode/Contents/MacOS/Code" -e 'let t = require("fs").readFileSync(process.argv[1], "utf8"); t = t.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/.*$/gm, "").replace(/,(\s*[}\]])/g, "$1"); JSON.parse(t)' "$settings"; }
default_title='${dirty}${activeEditorShort}${separator}${rootName}${separator}${profileName}${separator}${appName}'
contains() { grep -Fq -- "$1" "$settings" || { cat "$settings" >&2; fail "$2"; }; }

# Only the exact title Code-o-ween installed is managed; a custom prefix on the default title is the user's.
title set 🎃
contains '"window.title": "🎃 ${dirty}' "emoji title not set"
[[ "$(cat "$profile/window-title")" == "🎃 $default_title" ]] || fail "installed title not recorded"
title set 👻
contains '"window.title": "👻 ${dirty}' "recorded title not replaced by the new emoji"
title clear
if grep -Fq 'window.title' "$settings"; then fail "managed title not cleared"; fi
[[ ! -e "$profile/window-title" ]] || fail "title record not cleared"
printf '{ "window.title": "Work %s" }' "$default_title" >"$settings"
title set 🎃
contains "\"window.title\": \"Work \${dirty}" "custom-prefix title was overwritten"
title clear
contains "\"window.title\": \"Work \${dirty}" "custom-prefix title was removed"
rm -f "$settings"

# Missing settings file: created with the tint.
tint set purple
contains '"titleBar.activeBackground": "#7E57C2"' "tint not written to a new file"

# Duplicate keys: VS Code reads the last one, so that is the one pinned and the one that counts.
printf '{ "update.mode": "none", "update.mode": "default" }' >"$settings"
pin_updates
effective() { ELECTRON_RUN_AS_NODE=1 "$vscode/Contents/MacOS/Code" -e 'const t=require("fs").readFileSync(process.argv[1],"utf8"); process.stdout.write(String(JSON.parse(t)[process.argv[2]]))' "$settings" "$1"; }
[[ "$(effective update.mode)" == none ]] || { cat "$settings" >&2; fail "last update.mode occurrence not pinned"; }

# An invalid literal anywhere in the file leaves it untouched.
printf '{ "editor.fontSize": invalid }' >"$settings"
if tint set purple; then fail "edited a file with an invalid literal"; fi
[[ "$(<"$settings")" == '{ "editor.fontSize": invalid }' ]] || fail "invalid file was changed"

# Comments and unrelated colors inside workbench.colorCustomizations survive tinting and untinting.
cat >"$settings" <<'JSON'
{
  "workbench.colorCustomizations": {
    // my own colors
    "editor.background": "#101010",
    "titleBar.activeBackground": "#AAAAAA" /* stale tint */
  }
}
JSON
tint set purple
contains '// my own colors' "comment inside colorCustomizations lost on tint"
contains '"editor.background": "#101010"' "user color lost on tint"
contains '"titleBar.activeBackground": "#7E57C2"' "managed key not updated in place"
if grep -Fq '#AAAAAA' "$settings"; then fail "stale managed value kept"; fi
valid_jsonc || fail "tinted nested object is not valid JSON"
tint clear
contains '// my own colors' "comment inside colorCustomizations lost on untint"
contains '"editor.background": "#101010"' "user color lost on untint"
if grep -Fq 'titleBar' "$settings"; then fail "managed keys not removed"; fi
valid_jsonc || fail "untinted nested object is not valid JSON"
# When only managed keys were there, untinting removes the empty object too.
printf '{ "a": 1 }' >"$settings"
tint set purple
tint clear
if grep -Fq 'colorCustomizations' "$settings"; then cat "$settings" >&2; fail "empty colorCustomizations left behind"; fi

# Comment-only objects keep their comments when a property is added to them.
printf '{ "workbench.colorCustomizations": { /* keep */ } }' >"$settings"
tint set purple
contains '/* keep */' "comment in an empty colors object lost"
contains '"titleBar.activeBackground": "#7E57C2"' "tint not added to a comment-only object"
valid_jsonc || fail "comment-only object edit is not valid JSON"
printf '{ /* top */ }' >"$settings"
pin_updates
contains '/* top */' "comment in an empty settings object lost"
contains '"update.mode": "none"' "update.mode not added to a comment-only object"
valid_jsonc || fail "comment-only settings edit is not valid JSON"

# Clearing keeps an object that still holds a comment, and never touches an earlier duplicate.
printf '{ "workbench.colorCustomizations": { /* mine */ "titleBar.activeBackground": "#111111" } }' >"$settings"
tint clear
contains '/* mine */' "comment lost when clearing emptied the object"
contains 'colorCustomizations' "object holding a comment was removed"
printf '{ "workbench.colorCustomizations": { "editor.background": "#101010" }, "workbench.colorCustomizations": { "titleBar.activeBackground": "#222222" } }' >"$settings"
tint clear
contains '"editor.background": "#101010"' "earlier duplicate object removed"
[[ "$(grep -o 'colorCustomizations' "$settings" | wc -l | tr -d ' ')" == 2 ]] || { cat "$settings" >&2; fail "clearing changed the number of colorCustomizations occurrences"; }
if grep -Fq titleBar "$settings"; then fail "managed key survived clearing"; fi

# A disguise must never update itself: update.mode is pinned, and a user value is replaced.
pin_updates
contains '"update.mode": "none"' "update.mode not pinned"
printf '{ "update.mode": "default", "editor.fontSize": 14 }' >"$settings"
pin_updates
contains '"update.mode": "none"' "update.mode not overridden"
contains '"editor.fontSize": 14' "pinning update.mode disturbed other settings"
if [[ "$(grep -c 'update.mode' "$settings")" != 1 ]]; then fail "update.mode duplicated"; fi
tint set purple
contains '"update.mode": "none"' "tint edit dropped update.mode"

# Comments, trailing commas, other customizations, and look-alike strings survive.
cat >"$settings" <<'JSON'
// top comment
{
  "editor.fontSize": 14, // trailing comment
  /* block */ "workbench.colorTheme": "Default Dark Modern",
  "workbench.colorCustomizations": {
    "editor.background": "#101010", // a comment after a trailing comma
    "statusBar.background": "#FF0000", // another
  },
  "files.exclude": { "**/,}": true },
}
JSON
chmod 600 "$settings"
tint set "#FFD54F"
contains '// top comment' "top comment lost"
contains '"editor.fontSize": 14, // trailing comment' "trailing comment lost"
contains '"**/,}": true' "unrelated string changed"
contains '"editor.background": "#101010"' "user color customization lost"
contains '"statusBar.foreground": "#1F1F1F"' "dark text not chosen for a light color"
[[ "$(stat -f %Lp "$settings")" == 600 ]] || fail "file permissions not kept"

# Clearing removes only the managed keys.
tint clear
if grep -Fq 'titleBar' "$settings"; then fail "tint not removed"; fi
contains '"editor.background": "#101010"' "user color customization removed"

# Comment-only files keep their comments.
printf '// just a comment\n' >"$settings"
tint set blue
contains '// just a comment' "comment-only file overwritten"
contains '"titleBar.activeBackground": "#2276D2"' "tint not added to comment-only file"

# Invalid files are left untouched.
printf '{"a": ' >"$settings"
tint set blue || true
[[ "$(<"$settings")" == '{"a": ' ]] || fail "invalid file was modified"

# Symlinked settings stay symlinks; broken links are refused rather than replaced.
printf '{}' >"$test_root/real.json"
rm -f "$settings"
ln -s "$test_root/real.json" "$settings"
tint set blue
{ [[ -L "$settings" ]] && grep -Fq 'titleBar' "$test_root/real.json"; } || fail "symlink replaced"
rm -f "$settings"
ln -s "$test_root/missing.json" "$settings"
tint set blue || true
[[ -L "$settings" && ! -e "$test_root/missing.json" ]] || fail "broken symlink replaced"

# Emoji title: added to the default title, replaced when the emoji changes, removed cleanly.
rm -f "$settings"
printf '{\n  "editor.fontSize": 14\n}\n' >"$settings"
title set "🎃"
contains "\"window.title\": \"🎃 $default_title\"" "emoji title not added"
title set "👻"
contains "\"window.title\": \"👻 $default_title\"" "emoji title not replaced"
tint set teal
title clear
if grep -Fq 'window.title' "$settings"; then fail "emoji title not removed"; fi
contains '"editor.fontSize": 14' "other settings lost when removing the title"
valid_json || fail "settings invalid after removing the title"
# Removing the last property takes the comma before it with it. The title counts as ours only
# because the profile records it as the one Code-o-ween installed.
printf '{\n  "editor.fontSize": 14,\n  "window.title": "🦇 %s"\n}\n' "$default_title" >"$settings"
printf '🦇 %s' "$default_title" >"$profile/window-title"
title clear
[[ "$(<"$settings")" == $'{\n  "editor.fontSize": 14\n}' ]] || { cat "$settings" >&2; fail "last-property removal"; }
# A customized title is never touched.
printf '{ "window.title": "${rootName} — work" }' >"$settings"
title set "🎃" >/dev/null
title clear
contains '"window.title": "${rootName} — work"' "custom window.title changed"

printf 'PASS: window settings edits keep comments, permissions, user customizations, custom titles, invalid files, and symlinks\n'
