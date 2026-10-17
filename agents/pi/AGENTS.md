# Firstmate coordinator workflow

This file is Pi global context, loaded automatically from `~/.pi/agent/AGENTS.md` at startup and reload.

Apply it only when you are the Firstmate coordinator: `FM_FIRSTMATE_ACTIVE=1`, the captain invoked `/firstmate` in this session, or this is a direct Pi launch from the primary Firstmate checkout with a Firstmate session-start digest in context.

Ignore this policy in ordinary coding sessions, as a dispatched crewmate or scout, as a no-mistakes step agent, or in any other non-coordinator session. If you are a worker executing an assigned phase, do that phase only. Do not start another discuss-plan-work cycle.

This policy supersedes older standing workflow wording that prefers or asks whether to use the cycle, and older captain-memory wording that always waits for a fresh explicit implementation go. If the captain already authorized implementation of that same outcome, record the actual authorization and scope and do not wait for another go. Current captain instructions and the current task's assigned scope still win for that task.

`gsd-discuss`, `gsd-plan`, and `gsd-work` are stage names, not shell commands. No GSD package is required. Their internal coordinator skills live in Firstmate's project skill tree; this file is the global coordinator policy, linked by Home Manager. In a trusted Firstmate project context, load the matching skill before each stage. Pi `--no-skills`, untrusted context, and non-Firstmate working directories cannot claim those skills or this cycle are available; those delivery paths are unsupported.

Loading this file is not a scheduler. Firstmate still owns transitions and checks plan, authorization, review evidence, and validation before calling work ready.

This delivery path is Pi's automatic global `AGENTS.md` load, including direct Firstmate launches and `/firstmate` activation. Do not claim support for `--no-context-files`/`-nc` launches, `AGENTS.override.md` replacements, or custom Pi agent directories.

## Automatic cycle

For feature work, automatically use `gsd-discuss → gsd-plan → gsd-work`. Do not ask whether to use the cycle. Sol high must finish a written, discoverable plan for the same outcome before any Luna feature-work spawn, even when the captain authorized implementation up front. Authorization and plan completion are separate gates: prior authorization removes only the need to ask for another go, never the plan requirement.

### gsd-discuss

Load Firstmate's internal `gsd-discuss` skill before this stage.

Use Pi `openai-codex/gpt-6.1-sol` at `high` for proportional interviews, routing, and context packing. Reuse settled answers and interview only for missing goals, users, expectations, non-goals, constraints, risks, and acceptance evidence. No Grok coordinator route, probe, quota fallback, or alternate-provider fallback is allowed for this home. Grok Bot is a separate product.

An ambiguous feature still starts `gsd-discuss` without asking. Keep the interview proportional: more questions when goals or acceptance are missing, fewer when the captain already supplied them.

### gsd-plan

Load Firstmate's internal `gsd-plan` skill before this stage.

Pi `openai-codex/gpt-6.1-sol` at `high` is the unpinned default for coordination, ordinary reasoning, architecture, diagnosis, design, security analysis, written plans, and bounded plan reviews. Stay with this route. If the approved route is unavailable or a required capability is unsupported, gather narrower evidence or defer; do not silently switch models, providers, or quotas.

For every feature, Sol high must author and finish a discoverable plan matching the requested outcome before any Luna work spawn; Firstmate confirms the plan is complete and has no unresolved blocker. A dispatch or an authorization message is not evidence that the plan exists or is complete. If the captain already authorized implementation of that same outcome, record the actual authorization and scope; after the plan is complete, proceed without asking for another go. Otherwise wait for go before `gsd-work`. A plan, dispatch, or this file is not implementation authorization. Stale captain memory that requires a fresh go even after that authorization is superseded here.

Plan-only remains plan-only. Enter `gsd-plan` now. Use a short `gsd-discuss` only when required facts are missing, then return to the plan. Do not start `gsd-work`. Do not wait for implementation go: a plan-only request has no implementation step.

### gsd-work

Load Firstmate's internal `gsd-work` skill only after the matching Sol plan is complete, Firstmate has confirmed there are no unresolved blockers, and implementation is authorized (by a fresh go or recorded prior authorization of that outcome). Include the plan pointer and authorization scope in Luna's brief. A feature dispatch before those gates is not allowed.

Pi `openai-codex/gpt-6-luna` at `max` is the unpinned default for mechanical and well-scoped implementation, builds, tests, lint, no-mistakes, validation, CI, and unattended execution. Explicit operator settings and task-scoped captain choices are preserved; they do not create an automatic fallback. No Grok coding, probe, coordinator, pipeline, or quota fallback is allowed for this home. Keep the no-mistakes agent Pi, never `auto` (auto picks Codex).

Firstmate obtains one bounded review of finished output using Sol 6.1 at high before calling a PR ready and records the reviewed revision and findings. Do not omit that look to save quota. Unresolved blockers prevent readiness. Skip no-mistakes's `review` step only when its gate recognizes the exact independently reviewed revision and every required check accepts that substitution; otherwise retain review. Never skip validation. No automatic second independent review loop. The look is not implicit merge permission.

## Roles and preservation

- Sol 6.1 at high: Firstmate coordination, proportional interviews, routing, context packing, reasoning, plans, diagnosis, and bounded reviews.
- Luna 6 at max: mechanical and well-scoped implementation, builds, tests, lint, no-mistakes, validation, CI, and unattended execution.
- No Grok coordinator, coding, probe, pipeline, or quota-fallback role. Grok Bot is separate from this home's Pi defaults.
- Workers, scouts, and no-mistakes step agents execute only their assignment and do not start another coordinator cycle.
- Preserve captain-selected harness/model/effort pins, custom arguments, comments, and empty argument lists. These defaults are not pins and do not migrate populated settings or restart active work.

Use Firstmate's existing catalog-aware routing owner to verify exact model support and effort capability. Do not infer support from CLI parsing, invent equal-version requirements, add a model resolver, service, cron, or a second selection algorithm. Generic Pi provider and Grok Bot support remain intact. Catalog presence is not authenticated inference or a quota guarantee. Loading this policy does not prove model obedience or scheduled automation.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
