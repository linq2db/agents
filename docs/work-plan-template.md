# Work-plan template

The fillable skeleton `work-plan.ps1 -Init` copies into `.claude/plans/<key>/plan.md`. Block semantics live in [`work-plan.md`](work-plan.md); this file is the shape only.

It sits in `docs/` rather than inside the skill directory because the corpus convention is one `SKILL.md` per skill directory and nothing else.

Everything between the markers below is the template body.

<!-- TEMPLATE-BEGIN -->
# Work plan: {{KEY}} — {{TITLE}}

**Tier:** {{TIER}}  ·  **Status:** draft  ·  **Approved-at:** —  ·  **Branch:** {{BRANCH}}
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

<!-- fill: every `fill:` marker must be gone before approval — `work-plan.ps1 -Validate` fails on any that remain. Blocks marked (M/L) may be omitted entirely on a Tier S plan; delete the heading rather than leaving it empty. -->

## P1 Problem

<!-- fill: the observed failure or absent capability, stated falsifiably — a repro, a stack trace, the wrong SQL beside the right SQL. "It's broken" / "improve robustness" are not P1 statements: they cannot be shown to be fixed. -->

## P2 Success criteria

<!-- fill: one bullet per criterion. Each must be failable (you can state the observation that would show it unmet) and each maps to a TO-n in P8. -->

- SC-1 …  → TO-1

## P3 Constraints & anti-goals (M/L)

<!-- fill: what must NOT change. Public API outside LinqToDB.Internal.*, generated SQL for providers this change does not target, existing baselines, query-cache behaviour, a measured perf budget. -->

## P4 Unknowns (M/L)

<!-- fill: the blind-spot pass. One row per assumption, unresolvable unknown, or unmentioned edge case. Each row ends in `resolved-by <user answer | scout | probe>` or `OPEN`. NO `OPEN` ROW MAY SURVIVE APPROVAL — -Validate fails on one. -->

- U-1 … — resolved-by …

## P5 Decisions (M/L; rejected alternatives mandatory at L)

<!-- fill: one D-n block per consequential decision. The `failure mode of the choice` line is what makes the decision defensible rather than merely explained, and is usually where the critic finds its objection. -->

### D-1 — …

- **chosen:** …
- **rejected:** … — why not
- **why this:** …
- **failure mode of the choice:** …

## P6 Edit-points

<!-- fill: the AUTHORIZED CHANGE SURFACE, not a prediction. `-Reconcile` reports a changed file with no E-n. Touching anything not listed here needs a P11 amendment. One row per planned edit: `E-n path:symbol — what changes`. The row itself always lives here, never only in an amendment. -->

- E-1 `Source/LinqToDB/…:Symbol` — …

## P7 Impact map (M/L)

<!-- fill: SEARCHED, never reasoned. Search for: callers of every changed symbol · mirrored sites that must move in lockstep (sibling *SqlBuilder / *SqlOptimizer / *MemberTranslator, a base-class default overridden per provider, Insert AND Update, read AND write converters) · serialized/wire shapes (LinqService contracts, append-only serialized enums) · contract changes a caller must tolerate (throw→return null, a new enum member an existing switch doesn't handle). Every row carries exactly one verdict: `covered by E-n` | `deferred: <reason>` | `out-of-scope`. If a search finds nothing: `Localized — searched <symbol> across <scope>, no callers or emitted-SQL change.` A bare "localized" with no named search is invalid. -->

- `Source/LinqToDB/…:210` — … — covered by E-1

## P8 Test obligations (M/L)

<!-- fill: one TO-n per P2 criterion. Each names what it asserts and a proof mode: `red→green` (fails against unfixed code for the right reason, then passes — proven by running it, never by reading it) | `control` (same input accepted under the lenient path, rejected under the enforced one) | `characterization` (behaviour-preserving; say plainly it proves no new behaviour). Where an E-n touches a helper reachable from more than one path, one obligation must be a symmetry guard on the UNCHANGED path. -->

- TO-1 … — proof: red→green

## P9 Verification gates

<!-- fill: gate ids are the definition-of-done items — run `work-plan.ps1 -Gates` to derive the applicable subset from P6, then record each as `G-nn: pass | fail | n/a | skipped | blocked — <command run and what it returned>`. `skipped` must name what is therefore unverified; `blocked` must name the deferred dependency. Never dress either up as a pass. -->

- G-01: — (pending)

## P10 Adjudicated (M/L)

<!-- fill: accepted trade-offs and deliberate deferrals — THE DO-NOT-FLAG SET for this branch's reviews. Each entry needs a reason, and where the reason is a measurement, the measurement. An entry with no reason suppresses nothing; a reviewer that disagrees with an entry raises a finding against the entry. Leave as "_None yet._" when there is nothing adjudicated. -->

_None yet._

## P11 Amendments (M/L)

<!-- fill: append-only. One A-n per change to the plan after approval. Adding or materially changing an E-n VOIDS that part's approval and must be re-earned. The new E-n row goes in P6; this block carries only the rationale. Leave as "_None._" until the first amendment. -->

_None._

## P12 Critic verdict (M/L)

<!-- fill: the plan-critic result — `holds` | `weak` | `refuted` — its objections, and what changed in response. A `weak` verdict is carried forward with the objections VISIBLE, not silently absorbed. A self-critique by the author is not a verdict; when the critic cannot run, record `waived-by-user: <reason>`. -->

_Not yet critiqued._
<!-- TEMPLATE-END -->
