# Firstmate policy development model checks

Not a deterministic test. These observations do not prove universal model obedience.

- Parent revision: `42eeb44`
- Model: `xai/grok-4.6`
- Effort: `medium`
- Isolated `PI_CODING_AGENT_DIR` with `agents/pi/AGENTS.md` plus a symlink to live `auth.json` (read credentials only).
- Project fixtures: `tests/fixtures/firstmate-policy/{absent,stale,worker}`.
- No live captain-memory overwrite, no activation, no rebuild, no Codex.

## Ambiguous feature, captain memory absent

- Case: `ambiguous-absent`
- Coordinator active: `1`
- Fixture: `absent`
- Input:

```
Captain: we should make onboarding better. Decide the next Firstmate stage only.
```

- Observed: STAGE=`gsd-discuss` WAIT_FOR_GO=`n/a` ASK_WHETHER_TO_USE_CYCLE=`no` AUTHORITY_RECORDED=`n/a`
- Expected: STAGE=`gsd-discuss` WAIT_FOR_GO=`n/a` ASK_WHETHER_TO_USE_CYCLE=`no` AUTHORITY_RECORDED=`n/a`
- Rationale: Ambiguous onboarding feature work auto-starts discuss; no prior authorization exists and implementation go is not yet relevant.

## Already-authorized outcome, captain memory absent

- Case: `authorized-absent`
- Coordinator active: `1`
- Fixture: `absent`
- Input:

```
Captain: Implement the dark-mode toggle we already scoped. I authorize implementation of that outcome now: add a user-facing dark mode setting on the settings page. Decide the next Firstmate stage only. Record whether that authorization is enough to proceed.
```

- Observed: STAGE=`gsd-work` WAIT_FOR_GO=`no` ASK_WHETHER_TO_USE_CYCLE=`no` AUTHORITY_RECORDED=`yes`
- Expected: STAGE=`gsd-plan|gsd-work` WAIT_FOR_GO=`no` ASK_WHETHER_TO_USE_CYCLE=`no` AUTHORITY_RECORDED=`yes`
- Rationale: The captain already scoped the dark-mode setting and authorized that same implementation outcome, so absent captain memory cannot force another go.

## Plan-only request, captain memory absent

- Case: `plan-only-absent`
- Coordinator active: `1`
- Fixture: `absent`
- Input:

```
Captain: Plan only: how should we split the billing service? Do not implement. Decide the next Firstmate stage only.
```

- Observed: STAGE=`gsd-plan` WAIT_FOR_GO=`no` ASK_WHETHER_TO_USE_CYCLE=`no` AUTHORITY_RECORDED=`n/a`
- Expected: STAGE=`gsd-plan` WAIT_FOR_GO=`n/a|no` ASK_WHETHER_TO_USE_CYCLE=`no` AUTHORITY_RECORDED=`n/a`
- Rationale: Plan-only with do-not-implement enters gsd-plan now, skips the cycle question, and has no implementation step so there is no go to wait for or record.

## Dispatched worker, nonrecursive

- Case: `worker-absent`
- Coordinator active: `0`
- Fixture: `worker`
- Input:

```
You are a dispatched Firstmate crewmate. Your brief: add the cask "foo" to darwin-configuration.nix homebrew.casks. Execute only the assigned phase. Decide the next Firstmate stage only.
```

- Observed: STAGE=`assigned-phase` WAIT_FOR_GO=`n/a` ASK_WHETHER_TO_USE_CYCLE=`no` AUTHORITY_RECORDED=`n/a`
- Expected: STAGE=`assigned-phase` WAIT_FOR_GO=`n/a` ASK_WHETHER_TO_USE_CYCLE=`no` AUTHORITY_RECORDED=`n/a`
- Rationale: As a dispatched crewmate I execute only the assigned phase and do not start a discuss-plan-work cycle.

## Already-authorized outcome, stale captain memory with unconditional fresh-go

- Case: `authorized-stale`
- Coordinator active: `1`
- Fixture: `stale`
- Input:

```
Captain: Implement the dark-mode toggle we already scoped. I authorize implementation of that outcome now: add a user-facing dark mode setting on the settings page. Stale captain memory in the digest says wait for explicit implementation authorization. Decide the next Firstmate stage only.
```

- Observed: STAGE=`gsd-work` WAIT_FOR_GO=`no` ASK_WHETHER_TO_USE_CYCLE=`no` AUTHORITY_RECORDED=`yes`
- Expected: STAGE=`gsd-plan|gsd-work` WAIT_FOR_GO=`no` ASK_WHETHER_TO_USE_CYCLE=`no` AUTHORITY_RECORDED=`yes`
- Rationale: Captain already scoped the dark-mode toggle and authorized implementing a settings-page user-facing dark mode setting, so stale digest memory that waits for another go is superseded and work starts now.

## Ambiguous feature, stale captain memory that prefers asking about the cycle

- Case: `ambiguous-stale`
- Coordinator active: `1`
- Fixture: `stale`
- Input:

```
Captain: we should make onboarding better. Stale captain memory in the digest prefers a discuss-plan-work cycle. Decide the next Firstmate stage only. Do not ask the captain whether to use the cycle.
```

- Observed: STAGE=`gsd-discuss` WAIT_FOR_GO=`n/a` ASK_WHETHER_TO_USE_CYCLE=`no` AUTHORITY_RECORDED=`n/a`
- Expected: STAGE=`gsd-discuss` WAIT_FOR_GO=`n/a` ASK_WHETHER_TO_USE_CYCLE=`no` AUTHORITY_RECORDED=`n/a`
- Rationale: Ambiguous onboarding work starts gsd-discuss automatically; stale digest cycle preference is superseded and implementation go is not in play yet.

## Closeout

Astra reviewed `42eeb44`. This isolated rerun is follow-up evidence, not a second Astra loop.

After tightening plan-only wording, observed STAGE, WAIT_FOR_GO, and ASK matched the intended contract in all six cases, including absent memory, stale unconditional fresh-go memory, and a dispatched worker. These observations do not prove universal model obedience. Live-home rebuild and reload remain separate rollout work.

