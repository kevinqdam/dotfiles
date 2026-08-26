# Pi capabilities

Home Manager invokes `agents/converge-pi-packages` after Homebrew installs the
reviewed Pi 0.84.3 executable. The converger owns only these reviewed package
sources and leaves Pi settings, package state, credentials, sessions, and
runtime files writable by the captain.

| Capability | Pin and reviewed source | Pi entry point |
| --- | --- | --- |
| Telegram bridge | `npm:@llblab/pi-telegram@0.39.2`, npm integrity `sha512-SzleYw69R62QsGLQTLSw/do5XmbRp6uHy612FnVFjFAH5sZZ3zlIFpmHCTVr2kO1eAjwUWW5LCnmS5fuLzdLlg==`, from `https://github.com/llblab/pi-telegram` | Existing `/telegram-*` commands |
| Web search and browsing | `npm:pi-web-access@0.25.0`, npm integrity `sha512-DYOEIMEPwpC6pHElexBy3XuaYPnfMxH0ZBaGrILFsLNQzhhHJ3kJLrCQU4fnKXYXV6OEwxsLt2pBP76koK4hHg==`, repository tag `v0.25.0` at `08e347f4fe6bea807882c2363527118cce6eb539` | `web_search`, `fetch_content`, and related tools |
| Codex fast-mode toggle | `npm:@ryan_nookpi/pi-extension-codex-fast-mode@0.2.6`, npm integrity `sha512-DzJCqiXMnkAT77OjiGZm4y1nYPieTQzsjgR05O6+o43L4WrLrvxjUf360qBrNbNT2hGX6AbHvwC7fgXr0WrpmQ==`, release source `pi-extension` commit `80b0695503cd7234c9ce8d0fbe39d43907bcc8c9` | `/codex-fast on`, `/codex-fast off`, `/codex-fast status` |
| OpenAI server-side compaction | `git:github.com/algal/pi-openai-server-compaction@c6d593087709e9481223dc6c6c2269b371b5e055`, with exact runtime dependency `ws@8.18.3` at npm integrity `sha512-PEIGCY5tSlUt50cqyMXfCzX+oOPqN0vuGqWzbcJ2xvnkzkq46oOpz7dQaTDBdfICb4N14+GARUDw2XV2N4tvzg==` | Automatic compaction for supported OpenAI and Codex models |

The npm package manifests have no package lifecycle install scripts. Web
access runtime dependencies are installed by Pi's package manager, with Pi's
host packages supplied as peers. The checked sources were inspected for their
extension manifests, runtime dependencies, network calls, credential sources,
and install behavior before these pins were accepted. Web access performs
network or browser-cookie work only when a tool or command uses it. The fast
mode package changes OpenAI Codex request payloads only for its supported models.
The converger authenticates every managed npm package tree against its reviewed
tarball and reinstalls changed package contents. It also replaces the compaction
repository's floating `ws` resolution with the exact audited version above,
rejects any other runtime dependency graph, and disables dependency lifecycle
scripts during that repair.
The compaction package uses existing Pi authentication, sends supported
conversation context to the OpenAI Responses compaction endpoint, and stores
opaque provider artifacts in the local Pi session. None of these credentials or
runtime artifacts are provisioned by Nix.

The compaction repository declares an old peer range of `>=0.80.9 <0.81.0`
although its exact reviewed commit was loaded and its offline smoke checks were
run against the installed Pi 0.84.3 in an isolated agent directory. The source
implementation and Pi extension API compatibility passed that audit. The
converger refuses the reviewed set when the installed Pi version is not 0.84.3
instead of silently accepting a new compatibility combination.

## Post-activation setup

1. Rebuild the system, then start a new shell or Pi process so the declarative
   `VISUAL=vim` and `EDITOR=vim` environment is present. Pi's documented
   `Ctrl-G` external-editor action uses those variables when `externalEditor` is
   unset. No Pi `externalEditor` setting or custom modal editor is written.
2. Fast mode is off by default. Use `/codex-fast on` when the captain wants
   `text.verbosity=low` plus Codex `service_tier=priority`; use `/codex-fast off`
   to remove the priority tier. Its state remains in the ordinary-writable
   `~/.pi/agent/state/` directory.
3. Web search works without a checked-in key through its documented zero-config
   Exa path, and may also reuse existing Pi Codex authentication. Optional
   provider keys and routing belong in the local
   `~/.pi/web-search.json`, never in this repository or Nix.
4. Server-side compaction needs no separate key when the selected OpenAI or
   Codex model already works in Pi. The package's local config remains
   optional at `~/.pi/agent/openai-server-compaction.json`; set
   `PI_OPENAI_SERVER_COMPACTION_ENABLED=0` or add `{"enabled": false}` locally
   when a rollback is needed. The direct OpenAI path can retain context
   server-side because that is part of the reviewed extension behavior.
5. Telegram setup is unchanged: run `/telegram-setup`, then
   `/telegram-connect`, then pair the bot with `/start`. Keep the bot token and
   all pairing and message state local.
