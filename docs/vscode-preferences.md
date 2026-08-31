# Visual Studio Code preferences

The `visual-studio-code` Homebrew cask installs the application, but it does
not restore the captain's per-user preferences. Home Manager now links the
tracked files below into VS Code's macOS user directory:

- `vscode/settings.json` -> `~/Library/Application Support/Code/User/settings.json`
- `vscode/keybindings.json` -> `~/Library/Application Support/Code/User/keybindings.json`

The files were captured byte-for-byte from the captain's existing files. At
the follow-up audit, `settings.json` was 3,475 bytes and `keybindings.json` was
532 bytes; both matched their tracked sources exactly. This preserves the Vim
system-clipboard setting and mode bindings, cursor style and color settings,
selected One Dark Pro and Material Icon themes, formatter choices, language
settings, and every other intentional setting already present. The JSONC
comment in `settings.json` is intentional. On first activation,
Home Manager's existing `backupFileExtension = "backup"` setting preserves any
regular live file as `.backup` before publishing the managed link; the audit
and capture did not modify the live files.

## Extension boundary

The Homebrew cask does not install extensions. The audit found 71 active user
extension IDs, captured one per line in `vscode/extensions.txt`. Home Manager
ensures every audited ID is present, including the extensions needed by the
tracked Vim, formatter, language, theme, icon, and other settings.

IDs are installed from the VS Code Marketplace when absent. Marketplace
versions and extension payloads are not pinned because the repository has no
extension-version convention; the audited `--show-versions` output was used
as evidence only. Home Manager does not remove extra locally installed
extensions. To add a deliberately installed extension in the future, add its
ID to `vscode/extensions.txt` and rebuild.

## Scope and future changes

The audit found no user snippets, no `User/profiles` directory, and no
profile-specific settings, keybindings, or snippets. The direct User files
besides the captured settings and keybindings were an empty `mcp.json` and an
empty `chatLanguageModels.json`; both remain excluded because those surfaces
are reserved for MCP and chat/model state that may contain secrets. The
following are also intentionally excluded: authentication or machine
metadata, `globalStorage`, workspace storage, history, extension global
state, caches, and installed extension payloads. These are transient,
machine-specific, or may contain secrets.

To add a preference, edit the tracked JSONC files and rebuild. If snippets or
profiles become intentional preferences, add their reviewed files under
`vscode/` and add matching `home.file` entries in `home.nix`; do not copy the
live application-data directories wholesale.
