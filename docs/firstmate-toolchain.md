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

Plain `./rebuild.sh` applies declarative package presence and configuration only; it keeps `homebrew.onActivation.upgrade = false` and performs no targeted version upgrades. The wrapper resolves its own physical repository root, so a fresh clone can run `./rebuild.sh` without `~/.dotfiles`; the interactive `nix-rebuild` alias remains `~/.dotfiles/rebuild.sh` and continues to use that symlink target. This requires Apple Silicon macOS, the configured `kevindam` account, Git and Apple Command Line Tools, a working Nix daemon with flakes enabled, sudo rights, and network or cached Nix inputs. It does not bootstrap Nix or support arbitrary users or platforms. The wrapper resolves directory and wrapper symlinks to a complete clone; partial copies, broken or cyclic links, and Nix store copies are not supported as editable sources. `git add .` stages all local changes in the selected clone before the build.
`./rebuild.sh --upgrade` first runs `brew upgrade --greedy --no-ask` for the explicit allowlist of `pi-coding-agent`, `herdr`, `antigravity-cli`, `chatgpt`, `codex`, `ghostty`, `google-drive`, `google-chrome`, `google-gemini`, `grok-bot`, `iterm2`, `raycast`, `superwhisper`, `tailscale-app`, and `visual-studio-code`, then applies the normal Nix rebuild.
The clone-local wrapper root covers dotfiles staging, Nix build, activation, and invocation of the post-activation helper. `setup-harnesses` still operates on its separately configured `FIRSTMATE_ROOT` checkout (default `$HOME/dev/firstmate`), so a fresh clone requires that private mirror, SSH access, and a clean expected branch for the final setup stage; failure there occurs after system activation. The declared `anaconda` cask is deliberately excluded from that allowlist, as are `blueutil`, `mono`, `mysql`, `mysql-client`, `tcl-tk`, and all undeclared packages.
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
It installs gh-axi 0.1.33, chrome-devtools-axi 0.1.29, chrome-devtools-mcp 1.7.0, lavish-axi 0.1.57, tasks-axi 0.2.6, and quota-axi 0.1.51 through one Nix `buildNpmPackage` derivation.
`nix/axi-tools/package-lock.json` and its fixed npm dependency hash pin the complete dependency closure. The pinned Firstmate floors are `FM_TASKS_AXI_MIN=0.2.6` and `FM_QUOTA_AXI_MIN=0.1.51`. quota-axi 0.1.51 requires Node.js 22.19 or newer; the locked Nixpkgs toolchain provides Node.js 22.23.1.
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
The defaults select Herdr, Pi, the approved role routing, and a 7500-token startup memory budget. Fresh Firstmate coordination, proportional interviews, routing, context packing, reasoning, plans, diagnosis, and bounded reviews use Pi `openai-codex/gpt-6.1-sol` at `high`. Mechanical and well-scoped implementation, builds, tests, lint, no-mistakes, validation, CI, and unattended execution use Pi `openai-codex/gpt-6-luna` at `max`. Feature implementation follows a matching completed Sol plan and separate implementation authorization; prior authorization skips only another go, not the plan gate. No Grok or Astra coordinator, coding, probe, pipeline, alternate-provider, or quota-fallback route is configured for this home. Grok Bot is a separate product. These free-text dispatch descriptions are not a deterministic classifier.

The independent Firstmate finished-output look remains Sol 6.1 at high and must not be omitted to save quota. Explicit operator arguments and captain-selected task pins are preserved. No automatic second independent review or implicit merge permission is created.

A populated home is treated as captain-owned.
Existing regular config files are left byte-for-byte unchanged, and a captain-selected startup memory budget is preserved only when its first digit is 1 through 9, its remaining characters are decimal digits followed by exactly one newline, and it has one hard link.
A symlink or other non-regular config target causes activation to fail closed instead of replacing a Home Manager link or an unexpected object.
Missing settings are published atomically without replacing a target that appears concurrently; that race fails activation and preserves the competing file for review.
Canonical home and config directories are opened component by component without following symlinks, and all inspection, validation, temporary-file, and publication operations use their held directory descriptors.
Runtime state, task records, captain memory, backlog, data, project clones, credentials, authentication files, and generated monitoring artifacts are never touched by the activation hook.

Firstmate dispatch remains captain-owned: rebuild leaves an existing regular `crew-dispatch.json` byte-for-byte unchanged, including historical model IDs, explicit effort pins, and unrelated choices. It does not link, seed, or overwrite captain memory. A separate `agents/materialize-pi-settings.py` activation seeds only global standalone Pi defaults in `~/.pi/agent/settings.json`: when both model axes are absent it adds `openai-codex` / `gpt-6.1-sol`, and it adds `high` only if thinking is absent. For an existing exact Sol route it fills only a missing thinking level. Complete custom routes, explicit thinking, unknown settings, packages, extension filters, and empty resource arrays are preserved; an ambiguous partial route is left unchanged with a diagnostic. The settings file is never Home Manager-linked. Explicit CLI flags, including Firstmate's worker model/effort arguments, remain launch-level overrides.

Catalog refresh only discovers models. Configured provider catalogs can refresh automatically, and `pi update --models` refreshes them explicitly. Neither rewrites concrete model IDs in Firstmate dispatch, no-mistakes arguments, or Pi settings. A Pi binary upgrade is the separate `./rebuild.sh --upgrade` allowlist path and is not required to publish a seed ID. Package convergence still requires the audited Pi 0.84.3 release, so a blind binary upgrade can fail that guard.

Model support and effort capability stay with Firstmate's existing catalog-aware routing owner. Verify exact catalog membership and supported effort before selecting a route; CLI parsing alone is not support evidence. This repository adds no resolver, service, guessed latest alias, wildcard, or cron. A passive rebuild does not migrate existing pins. Future source seeds still need a reviewed dotfiles change. Catalog availability is not quota or successful inference. Grok provider and Grok Bot support remain intact, but are not coordinator or coding defaults for this home.

## no-mistakes pipeline agent

Home Manager does not symlink `~/.no-mistakes/config.yaml`. Replacing that live file with a generation link would smash daemon state.

Activation runs `agents/materialize-no-mistakes-config.py` against `~/.no-mistakes`.
It converges the no-mistakes harness safely:

- `agent: pi`
- a fresh/default `agent_args_override.pi`: `--model openai-codex/gpt-6-luna --thinking max` only when the Pi node is absent

The `agent: pi` key is enforced for test, lint, push, and PR; it is not `auto`, which would hire Codex because Codex is installed. The fresh/missing `agent_args_override.pi` uses `--model openai-codex/gpt-6-luna --thinking max`. Existing operator-selected Pi arguments, including provider, model, thinking, extra flags, comments, and an explicit empty list, are preserved verbatim. An existing Pi node that still names an older model is also preserved. Activation does not string-replace a historical model ID, because that cannot distinguish an explicit pin from a previous seed. Grok Bot.app is separate; no Grok coordinator or coding route is configured for this home.

Missing keys receive the default values. Unrelated captain-owned keys such as `ci_timeout` and `auto_fix` stay.
A symlink, directory, or other non-regular `config.yaml` fails closed instead of replacing live daemon state. Unsupported inline, scalar, or sequence `agent_args_override` containers also fail closed rather than being rewritten.

An existing-home migration, if separately authorized, is not seed convergence. Existing Firstmate dispatch and no-mistakes Pi argument nodes, including seed-shaped Grok 4.7 and Luna 5.6 values, remain byte-for-byte unchanged; do not infer that a concrete value is still an uncustomized seed. Any future migration requires a separately scoped inspect-then-update while the daemon is idle. A disk edit does not prove the running daemon has loaded new arguments. Activation must not stop, restart, or update the shared no-mistakes daemon; if a restart is ever required, Firstmate arranges it only after every lane's current run has finished and confirms the next safely started run.

Routine planning and the one required finished-output look are Firstmate passes on Pi `openai-codex/gpt-6.1-sol` at high. Firstmate owns these looks because no-mistakes has no per-step agent today; running review inside no-mistakes would use its configured Pi route or, with `agent: auto`, Codex.
Never omit the finished-output review to save quota. Skip no-mistakes `review` only when its gate recognizes the exact independently reviewed revision and every required check accepts that substitution; otherwise retain the review. Never skip validation. Keep the no-mistakes agent Pi and preserve captain-selected model/effort arguments. The standing Luna 6/max default applies to fresh execution.

## Firstmate coordinator policy

The instruction owner is `agents/pi/AGENTS.md`, linked by Home Manager to `~/.pi/agent/AGENTS.md`.
Pi loads that global file automatically at startup and reload, including direct Firstmate launches and `/firstmate` activation.
The bootstrap extension injects Firstmate checkout `AGENTS.md` only when `FM_FIRSTMATE_ACTIVE=1`, so docs or dispatch wording alone cannot deliver this policy.
The internal `gsd-discuss`, `gsd-plan`, and `gsd-work` stage skills live in Firstmate's project `.agents/skills/` tree, not in this global dotfiles file. In a trusted Firstmate project context, the coordinator loads the matching skill before each stage. `--no-skills`, untrusted context, and non-Firstmate working directories cannot claim the skills are available.

The policy applies only to Firstmate coordinator sessions. Ordinary coding sessions, dispatched crewmates and scouts, and no-mistakes step agents ignore it. Workers execute their assigned phase and must not start another cycle.

The managed policy routes coordination and interviews to Sol 6.1/high, and execution to Luna 6/max. It preserves explicit pins, does not perform model fallback, and forbids interrupting active sessions or runs. Workers do not start coordinator cycles. The managed text is available after rebuild and a Pi context reload or new session. Do not write through the live `~/.pi/agent/AGENTS.md` link. Prompt-composition tests prove delivery only. They do not prove model obedience or scheduled automation.

`gsd-discuss`, `gsd-plan`, and `gsd-work` are stage names in that file, not shell commands, and no GSD package is required. For feature work, the order is discuss, a completed matching Sol-authored plan, then Luna work. Pre-authorization permits work without a second go only after that plan is complete; a dispatch or authorization is not plan evidence. The dispatch seed is natural-language routing advice, not a stage engine, and rebuild does not migrate existing homes.
The shared Firstmate skills are in a separate repository and are not changed by this dotfiles PR. Firstmate owns a bounded guidance follow-up: `.agents/skills/gsd-discuss/SKILL.md` still names Grok-medium coordination, while `.agents/skills/gsd-plan/SKILL.md` permits Astra consults; align both with the home's Sol 6.1/high and Luna 6/max allowed roles. `.agents/skills/gsd-work/SKILL.md` already names Luna 6/max and should remain unchanged. This separate follow-up does not block delivery of these dotfiles defaults. After source activation, use `/reload` or start a fresh session to load the changed global context.

Activation still creates only missing regular Firstmate config files. It does not link, seed, or overwrite `data/captain.md`.

### Existing-home steps

Rebuild preserves an existing `~/.local/share/firstmate/config/crew-dispatch.json` byte-for-byte, including historical provider/model IDs, effort pins, and unrelated captain choices. This PR changes source defaults only: it performs no rebuild or live activation, Pi reload/restart, or Herdr operation, and existing Firstmate homes are not migrated. The separate fresh-settings seeder only fills the narrow missing standalone Pi defaults described above; it does not overwrite existing model/effort choices or alter active work.

Migrating an existing Firstmate dispatch is a separate inspect-then-update operation. This activation never edits it, and a concrete model ID cannot be assumed to be an uncustomized seed. Preserve ambiguous or captain-edited rules, effort pins, unrelated defaults, and captain memory. Never delete the file to force reseeding. Primary private dispatch and captain memory updates are owned by Firstmate, not this dotfiles activation.

Fresh Firstmate dispatch defaults use Sol 6.1/high for coordination and Luna 6/max for execution. Fresh no-mistakes execution uses Luna 6/max. Existing dispatch and no-mistakes Pi argument nodes are not migrated by rebuild, including historical provider/model pins or explicit non-max effort. Fresh global Pi settings use the narrow missing-only seeder; existing selected model/effort values and other settings remain intact. This source change does not modify live Firstmate/no-mistakes runtime files, credentials, or active work.

The existing `data/captain.md` inspect-then-update for prior-authorization guidance remains a separate runtime operation. Do not commit that private memory or overwrite it through activation.

For a fresh clone, run `cd /path/to/clone && ./rebuild.sh`; the wrapper uses that clone for staging, build, activation, and post-activation setup without requiring `~/.dotfiles`. The existing interactive alias remains `nix-rebuild=~/.dotfiles/rebuild.sh` and intentionally follows the linked repository target. After this change is in the canonical `~/.dotfiles` checkout, `cd ~/.dotfiles && ./rebuild.sh` remains valid. Then reload Pi context or start a fresh session. Do not restart the no-mistakes daemon.
Verify cold-start delivery with captain memory absent and with stale memory present: the policy supersedes older standing workflow wording, including older unconditional fresh-go captain memory, while preserving current captain instructions and task scope.
Isolated prompt-composition fixtures and development-only model checks live in `tests/firstmate-policy.test.sh` and `tests/firstmate-policy-model-checks.sh`. They do not replace live-home rebuild and reload, and they do not prove model obedience or scheduled automation. The optional prompt-check script uses Sol 6.1 at high as its isolated policy-probe model; it is not a deterministic test or CI gate and is not run as part of this change. `tests/firstmate-policy-model-check-evidence.md` remains historical evidence.

`--no-context-files`, `AGENTS.override.md`, and custom Pi agent directories are unsupported delivery surfaces until explicitly covered.

## Firstmate checkout remotes

`agents/setup-harnesses` uses `git@github.com:kevinqdam/firstmate-local.git` as `origin` and `https://github.com/kunchenguid/firstmate.git` as the fetch-only `upstream`.
A fresh machine clones the private mirror.
An existing clean checkout on the configured branch is fetched from the private mirror and advanced only with `git merge --ff-only`.
Uncommitted changes, a detached HEAD, a different checked-out branch, and a non-fast-forward divergence are preserved and refuse the update.
The upstream push URL is a deliberately unusable `no_push://` transport, so an accidental public push fails before network submission.
A one-time migration of an existing public-origin checkout changes only its remote configuration and then follows the same clean fast-forward gate.
