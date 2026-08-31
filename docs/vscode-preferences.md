# Visual Studio Code preferences

The `visual-studio-code` Homebrew cask installs the application, but it does
not restore the captain's per-user preferences. Home Manager now links the
tracked files below into VS Code's macOS user directory:

- `vscode/settings.json` -> `~/Library/Application Support/Code/User/settings.json`
- `vscode/keybindings.json` -> `~/Library/Application Support/Code/User/keybindings.json`

The files were captured byte-for-byte from the captain's existing files. This
preserves the Vim system-clipboard setting and mode bindings, cursor style and
color settings, selected One Dark Pro and Material Icon themes, formatter
choices, language settings, and other intentional settings already present.
The JSONC comment in `settings.json` is intentional. On first activation,
Home Manager's existing `backupFileExtension = "backup"` setting preserves any
regular live file as `.backup` before publishing the managed link; the audit
and capture did not modify the live files.

## Extension boundary

The Homebrew cask does not install extensions. Home Manager ensures only the
extensions required by the tracked preferences are present:

- `pkief.material-icon-theme` for `workbench.iconTheme`
- `vscodevim.vim` for the `vim.*` settings
- `zhuangtongfa.material-theme` for the One Dark Pro theme and `oneDarkPro.*`
  settings

The extension IDs are installed from the VS Code Marketplace when absent;
Marketplace versions and the other extensions on the captain's machine are
not pinned. The audit found 71 installed extension IDs. To restore any other
extension intentionally, run this on the fresh machine for each ID:

```sh
code --install-extension publisher.extension-id
```

## Scope and future changes

The audit found no user snippets and no VS Code profiles. The following are
intentionally excluded: authentication or machine metadata, `mcp.json`,
`chatLanguageModels.json`, `globalStorage`, workspace storage, history,
extension global state, caches, and installed extension payloads. These are
transient, machine-specific, or may contain secrets.

To add a preference, edit the tracked JSONC files and rebuild. If snippets or
profiles become intentional preferences, add their reviewed files under
`vscode/` and add matching `home.file` entries in `home.nix`; do not copy the
live application-data directories wholesale.
