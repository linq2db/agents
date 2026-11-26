# Gap ledger — PR #5931 (branch issue/5930)

## Round 1 — reviewed HEAD d4a75f3728c38f3a1afcd91a2b5564f07510ae75

No plan on this branch (external contributor). Each row names the plan block that would have carried the finding; no P9 results.

- **MAJ005** (option off: DTO shift returns NULL on Classic) — GAP-03 — no plan; the opt-in change in d4a75f372 needed a P11 amendment with a P7 consumer row for every SQL reader of the stored DateTimeOffset text; the shift lowering (SQLiteDateTimeHelper.cs:21-31, GLOB/strftime from e0214233f) assumes parseable text and was left ungated; secondary GAP-05: no TO-n for option-off Classic, every DTO shift test enables the option — — — preventable: yes
- **MIN006** (6.5.1 DateTime shift Round → TruncateDivide, undisclosed) — GAP-02 — no plan; the 7f182b0cf merge that took in #5987 kept the PR's TruncateDivide lowering and needed an A-n with a P4 probe at a sub-millisecond remainder and a P3 "user-visible deltas vs master" row; the body asserted "keeps one SQLite lowering" without checking equivalence — — — preventable: yes
- **MIN007** (new per-issue Issue5930Tests.cs fixture) — GAP-10 — rule landed in ed602b5 (#6058, 2026-10-17), after the last test commit (2026-10-12); test-writer.md previously prescribed Issue<N> names — — — preventable: no
- **NIT001** (one-line method chains) — GAP-10 — rule landed in 406f742 (2026-10-12 15:28 +0300), four hours after the last commit d4a75f372 — — — preventable: no
- **SUG005** (DTO branch renders date 5×, chains grow 5^n) — GAP-01 — no plan; no P2 criterion that the lowering composes linearly under chained AddX / nested Sql.DateAdd, which would have produced a P4 probe of a 3-level chain counting operand occurrences — — — preventable: partly

### Aggregate

3 of 5 (MAJ005, MIN006, SUG005) trace to blocks a Tier M plan would have required, each a mid-branch design change (reviewer-requested opt-in, conflict resolution against #5987, a new lowering's composition) applied locally and never re-propagated to dependent code. MIN007 and NIT001 are GAP-10: the rules post-date every commit and already reach external contributors via CONTRIBUTING.md:345-346 (#6274).

### Recommended durable fixes

- GAP-03 → plan-critic.md beside :87: an option that changes a stored representation lists every SQL reader of it (comparison, IN/Contains, date arithmetic, string functions) as a P7 consumer row, with a TO-n on each option arm including the default.
- GAP-02 → definition-of-done.md:29: when a merge resolution keeps the branch's implementation of behaviour master also implements, diff the two at boundary inputs (sub-unit remainder, negative amount) and list each difference as a P3 / PR-body behaviour delta.
- GAP-01 → plan-critic.md:130: generalise beyond limit checks — a lowering referencing its operand k > 1 times grows as k^n under nesting; demand a P4 probe of a 3-level chain counting operand occurrences, or a level-merging rewrite.
- testing.md: a feature that depends on an opt-in option gets an option-off test asserting the default behaviour.

### Corpus trace

- MAJ005 · rule plan-critic.md:87 (capability flag read by two consumers needs a probe through each) · did not fire: no plan, no critic; the maintainer's opt-in request didn't name the shift as a dependent reader; option remarks describe only the text format · recurs: plans/feature-optional-member-translations/gaps.md:13 (MIN003), plans/issue-5932-mark-optional-row-values/gaps.md:180 (NOTE001) — option-off arm missing or unable to go red.
- MIN006 · no rule for "a conflict resolution replacing master's implementation owes a behaviour diff"; definition-of-done.md:29-30 require a re-run and body/code match, but the body claimed no delta and the PR's own test pins the new truncation, so runs stayed green.
- MIN007 · testing.md:644 (post-dates branch) · no correction.
- NIT001 · testing.md:659 (post-dates branch) · no correction.
- SUG005 · no rule; plan-critic.md:130 scoped to limit checks; every PR test is single-level.
