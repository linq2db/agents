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
