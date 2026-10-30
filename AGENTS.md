# Working on Code-o-ween

Notes for coding agents and new contributors. The README says what the tool does; this file
says how the code is put together and what must not break.

## What it is

Code-o-ween clones a VS Code-style app, gives the clone a new bundle identifier, display name, icon and
ad-hoc signature, and starts it through a launcher that points it at its own settings folder.
The result is a separate app to macOS: own Dock icon, own ⌘-Tab entry, own logins. The original
app is never modified.

It is a Bash CLI with a thin SwiftUI manager on top. There is no build system, no package
manager, and no dependency beyond macOS and Apple Command Line Tools.

## Layout

| Path | What it is |
| --- | --- |
| `code-o-ween` | The whole CLI, one Bash script (~2,100 lines). Also sourced by the tests. |
| `ui/CodeOWeenApp.swift` | The manager app, one SwiftUI file. It reads disguise metadata and calls the CLI for every change. |
| `icons/` | Bundled `.icns` icons: eight colors for VS Code-style disguises, plus the app's own. |
| `build-ui.sh` | Compiles the manager into `~/Applications/Code-o-ween.app` with the CLI and icons inside it. |
| `build-dmg.sh` | Builds the manager into a staging folder and packages a disk image under `dist/`. |
| `install.sh` | Installs the CLI to `~/.local/share/code-o-ween` with a link in `~/.local/bin`, then runs `build-ui.sh`. |
| `set-repository.sh` | Rewrites every GitHub address in the README and the website for a given `OWNER/NAME`. |
| `tests/` | Shell tests; see below. `tests/ui/checks.swift` drives the manager's logic without clicking. |
| `docs/` | The GitHub Pages site: static HTML, CSS and JS, no build step. Deployed by `.github/workflows/pages.yml`. |
| `CHANGELOG.md` | Release notes. |

## Invariants

Each of these was learned the hard way. Keep them.

- **The source app is never modified.** Every change happens to a clone. `create` and `refresh`
  build the new bundle in a transaction folder and swap it in only at the end; a failure rolls
  back to the previous disguise (`create_instance`, `cleanup_create`).
- **Nothing is deleted unless Code-o-ween made it.** Settings folders carry a
  `.code-o-ween-profile` marker with the owning slug; terminal shortcuts carry a
  `# Managed by Code-o-ween: SLUG` line; the manager app is recognized by its bundle
  identifier. An unmarked folder is never adopted. The home folder and its ancestors are always
  refused, compared as physical paths. Symbolic links are refused as
  settings folders. See `profile_is_ours`, `assert_profile_ours`, `claim_profile`,
  `assert_shortcut_owned`.
- **Commands address disguises by slug, never by display name.** A slug read back from a bundle
  must pass `is_slug` before it becomes an argument (a bundle claiming the slug `--all` must not
  turn into `refresh --all`). The manager passes slugs too.
- **The manager never builds shell commands.** It runs the bundled CLI with an argument array
  and parses `--porcelain` output. Privileged logic lives in the CLI only, so the UI cannot drift
  from the reviewed path.
- **Signing stays hardened.** `sign_disguise` signs inside-out, keeps the hardened runtime,
  disables library validation (re-signed executables no longer share the publisher's Team ID
  with their frameworks), removes `com.apple.security.cs.allow-dyld-environment-variables`, and
  verifies its own output. A source bundle must pass `codesign --verify --deep --strict`;
  Visual Studio Code is pinned to Microsoft's Team ID.
- **Electron needs `CFBundleName` and the original executable name** to find its helper apps.
  Only `CFBundleExecutable` (the launcher), `CFBundleIdentifier`, `CFBundleDisplayName` and the
  icon change. `CFBundleIconName` is removed so an asset catalog cannot override the icon.
- **VS Code-style disguises never update themselves.** `"update.mode": "none"` is written on
  every create and refresh, and seeded by the launcher when it recreates a profile.
- **One disguise, one lock.** `lock_slug` takes `.lock-<slug>` in the app folder for the
  duration of a create, rebuild or remove.
- **Socket paths are short.** VS Code keeps its IPC socket under `--user-data-dir`; macOS
  limits socket paths to 103 bytes. `assert_socket_path_fits` counts bytes, not characters.

## Recipes

Each supported app is a recipe in `load_kind`: label, bundle name, bundle identifiers, optional
Team ID, and status. `ALL_KINDS` lists them: `vscode`, `vscode-insiders`, `vscodium`, and
`other` for any VS Code-style fork passed with `--source`. All are isolated the same way
(`--user-data-dir`, optional `--extensions-dir`, own Keychain item, shortcut on the bundled
CLI); `create` refuses a bundle without `Resources/app/product.json` and `bin/` before copying.

Recipe status is honest, not aspirational: `verified` only for Visual Studio Code, `unverified`
for apps that have not been run as disguises on a Mac. Do not promote a status without having
launched the disguise on a Mac.

## Bash conventions

- `set -euo pipefail` and `unset CDPATH` at the top of every script. Bash 3.2 is the system
  shell on macOS; avoid `declare -A`, `${var,,}`, `readarray` and other 4.x features.
- `die` for errors (prints `Error: …` to stderr, exits 1), `warn` for `Warning: …`, `note` for
  normal output. `run_quiet` shows a command's output only when it fails.
- Quote everything. Expand possibly empty arrays as `${arr[@]+"${arr[@]}"}`. Use `printf`, not
  `echo`. Use `local` in functions.
- **Never call a function that may `die` from a condition** (`if ! ( … )`, `$( … ) || true`):
  `exit` inside a condition does not stop the caller, and errexit is disabled inside it.
  `refresh --all` re-invokes the CLI per disguise for this reason.
- Generated scripts (launchers, shortcuts) are written from single-quoted heredoc lines; their
  `$variables` belong to the generated script. That is why `.shellcheckrc` disables SC2016.
- `shellcheck -x code-o-ween build-ui.sh build-dmg.sh install.sh tests/*.sh` must be clean.

## Swift conventions

- Target is macOS 13 (`build-ui.sh` passes `-target ARCH-apple-macos13.0`). Use
  `ObservableObject`, not the `@Observable` macro: some Command Line Tools installations lack
  `SwiftUIMacros`.
- The CLI is found at `Contents/Resources/cli/code-o-ween` inside the app bundle. Its standard
  output and standard error are read separately, through a temporary file, so neither can block.
- The App picker lists every recipe plus "Other app…", which must point at a VS Code-style
  bundle before Create is enabled; the CLI checks again.

## Tests

| Script | Needs | What it covers |
| --- | --- | --- |
| `tests/safety.sh` | Bash only, runs on Linux too | Sources the CLI and checks guards, metadata, slugs, generated launchers and shortcuts against fake executables. Seconds. |
| `tests/window-color.sh` | macOS, Visual Studio Code.app | The JSONC settings editor behind the window tint and emoji title. |
| `tests/rebuild.sh` | macOS, Visual Studio Code.app | create, update, refresh, remove in temporary folders, nothing launched. About a minute. |
| `tests/ui-check.sh` | macOS, Swift | Builds a harness app around the manager's code and runs `tests/ui/checks.swift`; renders screenshots. |
| `tests/launch-macos.sh` | macOS, Visual Studio Code.app | Creates a disguise, launches it through Launch Services, checks identity and Keychain item, removes it. Briefly opens a window. |

All tests use temporary app, data and bin roots (`CODE_O_WEEN_APP_ROOT`,
`CODE_O_WEEN_DATA_ROOT`, `CODE_O_WEEN_BIN_ROOT`) and clean up after themselves, including
Keychain items. Run `tests/safety.sh` and shellcheck after every change; run the macOS tests
for anything that touches bundles, signing, profiles or settings. Real verification happens on
a Mac; say plainly in a PR what was and was not run.

To try `build-ui.sh` without replacing the installed app, point it elsewhere:

```bash
CODE_O_WEEN_MANAGER_APP=/tmp/cow/Code-o-ween.app ./build-ui.sh
```

## Changing things

- A new feature or guard goes in the CLI first; the manager and the docs page follow.
- Colors live in `COLOR_TABLE` in the CLI; the docs page (`docs/index.html`, `docs/script.js`)
  and the manager mirror them, and every preset must keep a 4.5:1 contrast with white text.
- Keep the README's "by hand" section in step with what `create` actually does.
- The repository address appears only in `README.md` and `docs/index.html`; change it with
  `./set-repository.sh OWNER/NAME`, never by hand. The GoatCounter account on the website
  (`data-goatcounter` in `docs/index.html`) is separate and stays with whoever runs the site.
- Put the reason for a guard in a comment next to it, not just the fix; the comments are the
  only place that reasoning lives.
- Releasing: bump `VERSION` in `code-o-ween` (the build scripts read it from there), bump
  `CFBundleVersion` in `build-ui.sh`, add a `CHANGELOG.md` entry, tag `vX.Y.Z`. The release
  workflow checks the tag against `VERSION`, builds a universal disk image, attests it and
  attaches it to the GitHub release. A published image is never replaced; a fix is a new tag.
- There is no compatibility code for the layouts of unreleased prototypes (a `VS Code Instances`
  folder, `vscode-instance.*` metadata, unmarked settings folders, `VSCODE_INSTANCES_*`
  names). Do not add fallbacks for them.

## Gotchas

- `cp -cR` makes APFS clones, so a fresh disguise costs almost no disk space until the original
  app updates.
- Emoji and image icons are rendered by AppKit through JavaScript for Automation (`osascript`),
  with Quick Look and `sips` as fallbacks. The settings editor runs on VS Code's bundled Node
  (`run_bundled_node`), so it works without a system Node.
- A disguise keeps running after its last window closes; `assert_stopped` is a best-effort
  check of the process list, compared by both the given and the resolved app path.
- The Keychain item of a VS Code-style disguise is bound to the ad-hoc code hash of
  `Contents/MacOS/Code`, which changes with every VS Code version: one prompt per update is
  expected, not a bug.
- `docs/` is deployed from `main` by `pages.yml` and previewed per pull request by
  `preview.yml`; both push to the `gh-pages` branch, so they share a concurrency group.
