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
- **Gap-attributor contract** (the review-side feedback loop): `.claude/agents/review-gap-attributor.md`
- **Script**: `.claude/scripts/work-plan.ps1` — `-Action init | validate | gates | reconcile | gap-report`
- **Cross-cutting core trigger for Tier L**: `.claude/rules/cross-cutting-core.md`
- **Branch rules + slug format**: `.claude/docs/agent-rules.md` → *Creating a new branch*
- **Corpus commit rules**: `.claude/docs/agent-rules.md` → *The corpus is a submodule*

## When to run

- `/work-plan` — author a plan for the current branch.
- `/work-plan <key-or-branch>` — target an explicit key.
- `/work-plan amend` — record a `P11` amendment on an existing plan.
- `/work-plan check` — run `-Validate`, `-Gates` and `-Reconcile` and report.
- `/work-plan postmortem` — render the gap ledger a review produced and route its durable fixes.

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

**When the change adds a member to a type-keyed or enum-keyed set, sweep the *helpers*, not just the `switch` statements.** A `case <Enum>.` / `<x> switch` sweep finds the dispatch sites and reads as complete — but the sites that go missing are type-keyed **helper methods**: a `GetXxx` mapping a node kind to a value, a lookup table, a dictionary or `HashSet` keyed by the enum, an `if (x is A or B or C)` chain. They compile fine with the new member absent and answer wrong at runtime. Require the scout to name which *kind* of site each search covered, so "no missed dispatch site" cannot stand in for "no missed consumer". (Measured on the #5750 backtest: the plan and the critic both swept `case QueryElementType.` and `<x> switch`, both reported the dispatch map complete, and both missed `GetDbDataTypeImpl` — where four new AST nodes' declared `DbDataType` was silently replaced by the mapping-schema default. It was filed as a real review finding.)

Frame each so **"I couldn't find it" is a valid answer** (agent-rules → *Frame subagent prompts to allow failure*), and require a `file:line` per finding plus the exact pattern searched. A scout that reports "localized" without naming its search has not answered.

Run `git status` **and** `git -C <primary-clone>/.claude status` after the fan-out returns — subagent tool declarations are advisory, not enforced.

### 6. Author `P1`–`P9`

Write the blocks inline from the readiness answers, the scout evidence and the embedded conventions. Two authoring rules carry most of the weight:

- **The plan's authority comes from its evidence, not its confidence.** Every `P7` row traces to a named search; every behavioural claim about existing code carries a `file:line`.
- **Mark a `P4` row `OPEN` when it is genuinely unresolved.** Do not silently pick a plausible interpretation and build on it — `-Validate` fails on a surviving `OPEN`, which is the point.
- **Before dispatching the critic, read every `P5` decision beside the `P7` rows and `P4` answers you just wrote.** The blocks are authored in sequence and the later ones are where the design gets chosen, so a mechanism established in `P7` routinely fails to reach the decision that depends on it. The specific shape to look for: a decision that gates on the **absence** of a state your own impact map proved is **present**. It costs one read and it is the failure the critic should never have to find for you. (Surfaced on the #5818 backtest: `P7` established that a build flag survives into nested strict-`Sql` frames, and `P5` then chose a guard requiring the non-strict purpose. The contradiction was on the page and both passes talked past it.)

Then `work-plan.ps1 -Action init` and fill, or edit the existing file. Run `-Action gates` to derive the applicable `G-nn` subset from `P6` and seed `P9`.

### 7. Attack it with the critic (Tier M/L; mandatory at L)

One `Agent` call to `plan-critic`, **passing the model explicitly on the dispatch** — the model is load-bearing here, so do not rely on frontmatter being picked up.

**First run in this clone: ask two settings once, then persist them.** Read `.claude/plans/config.json` — **gitignored and per-user**, so a fresh clone legitimately has none and the prompt is expected, not a fault. For each key it does not carry, ask the user and write the answer back:

```json
{
  "criticModel":  { "claude-code": "fable" },
  "criticTiming": "before"
}
```

- **`criticModel`** — keyed by host tool, because the right answer differs per tool. The requirement is a model **from a different family than the author's**; a same-model critic re-derives the same blind spots. For Claude Code the suggestion is `fable`. Under another host the choice is the user's.
- **`criticTiming`** — `before` | `after` | `ask`. Not keyed by tool: it is a workflow preference, not a capability. See below.

Ask both in the **same** prompt when both are missing — don't make the user answer two turns for one setup.

#### `criticTiming` — when the critic runs relative to step 8

| Value | Flow | Trade-off |
|---|---|---|
| **`before`** | 7 → 8. The user first sees the plan with the verdict already folded in. | The user never reviews a design that is about to change, and approves knowing the strongest case against it. Costs a critic pass even on a plan the user would have rejected outright. |
| **`after`** | 8 → 7 → 8 again. Present the plan, take the user's reaction, *then* critique, then re-present the verdict and re-confirm. | The user can kill or redirect an approach before a critic pass is spent. Costs a second presentation round, and the first approval is provisional by construction. |
| **`ask`** | Ask per run, defaulting to whatever suits the plan's size. | No standing commitment; one extra question each time. |

**Under `after`, the first approval is provisional and must be said to be.** Approval is a final word on the *then-current* edit set (step 8), so a critic that subsequently returns `weak` or `refuted` voids it — exactly as a `P11` amendment would. Tell the user that when presenting, and re-confirm after the verdict. Never let a pre-critique approval stand as the approval of record.

**`before` remains the recommendation, and the reason is empirical:** on the first real run of this skill ([#5729](https://github.com/linq2db/linq2db/issues/5729)) the critic changed the design on both passes — pass 1 removed an edit-point and forced a helper re-decision, pass 2 refuted an entire folded-in half. Presenting first would have spent the user's attention twice on designs that did not survive.

**Tier S never asks.** No critic runs at Tier S, so neither setting applies; don't prompt for them on a Tier S plan.

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

**Under `criticTiming: after` this step runs twice**, and the two runs are not the same thing:

1. **Pre-critique** — present the design *without* a `P12` verdict, and say plainly that it has not been attacked yet and that approval here is provisional. The user's job at this point is to kill or redirect the approach, not to bless the details. Then go to step 7.
2. **Post-critique** — present the verdict and whatever changed in response, and take the approval of record. If the critic returned `holds` and nothing moved, say so in a line rather than re-pasting the whole plan.

Never record a pre-critique approval on the header line. If the user approves at (1) and the critic then returns `weak` or `refuted`, the approval is void the same way a `P11` amendment voids one — re-earn it at (2).

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

## Mode: postmortem

After a review has produced a gap ledger (`/review-pr` step 7c writes `.claude/plans/<key>/gaps.md`), `/work-plan postmortem` renders it and routes its recommendations.

1. `work-plan.ps1 -Action gap-report -Key <key>` — counts per class, the dominant actionable class, and the unpreventable ratio.
2. Read the ledger's `## Recommended durable fixes` and walk them **one per turn**, per the interactive-review rule in [`agent-rules.md`](../../docs/agent-rules.md) → *Batching and user interaction*. Each goes to one of: the scout brief (step 5 above), an attack vector in [`plan-critic.md`](../../agents/plan-critic.md), a block's semantics in [`work-plan.md`](../../docs/work-plan.md), a [`definition-of-done.md`](../../docs/definition-of-done.md) gate, or a `code-reviewer` rubric rule.
3. Anything the user accepts is a **corpus** edit — route it through `/session-reflect`'s `plan-rule` bucket rather than editing in place from here, so it lands with the rest of the session's captures.

**A `GAP-10`-dominant ledger means cut the ceremony, and that outcome must be reported as-is.** The script flags it. Do not respond by adding another search discipline to a design pass that the evidence says is not paying for itself on this shape of work — say so, and propose lowering the tier or dropping the plan requirement for that class of change.

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
