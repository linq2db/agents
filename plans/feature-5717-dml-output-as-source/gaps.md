# Gap ledger: feature/5717-dml-output-as-source

Round 1 was attributed as if the branch had no plan; it carried A-1..A-10 at that head (corrected in round 2).

## Round 1 — reviewed HEAD 6f9f0473b4d73c0d66881b7be6dd9a9928a8dab8

- **MIN005** (dynamic column throws at render) — GAP-03 — needed a P7 mirrored-site row for InsertWithOutput, whose Sql.Property output works while the name-keyed lookup in BuildDataModificationCteBody only searches target.Fields; second class GAP-05, no TO-n read a column outside the mapped entity — — — preventable: partly
- **MIN006** (remark false under eager loading) — GAP-02 — needed a P11 amendment for the earlier SUG001, backed by a P4 row on transaction × eager load × direct/remote; the remark arrived in 545a7d49f when EagerLoadOverOutputRollsBackOnFailure already existed — — — preventable: partly
- **MIN007** (two unnecessary DisableBaseline waivers) — GAP-10 — waivers came in 4fa6e5da4; CommitTransaction stripping arrived on the parallel stack line in ec94a2892, a dependency that moved mid-branch — — — preventable: no
- **MIN008** (Concat source renders UNION ALL after RETURNING) — GAP-03 — needed a P7 row for the insert-from-source render path the new overload inherits; the shape was refused on the CTE body only — — — preventable: partly
- **SUG002** (EagerLoad message does not fit QueryBatch) — GAP-10 — message wording; no plan block carries it — — — preventable: no
- **SUG003** (Correlated message, untested arm) — GAP-05 — needed a P8 TO-n per overload; CorrelatedCallThrows covers only the setter overload — — — preventable: yes
- **SUG004** (repeated AllPostgreSQL attributes) — GAP-01 — no written rule exists, only sibling practice — — — preventable: partly
- **NIT001** (missing space) — GAP-10 — typo; no plan block carries it — — — preventable: no
- **NIT002** (`=` misaligned) — GAP-07 — no plan-step embed of the alignment rule; the catch is the diff read — G-06 — preventable: partly
- **NIT003** (`=>` misaligned) — GAP-07 — same embed; the touched-lines rule pulls the other way — G-06 — preventable: partly
- **NIT004** (missing LinqTunnel) — GAP-07 — no plan-step embed of the JetBrains-contracts rule — — — preventable: partly

### Aggregate

4 of 11 findings trace to blocks a Tier L plan would have required: P7 (MIN005, MIN008), P4/P11 (MIN006), P8 (SUG003). Three (NIT002-004) trace to the convention embed at low marginal value. Four map to no existing block. The substantive cluster is GAP-03: what the new API inherits from the existing insert pipeline was never enumerated.

### Recommended durable fixes (unverified, for session-reflect)

- work-plan SKILL step 5 scout brief: for a new public API over an existing pipeline, list the input shapes that pipeline accepts (dynamic columns, set-operator sources, each overload), one P7 verdict each.
- acting-on-findings.md: a behavioural sentence added to answer a finding is checked against the branch's own tests on that subject before it lands.
- testing.md: reports that BaselinesWriter.Normalize does not strip the commit, while origin/master strips CommitTransaction.

## Round 2 — reviewed HEAD af52f547d93dbe19ab7ee6ace3f5c7782080e051

Own files unchanged at e26366662. Review 6092598502.

- **MIN009** (remarks: eager-load transaction rolls back "a failure while the returned rows are read"; QueryBatch not named) — GAP-08 — A-12 adopted af52f547d's E-19 remarks, but its `re-derives:` line names E-19 and P9 (G-01), not G-03, so G-03's content check was never re-run against D-10 / L-9 (a caller-code failure keeps the insert) or L-23 (QueryBatch reaches the same opener); second class GAP-02: critic round 9 built no caller-code-failure shape — G-03 — preventable: yes
- **MIN010** (same remark on the source overload, LinqExtensions.Insert.cs:1212-1214) — GAP-08 — the same E-19 paragraph on the second overload; the G-03 re-run that MIN009 lacked would have read both — G-03 — preventable: yes
- **MIN011** (InsertWithOutputQueryTests.cs:1228 comment and test name EagerLoadOverOutputCommitsWhenEnumerationEnds describe the removed spanning transaction) — GAP-03 — stack merge a30249518 (2026-11-04) brought #6111's bbd9de082, which replaced A-8's spanning transaction; no A-n recorded it, A-11 left six deleted edit-points standing, and A-12 sent the comment and name to review; second class GAP-05: TO-26's mutation cannot tell "commits when enumeration ends" from "commits before the first row" — — — preventable: yes
- **NIT005** (:1438 "streams the insert with its reader open", false under buffering) — GAP-03 — the same unrecorded merge a30249518; the comment states A-8's TO-28 premise, which A-12 turned into a characterization and sent to review — — — preventable: yes
- **NIT006** (missing blank line between two tests at :1487) — GAP-01 — no corpus rule or sweep check requires a blank line between members; introduced in A-9's 8b70c7b6d, survived G-09 and round 1; recurs (fix-6303-interceptor-cache gaps.md NIT005) — — — preventable: partly
- **NIT007** (14 Shouldly `ShouldThrow<T>` + `Message.ShouldBe` where testing.md prescribes `Assert.That(…, Throws.TypeOf<T>().With.Message…)`) — GAP-07 — the rule landed 2026-11-15 (62b6f2a) after 13 of the 14 sites; A-12's `conventions:` line copied "Test layout rules 1-2" forward, and its sweep ran before check 15 `shouldlyThrowAssertions` existed (0ed32d2) — — — preventable: partly

### Aggregate

Six findings: GAP-03 ×2, GAP-08 ×2, GAP-07 ×1, GAP-01 ×1. The four substantive ones (MIN009-MIN011, NIT005) share one entry point. Stack merge a30249518 changed the mechanism D-10 described, and for 23 days no amendment recorded it. A-11 missed it. A-12 caught the plan text, but it adopted another author's remark without re-running G-03 against the limits it had just rewritten. The change that would have prevented the most: make `-Action reconcile` report P6 edit-points whose file has left the own delta.

### Recommended durable fixes

- GAP-03 ×2 (and part of MIN009 / MIN010) → `scripts/work-plan.ps1` `Invoke-Reconcile`: report and fail on `vanished`, meaning authorized P6 paths absent from `git diff <base>...<head>`. Then widen `skills/work-plan/SKILL.md` *After merging master into a planned branch* to cover master or the stacked base branch, whoever made the merge.
- GAP-08 ×2 → `docs/definition-of-done.md` G-03 content check: read the doc against every P10 L-n on the member's path. An A-n that re-touches a doc E-n puts G-03 on its `re-derives:` line and re-records it in P9. Also `agents/plan-critic.md`: check prose claims against the plan's own `U-n` **and** `P10` limits.
- GAP-01 ×1 → `scripts/test-diff-sweep.ps1`: add a member-spacing check for a `}` line directly followed by an attribute or member line at the same indent. The shape now recurs across branches.
- GAP-07 ×1 → no new rule. Check 15 already exists; re-run the sweep at the head.

### Corpus trace

- MIN009 / MIN010 · rule: `docs/definition-of-done.md` (G-03 doc content), `docs/work-plan.md` (an A-n that changes documented behaviour names the doc E-n), `agents/plan-critic.md` (prose behavioural claims vs U-n) · why it did not fire: the sentence was another author's, adopted after the fact; A-12's `re-derives:` named E-19 but not G-03; round 10 listed D-10's ForEachAsync sentence as not re-attacked; the critic checks prose against U-n, not P10 · correction: as in the fixes above · recurs: round 1 MIN006, A-7's G-09 MIN006, and feature-1404-query-batch gaps.md MIN006 / MIN018 (the same transaction sentence, wrong for the third time)
- MIN011 / NIT005 · rule: `skills/work-plan/SKILL.md` post-merge P7 re-run; `agents/plan-critic.md` (an A-n that swaps a mechanism re-derives every comment citing it) · why it did not fire: the mechanism changed in a base-branch merge, which the SKILL rule (master only) does not cover; reconcile is file-keyed and reports only unplanned files, so the vanished edit-points raised nothing · correction: vanished-edit-point check; "master" → "master or the stacked base" · recurs: round 1 MIN007 (stack ec94a2892 moved a premise mid-branch); feature-1404-query-batch gaps.md MIN018
- NIT006 · rule: none · why it did not fire: no rule, no detector · correction: member-spacing sweep check · recurs: fix-6303-interceptor-cache gaps.md NIT005
- NIT007 · rule: `docs/testing.md` head (since 62b6f2a) · why it did not fire: 13 sites predate it; the embed copied "Test layout rules 1-2" forward; the sweep had no category until check 15 · correction: none new · recurs: round 1 NIT002-NIT004 (convention not embedded)

### Continuity

- Round 1 MIN006 (GAP-02: the E-19 remark was false under eager loading) recurs as MIN009 and MIN010, the third wrong version of the same transaction sentence. Round 1 recommended a rule checking a behavioural sentence against the branch's own tests. It did not land, and it would have missed this case anyway, because no test pins the caller-code order (L-9). The check needed is against P10.
- Round 1 MIN007 (stack ec94a2892 moved mid-branch) recurs as MIN011 and NIT005, through the same entry point: a stack-base merge with no amendment. A second occurrence makes it systemic, not unpreventable.
- Round 1 NIT002-NIT004 (GAP-07, convention not embedded) recurs as NIT007. The `conventions:` line is still copied forward rather than derived.
- Ledger header correction: round 1's "No work plan on this branch" is false. plan.md carried A-1..A-10 at round 1's HEAD 6f9f0473b.
