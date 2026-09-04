# Firstmate toolchain

This flake keeps the Firstmate toolchain declarative for the supported `aarch64-darwin` configuration.
`flake.lock` is the reproducibility anchor for Nixpkgs, nix-darwin, Home Manager, nix-homebrew, and the locked Homebrew source.

## Package surfaces

The Firstmate configuration documents a universal toolchain of Node, Git, GitHub CLI, no-mistakes, gh-axi, chrome-devtools-axi, lavish-axi, tasks-axi, and quota-axi.
The active Herdr backend adds Herdr, jq, and Treehouse.

Nixpkgs supplies Node 22, Git, GitHub CLI, jq, ShellCheck 0.11.0, and actionlint 1.7.12.
Those package versions are resolved from the locked Nixpkgs input rather than from a mutable Homebrew or npm installation.

Pi, Agy, Herdr, and the declared desktop casks remain Homebrew-managed because the existing configuration already uses their supported macOS installation surfaces.
Pi is the `pi-coding-agent` formula, Herdr is the `herdr` formula, and Agy is the `antigravity-cli` cask.
The flake lock pins the nix-homebrew Homebrew implementation, but it does not pin Homebrew formula metadata, cask recipes, or payloads.
They are an explicitly mutable containment boundary: tap mutation and Homebrew's implementation auto-update are disabled, and Homebrew Bundle installs missing declarations without globally upgrading the Brewfile.

Plain `./rebuild.sh` applies declarative package presence and configuration only; it keeps `homebrew.onActivation.upgrade = false` and performs no targeted version upgrades.
`./rebuild.sh --upgrade` first runs `brew upgrade --greedy --no-ask` for the explicit allowlist of `pi-coding-agent`, `herdr`, `antigravity-cli`, `chatgpt`, `codex`, `google-drive`, `google-chrome`, `google-gemini`, `grok-bot`, `iterm2`, `raycast`, `superwhisper`, `tailscale-app`, and `visual-studio-code`, then applies the normal Nix rebuild.
The declared `anaconda` cask is deliberately excluded from that allowlist, as are `blueutil`, `mono`, `mysql`, `mysql-client`, `tcl-tk`, and all undeclared packages.
The declared `logitune` cask (Logi Tune) is also excluded because Homebrew identifies it as installer-manual; its vendor installer or application self-update remains a manual operation. This keeps a Logi Tune update from preventing the Nix rebuild.
A cask upgrade can download a new payload and replace its installed application bundle during the rebuild; affected applications may need to be restarted.
Fresh machines should use a plain rebuild first so declarative Homebrew installation creates the packages before an opt-in upgrade.
Identical flake locks can therefore resolve different versions for these mutable Homebrew packages.

## Pi package capabilities

Home Manager converges the reviewed Pi package set through Pi's package manager after Homebrew has installed Pi. The pins, source audit, isolated compatibility evidence, and minimal local setup are documented in [Pi capabilities](./pi-capabilities.md). The convergence helper refuses the reviewed set unless the installed Pi is the audited 0.84.3 release.

Activation manages only package sources and their Pi-owned ordinary-writable installation paths. It does not create or link Telegram configuration, provider keys, OpenAI credentials, browser-cookie state, pairing state, message history, session files, or extension runtime files. Those remain local captain-owned runtime artifacts outside the repository and declarative configuration.

After activation, the captain must start Pi locally and complete the existing Telegram setup: `/telegram-setup`, `/telegram-connect`, then open the bot DM and send `/start`. Web provider keys, if needed, and the optional compaction or fast-mode settings are configured locally as described in [Pi capabilities](./pi-capabilities.md). Never commit any token or generated runtime state.

## Homebrew migration boundary

This Apple Silicon configuration manages only the native `/opt/homebrew` prefix.
`nix-homebrew.enableRosetta = false` deliberately leaves the existing `/usr/local` Homebrew tree, including its taps and package state, untouched.
Before native nix-homebrew setup, activation removes an ordinary `/opt/homebrew/Library/Taps` directory only when it is empty and owned and searchable by the configured Homebrew user.
After nix-homebrew creates its root:admin symlink to a single Nix-store `*-taps-env` directory, later activations preserve that exact managed state.
A non-empty, arbitrary-target, dangling, non-directory, unreadable, wrong-owner, or otherwise ambiguous path fails closed instead of being overwritten.

The current Firstmate installers pin no-mistakes 1.57.0 and Treehouse 2.0.1 to official macOS arm64 release assets with fixed SHA-256 hashes.
The Nix derivation in `nix/firstmate-toolchain.nix` owns those pins and does not run either upstream installer.

The supported npm surfaces for the AXI tools are `npm install -g` and, where documented, an explicit `setup hooks` command.
This configuration does not use global npm state.
It installs gh-axi 0.1.33, chrome-devtools-axi 0.1.29, chrome-devtools-mcp 1.7.0, lavish-axi 0.1.57, tasks-axi 0.2.5, and quota-axi 0.1.30 through one Nix `buildNpmPackage` derivation.
`nix/axi-tools/package-lock.json` and its fixed npm dependency hash pin the complete dependency closure.
The chrome-devtools-axi wrapper points directly to the pinned MCP entry in its Nix store closure, so browser commands never fall back to `npx` downloads.
The Homebrew-managed Google Chrome cask supplies the supported stable browser on a fresh Mac and follows the documented mutable Homebrew metadata boundary.
The command-line tools remain available on PATH without running a mutable global setup command.

The versions meet the Firstmate floors in `docs/configuration.md` of the authoritative Firstmate checkout.
The checked-in Firstmate source also owns the exact Herdr protocol floor and the Treehouse lease capability required by its Herdr backend.

## Agy update boundary

The official Antigravity CLI page documents `curl -fsSL https://antigravity.google/cli/install.sh | bash` as its macOS installation surface.
This configuration intentionally keeps the existing Homebrew `antigravity-cli` cask instead of replacing it with an imperative installer.

The cask remains declaratively present, but its recipe and payload are not pinned by `flake.lock`, and the upstream CLI advertises automatic updates.
Home Manager exports the supported `AGY_CLI_DISABLE_AUTO_UPDATE=true` opt-out, so Agy processes launched from the managed session leave upgrades to the explicit `./rebuild.sh --upgrade` path.
The cask is upgraded greedily against refreshed Homebrew metadata by the allowlisted Homebrew command. Homebrew owns Agy installation and versioning; the rebuild path does not inspect receipts, execute Agy, or repair package conflicts. An exceptional pre-existing conflict remains visible in Homebrew's error output for one-time operator repair, and an upgrade can replace the Agy application bundle while it is closed or running.
A captain can still re-enable the upstream updater by overriding the environment variable or launching Agy outside the managed session.
No credentials or Agy authentication files are managed here.

Pi exposes `pi update` and Herdr exposes `herdr update` as explicit self-update commands as well.
Those commands are outside declarative activation and can create drift, while the next `./rebuild.sh --upgrade` invocation again requests Homebrew's currently resolved upgrades.
The Nix-packaged no-mistakes and AXI tools are likewise updated by changing their pinned release or npm lock inputs, not by invoking a mutable updater.

## Operational-home activation

Home Manager exports `FM_HOME` and `FIRSTMATE_HOME` to `/Users/kevindam/.local/share/firstmate` for the primary session.
The Pi bootstrap extension applies the same default when Pi starts directly in the primary Firstmate checkout.
Secondmate launchers pass explicit `FM_HOME` and `FM_ROOT_OVERRIDE` values, including the intentional empty root override, and the extension preserves those values.

Home Manager builds the native materializer from `agents/materialize-firstmate-config.c` and invokes it with the canonical home.
It creates only missing regular files for `config/backend`, `config/crew-harness`, `config/crew-dispatch.json`, and `config/startup-memory-budget`.
The defaults select Herdr, Pi, the approved Pi model and effort routing, and a 7500-token startup memory budget.
Sol is scarce and strategic: at most one or two bounded high-reasoning passes on a ship.
Fresh homes route architecture, ambiguous diagnosis, planning, security analysis, or a bounded review of already-produced output to `gpt-5.6-sol` at effort `high`; mechanical fully specified edits to `xai/grok-4.6` at effort `medium`; and well-scoped implementation, driving no-mistakes, validation, CI, or any long unattended pipeline, plus the default, to `xai/grok-4.6` at effort `high`.
Unattended overnight no-mistakes must run on Grok after that, never as an automatic Sol cadence.
The Firstmate dispatcher still gives explicit per-task captain `--harness`, `--model`, and `--effort` requests precedence over these defaults.

A populated home is treated as captain-owned.
Existing regular config files are left byte-for-byte unchanged, and a captain-selected startup memory budget is preserved only when its first digit is 1 through 9, its remaining characters are decimal digits followed by exactly one newline, and it has one hard link.
A symlink or other non-regular config target causes activation to fail closed instead of replacing a Home Manager link or an unexpected object.
Missing settings are published atomically without replacing a target that appears concurrently; that race fails activation and preserves the competing file for review.
Canonical home and config directories are opened component by component without following symlinks, and all inspection, validation, temporary-file, and publication operations use their held directory descriptors.
Runtime state, task records, captain memory, backlog, data, project clones, credentials, authentication files, and generated monitoring artifacts are never touched by the activation hook.

## Firstmate checkout remotes

`agents/setup-harnesses` uses `git@github.com:kevinqdam/firstmate-local.git` as `origin` and `https://github.com/kunchenguid/firstmate.git` as the fetch-only `upstream`.
A fresh machine clones the private mirror.
An existing clean checkout on the configured branch is fetched from the private mirror and advanced only with `git merge --ff-only`.
Uncommitted changes, a detached HEAD, a different checked-out branch, and a non-fast-forward divergence are preserved and refuse the update.
The upstream push URL is a deliberately unusable `no_push://` transport, so an accidental public push fails before network submission.
A one-time migration of an existing public-origin checkout changes only its remote configuration and then follows the same clean fast-forward gate.
