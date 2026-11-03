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
