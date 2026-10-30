# shellcheck shell=bash
# Shared helpers for the test scripts. Source it after `set -euo pipefail`.

package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Generated launchers show their refusals as alerts for Finder launches; a test must not wait
# for someone to click one.
export CODE_O_WEEN_NO_ALERT=1
# Used by the scripts that source this file.
# shellcheck disable=SC2034
cli="$package_dir/code-o-ween"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

# Runs a command in a subshell and fails the test if it succeeds.
expect_fail() {
  if ("$@") >/dev/null 2>&1; then fail "expected failure: $*"; fi
}

# Usage: wait_for SECONDS COMMAND... — polls every half second.
wait_for() {
  local tries=$(($1 * 2))
  shift
  while ((tries-- > 0)); do
    if "$@"; then return 0; fi
    /bin/sleep 0.5
  done
  return 1
}

skip_unless_macos_with_vscode() {
  [[ "$(uname -s)" == Darwin ]] || { printf 'SKIP: macOS only\n'; exit 0; }
  [[ -d "${VSCODE_APP:-/Applications/Visual Studio Code.app}" ]] || { printf 'SKIP: Visual Studio Code.app not found\n'; exit 0; }
}

# Creates temporary app/data/bin roots and exports them for the CLI. The data root is under
# /tmp because VS Code's IPC socket path inside it must stay short.
use_temp_roots() {
  test_root="$(cd -P "$(mktemp -d "${TMPDIR:-/tmp}/cow-test.XXXXXX")" && pwd)"
  data_root="$(cd -P "$(mktemp -d /tmp/cow.XXXXXX)" && pwd)"
  export CODE_O_WEEN_APP_ROOT="$test_root/apps"
  export CODE_O_WEEN_DATA_ROOT="$data_root"
  export CODE_O_WEEN_BIN_ROOT="$test_root/bin"
}

random_suffix() {
  printf '%04x%04x' "$RANDOM" "$RANDOM"
}
