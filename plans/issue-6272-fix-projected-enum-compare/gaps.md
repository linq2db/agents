# Gap ledger: issue-6272-fix-projected-enum-compare

## Round 1 — reviewed HEAD 466207b6a

- **MAJ001** (direct cast with constant returned wrong rows, `ExpressionBuildVisitor.cs:2861`) — GAP-03 — U-4 and P7 mapped E-1's consumers by searching the flag, so `ConvertEnumConversion` got no row: it never reads the flag, keys on the raw `left.NodeType is Convert`, and for this cast runs only once E-1 lets the operand build; second class GAP-05, since no TO put the cast and the constant in one predicate until TO-19 and TO-20 — — — preventable: yes
- **MAJ002** (`DistinctBy` test without its sibling's gate, `EnumMappingTests.cs:2602`) — GAP-07 — TO-16 had no sibling comparison; `testing.md:540` requires a new test to inherit a same-mechanism sibling's measured gate or run the provider, but the step-4 embed reduces that to gates a TO adds, and the critic vector compares only siblings in the same fixture — — — preventable: yes
- **MIN002** (union tests on bare `[DataSources]`, `EnumMappingTests.cs:2513`) — GAP-07 — same rule on TO-13 and TO-14; the code was correct, and the only gap was the measurement A-1 later made on Access.Ace.OleDb and Firebird.2.5 — — — preventable: yes
- **NIT001** (field alignment, `ParametersContext.cs:402`) — GAP-10 — the alignment column exists only once both field declarations are typed — — — preventable: no

## Aggregate

GAP-07 is the most frequent class (2 of 4). GAP-03 (1 of 4) matters most, because it is the only wrong-results finding: the map was keyed on the flag name, and the critic searched by the same key.

Unestablished: whether step 4 embedded *A narrowed provider set is a claim* (if it was, the two GAP-07 rows become GAP-06), and whether the scouts had the rule at `work-plan/SKILL.md:107`, which landed about three hours before the plan commit.

## Recommended durable fixes

- GAP-07 × 2 → `skills/work-plan/SKILL.md:71` (step 4 embed): add that a new bare `[DataSources]` test inherits a same-mechanism sibling's measured gates or runs those providers.
- GAP-07 × 2 → `agents/plan-critic.md:55`: widen "same-shape tests in that fixture" to the home fixture of each operator or load strategy the test exercises, and state that a bare `[DataSources]` is in scope.
- GAP-03 × 1 → `skills/work-plan/SKILL.md:107` (reword): extend the trigger to branches that key on the raw input expression and run once the operand builds, and require a flag-gated change to sweep the consuming methods as well as the flag's setters and readers.

## Round 2 — reviewed HEAD 2f77524bd

- **SUG001** (E-2's widened arm, `ParametersContext.cs:290`, fires for any two different enums; unpinned for the unregistered case) — GAP-05 — D-2's failure mode named the case, but P8 never turned it into a TO; TO-24's `DtoGender` has the same MapValues as `Gender` and covers a constant only, so it cannot go red. Second class GAP-02: the consequence was recorded in prose and never measured; `DirectCastToEnumWithOtherMapValuesEqualParameter` shows master returning 0 rows instead of 1 (`CAST([p].[Gender] AS NVarChar(255)) = 'Female'`), so E-2 also fixes a bug outside the feature — — — preventable: yes

### Aggregate

1 finding: GAP-05, second class GAP-02. A D-block failure mode stated in prose with no discriminating TO, next to a sibling TO whose fixture coincides with the intended case.

### Recommended durable fix

- GAP-05 → `docs/work-plan.md` P8 semantics and an `agents/plan-critic.md` attack vector: every "failure mode of the choice" line maps to a TO whose fixture discriminates the failing input from the intended one (measured red/green), or says why none is needed; the critic checks that a sibling TO's fixture does not coincide with the intended case.

### Continuity with round 1

- GAP-05 recurs: round 1's MAJ001 also lacked an obligation next to a TO that existed but did not discriminate (closed by TO-19/TO-20).
- GAP-03, GAP-07 and GAP-10 do not recur.

## Round 3 — reviewed HEAD 6d69aeb09

- **MAJ003** (TO-37 #6298 gate red on strict providers, `EnumMappingTests.cs:2918`) — GAP-02 — A-4 pinned TO-35..TO-38 on bare `[DataSources]` with one declared failure from a SQLite.MS-only measurement, while G-01 already recorded the head SQL as `CAST([Gender] AS INTEGER) = @gender` with `'F'`, an int-vs-string compare a strict server rejects; second class GAP-08: G-01 recorded `pass` with "left to `test-all`" in its sub-bullets, which `work-plan.ps1` validates only on the head line and one spelling; no CI ran TO-37 (6d69aeb09 never built: Linux legs ran 89c474425, Windows restore failed without #6295) — G-01 — preventable: yes

### Aggregate

1 finding, GAP-02 (second class GAP-08): a known-issue gate claimed for every provider from one provider's measurement, against the plan's own recorded SQL and with a strict-provider container already in use.

### Recommended durable fix

- GAP-02 → `docs/testing.md` *Gating an assertion failure* (embedded by `skills/work-plan/SKILL.md:73`): an unscoped `[ActiveIssue]` on bare `[DataSources]` is measured on one strictly typed provider and one file DB before pinning; a recorded mismatched-type compare (`CAST(col AS Int) = 'F'`) predicts a server error, so scope the gate or use `no-declaration:`.
- GAP-08 → `scripts/work-plan.ps1` -Validate: fold G-01 sub-bullets into the "left to CI" check and match "left to `test-all`" / "pending"; warn on a bare-`[DataSources]` P8 row measured on SQLite only with no reason.

### Continuity with rounds 1-2

- GAP-02 recurs from round 2's second class (SUG001), in the same #6298 area: a cross-provider claim stated from one provider.
- Round 1's GAP-07 fix (sibling gate inheritance) landed but does not cover a new gate's reach.
- Round 2's recommended P8/critic rule ("sibling fixture does not coincide") was not found in `docs/work-plan.md` or `agents/plan-critic.md`; unverified whether it landed under other wording.

## Round 4 — reviewed HEAD 47905b5b9

- **MAJ001** (E-9 folds an inlined parameter against enum literals to `1 = 0`) — GAP-03 — P7's E-9 row counts `TryEvaluateNoParameters` callers, not the operands and partners that reach `TryEvaluateAsProviderValue`'s `result is Enum` key: no row for an unregistered enum, an inlined parameter, or an enum `SqlValue` literal kept by `SetValueToSqlConverter`; TO-27..TO-33 all use the registered `ApiGender`. Second class GAP-02: P10 recorded only the opposite direction, unmeasured. Critic round 3 (delta on A-2) existed; the partner census (`plan-critic.md:154-155`) was not applied to E-9 — — — preventable: yes
- **MIN001** (E-3 matches `p.Gender.Equals((object)ApiGender.Female)` on the plain column) — GAP-02 — D-3 assumed its `IsDefaultMappedTo` gate selects only the projected cast and never checked that the uncast column satisfies it; TO-18's twin with `ApiGender` would have settled it. Second class GAP-05: TO-18 pins only the unrelated-enum half. The gate vector (`plan-critic.md:136`) was applied only to the unrelated-enum direction — — — preventable: yes
- **SUG101** (TO-30 never sends a null `ApiGender?`) — GAP-05 — TO-30 names Nullable but has no null value as a discriminating input, so E-8's nullable null path had no obligation that could go red — — — preventable: yes
- **REG001** (E-8 converts every column-less parameter; a selected `ApiGender` parameter sends `'F'` and cannot read it back; raw SQL `{gender}` goes from 1 to `'F'`) — GAP-03 — P7's E-8 row counts registrations, not consumers of the no-descriptor branch; projection, raw SQL and read-back have no row. E-8 entered through A-2 with no D-n, so no reach line existed; critic vectors `plan-critic.md:145,152,157` (substitute value per consumer, naming `Sql.AsSql`) were not applied in round 3 — — — preventable: yes

### Aggregate

Three of four findings (MAJ001, SUG101, REG001) sit in E-8/E-9, added by A-2 with "D-1..D-3 stand" and no new D-n, so no failure-mode or reach line existed for the critic vectors to attack; P7 filled the gap with symbol-keyed rows. Dominant class GAP-03 (2 of 4), then GAP-02 and GAP-05 (1 each). The rule "an amendment that adds an edit-point with a new predicate must add its own D-n" exists nowhere in the corpus; the #5932 ledger recommended it (`plans/issue-5932-mark-optional-row-values/gaps.md:259`).

### Recommended durable fixes

- GAP-03 ×2, GAP-05 ×1 → `docs/work-plan.md` P11 semantics plus `work-plan.ps1 -Action validate`: an `A-n` adding an `E-n` with a predicate outside every existing D-n's scope must carry a new D-n (chosen / failure mode / reach); "D-n stand" is rejected when the `A-n` cites a new `E-n`.
- GAP-03 ×2 → `skills/work-plan/SKILL.md:101`: widen the per-admitted-kind trigger to any `E-n` predicate keyed on a type or an absence (`result is Enum`, no column descriptor), owing one P7 row per consumer (comparison, projection / `Sql.AsSql`, raw SQL, read-back) and per partner (column, parameter inlined and not, literal), registered and unregistered.
- GAP-02 ×1 → `agents/plan-critic.md:136`: a gate keyed on a registration is also satisfied by the uncast form of the intended subject; demand a twin TO-n in that direction.

### Continuity with rounds 1-3

- GAP-03 recurs from round 1 MAJ001: P7 counted a symbol (flag name, then callers, then registrations) rather than the population reaching the branch.
- GAP-05 recurs from round 2 SUG001: a D-n failure mode with no discriminating TO-n (D-3 now, D-2 then); `plan-critic.md:131` covers only inputs a failure-mode line names, and MIN001's input was never named.
- GAP-02 recurs from rounds 2-3: an outcome stated in P10 or a D-n without a probe.
- Round 3's GAP-02 fix (`docs/testing.md`, 4a02833) landed; no round-4 finding falls in its scope.
- Correction to A-2: critic round 3 was a delta on A-2; A-2's "No critic round on this amendment" is stale.

## Round 5 — reviewed HEAD 8025303f4

- **MAJ001** (mirrored and projected inline-array `Contains` sent `@api = 1`, `ExpressionBuildVisitor.cs:5716` `ConvertInPredicate`) — GAP-03 — D-4's reach line and P7's `ConvertInPredicate` NewArrayInit row (plan.md:116) listed IN shapes only where the searched value is the cast. `ConvertCompareExpression` was given both operand orders (`TryCompareInRegisteredEnum` with the arguments swapped, the TO-25 precedent from critic round 2), but the IN arm was not. P7's column-less-consumer row (:117) said that removing E-8 left every column-less consumer on master's ordinal. It did not record that master's `ConvertInPredicate` passes a descriptor from the value to the items only, so a value searched among E-1 pass-through items gets no descriptor. The projected form has been latent since U-4/P7's `Contains` row (TO-7 and TO-26 search the cast). E-8 hid it in A-2..A-5, and A-6 exposed it again. Second class GAP-05: TO-7, TO-26, TO-54 and TO-55 all search the cast — — — preventable: yes
- **MIN001** (`Sql.Constant` / `Sql.Parameter` lost inside `CastRegisteredEnum`, `ExpressionBuildVisitor.cs:5396`) — GAP-03 — P7's "E-14's partners" row (plan.md:118) lists the partner expressions (column cast, conditional/CASE, nullable cast, IN list, converter) but not the spellings of the client value a wrapping rewrite has to preserve. `ExpressionHelpers.MoveValueMarkerOutside` already existed on master, with callers at `DateFunctionsTranslatorBase.cs:781,1046`, so a search for how other rewrites wrap a client value would have found the convention. SKILL.md:103's partner list ("parameter inlined and not, literal") landed after A-6 and does not name value markers — — — preventable: partly
- **MIN002** (test comments claim master behaviour on DB2 / Jet, measured only on Firebird.5 / ACE) — GAP-10 — The DB2 and Jet failures first appeared in `test-all` 25700 on `fee066169`, after A-6. Against the A-6 plan the comment wording is a prose finding with no block to carry it. Measured against A-7 it would be GAP-06, since A-7 embeds *A narrowed provider set is a claim*. Critic round 13 had already named these comments as review-round-5 items, so the review re-found a known item rather than a miss — — — preventable: no
- **MIN003** (E-11 checked a `CanBeConstant` value once at build time and a cache hit skipped the check, `ExpressionBuildVisitor.cs:4270`) — GAP-02 — E-11 (plan.md:93) asserted that "a constant is checked once at build time" is safe. The plan already held the contrary fact: D-4's rejected line (critic round 8, TO-52) says a value read off a constant instance is not in the cache key. P4 had no row on how E-11's build-time `EvaluateExpression` reaches the cache key, which `work-plan/SKILL.md:143` has required since 2026-10-11. Critic round 12 raised exactly this case, and the answer was TO-75 "green". Second class GAP-05: TO-75's two queries had different shapes, so it could not hit the cache, although the plan already had the cache-hit pin idiom in TO-68 (`[QueryCacheTest]`, miss count) — — — preventable: yes
- **SUG001** (conversion message duplicated in `ExpressionBuildVisitor.ThrowIfOtherEnum` and `ConvertBuilder.cs:30`) — GAP-07 — The rule exists at `agents/code-reviewer.md:262` (new message literals go in `ErrorHelper`; a firm recommendation when the same literal appears at more than one site). Step 4 (`work-plan/SKILL.md:67-77`) embeds only `testing.md`, cross-cutting-core and analyzer sections, never review-rubric code conventions. A-6's `conventions:` line names *Test layout* only. E-11's own text ("fails as an unconvertible value does") points at the copied literal — — — preventable: yes
- **SUG002** (`ReconcileEnumValues`' two-enum branch, `SqlExpressionOptimizerVisitor.cs:189`, had no reaching test after E-14) — GAP-05 — The branch's only obligations, TO-50 and TO-51 (plan.md:170), have the proof "characterization (critic round 7 traced the red; not run before the fix)". `work-plan.md:154` says a characterization proves no new behaviour, so the branch never had an obligation that could go red. E-14 landed in the same round, upstream of it, and rerouted both inputs, which went unnoticed because no mutation was recorded in G-01. A-8's mutation leaves TO-50 green and only TO-78 red — — — preventable: yes
- **SUG003** (E-9 also fixes an unregistered enum, `(p.ID > 2 ? Gender.Female : Gender.Male) == gender` inlined, 0 rows on master) — GAP-03 — P7's E-9 row (plan.md:113) still counts `TryEvaluateNoParameters` callers. Round 4's MAJ001 named "no row for an unregistered enum" against this exact row. A-6 revised E-9 but its `re-derives:` line does not list that row, so the unregistered partner (and its release-note beneficiary) never got a row or a TO-n. Same shape as round 2's SUG001 (E-2 fixing a bug outside the feature) — — — preventable: yes
- **NIT001** (one-line chains in `ShuffledRegisteredEnumComparesAsNumericCast`, `EnumMappingTests.cs:3343`) — GAP-08 — A-6's `conventions:` line ("swept … no hits") was recorded before the round-12 tests (`36afe9926`). The round-12 G-01 row (plan.md:241) has no sweep count, although `work-plan/SKILL.md:318` and `definition-of-done.md:11` require one on the implemented tree. When A-7 did run the sweep it found chains 8 / nestedChains 1 and deferred them as "review items" instead of fixing them — G-01 — preventable: yes
- **NIT002** (one-line chains in `EqualsInstanceValueCheckedPerInstance`, `EnumMappingTests.cs:3430`) — GAP-08 — The same skipped implemented-tree sweep after the round-12 tests, and the same A-7 deferral of recorded hits — G-01 — preventable: yes
- **NIT003** (stale TO-50 / TO-51 comments after E-14, `EnumMappingTests.cs:2945`, `:2981`) — GAP-05 — Same root as SUG002. The comments describe the E-9 two-enum path that E-14 stopped these tests from reaching, and nothing showed it because TO-50/TO-51 were never red-proved. Second class GAP-10 for the wording itself — — — preventable: partly

### Aggregate

Of the 10 findings, GAP-03 has 3 (MAJ001, MIN001, SUG003), GAP-05 and GAP-08 have 2 each, and GAP-02, GAP-07 and GAP-10 have 1 each. All three GAP-03 findings are the same population miss on E-14 and E-9. P7 counted the partners of a rewrite but not which side of a two-sided consumer the value sits on (MAJ001), how the value is spelled (MIN001), or the unregistered enum the round-4 ledger had already named for row 113 (SUG003). The single most useful change is to extend the population rule at `work-plan/SKILL.md:103` to cover operand position and value spelling, and to require any amendment that touches an `E-n` to re-derive that `E-n`'s existing P7 row. That would have prevented MAJ001, MIN001 and SUG003, and probably MIN003 too, because the cache-key question is a property of the value spelling.

### Recommended durable fixes

- GAP-03 × 3 → `skills/work-plan/SKILL.md:103` (scout brief) — add to the partner census (1) operand position for every two-sided consumer: binary left/right, IN searched value vs list item (master's `ConvertInPredicate` passes a descriptor from the value to the items only), `Equals` receiver vs argument; and (2) value spellings a wrapping rewrite must preserve (`Sql.Constant`, `Sql.Parameter`, inlined; cite `ExpressionHelpers.MoveValueMarkerOutside`). Also state that an `A-n` revising an `E-n` re-derives that `E-n`'s existing P7 row against the census.
- GAP-05 × 2 → `docs/work-plan.md` P8 proof modes (next to :153-158) — a new branch whose only obligation is `characterization` has no obligation and needs a `control` with a G-01 mutation record. An amendment that adds an `E-n` upstream of an existing branch (E-14 ahead of E-9) re-runs that branch's mutation, and the branch's TO comments are re-derived with it.
- GAP-08 × 2 → `scripts/work-plan.ps1 -Action validate` plus `definition-of-done.md:11` — fail G-01 when its newest sweep count predates the newest commit or `P12` round that adds `TO-n` tests, and treat sweep hits recorded as "review items" as keeping G-01 open rather than satisfied.

### Continuity with rounds 1-4

- GAP-03 recurs (rounds 1, 4, 5): P7 counts a symbol or one spelling (flag name, callers, registrations, and now one operand order) instead of the population reaching the branch. Round 4's fix landed at `SKILL.md:103` (`3c4f232`, 2026-11-15 18:51), 21 minutes after the A-6 plan commit (`20adef8`, 18:30). No amendment before this round applied it to this plan, and A-8's `re-derives:` still omits the E-9 row (plan.md:113).
- GAP-05 recurs (rounds 1, 2, 4, 5): an obligation that exists but cannot go red. This round it appears twice: a `characterization` label on a new branch (TO-50/TO-51), and a cache-sensitive TO whose two queries never hit the cache (TO-75, MIN003's second class).
- GAP-02 recurs (rounds 2, 3, 4, 5): the plan asserted an outcome it held contrary evidence for (D-4's cache-key line against E-11). The governing rule (`SKILL.md:143`, `plan-critic.md:117`) predates the plan.
- GAP-08 recurs from round 3's second class: a gate stamped at a head earlier than the code it is supposed to cover.
- GAP-07 recurs from round 1 with a different rule: round 1 was a `testing.md` gate-inheritance rule (since embedded at `SKILL.md:73`); this round it is the `code-reviewer.md:262` `ErrorHelper` rubric rule, which step 4 does not embed.
- Round 4's P11 rule ("an `A-n` adding an `E-n` carries its own `D-n`") landed at `docs/work-plan.md:290`. D-4 exists for E-14, and no round-5 finding comes from a missing D-n.
- Not attributed: the reverted `=`/`<>` limit on E-7/E-9's provider-value retry (recorded in P10) and the Firebird/DB2 CASE-of-two-parameters gap (#6335, pre-existing). Neither is a finding.
