# Work plans — schema, tiers, lifecycle

A **work plan** is a per-branch design document written *before* the first source edit, kept current through implementation, and read by review as its primary statement of intent. This doc is the canonical schema; [`../skills/work-plan/SKILL.md`](../skills/work-plan/SKILL.md) is the workflow that produces one and [`work-plan-template.md`](work-plan-template.md) is the fillable template.

## Why the artifact exists

Review had no durable statement of intent. `code-reviewer`'s entire picture of design intent was the PR body, linked issues one level deep, a 3–8 bullet change summary written on the spot, and one user-typed sentence at the scope gate — **all four regenerated per review**. Successive reviews of one branch therefore measured against a different yardstick each round, which is why they re-raised settled points instead of converging. A plan fixes the yardstick.

The second cost was that an accepted trade-off had nowhere to live: a deferral adjudicated in round 1 left no artifact, so round 2 raised it again. That is what `P10` is for.

## Location and key

```
.claude/plans/<key>/plan.md
```

`<key>` is the branch name with `/` replaced by `-`: `issue/5818-fix-setop-concat` → `.claude/plans/issue-5818-fix-setop-concat/plan.md`.

Deterministic, derivable before a PR number exists, and never needs renaming.

**Plans live in the corpus submodule, not in linq2db.** They are committed inside `.claude/` and pushed to the agents repo's `master` like any other corpus change ([`agent-rules.md`](agent-rules.md) → *The corpus is a submodule*). Consequences worth knowing:

- The plan is present in **every** worktree with no merge, and readable while reviewing a PR that is not checked out — `/review-pr` reads it from disk, not from the branch.
- It is **never squashed away**. A linq2db PR squash-merges; the plan is unaffected because it was never on that branch.
- It is **invisible to GitHub-side reviewers** (Copilot, humans reading the diff). Accepted trade-off: our own review pipeline is the consumer.
- The plan is committed **on its own**, separately from any linq2db work, per the corpus commit rules.

## Tiers

Tier sets which blocks are mandatory and whether the critic runs.

| Tier | Trigger | Mandatory blocks | Critic |
|---|---|---|---|
| **S** | ≤3 files, one area, mechanical — a version pin, an `[ActiveIssue]` enable, a typo, doc-only, flipping a documented flag | `P1` `P2` `P6` `P9` | none |
| **M** | anything not S or L — the common case | all | advisory; verdict recorded in `P12` |
| **L** | ≥2 areas, **or** a path matching [`../rules/cross-cutting-core.md`](../rules/cross-cutting-core.md)'s `paths:` list (`Source/LinqToDB/**/SqlQuery/**`, `Source/LinqToDB/**/Translation/**`), **or** `IDataProvider` / SQL-builder base classes, **or** new public API outside `LinqToDB.Internal.*` | all, and `P5` must name rejected alternatives | **mandatory**; a missing `P12` is a `-Validate` error |

**Tier is a floor, not a ceiling.** Escalate through `P11` when the work turns out bigger than it looked. **Never de-escalate to dodge the critic** — that is the gaming shape this mechanism exists to prevent.

**Tier S omits `P7`, and that is exactly how a lockstep mirror ships.** A one-line change to a *matcher* — a provider capability flag, a type-keyed switch in a SQL builder, a `switch` over `DataType`, a message-literal predicate — is Tier S by every criterion while being the shape most likely to have a silent twin. linq2db is dense with these: a `SqlServerSqlBuilder` change with an unmoved counterpart in `SybaseSqlBuilder`, an `Insert` path without its `Update` mirror, a flag defaulted in one `SqlProviderFlags` initializer and not another. **When the edit adds a case to a match, search the matched value — the literal, the type, the enum member — tree-wide regardless of tier.**

## Blocks

Blocks marked (M/L) are omitted entirely on a Tier S plan — delete the heading rather than leaving it empty.

### P1 Problem

The observed failure or absent capability, stated **falsifiably**: a reproduction, a stack trace, the wrong SQL beside the right SQL. "It's broken" and "improve robustness" are not `P1` statements because they cannot be shown to be fixed.

### P2 Success criteria

One `SC-n` per criterion. Each must be **failable** — you can state the observation that would show it unmet — and each maps to a `TO-n` in `P8`.

### P3 Constraints & anti-goals (M/L)

What must **not** change. For linq2db the recurring ones: the public API contract outside `LinqToDB.Internal.*`; generated SQL for providers the change does not target; existing baselines; query-cache behaviour; a perf budget where one was measured.

### P4 Unknowns (M/L)

The blind-spot pass that [`agent-rules.md`](agent-rules.md) → *Do a blind-spot pass before coding in an unfamiliar subsystem* already demands but produces no artifact for. One row per assumption, unresolvable unknown, or unmentioned edge case. Each row ends `resolved-by <user answer | scout | probe>` or `OPEN`.

**No `OPEN` row survives approval** — `-Validate` fails on one. Mark a row `OPEN` when it is genuinely unresolved; do **not** silently pick a plausible interpretation and build on it.

### P5 Decisions (M/L; rejected alternatives mandatory at L)

One `D-n` block per consequential decision:

- **chosen:** …
- **rejected:** … — why not
- **why this:** …
- **failure mode of the choice:** …

The `failure mode` line is what makes a decision defensible rather than merely explained, and is usually where the critic finds its objection.

### P6 Edit-points

The **authorized change surface**, not a prediction. One row per planned edit: `E-n <path>:<symbol> — what changes`. Touching anything not listed here needs a `P11` amendment.

**The new `E-n` row itself goes in `P6`; `P11` carries only the rationale.** Reconciliation reads `P6` and nothing else, so an edit-point recorded only in an amendment is invisible to it — the gate then reports authorized work as unplanned.

### P7 Impact map (M/L)

**Searched, never reasoned.** Search for:

- callers of every changed symbol
- **mirrored / parallel sites that must move in lockstep** — the dominant linq2db shape: sibling `*SqlBuilder` / `*SqlOptimizer` / `*MemberTranslator` classes, a base-class default overridden per provider, `Insert` and `Update` paths, read and write converters
- serialized / wire shapes — `LinqService` remote contracts, serialized enums (append-only; see [`pr-and-push.md`](pr-and-push.md))
- contract changes where a caller must tolerate a new value — a `throw` that becomes a `return null`, an added enum member a `switch` does not handle

Every row carries exactly one verdict: `covered by E-n` | `deferred: <reason>` | `out-of-scope`. If a search finds nothing, write `Localized — searched <symbol> across <scope>, no callers or emitted-SQL change.` **A bare "localized" with no named search is invalid.**

### P8 Test obligations (M/L)

One `TO-n` per `P2` criterion. Each names what it asserts and a proof mode:

- `red→green` — fails against the unfixed code **for the right reason**, then passes. Proven by running it, never by reading it.
- `control` — for an added guard: the same input accepted under the lenient path, rejected under the enforced one.
- `characterization` — behaviour-preserving; say plainly that it proves no new behaviour.

Where an `E-n` touches a helper reachable from more than one path, one obligation must be a **symmetry guard on the unchanged path**.

### P9 Verification gates

Gate ids are **not defined here** — they are the items of [`definition-of-done.md`](definition-of-done.md), which is the canonical exit checklist. `P9` records which of them applied and what they returned:

| Gate | Definition-of-done item |
|---|---|
| `G-01` | Tests run and pass via `/test`, with the declared proof mode observed |
| `G-02` | Baselines reviewed, not just regenerated |
| `G-03` | New public surface accounted for (`PublicAPI.Unshipped.txt`, XML doc, a test) |
| `G-04` | API baselines refreshed via `/api-baselines` when the surface changed |
| `G-05` | Builds on the portable TFMs, not just `net10.0` |
| `G-06` | No unrelated reformatting / renames |
| `G-07` | No playground scratch staged |
| `G-08` | Cross-cutting core change surfaced, and resting on a red→green test or CI rather than static reasoning |

Record each as `G-nn: pass | fail | n/a | skipped | blocked — <the command run and what it returned>`. **`skipped` must name what is therefore unverified; `blocked` must name the deferred dependency. Never dress either up as a pass.**

Analyzers are Release-only and `Testing` builds `net10.0` only, so `G-05` is not satisfied by a green `Testing` build ([`agent-rules.md`](agent-rules.md) → *Build & push gotchas*).

### P10 Adjudicated (M/L)

Accepted trade-offs and deliberate deferrals — **the do-not-flag set for this branch's reviews**. Each entry needs a reason, and where the reason is a measurement, the measurement.

Two guards keep this from becoming a silencer, and both are enforced in the reviewer's briefing:

- **An entry with no reason suppresses nothing.**
- **A reviewer who disagrees with an entry raises a finding *against the entry*,** quoting both sides. The user decides which stands.

### P11 Amendments (M/L)

Append-only. One `A-n` per change to the plan after approval.

**Amendment voids approval.** A user approval is a final word on the *then-current* edit set. Adding an `E-n`, or materially changing one's scope, resets that part to unapproved and needs a `P11` entry — whoever makes the change. Never silently carry an approval across a widened edit set: that converts per-change consent into a blanket one.

**A refuted design is recorded as abandoned, not deferred.** "Deferred" asserts the design was sound and the timing was off, so the next reader picks it back up and re-derives the refutation from scratch.

### P12 Critic verdict (M/L)

The `plan-critic` result — `holds` | `weak` | `refuted` — its objections, and what changed in response.

**A `weak` verdict is carried forward with the objections visible, not silently absorbed.** The user approves knowing the strongest case against the design.

**A self-critique by the plan's author is not a verdict.** When the critic genuinely cannot run, record `waived-by-user: <reason>`, which makes the skip visible to the user instead of to nobody.

## Lifecycle

```
draft ──authored──> critiqued ──> approved ──> implementing ──> reviewed ──> closed
                        │                          │
                   refuted: one              amendment (P11)
                   re-author pass            voids affected approval
```

**A status advances only on evidence.** No block flips toward done without a resolvable `file:line`, a command output, or a commit citation. Process-artifact churn must not outrun real code churn — see [`agent-rules.md`](agent-rules.md) → *Don't let progress artifacts outpace real work*.

## Consumers

| Consumer | Reads | Writes |
|---|---|---|
| `/work-plan` | all | all |
| `plan-critic` | `P1`–`P9` | nothing (read-only; the skill records `P12`) |
| `/review-pr`, `/verify-review` | `P1`–`P3` (intent), `P7` (coverage), `P10` (do-not-flag), `P11`, `P12` | dispositions fold back into `P10` / `P11`; `gaps.md` |
| `review-gap-attributor` | the whole plan + `P9` results + the final findings | nothing (read-only; the skill writes `gaps.md`) |
| `work-plan.ps1` | `P4`, `P6`, `P7`, `P8`, `P12`, `gaps.md` | scaffold only |

**A plan states the *intended* contract, not verified fact.** It predates the code and may describe behaviour the diff never implements — deciding that is the review's job. Without this posture the plan launders the author's framing into the review's voice, which [`review-conventions.md`](review-conventions.md) names as the one thing a reviewer is there not to do, and it contradicts `code-reviewer`'s standing rule that *a PR's own root-cause account is a claim*.

## Gap classes — closing the loop back to the plan

A review finding is also evidence about the *plan*. After a review's findings are final, [`review-gap-attributor`](../agents/review-gap-attributor.md) attributes each one to the upstream artifact that would have prevented it and writes `.claude/plans/<key>/gaps.md`. This is what makes review rounds converge **across** PRs rather than only within one — the rest of the mechanism sharpens a single branch, this is the only part that feeds back.

| id | Class | What was missing | Durable home for the fix |
|---|---|---|---|
| `GAP-01` | unstated requirement | `P1`/`P2` never named the behaviour the finding requires | the readiness gate; sometimes a new rule |
| `GAP-02` | unverified assumption | `P4` didn't ask; the plan asserted it | the scout brief / probe discipline |
| `GAP-03` | impact-map miss | a caller, mirrored provider site, type-keyed helper or wire shape `P7` never searched | the scout brief; a new `G-nn` when the shape recurs |
| `GAP-04` | wrong altitude | correct code at the wrong layer — a flag, mapping-schema registration or `Sql.Extension` already expressed it | `P5` — the altitude question wasn't asked |
| `GAP-05` | missing test obligation | no `TO-n` covered the path, or the one that did couldn't go red | `P8`; [`testing.md`](testing.md) when the shape recurs |
| `GAP-06` | convention not applied | the rule was embedded in the plan's baseline and violated anyway | the rule needs a do/don't example |
| `GAP-07` | convention not embedded | the rule exists but step 4 didn't put it in front of the author | the skill's embed step |
| `GAP-08` | gate not run | a `G-nn` would have caught it and was skipped, or recorded `fail` and ignored | `P9` derivation, or [`definition-of-done.md`](definition-of-done.md) |
| `GAP-09` | amendment not logged | code went outside `P6` with no `P11` entry | `-Reconcile` should have failed — find why it didn't |
| `GAP-10` | unpreventable | information that did not exist at plan time | nothing — this is the honest floor |

Two outcomes that are **not** gaps, reported as themselves rather than forced into a class:

- **`not-a-gap: reviewer-disagrees-with-P10`** — the finding contests an adjudicated entry. That is a legitimate finding *about the adjudication*, not a planning failure.
- **`not-a-gap: out-of-plan-scope`** — the finding concerns code `P7` deliberately marked `deferred:` or `out-of-scope`, **with a reason**. A deferral with no reason *is* a gap (`GAP-03`).

**Attribute to the earliest artifact in the chain, not the last.** A gate that would have caught something but was driven off a plan block that lacked the entry is `GAP-03`, not `GAP-08` — the gate could not catch what the map never listed, so the durable fix belongs in the scout brief rather than the gate.

**`GAP-10` is the calibration signal, not a dumping ground.** Use it only when you can name the information that did not exist at plan time. A dominant `GAP-10` means the design pass is not earning its cost, and the right response is to say so and **cut the ceremony** — not to defend the machinery.

## No plan on the branch

External-contributor PRs, and any branch predating this mechanism, have no plan. **"No plan" is a first-class valid state.** Every consumer degrades to its previous behaviour: `/review-pr` falls back to the hand-typed scope sentence, and nothing reports an error.
