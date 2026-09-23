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
The defaults select Herdr, Pi, the approved model and effort routing, and a 7500-token startup memory budget.
Fresh homes route ordinary planning, architecture, diagnosis, design, security analysis, and bounded reviews of a plan or finished output to `gpt-6-sol` at effort `high`. An exceptional `gpt-6-astra` high rule precedes that Sol rule and is limited to an explicit captain selection or a documented consequential reasoning blocker that remains after a Sol-high pass, with a bounded decision question and why another Sol pass or narrower evidence cannot settle it. Stage, security category, subjective difficulty, quota/cost, or Sol outage alone are not grounds to escalate. The coordinator policy in `agents/pi/AGENTS.md` requires checking this evidence gate before dispatch; these free-text `when` descriptions are not a deterministic classifier.
Mechanical fully specified edits route to `xai/grok-4.7` at effort `medium`; well-scoped implementation, no-mistakes, validation, CI, unattended pipelines, and the default route to `xai/grok-4.7` at effort `high`. Grok owns execution and validation; the independent Firstmate finished-output look remains Sol high by default. Do not omit it to save quota. Astra is not reserved by a plan or review stage and does not implement, test, or watch CI.
Explicit captain per-task `--harness`, `--model`, and `--effort` requests take precedence, including an explicit Astra choice or an authorized Pi-based OpenAI fallback. No automatic second Sol or Astra loop and no implicit merge permission.

A populated home is treated as captain-owned.
Existing regular config files are left byte-for-byte unchanged, and a captain-selected startup memory budget is preserved only when its first digit is 1 through 9, its remaining characters are decimal digits followed by exactly one newline, and it has one hard link.
A symlink or other non-regular config target causes activation to fail closed instead of replacing a Home Manager link or an unexpected object.
Missing settings are published atomically without replacing a target that appears concurrently; that race fails activation and preserves the competing file for review.
Canonical home and config directories are opened component by component without following symlinks, and all inspection, validation, temporary-file, and publication operations use their held directory descriptors.
Runtime state, task records, captain memory, backlog, data, project clones, credentials, authentication files, and generated monitoring artifacts are never touched by the activation hook.

A seed model change does not migrate an existing home. Rebuild leaves an existing regular `crew-dispatch.json` byte-for-byte unchanged, including an older concrete model ID or an already selected successor. It does not link, seed, or overwrite captain memory. The global Pi model selection in `~/.pi/agent/settings.json` is unrelated captain-owned runtime state. Activation does not read or replace it, and a Grok seed change is not authority to overwrite it.

Catalog refresh only discovers models. Configured provider catalogs can refresh automatically, and `pi update --models` refreshes them explicitly. Neither rewrites concrete model IDs in Firstmate dispatch, no-mistakes arguments, or Pi settings. A Pi binary upgrade is the separate `./rebuild.sh --upgrade` allowlist path and is not required to publish a seed ID. Package convergence still requires the audited Pi 0.84.3 release, so a blind binary upgrade can fail that guard.

Future same-family successors stay with Firstmate's existing catalog-aware dispatch policy. Verify support through the chosen harness catalog, then select a concrete model ID. This repository adds no resolver, service, guessed latest alias, wildcard, or cron. A passive rebuild does not migrate existing pins. Future source seeds still need a reviewed dotfiles change. Catalog availability is not quota or successful inference.

## no-mistakes pipeline agent

Home Manager does not symlink `~/.no-mistakes/config.yaml`. Replacing that live file with a generation link would smash daemon state.

Activation runs `agents/materialize-no-mistakes-config.py` against `~/.no-mistakes`.
It converges the no-mistakes harness safely:

- `agent: pi`
- a default `agent_args_override.pi`: `--model xai/grok-4.7 --thinking high` only when the Pi node is absent

The `agent: pi` key is enforced for test, lint, push, and PR; it is not `auto`, which would hire Codex because Codex is installed. Existing operator-selected Pi arguments, including provider, model, thinking, extra flags, comments, and an explicit empty list, are preserved verbatim. An existing Pi node that still names an older model is also preserved. Activation does not string-replace a historical model ID, because that cannot distinguish an explicit pin from a previous seed. Captain-approved quota fallback may therefore select OpenAI through Pi without becoming a rebuild-time hard pin. See [Captain-authorized OpenAI fallback](#captain-authorized-openai-fallback) for its preferred selector and precedence. Grok Bot.app is not this agent, and the grok CLI is not installed; Grok remains only the initial default.

Missing keys receive the default values. Unrelated captain-owned keys such as `ci_timeout` and `auto_fix` stay.
A symlink, directory, or other non-regular `config.yaml` fails closed instead of replacing live daemon state. Unsupported inline, scalar, or sequence `agent_args_override` containers also fail closed rather than being rewritten.

A one-time edit of a home whose `agent` and `agent_args_override.pi` still match the previous managed Pi/Grok/high default is a separate Firstmate operation, not seed convergence. Re-inspect those fields immediately before editing. If they still match, change only the model ID and preserve effort and unrelated bytes. If the node has diverged, preserve it. Do not edit the shared file while a run is active or while daemon reload behavior is uncertain. A disk edit does not prove the running daemon has loaded the new arguments. Activation must not stop, restart, or update the shared no-mistakes daemon. If a restart is required, Firstmate arranges it only after every lane's current run has finished, then confirms the next safely started run. Leave that activation pending rather than restarting to make validation convenient.

Routine plan reasoning and the one required finished-output look are Firstmate passes on `gpt-6-sol` at high. Astra is one bounded consult only for the documented consequential blocker after Sol, unless explicitly selected by the captain. Firstmate owns these looks because no-mistakes has no per-step agent today; running review inside no-mistakes would use its configured Pi route or, with `agent: auto`, Codex.
Never omit the finished-output review to save quota. After that independent look, Grok drives no-mistakes with `--skip=review`; do not skip validation. Keep the no-mistakes agent Pi, preserve captain-selected model/effort arguments, and allow the documented OpenAI quota fallback. Quota conservation is not a skip.

## Firstmate coordinator policy

The instruction owner is `agents/pi/AGENTS.md`, linked by Home Manager to `~/.pi/agent/AGENTS.md`.
Pi loads that global file automatically at startup and reload, including direct Firstmate launches and `/firstmate` activation.
The bootstrap extension injects Firstmate checkout `AGENTS.md` only when `FM_FIRSTMATE_ACTIVE=1`, so docs or dispatch wording alone cannot deliver this policy.

The policy applies only to Firstmate coordinator sessions. Ordinary coding sessions, dispatched crewmates and scouts, and no-mistakes step agents ignore it. Workers execute their assigned phase and must not start another cycle.

### Captain-authorized OpenAI fallback

When the captain authorizes an OpenAI quota fallback from Grok, the preferred Firstmate route is harness Pi, model `gpt-6-luna`, effort `max`. The matching provider-qualified Pi CLI arguments are `--model openai-codex/gpt-6-luna --thinking max`. The reviewed Pi catalog lists `gpt-6-luna` under provider `openai-codex` and maps thinking level `max` to `max`; verify the current Pi catalog again before dispatch. Catalog availability is not evidence of remaining quota or successful inference. This is not an automatic fallback, a replacement for Grok-first implementation/validation, or a change to the normal Sol/Astra reasoning and review roles or fresh-home routes.

Captain-selected harness, model, and effort fields each take precedence when explicitly pinned. Preserve existing operator arguments, comments, empty/custom argument lists, and existing home configuration byte-for-byte; neither policy publication nor catalog refresh migrates Luna 5.6 or any other concrete ID. Publish policy through the normal rebuild, then allow Pi context reload or a new session to deliver it. Do not interrupt or reroute active work to force adoption: use the fallback only at the next safely started, captain-authorized segment. The no-mistakes fresh default remains Pi with Grok high, and any existing no-mistakes Pi arguments remain operator-owned.

The same file tells the coordinator to adopt the newest verified generally available successor in the chosen Grok family for unpinned defaults, without a fresh upgrade request, using Firstmate's existing catalog-aware selection policy. That successor rule preserves explicit pins and configured roles and efforts; it does not alter Grok-first execution defaults. A separate captain-authorized OpenAI fallback rule preserves explicit per-task pins and forbids interrupting active sessions or runs. Workers do not apply either coordinator rule. The managed text is available after rebuild and a Pi context reload or new session. Do not write through the live `~/.pi/agent/AGENTS.md` link. Prompt-composition tests prove that delivery only. They do not prove model obedience or scheduled automation.

`gsd-discuss`, `gsd-plan`, and `gsd-work` are stage names in that file, not shell commands.

Activation still creates only missing regular Firstmate config files. It does not link, seed, or overwrite `data/captain.md`.

### Existing-home steps

Rebuild preserves an existing `~/.local/share/firstmate/config/crew-dispatch.json` byte-for-byte, including Astra-shaped routing, concrete model IDs, effort pins, and unrelated captain choices. An old Astra dispatch beside the updated global Sol-first policy is a known mismatch, not a live migration.

Adopting Sol routing in an existing coordinator home requires separate captain authorization and an inspect-then-update. Verify that the old broad Astra rule is the unchanged seed-shaped default by matching its original `when` and `why`, `use.harness: pi`, `use.model: gpt-6-astra`, and `use.effort: high`. For that verified default only, change `use.model` to `gpt-6-sol`, narrow `when` and update `why` to the routine Sol policy, and insert the gated Astra-high exception before it. Preserve its effort, all unrelated rules and defaults, and captain memory. If provenance is ambiguous or any rule is edited/custom, treat it as a pin and preserve its model and effort until the captain decides otherwise. An explicit captain-selected Astra model is not a seed to migrate. Never delete the file to force reseeding.

Grok 4.7 is the new seed for fresh or missing defaults only. Existing Firstmate dispatch and no-mistakes Pi argument nodes are not migrated by rebuild; the separate no-mistakes seed-shaped update instructions above remain subject to re-inspection and idle-run safety. Do not change Pi global settings. This PR does not modify any live Firstmate/no-mistakes config, credentials, or user settings.

The existing `data/captain.md` inspect-then-update for prior-authorization guidance remains a separate runtime operation. Do not commit that private memory or overwrite it through activation.

For a fresh clone, run `cd /path/to/clone && ./rebuild.sh`; the wrapper uses that clone for staging, build, activation, and post-activation setup without requiring `~/.dotfiles`. The existing interactive alias remains `nix-rebuild=~/.dotfiles/rebuild.sh` and intentionally follows the linked repository target. After this change is in the canonical `~/.dotfiles` checkout, `cd ~/.dotfiles && ./rebuild.sh` remains valid. Then reload Pi context or start a fresh session. Do not restart the no-mistakes daemon.
Verify cold-start delivery with captain memory absent and with stale memory present: the policy supersedes older standing workflow wording, including older unconditional fresh-go captain memory, while preserving current captain instructions and task scope.
Isolated prompt-composition fixtures and development-only model checks live in `tests/firstmate-policy.test.sh` and `tests/firstmate-policy-model-checks.sh`. They do not replace live-home rebuild and reload, and they do not prove model obedience or scheduled automation. The optional check script's default model is the current unpinned Grok seed at medium. `tests/firstmate-policy-model-check-evidence.md` is historical evidence and stays unchanged unless those checks are actually rerun.

`--no-context-files`, `AGENTS.override.md`, and custom Pi agent directories are unsupported delivery surfaces until explicitly covered.

## Firstmate checkout remotes

`agents/setup-harnesses` uses `git@github.com:kevinqdam/firstmate-local.git` as `origin` and `https://github.com/kunchenguid/firstmate.git` as the fetch-only `upstream`.
A fresh machine clones the private mirror.
An existing clean checkout on the configured branch is fetched from the private mirror and advanced only with `git merge --ff-only`.
Uncommitted changes, a detached HEAD, a different checked-out branch, and a non-fast-forward divergence are preserved and refuse the update.
The upstream push URL is a deliberately unusable `no_push://` transport, so an accidental public push fails before network submission.
A one-time migration of an existing public-origin checkout changes only its remote configuration and then follows the same clean fast-forward gate.
