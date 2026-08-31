---
name: work-plan
description: Author, critique and maintain the per-branch work plan that records a change's design before the first source edit — problem, success criteria, decisions, authorized edit-points, impact map, test obligations and verification gates. Dispatches an adversarial critic on a different model to attack the design while it is still cheap to change, then commits the plan to the corpus for `/review-pr` to read as its primary statement of intent. Never writes product code and never commits linq2db work.
---

# /work-plan

User-triggered. Produces `.claude/plans/<key>/plan.md` — the design document that implementation is confined to and that review reads instead of re-deriving intent from the diff every round.

The skill **does not write the fix**. It owns "task → searched design → attacked design → approved plan"; the user (or `/fix-issue`) drives the code from there.

Block semantics, tiers, and the location rule are canonical in [`work-plan.md`](../../docs/work-plan.md) — this file is the workflow only and does not restate them.

## Shared reference material

- **Schema, tiers, lifecycle, consumers**: `.claude/docs/work-plan.md`
- **Fillable template**: `.claude/docs/work-plan-template.md`
- **Gate ids** (`G-01`…`G-08`): `.claude/docs/definition-of-done.md` — the plan records results, it does not define gates
- **Critic agent contract**: `.claude/agents/plan-critic.md`
- **Script**: `.claude/scripts/work-plan.ps1` — `-Action init | validate | gates | reconcile`
- **Cross-cutting core trigger for Tier L**: `.claude/rules/cross-cutting-core.md`
- **Branch rules + slug format**: `.claude/docs/agent-rules.md` → *Creating a new branch*
- **Corpus commit rules**: `.claude/docs/agent-rules.md` → *The corpus is a submodule*

## When to run

- `/work-plan` — author a plan for the current branch.
- `/work-plan <key-or-branch>` — target an explicit key.
- `/work-plan amend` — record a `P11` amendment on an existing plan.
- `/work-plan check` — run `-Validate`, `-Gates` and `-Reconcile` and report.

Invoked directly, or by `/fix-issue` after the branch exists and existing test coverage has been mapped.

**Not every change needs the full ceremony** — a Tier S plan is four blocks and ten lines. But a change that touches shared engine code, or that a reviewer would reasonably ask "why this way?" about, does.

## Steps

### 1. Resolve the branch, the key, and the mode

1. `work-plan.ps1 -Action validate` with no `-Key` derives the key from the current branch. It refuses `master` / `main` — a plan belongs to a work branch.
2. **If a plan already exists, switch to `amend` mode. Never overwrite one.** `-Action init` refuses an existing plan unless `-Force`, and `-Force` is the user's call, not yours.
3. If the branch does not exist yet, stop and say so — the branch comes first (agent-rules → *Creating a new branch*). Do not create it from here.

**In a worktree, the plan lands in that worktree's own `.claude/` checkout**, which the `post-checkout` hook bootstraps on a detached HEAD. Before committing a plan from a worktree, `git -C <worktree>/.claude switch master` — otherwise the commit is stranded. See [`worktree.md`](../../docs/worktree.md).

### 2. Classify the tier

Apply the table in [`work-plan.md`](../../docs/work-plan.md) → *Tiers*. Show the user the tier you picked **and why**, and accept an override.

Escalation is free; **de-escalation to skip the critic is the one move this mechanism exists to prevent** — if the user asks for it, record it in `P12` as `waived-by-user: <reason>` rather than silently dropping the pass.

### 3. Readiness gate

A plan cannot be authored from an under-specified task. Confirm all four, batching every question into **one** message (agent-rules → *Ask-ask-do-all*):

1. **Need** — what observable failure or absent capability is this for? (`P1`)
2. **Success criterion** — what observation would show it fixed? (`P2`)
3. **Pin** — the issue number, the repro, the failing test, or the SQL that is wrong.
4. **Constraints** — anything that must not change. (`P3`)

**Ask once for a missing load-bearing field, then stop and wait.** Do not infer a success criterion from a bug title and build a design on it.

### 4. Load the conventions and KB context *before* designing

Path-scoped rules under `.claude/rules/` fire when someone **edits** a matching file — which is after the design is already fixed — and they never reach a subagent at all. So load them now and **embed** the relevant section in the author's and the critic's context:

- `.claude/rules/cross-cutting-core.md` when `P6` will touch `SqlQuery/` or `Translation/`.
- `areas/<AREA>/{issues,decisions,patterns,tech-debt}.md` — map the path to its area by **`Grep`-ing** [`kb-areas.md`](../../docs/kb-areas.md), never `Read`-ing it (the table is ~37 k tokens). Skip silently when the KB isn't built.
- Auto-memory `project_*` entries for recorded dead-ends on this subsystem.

This is the step that stops a design that violates an already-enforced rule.

### 5. Scout the impact map (Tier M/L)

`P7` is **searched, never reasoned**. Derive 2–6 questions from the intended edit surface and dispatch them to the **`Explore` subagent in a single message** so they run concurrently. Typical questions for linq2db:

- Who calls `<symbol>`, and which callers are in other providers?
- Which sibling `*SqlBuilder` / `*SqlOptimizer` / `*MemberTranslator` carries the same override or literal?
- Is this flag defaulted in more than one `SqlProviderFlags` initializer?
- Does a `LinqService` remote contract or a serialized enum carry this shape?
- Is there an `Insert`/`Update` or read/write pair where only one side is in scope?

Frame each so **"I couldn't find it" is a valid answer** (agent-rules → *Frame subagent prompts to allow failure*), and require a `file:line` per finding plus the exact pattern searched. A scout that reports "localized" without naming its search has not answered.

Run `git status` **and** `git -C <primary-clone>/.claude status` after the fan-out returns — subagent tool declarations are advisory, not enforced.

### 6. Author `P1`–`P9`

Write the blocks inline from the readiness answers, the scout evidence and the embedded conventions. Two authoring rules carry most of the weight:

- **The plan's authority comes from its evidence, not its confidence.** Every `P7` row traces to a named search; every behavioural claim about existing code carries a `file:line`.
- **Mark a `P4` row `OPEN` when it is genuinely unresolved.** Do not silently pick a plausible interpretation and build on it — `-Validate` fails on a surviving `OPEN`, which is the point.

Then `work-plan.ps1 -Action init` and fill, or edit the existing file. Run `-Action gates` to derive the applicable `G-nn` subset from `P6` and seed `P9`.

### 7. Attack it with the critic (Tier M/L; mandatory at L)

One `Agent` call to `plan-critic`, **passing the model explicitly on the dispatch** — the model is load-bearing here, so do not rely on frontmatter being picked up.

**First run in this corpus: ask which model to critique with.** Read `.claude/plans/config.json`; if it carries no entry for the current host tool, ask the user once, then write it:

```json
{ "criticModel": { "claude-code": "fable" } }
```

The requirement is a model **from a different family than the author's**, because that is the entire mechanism — a same-model critic re-derives the same blind spots. For Claude Code the suggestion is `fable`. Under another host (Codex, or anything else reading this corpus) the choice is the user's; record it under that tool's key.

**Dispatch hygiene — this is the difference between a critic that earns its cost and one that rubber-stamps:**

- **Forward every measurement you already hold, verbatim.** The critic cannot see your probes, so a fact you measured and withheld is one it will re-derive from documentation — and documentation is exactly what a careful critic reaches for.
- **Label every fact `measured:` or `reasoned, unprobed:`.** A reasoned claim wearing the `measured` label buys silence on precisely the point that needed noise.
- **Never pre-empt an objection by name.** Saying "this is fine because X" instructs the critic not to look there. A wrong `refuted` costs one visible re-author round; a suppressed correct objection costs the implementation.

Reconcile by verdict:

- **`holds`** — carry forward; record in `P12` **what the critic searched**, not just the word.
- **`weak`** — carry forward with the objections **visible in the plan you show the user**. Do not absorb them silently; the user approves knowing the strongest case against the design.
- **`refuted`** — revise once, then **send the revision back to the critic**, not straight to the user. Cap at one round: if the revision still cannot answer the objections, present both and stop for user direction.

**A refutation resting on documentation is probed before it is accepted *or* rejected.** When the critic contradicts something you believe and a build, test or container is to hand, measure it. Record the measurement in `P4` with its result, and note which way the evidence fell in `P12`.

### 8. Present and get approval

Show the user the plan — tier, `P2` criteria, `P6` edit-points, the critic verdict with its objections, and any `P4` row still open. **Ask for approval in the main loop, never from inside a subagent** — subagents run non-interactively and a prompt there is auto-denied.

Approval is a final word on the **then-current** edit set. Record it on the header line.

### 9. Validate, then commit the plan on its own

1. `work-plan.ps1 -Action validate` — must exit 0. Fix what it names; do not talk past it.
2. Commit **inside the submodule**, plan only:
   `git -C .claude add plans/<key>` then `git -C .claude commit -F <msg-file>`.
   Message shape: `plan(<key>): <one-line intent>` plus 2–3 lines on approach, critic verdict, and the authorized surface.
3. Push to the agents repo's `master` — **but only on an explicit user request this turn**, like any other publish (agent-rules → *Git commit rules*).

The plan never lands on a linq2db branch and never bumps the `.claude` gitlink.

### 10. Hand off

Report: key + path, tier, critic verdict, `P6` edit-point count, applicable gates, and any `P4` row the user still owes an answer on. Then stop — implementation is the user's or `/fix-issue`'s.

## Mode: amend

1. Add the new `E-n` row **to `P6`** — `-Reconcile` reads `P6` and nothing else, so an edit-point recorded only in the amendment is invisible to it and the gate then reports authorized work as unplanned.
2. Add an `A-n` entry to `P11` carrying the rationale, and say plainly that the affected approval is void and must be re-earned.
3. **At Tier L, re-dispatch the critic on the delta** when the amendment widens `P6` or adds an area, and append the verdict to `P12`. A whole-plan re-critique for a one-row amendment is waste; skipping it entirely is how prose added after the single critic pass ships unattacked.
4. Re-run `-Action validate`.

## Mode: check

Run all three (`-Validate`, `-Gates`, `-Reconcile`) and report. `-Reconcile` exits non-zero when a changed file has no `E-n`; that is a prompt to amend `P6`, not to widen the match until it passes.

## Don'ts

- **Do not write product code.** The skill's scope ends at an approved plan.
- **Do not commit or push anything without an explicit request this turn** — including the plan. "The plan validates" is not a request.
- **Do not overwrite an existing plan.** Amend it. `-Force` is the user's call.
- **Do not let the author critique its own plan.** A self-critique is not a verdict; if the critic cannot run, record `waived-by-user: <reason>` so the skip is visible to the user rather than to nobody.
- **Do not de-escalate a tier to skip the critic**, and do not offer it as a shortcut.
- **Do not fill `P7` by reasoning.** A row with no named search is invalid even when it happens to be right — the implementer cannot tell the difference.
- **Do not mark a gate `pass` that you did not run.** `skipped` must name what is therefore unverified; `blocked` must name the dependency.
- **Do not treat an absent plan as an error.** Branches predating this mechanism and external-contributor PRs have none, and every consumer degrades cleanly.
