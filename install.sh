#!/bin/bash

set -euo pipefail

# A CDPATH in the environment would make `cd` resolve relative paths against other folders.
unset CDPATH

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${CODE_O_WEEN_INSTALL_DIR:-$HOME/.local/share/code-o-ween}"
BIN_DIR="${CODE_O_WEEN_BIN_ROOT:-$HOME/.local/bin}"

mkdir -p "$INSTALL_DIR" "$BIN_DIR"
# Absolute, physical paths: the command links point at INSTALL_DIR, so a relative override would
# make links that resolve relative to BIN_DIR instead, and the two must not be the same place or
# the first link would replace the installed script with a link to itself.
INSTALL_DIR="$(cd -P "$INSTALL_DIR" && pwd)"
BIN_DIR="$(cd -P "$BIN_DIR" && pwd)"
if [[ "$INSTALL_DIR" == "$BIN_DIR" ]]; then
  printf 'Refusing to install: the install folder and the command folder are the same place (%s).\n' "$INSTALL_DIR" >&2
  exit 1
fi
command_path="$BIN_DIR/code-o-ween"
if [[ -e "$command_path" || -L "$command_path" ]]; then
  if [[ "$(readlink "$command_path" 2>/dev/null || true)" != "$INSTALL_DIR/code-o-ween" ]]; then
    printf 'Refusing to overwrite existing command: %s\n' "$command_path" >&2
    exit 1
  fi
fi
# Only ever replace an earlier installation. INSTALL_DIR is overridable, and the icons/ and ui/
# folders are removed below, so an unrelated folder at that path must not be touched.
if [[ -e "$INSTALL_DIR" ]]; then
  [[ -d "$INSTALL_DIR" ]] || { printf 'Refusing to install into %s: not a folder.\n' "$INSTALL_DIR" >&2; exit 1; }
  if [[ -n "$(ls -A "$INSTALL_DIR")" && ! -f "$INSTALL_DIR/code-o-ween" ]]; then
    printf 'Refusing to install into %s: it is not empty and does not contain an earlier Code-o-ween installation.\n' "$INSTALL_DIR" >&2
    exit 1
  fi
fi

# Stage everything, then move it into place: a running `code-o-ween` keeps reading its old file
# instead of bytes from the new one.
staging="$(mktemp -d "$INSTALL_DIR/.install.XXXXXX")"
trap 'rm -rf -- "$staging"' EXIT
cp "$SCRIPT_DIR/code-o-ween" "$SCRIPT_DIR/build-ui.sh" "$staging/"
cp -R "$SCRIPT_DIR/icons" "$SCRIPT_DIR/ui" "$staging/"
chmod +x "$staging/code-o-ween" "$staging/build-ui.sh"
for item in icons ui; do
  rm -rf -- "${INSTALL_DIR:?}/$item"
  mv "$staging/$item" "$INSTALL_DIR/$item"
done
mv -f "$staging/build-ui.sh" "$INSTALL_DIR/build-ui.sh"
mv -f "$staging/code-o-ween" "$INSTALL_DIR/code-o-ween"
ln -sfn "$INSTALL_DIR/code-o-ween" "$BIN_DIR/code-o-ween"

printf 'Installed Code-o-ween at %s\n' "$BIN_DIR/code-o-ween"
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  printf '\nAdd this line to ~/.zshrc, then open a new terminal:\n'
  # The folder that was actually used, shell-quoted, not the default one.
  printf '  export PATH=%q:"$PATH"\n' "$BIN_DIR"
fi
printf '\nTry:\n  code-o-ween create Cauldron --color orange --emoji "🎃" --extensions isolated\n'
printf '  code-o-ween create Nightly --app vscode-insiders --color purple --emoji "👻"\n'
printf '  code-o-ween apps\n'

if [[ "$(uname -s)" == "Darwin" ]] && command -v xcrun >/dev/null && xcrun --find swiftc >/dev/null 2>&1; then
  if "$INSTALL_DIR/build-ui.sh"; then
    printf 'Open "Code-o-ween" from your Applications folder.\n'
  else
    printf '\nThe command-line utility was installed, but the optional manager UI could not be built.\n' >&2
  fi
else
  printf '\nManager UI skipped: Apple Command Line Tools with Swift are required.\n'
  printf 'The command-line utility is fully installed.\n'
fi
