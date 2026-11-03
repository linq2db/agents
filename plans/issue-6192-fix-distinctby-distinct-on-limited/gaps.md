# Gap ledger: issue-6192-fix-distinctby-distinct-on-limited

## Round 1 — reviewed HEAD `46c4dbcd76a326ea231b13f7621b5f5c7e973e5b`

Review of PR #6197 (2026-10-30). Finding IDs are the ones posted on the PR (comment 6535347204). The passes' window IDs were SUG201–SUG203, and the NIT was the walk's item 5. All four were fixed by test-only commits 3460208e6, 7ac826f91, bbc15db21 and b7e89e19f.

### Attribution

- **SUG001** — GAP-05 — P8 TO-22 (`Confirm_Union_RootAfterGroupByDropsNonKeyOrdering`, an A-2 critic fold-in) was specified as asserting the rows "ignoring order" over `GenerateHierarchy`. There, Name order equals key order, so the seed had no row that could separate "non-key ordering dropped" from "non-key ordering leaked". Its sibling TO-21 states its fallback answer ("key-column fallback would give 1, 2, 3"), and TO-17 seeds "out of PK order"; TO-22 does neither. P9 G-01 then recorded `m12b` green on PG16 and SQLite.MS and relabelled the row "characterization elsewhere" instead of reseeding it. — G-01 — preventable: yes
  - The rules that would have forced the reseed exist and were not applied: `work-plan.md:149` ("a missing row is a seed change") and `work-plan.md:191` (a cell named for a property must separate it "from every alternative the name rules out"). This is not GAP-08: the gate ran and showed the mutant surviving, and the plan accepted that as a different proof mode.
- **SUG002** — GAP-05 — P8 has no CteUnion obligation for D-5's no-wrap arm (`if (!reordered)` → `RegisterOrderBy`). TO-26 (`OrderByDescending(Id).DistinctBy(Name)`) takes only the reordered arm. The P7 A-3 consumer row (plan.md:177) says "the stacked `DistinctBy` and the CteUnion root are asserted (TO-25, TO-26, TO-28)" without splitting by arm. The plan split TO-27 by arm for the stacked-`DistinctBy` consumer (`m18-no-publish`), but never applied the same split to the CteUnion consumer. — G-09 — preventable: yes
  - Second class: GAP-08. The two-arm D-5 is the user's second decision after round A-3c, and it was rewritten in place. P12 (plan.md:298) says it would be "re-attacked by the next delta round", and no such round exists. P9 G-09 still records only the 2026-10-28 pass, although P11 A-3's `re-derives:` line requires G-05 … G-09 to be re-run on the A-3 tree.
  - The rewrite got no `A-n`, so the `work-plan.md:259-264` rule ("an amendment that replaces a `D-n` is a new plan pass": re-derive P7/P8, re-run the critic) never fired. `-Validate` could not see it either, because it keys on the `A-n` text.
- **SUG003** — GAP-05 — D-5's own failure-mode line (plan.md:111 and :122) names the permuted composite key `OrderBy(b).ThenBy(a).DistinctBy(new { a, b })` and says "there the wrapper is required". But no `TO-n` cites that input, and P10 has no unprobed entry for it, so nothing pinned that the reorder check is order-sensitive. — G-09 — preventable: yes
  - `work-plan.md:171` requires both halves: "write the separating input into the decision, and have the `TO-n` cite it". The first half was done and the second was not.
  - The critic saw this text: the superseded D-5 carried it into rounds A-3 and A-3b, and A-3b "confirmed … the composite-key decline of round A-3 is right". `plan-critic.md:118` asks whether a failure mode "name[s] a problem the plan then ignores?", but no obligation came of it. Second class: GAP-08, the same missing round on the final D-5 as in SUG002.
- **NIT001** — GAP-10 — prose in the test. P8 TO-28 and P9 correctly record it as "characterization" with no mutation. The comment written while folding round A-3c's nit ("TO-28's reason line misstated the code") upgraded that to "pins". When TO-28 was authored there was no `IgnoreOrderBy` early return (it came in as an A-3c fold-in, and `OrderByBuilder.cs:51` already returned the sequence untouched) and no rewritten comment text to check. — - — preventable: no
  - Weak link only: the fourth shape of `work-plan.md:272` (an added early return re-derives every `TO-n` whose input takes that branch and re-runs its mutations) would have shown that no mutation separates that return. That might have discouraged the word "pins", but no plan block decides comment wording.

### Aggregate

Three of the four findings are GAP-05. Each is an obligation whose seed or arm could not discriminate something the plan itself had named:
- an order-named test asserting without order over an order-neutral seed;
- a consumer covered on only one of two arms;
- a failure-mode input with no `TO-n`.

The governing rules already exist (`work-plan.md:149`, `:171`, `:191`; `plan-critic.md:75`, `:118`), so the miss is enforcement, not missing doctrine. SUG002 and SUG003 share one cause: the final two-arm D-5 replaced the mechanism without a logged `A-n`, so P8 was never re-derived for it, no critic round attacked it, and G-09 was never re-run.

### Recommended durable fixes (route to `/session-reflect` → plan-rule; not applied)

- GAP-05 × 2 (SUG002, SUG003; the GAP-08 notes) → `work-plan.ps1 -Action validate -Done` plus `work-plan.md` P11 near :259.
  - Fail when the last P12 entry is a user decision that rewrites a `D-n` ("re-attacked by the next delta round", "Not yet attacked") and no later `A-n` or critic round exists.
  - Require a backticked reviewed sha in every round header. The fold-in check at `work-plan.ps1:664` takes the last backticked sha in file order, which here is the oldest round's `7fd98eda5e`. The A-3 rounds write "base e9eb46ce88" without backticks and A-3c names no commit, so the post-round commit listing was measured from master.
- GAP-05 × 2 (SUG002, SUG003) → `plan-critic.md`: sharpen the existing question at :118 rather than adding a new vector.
  - For every code-spanned input that a `D-n` failure-mode line names as changing behaviour, demand a `TO-n` that cites it, or a P10 entry.
  - For a `D-n` with arms, demand one obligation per arm × P7 consumer row the decision publishes to, each reddened by that arm's mutation. `m18` existed and reached no CteUnion test.
- GAP-05 × 1 (SUG001) → `work-plan.md` P8/P9, next to :149 and :191.
  - A recorded mutation that stays green on a provider inside the `TO-n`'s scope is a seed change, never a relabel to "characterization elsewhere".
  - A cell named for an ordering property needs a seed whose order differs from the fallback (key or PK) order, plus an in-order assertion.

## Round 2 — reviewed HEAD `a33ab67fa7ab92e81ce3c086326e5b5586317cda`

Review of PR #6197 (2026-11-02). The round delta is ef6b80a62 (P11 A-4 … A-6) plus a33ab67fa (test gating, no P11 entry, no finding against it). Both findings were fixed by 98a9e4794 and d33510917; nothing was posted as a review, and the round's status went to the PR as comment 6591453726. The reviewer's out-of-scope item ("outer-correlated grouping key never covered") was dropped after a probe (LINQ rows at HEAD) and is not attributed.

### Attribution

- **MAJ002** (empty capture → recoverable `Error` in a projection) — GAP-02 — SC-4 (plan.md:34) and the P3 A-4 delta (plan.md:61) promise `Error_DistinctByRequiresOrderBy` "on every provider", which assumes `BuildSequenceResult.Error` at `DistinctByBuilder.cs:116` is terminal; P4 has no row asking that. The plan held the counter-evidence twice: U-18 (plan.md:81) says the aggregate fallback consumes this error inside `Select(p => ….Count())` ("untraced (critic round A-4d)"), and P11 A-5 (plan.md:362) measured the correlated subquery falling back to eager loading for `m25`; both were closed on the test side (TO-41 asserts `DISTINCT ON`) and never turned back on the SC — — — preventable: yes
  - The governing rule exists: `work-plan.md:86` (each stage of a two-stage chain gets its own row: emitting the error, then how the projection consumes it). U-18 is marked `resolved-by probe` although its second stage is explicitly untraced.
  - Contributing: session-reflect 3187d00 turned the `m25` observation into `evidence-discipline.md:44` as a test-visibility rule. That rule says the fallback "returns the same rows", which MAJ002 disproves: the client-side `DistinctBy` runs over an unordered detail query, and with an aggregate on top the query hits the #5787 `AggregateExecute` fallback.
- **MIN003** (`SqlConcatExpression` missing from the closed composite list) — GAP-03 — `IsBuiltFromKeys` / `IsOperand` is a type-keyed helper keyed on `QueryElementType`, and no P7 row or P11 A-6 `class:` line listed its domain; D-6 (plan.md:149) specified a kind-independent leaf test, A-6 found the code narrower and widened it by instance (the kinds the critic named), and the A-6 critic round (plan.md:385-387) checked only admitted kinds, never rejected ones — — — preventable: yes
  - Second class: GAP-08 in shape. The rule that fits exactly, `plan-critic.md:99` ("a closed list … owes a census of what it now rejects", naming string functions), was written from this plan's A-6 in 3187d00 at 2026-11-01 00:42, twelve minutes after ef6b80a62 (00:30). No critic round re-attacked the list with it before review.

### Aggregate

The two findings sit in two classes (GAP-02, GAP-03), neither GAP-10. In both, the plan already held the information — U-18's "untraced" note plus the A-5 `m25` fallback for MAJ002, A-6's own lesson for MIN003 — and the evidence was routed to a corpus rule or a test fix instead of back to the decision it undermined. The one change that would have prevented both: when a round's lesson becomes a corpus rule, re-apply it to the live plan (a P11 entry and a re-attack) before the next push.

### Recommended durable fixes (route to `/session-reflect` → plan-rule; not applied)

- GAP-02 × 1 + GAP-03 × 1 → `work-plan.md` P11 semantics (near :259-272): a rule session-reflect derives from the live plan, or an observation recorded as "untraced" / "falls back", triggers a P11 entry that re-checks every SC / `D-n` it touches; widening a type-keyed closed list carries a `class:` line with the domain census (the `QueryElementType` members a LINQ shape can produce in that position) and a master probe per rejected kind.
- GAP-02 × 1 → `evidence-discipline.md:44`: correct "returns the same rows" — the eager-load and aggregate fallbacks can change semantics; an SC promising a `BuildSequenceResult.Error` needs a probe in a correlated projection, scalar and aggregate.
- GAP-03 × 1 → the step-5 scout brief in `work-plan/SKILL.md`: for an `is A or B …` / `case QueryElementType.` helper the plan adds or widens, P7 lists the enum or implementor domain with admitted / rejected per member (the producer-side twin of `plan-critic.md:37` and `:99`, which fire only when a critic round runs).

### Continuity with Round 1

- Round 1's dominant class, GAP-05, does not recur as a primary class.
- Its underlying mechanism does: evidence the plan names but never turns into an obligation — round 1's SUG003 failure-mode input with no `TO-n`; here U-18's untraced fallback and the A-5 `m25` note (MAJ002).
- Round 1's GAP-08 note (a decision changed without a re-attack round) recurs in shape in MIN003: the `plan-critic.md:99` census rule landed after the A-6 round and was never run against A-6.
- Round 1's `plan-critic.md:118` recommendation landed (now `plan-critic.md:125`) and is not re-proposed.

## Round 3 — reviewed HEAD `128f2bf82cbcf62000dbe9784ecfd1db8a5a91c3`

Review of PR #6197 (2026-11-03). The round delta is 98a9e4794 … 128f2bf82 (P11 A-7 D-8 and the `SqlConcat` admission, A-8 six kinds, A-9 `SqlInterval` and TO-69). igor-tkachev's review 5754176813 points 1–3 are folded in as MAJ003 … MAJ005; every finding is fixed on the branch, none posted. Measured locally: HEAD 20 / 27 failed, master 25 / 27 passed (SQLite.MS / DuckDB / SqlServer.2022, each with `.LinqService`).

### Attribution

- **MAJ003** (D-8 throws for every empty capture, `DistinctByBuilder.cs:116-119`) — GAP-02 — D-8 treats "capture emptied by the GroupBy pruning" (U-20 / MAJ002) and "source never ordered" as one input; its failure-mode line's "measured: none in `DistinctByMethodTests` + `EagerLoadingStrategyUnionTests`" is absence from a sweep that has no never-ordered `DistinctBy` in a correlated subquery or eager-loaded collection; no `U-n` asked what master does for a never-ordered input — — — preventable: yes
  - Contributing: round 2's durable fix `architecture.md` → *A `BuildSequenceResult.Error` is recoverable inside a projection* (32ae8ff) says such a builder "must therefore throw", with no carve-out for an input whose fallback loses nothing.
- **MAJ004** (key-function ordering + aggregate-reading DistinctBy key on ROW_NUMBER → `no such column: e.Count_1`, `GroupByBuilder.cs:250-253`) — GAP-02 — P11 A-5 attributed the SQLite failure to P10 L-7 as pre-existing and reshaped TO-35 to `(x.Key ?? 0) % 2` without a master run of that shape, while TO-35's own P8 row still specified `DistinctBy(x => x.Count)` and recorded master green on SQLite.MS; L-7 was measured on a different (post-GroupBy) shape — G-01 — preventable: yes
  - The governing rules existed: `bug-investigation.md:41` (confirm "pre-existing" by running the base) and `:501` (never narrow a test's input to avoid one failure). L-7's "follow-up issues proposed" were never filed, so the entry became a place to park an unrelated failure.
- **MAJ005** (`IsPure` conjunct rejects translator-built `SqlExpression`, `GroupByBuilder.cs:403-405`) — GAP-03 — the P7 closed-list row, the A-8 residual line and both critic censuses list the domain by `QueryElementType` only; `SqlParameterizedExpressionBase` is an admitted kind there, so the census cannot see the second rejection axis inside it (`IsPure`, which `factory.Expression` / `NotNullExpression` nodes with `SqlFlags.None` fail); the conjunct, added in ef6b80a62, is narrower than D-6's own text (only `IsAggregate` / `IsWindowFunction`) — — — preventable: yes
  - Second class GAP-02: nobody checked the premise that translator output is flagged pure. Doing the A-8 residual census as written, by element kind, would still have marked these nodes admitted.
- **MIN004** (`…OrderedByDateDifferenceOfKey`, TO-65, `DistinctByMethodTests.cs:1282-1283`) — GAP-05 — ascending ordering monotone in the key with a constant partition `Year > 0`; `m39-no-a8-kinds` reddens it only through the throw, the case `work-plan.md:201` says leaves the value arm unwitnessed; no `separates:` line — G-01 — preventable: yes
  - Critic round A-8 found the class on TO-63 / TO-64; A-9 flipped those two and did not sweep their four siblings under the same mutation (`plan-critic.md:34`).
- **MIN005** (`…DateDifferencePartOfKey`, TO-66, `DistinctByMethodTests.cs:1300-1301`) — GAP-05 — same row and miss as MIN004 — G-01 — preventable: yes
- **MIN006** (`…ComparisonOfKey`, TO-54, `DistinctByMethodTests.cs:1126-1127`) — GAP-05 — A-6 specified `OrderBy(p => p.ParentID > 2).ThenByDescending(ParentID)`, which picks odd 1 / even 2 = key order; `m35-no-predicate-kinds` reddens it only through the throw; `work-plan.md:159` (seed differs from the fallback order) and `:201` (`separates:` row) were in place and not applied — G-01 — preventable: yes
- **Cosmetic** (ROW_NUMBER projects a rebuilt key ordering twice, `as RowNumber` / `as c1`; DISTINCT ON `…ConcatOfKey` repeats `Key_1 || 'x' DESC`) — GAP-08 — A-4's re-derives line required G-02 on the A-4 tree; P9 recorded "G-02 not re-run … the CI baselines PR is the record" and no G-02 entry exists for A-4 … A-9 — G-02 — preventable: partly

### Aggregate

Seven findings in four classes: GAP-05 × 3, GAP-02 × 2, GAP-03 × 1, GAP-08 × 1; no GAP-10. The three MINs are one family (ordering cells whose mutation reddens them only by the throw) whose rules already exist — enforcement, not doctrine. MAJ003 and MAJ005 share a shape: a rejecting or throwing predicate whose input domain was split along one axis only (empty capture without asking how it became empty; element kind without asking what each admitted arm's extra conditions reject). MAJ004 repeats round 2's mechanism: the plan held the master-green measurement and still filed the failure as pre-existing. The change that would have prevented the most severe findings: census every population that reaches a changed rejection or throw, with a master probe each, not only node kinds.

### Recommended durable fixes (route to `/session-reflect` → plan-rule; not applied)

- GAP-05 × 3 → `plan-critic.md:34` sibling sweep + `work-plan.md:201`: a fold-in that fixes one non-separating cell re-checks every `TO-n` reddened by the same mutation for a `separates:` row; a mutation that reddens only through `Error_DistinctByRequiresOrderBy` does not count for a cell named `OrderedBy…`.
- GAP-03 × 1 + GAP-02 × 1 → `work-plan/SKILL.md` step-5 closed-list paragraph and `plan-critic.md:101`: the census lists rejections per conjunct, not per kind (for each admitted kind with an extra condition, name the producers that fail it and master-probe one); for an exit whose outcome a `D-n` changes, list every population that reaches it and master-probe each. Give `architecture.md` → *A `BuildSequenceResult.Error` is recoverable inside a projection* a carve-out: throw only when the fallback loses information the input carried.
- GAP-02 × 1 → `work-plan.md` P11 semantics: an `A-n` that blames a HEAD failure on a P10 / pre-existing entry cites a master run of that exact shape; a P8 row recording master green refutes it; a test reshaped to avoid the failure gets a `U-n`, not a test correction.

### Continuity with Rounds 1–2

- Round 2 "re-apply a lesson to the live plan" landed (`work-plan.md:291`, 32ae8ff) and was applied partially: A-8 recorded the residual as "not censused … reasoned, unprobed" instead of probing it; MAJ005 came from that residual.
- Round 2 "domain census + master probe per rejected kind" landed in `work-plan/SKILL.md` step 5; its axis (element type) is itself the gap MAJ005 exposes — a defect in the rule, re-proposed above widened to conjuncts.
- Round 2's `architecture.md` "must therefore throw" generalisation contributed to MAJ003: a round-2 fix enabled a round-3 finding.
- Round 2's mechanism "evidence held in the plan, routed elsewhere" recurs in MAJ004 (TO-35's master-green row beside A-5's L-7 attribution).
- Round 1's ordering-cell seed rule (`work-plan.md:159`, 41b2bee) landed before A-6 / A-8 and was not applied to TO-54 / TO-65 / TO-66; round 1's dominant class GAP-05 returns as this round's most frequent.
- Round 1's GAP-08 note recurs in shape: A-4's required G-02 stayed "not re-run" through A-9.
