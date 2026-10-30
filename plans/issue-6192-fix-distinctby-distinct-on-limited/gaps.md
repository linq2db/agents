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
