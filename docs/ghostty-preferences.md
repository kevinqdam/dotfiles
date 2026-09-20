# Ghostty preferences

The `ghostty` Homebrew cask installs the application. Home Manager links the
tracked config below into Ghostty's macOS default location:

- `ghostty/config.ghostty` -> `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty`

The destination is a read-only symlink into the Home Manager generation, not
back to the editable checkout. Changing the tracked source does not change
Ghostty until the selected clone's `./rebuild.sh` runs. Do not write through
the managed link with `:w!`, delete the link, or sudo-edit Nix store paths.

## Terminal Vim workflow

Global `EDITOR` and `VISUAL` stay unset. Pi still gets Vim only through
`nix/pi-with-vim.nix`. A zsh alias scopes the same editor to Ghostty's
terminal config command:

```sh
alias ghostty-config='env VISUAL=vim EDITOR=vim /Applications/Ghostty.app/Contents/MacOS/ghostty +edit-config'
```

`env` limits those variables to the launched process. The explicit
`/Applications/Ghostty.app/Contents/MacOS/ghostty` path works from ordinary
iTerm zsh sessions that do not have `ghostty` on `PATH`.

`ghostty-config` opens the managed destination in terminal Vim. That is
useful for inspection and demonstrates the selected editor, but the file is
read-only. To persist a preference, edit `ghostty/config.ghostty` in the
active clone (`vim ghostty/config.ghostty`) and rebuild.

Ghostty **File > Settings** uses the macOS default GUI editor (`open_config`),
not `VISUAL`/`EDITOR`. It may continue opening TextEdit. This alias does not
change that menu, install MacVim, or alter file associations.

## Startup preferences

These are startup and prompt defaults. They do not migrate font family,
theme, or window geometry, and they do not stop applications such as Vim or
Pi from requesting their own cursor styles.

| Setting | Value | Notes |
| --- | --- | --- |
| `font-size` | `18` | Matches the current iTerm default-profile Normal Font of 18 points. Ghostty's own default is 13. Manually zoomed terminals can keep their adjusted size after reload; confirm size in a fresh terminal. |
| `cursor-style` | `block` | Default prompt cursor. |
| `cursor-style-blink` | `false` | Steady default. Applications can still use DECSCUSR. |
| `cursor-color` | `#d1329b` | Same pink as VS Code `editorCursor.foreground` and `terminalCursor.foreground`. |
| `shell-integration-features` | `no-cursor` | Stops prompt integration from replacing the block with a bar. Other integration features keep their defaults. |

`ghostty +edit-config` does not reload changes automatically. Reload or open
a fresh Ghostty terminal after rebuild when checking appearance. Parser
validation does not prove visual appearance.

## Tests, backups, and rollback

- `tests/ghostty-editor.test.sh` checks that Home Manager still exports no
  global editor, that the alias is in the generated zsh config, and that the
  alias scopes `VISUAL`/`EDITOR` to `vim` without changing the parent shell.
- `tests/ghostty-preferences.test.sh` checks the five settings, the generated
  Home Manager link, and Home Manager's existing backup/collision behavior.
- `tests/pi-editor.test.sh` remains the regression guard for Pi-only Vim.

Reuse Home Manager's existing `backupFileExtension = "backup"` behavior.
Regular live files are moved to `config.ghostty.backup` before the generation
link is published. Managed generation symlinks are replaced, not repeatedly
backed up. Differing unmanaged symlinks and a differing regular file whose
`.backup` already exists are rejected by collision preflight. Do not set
`force = true` or `HOME_MANAGER_BACKUP_OVERWRITE`. Backups are not restored
automatically.

To roll back preferences, restore the previous tracked `ghostty/config.ghostty`
on a feature branch in the active clone and run its `./rebuild.sh`. To undo
only the alias, revert the `zshrc` change and rebuild; a fresh interactive
shell then no longer has `ghostty-config`. No global editor environment needs
restoration because none was changed. If Ghostty ownership is removed
entirely, Home Manager removes its generation link but does not restore
`config.ghostty.backup`; preserve that backup.
