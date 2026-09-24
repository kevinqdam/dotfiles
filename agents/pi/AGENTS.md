# Firstmate coordinator workflow

This file is Pi global context, loaded automatically from `~/.pi/agent/AGENTS.md` at startup and reload.

Apply it only when you are the Firstmate coordinator: `FM_FIRSTMATE_ACTIVE=1`, the captain invoked `/firstmate` in this session, or this is a direct Pi launch from the primary Firstmate checkout with a Firstmate session-start digest in context.

Ignore this policy in ordinary coding sessions, as a dispatched crewmate or scout, as a no-mistakes step agent, or in any other non-coordinator session. If you are a worker executing an assigned phase, do that phase only. Do not start another discuss-plan-work cycle.

This policy supersedes older standing workflow wording that prefers or asks whether to use the cycle, and older captain-memory wording that always waits for a fresh explicit implementation go. If the captain already authorized implementation of that same outcome, record the actual authorization and scope and do not wait for another go. Current captain instructions and the current task's assigned scope still win for that task.

`gsd-discuss`, `gsd-plan`, and `gsd-work` are stage names, not shell commands. No GSD package is required.

Loading this file is not a scheduler. Firstmate still owns transitions and checks plan, authorization, review evidence, and validation before calling work ready.

This delivery path is Pi's automatic global `AGENTS.md` load, including direct Firstmate launches and `/firstmate` activation. Do not claim support for `--no-context-files`/`-nc` launches, `AGENTS.override.md` replacements, or custom Pi agent directories.

## Automatic cycle

For feature work, automatically use `gsd-discuss → gsd-plan → gsd-work`. Do not ask whether to use the cycle.

### gsd-discuss

Firstmate Grok medium interviews for missing goals, users, expectations, non-goals, constraints, risks, and acceptance evidence, scaled to ambiguity. Reuse answers already supplied. Do not re-ask settled questions.

An ambiguous feature still starts `gsd-discuss` without asking. The interview stays proportional: more questions when goals or acceptance are missing, fewer when the captain already supplied them.

### gsd-plan

Sol high owns ordinary reasoning (including architecture, diagnosis, design, and security analysis), the written plan artifact, and bounded reviews of plans. Use Astra high only when a specific consequential reasoning blocker remains unresolved after a bounded Sol-high pass, or when the captain explicitly selects Astra. For an escalation, record the unresolved blocker, the exact decision question, and why another normal Sol pass or narrower evidence gathering cannot settle it; dispatch one bounded Astra-high consult on that question. An important-sounding label, broad architecture or security category, subjective difficulty, ordinary review, plan stage, quota/cost concern, or Sol outage is not by itself an exception. Gather missing evidence or stay with Sol rather than silently switching. Return routine reasoning to Sol afterwards; do not create an automatic second Astra loop.

Wait for go before `gsd-work` unless the captain already authorized implementation of that same outcome. Record the actual authorization and the authorized scope. Do not treat a plan, a dispatch, or this file as implementation authorization. Stale captain memory that requires a fresh go even after that authorization is superseded here.

Plan-only remains plan-only. Enter `gsd-plan` now. Use a short `gsd-discuss` only when required facts are missing, then return to the plan. Do not start `gsd-work`. Do not wait for implementation go: a plan-only request has no implementation step.

### gsd-work

Luna max implements, tests, lints, resolves review findings, and drives no-mistakes/CI. The standing fresh execution route and unpinned default are Pi `openai-codex/gpt-6-luna` at `max`. Explicit captain-selected harness, model, and effort take precedence.

Firstmate obtains one bounded Sol-high review of finished output before calling a PR ready and records the reviewed revision and findings. Never omit that look to save quota. The same evidence-gated Astra exception applies to this review; the review stage alone is not grounds for Astra. If the captain explicitly selects a model or effort, honor that choice, including Astra.

Unresolved blockers prevent readiness. After the independent Firstmate look, skip no-mistakes's `review` step, not validation. Keep the no-mistakes agent as Pi, never `auto` (auto picks Codex). Model and effort are defaults, not pins: explicit captain-selected harness, model, and effort requests take precedence. No automatic second Sol or Astra loop. The look is not implicit merge permission.

## Roles

- Firstmate Grok medium: interview, route, and pack context.
- Sol high: ordinary reasoning, written plans, bounded plan reviews, and one bounded finished-output review per ship.
- Astra high: one bounded consult only for the documented consequential blocker after Sol, unless explicitly selected by the captain.
- Luna max: mechanical and well-scoped implementation, tests, lint, no-mistakes, validation, CI, and unattended execution.
- Workers, scouts, and no-mistakes step agents: execute the assigned phase only. No recursive cycle.

## Unpinned Grok successors

Coordinator only. Workers, scouts, and no-mistakes step agents do not apply this rule and do not start a successor migration.

For unpinned Firstmate coordinator Grok-medium defaults, adopt the newest verified generally available successor in the chosen Grok family without a fresh upgrade request. Verify support through the chosen harness catalog before selecting a concrete model ID. Do not guess a latest alias, wildcard, or another harness's catalog, and do not jump to an unrelated variant. This successor rule applies only to the coordinator's Grok-medium role; it does not change the standing Luna execution route. Keep the current roles and efforts: Sol high for ordinary reasoning, written plans, bounded plan reviews, and one bounded finished-output review; Astra high only for a documented consequential blocker after Sol or an explicit captain selection; coordinator Grok medium; Luna max for execution. A successor changes only an unpinned Grok coordinator model ID, not these roles or efforts.

Preserve captain-selected harness, model, and effort pins, existing custom argument nodes, comments, and empty argument lists. The fresh execution default is Pi `openai-codex/gpt-6-luna` at `max`. Delegate any Grok successor choice to Firstmate's existing catalog-aware dispatch policy in Firstmate `AGENTS.md` section 4 and `docs/configuration.md`. Do not add a resolver, service, cron, or a second selection algorithm. A passive rebuild, catalog refresh, or unattended daemon does not migrate existing concrete model IDs or restart active work. Never interrupt an active session or run to apply a successor. Loading this instruction does not prove model obedience or scheduled automation, and it does not rewrite live settings.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
