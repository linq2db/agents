# Gap ledger — issue-5788-server-side-only-contract-analyzers

Schema: `.claude/docs/work-plan.md` → *Gap ledger*. Written by `/review-pr` step 7c.
Append rounds; never replace. The continuity section is the point of the file.

## Round 1 — reviewed HEAD `0370a6be5d5cb68013607832bdc55397f93876f8` (2026-09-05)

Review: `/review-pr 5870`, three `code-reviewer` passes (code-correctness, runtime-semantics, api-and-test)
plus an orchestrator-run baselines measurement. 9 findings. Every `P9` gate the plan declared came back
pass, including the 19→0 Release transition, both portable TFMs, the dogfood pass and a full `Tests/Linq`
run — so all 9 were produced by review, not by any declared gate.

| Finding | Gap | Upstream artifact that would have prevented it | Gate that would have caught it | Preventable |
|---|---|---|---|---|
| MAJ001 — code fix emits `nameof(M)` for an explicit interface implementation (`CS0103`) | GAP-02 | `D-12` admitted `ExplicitInterfaceImplementation` into the symbol-kind set and, in the *same* failure-mode line, reasoned about which admitted kinds make the fix emit uncompilable code — stopping at `AttributeTargets` and never asking what `nameof(<Identifier>)` renders for a dotted name. No `P4` row asked it, though `U-5` asked exactly this shape for property accessors. `TO-5` enumerates a constructor case and no explicit-implementation case. | — | yes |
| MIN001 — implemented-interface walk dead for explicit implementations | GAP-02 | Same unprobed symbol kind, one artifact earlier: `E-1` specified "the implemented-interface walk" alongside `D-12`'s admission, with no `P4` row on how `ISymbol.Name` presents for that kind. `P10`'s interface-walk row adjudicates the walk's *suppression* consequence — evidence it was thought about as a behaviour and never as a symbol-naming mechanism. | — | yes |
| MIN002 — add-marker fix duplicates a trailing comment | GAP-05 | `TO-5` says "trivia battery" without naming its axis, so a fixture set covering only the no-attributes branch satisfies the obligation as written. `A-6` records three trivia defects already found by hand during implementation, so the hazard class was known and the obligation still was not decomposed per remedy branch. | — | yes |
| MIN003 — no fixture for marker form 3 | GAP-08 | `TO-2` explicitly requires "**all four** D-8 marker forms are recognised". The plan block was right; `G-01` was recorded as a run total (`78/78`) instead of the per-`TO-n` row `work-plan.md` mandates, so a missing form-3 fixture is indistinguishable from a satisfied proof mode. | G-01 | yes |
| MIN004 — `allowed_exception_types` additivity unpinned | GAP-05 | `SC-7` requires both options additive and `D-11` records "replaces" as a rejected alternative, but `TO-7` writes the discriminating guard for only one of the pair — the sibling gets "silences the exception rule for it", green under either implementation. | — | yes |
| MIN005 — second package readme not updated | GAP-03 | `P7`'s registration-surface row counts and paths the two `AnalyzerReleases` files but collapses the readmes into a singular role name ("the package `readme.md`"). `Source/LinqToDB/readme.md:694-728` carries an `## Analyzers` table listing `L2DB1001`, so the declared repo-wide sweep hit it; only `E-8` exists. | — | yes |
| SUG001 — analyzer/fixer disagree on where a marker-capable attribute may live | GAP-04 | `D-5` asked the altitude question and answered it for two of three consumers. The third was routed via `Diagnostic.Properties` in `E-2`/`E-7`; `A-5` re-litigated only the *visibility* of the remedy constants. Neither is a `D-n`, so neither carries a failure-mode line, and nothing records that a predicate not encoded in `Properties` must be re-implemented in the fixer. | — | partly |
| SUG002 — neither wiki page documents the generated-code exclusion | GAP-01 | No `SC-n` names user-facing documentation of a rule's non-firing conditions, and no `E-n` covers the wiki at all — the word appears nowhere in the plan. `E-8` specifies readme content down to "both option keys documented" with no counterpart for the doc pages. | — | partly |
| NIT001 — two comments in `GetStubThrownType` contradict each other | GAP-10 | The `IOperation` shape genuinely did not exist at plan time: `U-7` asserted a lone `IThrowOperation`, and only `A-4`, measured mid-implementation, established `Block → Return → Conversion → Throw`. The surviving comment states the pre-`A-4` model. No design block governs sweeping a file's prose after an amendment corrects its model. | — | no |

### Aggregate

Flat ledger — two small clusters and four singletons; no single systemic failure.

- **Largest cluster (3 of 9: MIN002, MIN003, MIN004)** — one shape: an obligation naming an **enumerated
  set** ("all four marker forms", "both options additive", "a trivia battery") was satisfied by a fixture
  set covering a subset, and `G-01`'s run-total recording could not tell a covered element from an absent
  one.
- **Second cluster (2 of 9, including the only MAJ)** — one unprobed input class: explicit interface
  implementations were *deliberately admitted* by `D-12` and never probed through either consumer, while
  the neighbouring symbol-kind question (property accessors) got its own `P4` row in `U-5` and shipped
  correct.

Single change preventing the most findings: decompose enumerated obligations into one named fixture per
element and record `G-01` per element. Single change with the highest severity yield: probe every symbol
kind a detection rule admits, end-to-end through the fixer as well as the analyzer.

### Recommended durable fixes

Surfaced, not applied — these route to `/session-reflect`'s `plan-rule` bucket and are the user's call.

- `<GAP-05 × 2, GAP-08 × 1>` → a `P8`-block semantics line in `work-plan.md`, paired with the per-`TO-n`
  `G-01` rule in `definition-of-done.md`: an obligation that names a set is not one obligation — expand it
  in `P8` to one named fixture per element, and record `G-01` as one row per element with the observation
  proving it ran, since a subset of the set is green and indistinguishable from the whole.
- `<GAP-02 × 2>` → the scout brief in `work-plan/SKILL.md` step 5: when a `P5` decision *admits* a symbol
  kind, input class or node type into a detector's scope, the plan owes a `P4` row per admitted kind
  probed through **every** consumer (detector, fixer, message rendering), not just the detector. Worked
  example: `MethodKind.ExplicitInterfaceImplementation`, whose `ISymbol.Name` is dotted (killing a
  name-equality walk) and whose bare identifier does not compile inside `nameof`.
- `<GAP-03 × 1, GAP-01 × 1>` → the scout brief plus `authoring-analyzers.md`: a `P7` "registration
  surface" row lists **paths, one per hit**, never a role name — "the package `readme.md`" hid a second
  packed readme the declared repo-wide sweep had already returned — and it must state the surfaces a
  repo-wide grep structurally cannot reach, the wiki pages, which are also outside anything
  `-Action reconcile` can see.

### Continuity

First ledger for this branch — no prior round to carry forward.

## Round 2 — reviewed HEAD 22fba315bab1c75f2259a313f2ee834fa53e4196 (2026-09-06)

Review: orchestrator-verified findings (structural + consequence, per finding). CI green since round 1 on the
reviewed content (Azure `test-all` build 23419, GH Actions `build` 33998999731/33998985921 on `c5398c2f6`).
5 findings. Every `P9` gate the plan declared came back pass — the 19→0 Release transition, both portable
TFMs, the dual-Roslyn build, the dogfood pass with its pre-registered prediction met, `Tests/Tests.Analyzers`
at 78/78, the full provider suite, the EF legs — so all 5 were produced by review, not by any declared gate.
One exception carried over from round 1: `G-01` is recorded as a run total rather than one row per `TO-n`
element, so a missing fixture for a *named* element is indistinguishable from a satisfied proof mode.

| Finding | Gap | Upstream artifact that would have prevented it | Gate that would have caught it | Preventable |
|---|---|---|---|---|
| MAJ001 — add-attribute remedy writes the marker onto the reported implementation, with no interface branch | GAP-02 | `P5` (`D-8`/`D-12`) admits the implemented-interface walk into arm A's scope, and round 1's `SUG001` fix (`ApplyToDeclaringDocumentAsync`, `CodeFixProvider.cs:71-118`) taught the fixer to resolve it — but only for the `set-named-argument` remedy. Nobody asked whether `RemedyAddAttribute` (`ServerSideOnlyContractAnalyzer.cs:112-114`, chosen when `hasAttribute` is false) needs the same interface-target resolution. `TO-5`'s "a no-attribute member where the fix adds `[ServerSideOnly]`" shape is satisfied by `AddsServerSideOnlyAttributeWhenNoAttributeIsPresent`, a fixture with no interface at all, so the cross-case was never enumerated. `P10`'s interface-walk row adjudicates only the opposite (suppression) direction and does not cover this. | — | yes |
| MIN001 — `TableFunctionAttribute` disjunct in arm A's helper is unreachable, and wrong if it were reached | GAP-02 | `D-12` (`P5`) itself: arm A is defined as "the member carries a marker-capable attribute — `Sql.ExpressionAttribute`-derived or `TableFunctionAttribute`-derived — whose `ServerSideOnly` is explicitly false or unset." A `TableFunctionAttribute`-derived type has no `ServerSideOnly` property (`D-8` form 3 is unconditional), so that clause cannot coherently apply to it. The reachability check against `D-8`'s own form definitions was never made, and `TryFindMarkerCapableAttributeOn` (`ServerSideOnlyContract.cs:304-318`) faithfully implements the contradictory text. | — | yes |
| MIN002 — Fix-All silently skips the cross-document remedy branch | GAP-05 | `SC-5` (`P2`) requires the fix apply to "every flagged site under Fix-All", unqualified — but `TO-5` (`P8`) operationalizes it as only "a ≥3-adjacent-occurrences Fix-All case", a same-document repetition shape matching `E-7`'s `Overlaps` rationale. No obligation names a cross-document Fix-All case, so no fixture could have gone red for `ContractFixAllProvider`'s `Document?`-only signature (`FixAllAsync` `continue`s past the cross-file remedy, `CodeFixProvider.cs:398-406`) even in principle. | — | yes |
| MIN003 — no fixture for the explicit `ServerSideOnly = true` marker form | GAP-08 | `TO-1` ("the same with `= true` does **not** [report]") and `TO-2` ("all four D-8 marker forms") both explicitly name the missing element — the plan block is right, exactly as round 1's MIN003. `G-01` records the analyzer half as a run total (78/78) rather than one row per named element, so a fixture set covering 3 of the 4 named forms passes indistinguishably from one covering all 4. | G-01 | yes |
| MIN004 — no fixture exercises the cross-document solution-level fix path | GAP-05 | `TO-5` (`P8`) lists five code-fix "shapes" needing a red-green proof (trivia, same-document Fix-All, named-argument-set, no-attribute-add, constructor-decline), and none of them is "cross-document / interface in another file" — the shape round 1's `SUG001` fix (`ApplyToDeclaringDocumentAsync`) exists specifically to handle. `CodeFixVerifier.VerifyAsync` (`CodeFixVerifier.cs:25-33`) also has no `TestState.Sources` overload, so even a motivated author could not have written the fixture without first extending the harness. | — | yes |

### Aggregate

Not flat this round: the same two clusters round 1 found reappear at the same relative weight. **GAP-05 × 2 +
GAP-08 × 1 (3 of 5)** is round 1's dominant shape recurring verbatim — an obligation naming an enumerated set
or shape list, satisfied by a fixture subset, with `G-01`'s run-total recording (or the obligation's own
narrowing) unable to tell a covered element from an absent one. **GAP-02 × 2 (2 of 5)** is round 1's second
cluster recurring in generalized form — an admitted design element (the implemented-interface walk) reasoned
about and fixed for one consumer path, never swept to its sibling. Single change preventing the most findings:
decompose `TO-5`'s and `TO-2`'s shape/form lists into one named fixture per element and record `G-01` per
element — this alone would have caught MIN002, MIN003 and MIN004. Single change with the highest severity
yield: when a fix lands in response to a review finding (as `SUG001`'s did), sweep the same admitted
relationship across every sibling consumer path it could also reach — this would have caught MAJ001.

### Recommended durable fixes

- `<GAP-05 × 2, GAP-08 × 1>` → the same `P8`-block semantics line in `work-plan.md` + per-`TO-n` `G-01` rule
  in `definition-of-done.md` recommended in round 1 — **this is the second occurrence of the identical
  shape one round later**, having been "surfaced, not applied" the first time. Expand an obligation naming a
  set or list of shapes into one named fixture per element, and record `G-01` as one row per element with
  the observation proving it ran. Worked example this round: `TO-5`'s Fix-All bullet named only "a
  ≥3-adjacent-occurrences case" when `SC-5` itself says "every flagged site" — the narrowing from success
  criterion to test obligation is exactly where the missing shape fell out.
- `<GAP-02 × 2>` → the scout brief in `work-plan/SKILL.md` step 5, generalizing round 1's recommendation:
  not just "probe every admitted *symbol kind* through every consumer" but **probe every admitted
  *relationship or capability* through every *consumer path* a single design decision can produce** —
  including sibling remedy branches of the same fixer, not only sibling symbol kinds. Worked example: the
  implemented-interface walk was fixed for `RemedySetNamedArgument` (round 1's `SUG001`) and never asked
  of `RemedyAddAttribute`, its structural sibling in the same `switch`.
- `<process gap underlying both clusters>` → `work-plan.md`'s `P11` semantics: a code fix made in direct
  response to a review finding (round 1's `SUG001`, whose fix is `ApplyToDeclaringDocumentAsync`) landed
  with no `P11` amendment and no new `P4`/`P8` row recording it. Require that any such fix on a Tier M/L
  branch get a `P11` line stating what changed and which sibling paths were checked — its absence here is
  why nobody could ask "does this reasoning also apply to `RemedyAddAttribute`?": there was no artifact
  recording that the reasoning existed at all.

### Continuity

**MIN003 recurs round 1's enumerated-set shape exactly, and the recommendation was not applied.** Same
`TO-n` pair (`TO-1`'s negative control, `TO-2`'s "all four marker forms"), same missing-element type (a
marker form), same `G-01` run-total masking. Round 1 labeled its fix "surfaced, not applied — the user's
call"; it was not applied, and the identical failure reproduced one round later in the same test file. MIN002
and MIN004 are the same shape again (`TO-5`'s shape list under-enumerating a scenario), pushing this cluster
from 3-of-9 in round 1 to 3-of-5 in round 2 — proportionally worse, not better.

**MAJ001 recurs round 1's unprobed-consumer shape, in generalized form, and the recommendation was likewise
not applied as a mechanism.** Round 1's MAJ (fixer mishandling an admitted *symbol kind* — explicit interface
implementation — via `nameof()`) was fixed in code (`GetNameOfArgument`/`Qualify`, confirmed present at
HEAD), but only as a point fix; no `P4` row or process rule was adopted requiring the same admitted element
to be swept across every consumer going forward. Round 1's `SUG001` (a *different* finding, GAP-04: analyzer
and fixer disagreeing on where a marker-capable attribute may live) got the same treatment — fixed for one
remedy branch (`RemedySetNamedArgument`, via `ApplyToDeclaringDocumentAsync`), with no sweep of the sibling
branch. Round 2's MAJ001 is that unswept sibling: the fixer mishandling the *same* admitted relationship
(the implemented-interface walk) through the remedy branch (`RemedyAddAttribute`) nobody probed. Per the
task's own framing, this is the **stronger** of the two possible readings — a recommendation that went
unapplied and produced a same-shape defect again, not one that was applied and still let a defect through.
Both clusters point at the same underlying failure: round 1's recommendations were written down but never
became a plan mechanism, so nothing forced the next reactive fix to ask "does this generalize?"
