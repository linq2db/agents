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

- `<GAP-05 × 2, GAP-08 × 1>` → **already codified, and it did not help this branch.** Round 1's
  recommendation landed in `work-plan.md` as the `P8` enumerated-set rule, citing this PR. The shape still
  recurred, because the rule governs plan *authoring* and this plan predates it. So the durable fix is not
  the rule again — it is a **re-walk of an existing plan's `P8` and `P4` against rules added since**,
  recorded as a `P11` amendment, which `work-plan.md` → *Gap classes* now states. Worked example this round:
  `TO-5`'s Fix-All bullet named only "a ≥3-adjacent-occurrences case" when `SC-5` itself says "every flagged
  site" — the narrowing from success criterion to test obligation is exactly where the missing shape fell
  out, and a re-walk would have caught it.
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

**MIN003 recurs round 1's enumerated-set shape exactly — and the recommendation *was* applied, which is the
more useful finding.** Same `TO-n` pair (`TO-1`'s negative control, `TO-2`'s "all four marker forms"), same
missing-element type (a marker form), same `G-01` run-total masking. MIN002 and MIN004 are the same shape
again (`TO-5`'s shape list under-enumerating a scenario), pushing this cluster from 3-of-9 in round 1 to
3-of-5 in round 2.

*Corrected after this ledger was first written:* it originally asserted the recommendation had not been
applied. It had. `work-plan.md` carries it — *"An obligation that names a set is not one obligation — expand
it to one named fixture per element"* — and cites this PR's round 1 as its source. The defect recurred
anyway, because these rules bind at **authoring** time and this branch's `P8` was written before the rule
landed, with nothing re-walking an existing plan against rules added since. That is a different failure from
"the recommendation was ignored" and it prescribes a different fix: re-walk a long-lived plan's `P8` and `P4`
against the current rule set and record it as a `P11` amendment. The lesson for the ledger itself is to
`Grep` the destination file for the recommendation's wording before concluding anything about recurrence —
now recorded in `work-plan.md` → *Gap classes*.

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

## Round 3 — reviewed HEAD `72b975ce380b0f4eec527ac5ca15e46cc969e2a2` (2026-09-07)

Review: three parallel `code-reviewer` passes (code-correctness, a Roslyn/analyzer-infrastructure pass
reframed in place of `sql-and-provider`, api-and-test), with the baselines pass replaced by an
orchestrator measurement. 8 items — 6 findings and 2 out-of-scope observations. Weighted toward
`4c6b66c8c` and `72b975ce3`, the two commits Copilot never reviewed (quota limit), and **both findings
that turned out to be defects live in code those commits introduced**. Every `P9` gate came back pass,
including the full `test-all` matrix at build 23461 on the reviewed HEAD — so all 8 were produced by
review, not by any declared gate. `G-01`'s per-`TO-n` recording exception carries over from rounds 1
and 2 for a third time.

| Finding | Gap | Upstream artifact that would have prevented it | Gate that would have caught it | Preventable |
|---|---|---|---|---|
| MAJ001 — add-attribute remedy marks the implementation when the interface member is declared in metadata | GAP-02 | `A-11` itself, one round old. It admitted the implemented-interface walk into the fixer and enumerated the shapes it must handle, naming the metadata case explicitly and asserting the fix *declines* there — so the input class was identified, reasoned about, and then implemented as an ambiguous `null` that the sibling consumer reads with the opposite meaning. No `P4` row asked how `E-7` distinguishes "walk found nothing" from "walk found something unwritable", and `TO-5` has no metadata-reference shape, so no fixture could have gone red. | — | yes |
| MIN006 — only the first of several implemented interface members is marked | GAP-02 | Same artifact, the other unasked question: `E-1`'s walk was specified as singular (`FindInterfaceMarkerTarget`) while `D-8`'s marker semantics are existential — *any* marker satisfies `DeclaresServerSideOnly` — so one target can never be sufficient. The contradiction is between two design blocks, visible without reading code, and `P10`'s interface-walk row adjudicates only the suppression direction. | — | yes |
| MIN001 — no fixture reaches `TryRewriteAt`'s cross-file add-attribute arm | GAP-05 | Round 2's MIN002/MIN004 added `TO-5`'s cross-document shape and `A-11` implemented it, but the obligation was written in the singular — "a cross-document case" — and satisfied by the `set-named-argument` half. The *remedy* axis was never crossed with the *document* axis, which is round 2's own recommendation (sweep an admitted relationship across every sibling remedy branch) unapplied one round later. | G-01 | yes |
| MIN002 — the fixture named for explicit `ServerSideOnly = false` cannot discriminate | GAP-08 | `TO-1` names the element and a fixture bearing its name exists, so the enumerated-set rule reads as satisfied. What no artifact states is *which input separates the two halves of the predicate* `D-8` form 2 defines: only an `ExtensionAttribute`-derived attribute can disagree with its own ctor default, and `Sql.Function` is not one. A `P4` row on form 2's decision boundary would have named it. | G-01 | yes |
| MIN003 — `GeneratedCodeAnalysisFlags` untested on both hosts | GAP-08 | `D-4` is a full decision block with a stated failure mode — "the hosts diverge on one line and a future reader may harmonize them" — and no `TO-n` at all. `P12` round 5 then used that untested line to close the critic's `LinqToDB.Scaffold` observation, so a design claim was discharged by an assertion nothing gated. `E-13` also silently removed the internal host's only reportable generated stub, making `TO-3` blind to it. | — | yes |
| MIN005 — `RunMultiFile`'s injected `.editorconfig` never reaches its sources | GAP-05 | `E-19` specified a verifier overload for `.editorconfig` fixtures and round 2 added the multi-source one; neither obligation says the injected config must be *demonstrated to apply*. `A-6` and the `P12` CI note both record that formatting assertions are invisible to a fixture whose only edit sits within a line — the exact blindness that hid this — so the hazard was documented and not converted into a requirement. | — | yes |
| MIN004 — the operators/indexers exclusion's recorded justification is false | GAP-03 | `D-12`'s failure-mode line asserts `AttributeTargets.Property | Method` makes a fix on those kinds uncompilable. It is a checkable claim about C# that was never checked, and it propagated verbatim into `P10`, a core doc comment and the shipped `L2DB1003` wiki page. `P7` has no row for the wiki, which is also outside anything `-Action reconcile` can see — round 1's `SUG002`/GAP-01 recommendation, unapplied. | — | yes |
| SUG002 — duplicate fixture; an enumerated `TO-4` cell has none | GAP-08 | `TO-2`'s negative control and `TO-4`'s four consumer shapes overlap without saying so, so one slot was spent restating a pinned negative while a named positive cell relied on the dogfood corpus. Same enumerated-set masking as rounds 1 and 2. | G-01 | yes |

### Aggregate

**GAP-02 × 2 for the second round running, and this time the artifact that failed is the *previous
round's own fix*.** Round 2's MAJ001 was `A-11`; round 3's two real defects are both inside `A-11`'s
implementation — the metadata case it named and claimed to handle, and the multiplicity question its
singular walk never raised. Round 2 predicted exactly this: *"when a fix lands in response to a review
finding, sweep the same admitted relationship across every sibling consumer path it could also reach."*
`A-11` was that fix, it was written without such a sweep, and it produced two same-shape defects.

**GAP-08 × 3 + GAP-05 × 2 (5 of 8)** is rounds 1 and 2's dominant cluster for the third time, but the
sub-shape has shifted and is worth naming separately: in rounds 1 and 2 the element had **no** fixture;
here three elements have a fixture that **cannot fail** for the thing it is named after. That is strictly
worse, because it reads as covered in `G-01` *and* in the file. The distinguishing test is not "is there a
fixture per element" but "does an input exist that separates the arms, and does the fixture use it" — and
for `MIN002` that input is derivable from `D-8` form 2's own definition.

Single change preventing the most findings: for each predicate a `P5` block defines, record the input that
separates its arms and require the fixture to use it — this alone covers MIN002, MIN003 and SUG002. Single
change with the highest severity yield: when a fix answers a review finding, enumerate the input classes
the finding's own text names and require one fixture per class — `A-11` named the metadata case in prose
and shipped it untested.

### Recommended durable fixes

Surfaced, not applied — these route to `/session-reflect`'s `plan-rule` bucket and are the user's call.

- `<GAP-08 × 3>` → **applied** to `work-plan.md` on 2026-09-07. A `P8` semantics line one level deeper
  than round 1's enumerated-set
  rule (which is now codified and was satisfied here): a fixture for a named element must use an input on
  which the element's **decision boundary** actually turns, and the plan should record that input beside
  the decision. Worked example: `D-8` form 2 is "explicit argument, else `ExtensionAttribute` ctor
  default", so the only discriminating input is an `ExtensionAttribute`-derived attribute with an explicit
  `ServerSideOnly = false` — and the fixture named for that case used `Sql.Function`, which is not one.
  The cheap enforcement is the mutation check this round used on all three: break the product, watch only
  the intended fixture go red.
- `<GAP-02 × 2>` → **applied** to `work-plan.md` on 2026-09-07, promoting round 2's recommendation from
  prose to a requirement in `P11` semantics,
  because it was recorded and then not applied by the very next amendment: an amendment that
  answers a review finding must list the **input classes the finding's text names** and carry a `TO-n` per
  class. `A-11` wrote "an interface member declared in metadata yields no location and the fix declines"
  and shipped no fixture for it; the sentence was the specification and nothing checked it.
- `<GAP-03 × 1>` → `work-plan.md`'s `P5` semantics: a failure-mode line that makes a **checkable claim
  about the language or a framework** is a `P4` row, not prose — `AttributeTargets` and
  attribute-target defaults are one compile away, and left in prose the claim propagates into `P10`,
  into a comment at the site, and into user-facing docs where a reader who tests it finds it wrong.
  **Applied** to `work-plan.md` on 2026-09-07.

  *Corrected after this ledger was first written:* the entry originally paired the above with "and a
  `P7` registration-surface row must list the wiki pages by path … round 1's GAP-01 recommendation,
  still unapplied". That second half **was already applied** — `work-plan.md`'s *A registration-surface
  row lists paths, one per hit* requires naming the surfaces a repo-wide grep structurally cannot
  reach, wiki pages included, and cites this PR's round 1 as its source. So MIN004 is not a missing
  `P7` rule: this plan's `P7` was written **before** that rule landed, which makes it round 2's
  authoring-time recurrence in a third guise and prescribes the same fix — re-walk a long-lived plan
  against rules added since. The ledger's own lesson, applied to itself: `Grep` the destination before
  asserting a recommendation went unapplied.

### Continuity

**Round 2's MAJ recommendation went unapplied and produced two same-shape defects — the strongest possible
form of the recurrence.** Round 1's `SUG001` was fixed for one remedy branch; round 2's MAJ001 was that
unswept sibling; round 3's MAJ001 and MIN006 are both inside round 2's *fix* for it. Three consecutive
rounds, one relationship (the implemented-interface walk), each round fixing the instance in front of it
without sweeping the admitted element. Round 2 wrote the correct prescription verbatim; `A-11` was
authored without it.

**The enumerated-set cluster recurs a third time, mutated into a harder-to-see form.** Rounds 1 and 2:
named element, no fixture. Round 3: named element, fixture present, fixture cannot fail. Round 2's
`work-plan.md` rule ("expand an obligation that names a set to one named fixture per element") is
*satisfied* by all three of this round's cases, which is why it did not help — the gap moved from
existence to discriminating power. Per round 2's own lesson, the destination file was grepped before
concluding this: the rule is there and it is not the missing one.

**`G-01`'s run-total recording is now unremedied across three rounds** and has masked a coverage gap in
every one. It remains the single cheapest change available to this plan.

**One round-2 recommendation *was* applied and did work.** Re-walking an existing plan's `P8`/`P4` against
rules added since is what surfaced `MIN003` — `D-4` had no `TO-n` at all, which the re-walk makes visible
and a diff-driven review does not.
