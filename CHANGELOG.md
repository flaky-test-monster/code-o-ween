# Changelog

## Unreleased

- The home-folder guard also refused `~/.code-o-ween/..` only when `~/.code-o-ween` existed;
  paths whose last part does not exist yet are now normalized before the check. No command
  could build such a path, so no data was at risk, but the guard is meant to hold on its own.
- Launchers no longer show a refusal as an alert when run from a terminal, or when
  `CODE_O_WEEN_NO_ALERT` is set, which the tests do.
- `install.sh` no longer suggests a recipe that does not exist.

## 0.1.0: first release

Code-o-ween disguises VS Code and other Mac apps: each disguise is a separate copy of the app
with its own Dock icon, ⌘-Tab entry, settings, sessions and logins.

- `create`, `update`, `open`, `list`, `apps`, `colors`, `refresh`, `remove`, `doctor` and `gui`
  commands; recipes for Visual Studio Code (verified), VS Code Insiders, VSCodium, and any other
  VS Code-style app through `--source`.
- Halloween costumes, any emoji, or a custom image as the icon; 15 preset colors plus any
  `#RRGGBB`; a window tint and emoji title for VS Code-style apps; a pinned project folder.
- A SwiftUI manager app for creating, editing, refreshing and removing disguises.
- Disguises keep the app's hardened runtime, get their own code signature identity and
  Keychain item, and never update themselves.
- Settings folders carry an ownership marker; Code-o-ween refuses to use or delete a folder it
  did not create, a symbolic link, or the home folder.
- `install.sh`, `build-ui.sh`, `build-dmg.sh`, a release workflow with build provenance
  attestation, and a GitHub Pages site.
