# Gap ledger — feature-access-libred-dialect

## Round 1 — reviewed HEAD cd009d488

Plan judged at its review-time version (corpus `94150de`, through A-9 and critic round 7). Attributed by `review-gap-attributor`, 2026-11-15.

- **MIN001** (refuted >2^31 DateAdd prediction) — GAP-05 — A-3/D-5 enabled `CanLowerIntervalShift` with `DateAdd('ms')` but P8 had no TO-n at the 32-bit shift boundary; the existing witness `ALongSpanIsMeasuredWhereCountingAnswersIt` (`IntervalTranslationTests.Difference.cs:656`) covers only TotalSeconds and was never cited; TO-20 added afterwards — — — preventable: partly
- **MIN002** (Skip ORDER BY injection promised, not built) — GAP-02 — D-4's failure-mode line left a checkable engine claim in prose instead of a P4 row (work-plan.md:249), never probed; E-7 shipped without the injection and no P11 line; second class GAP-08: G-01 signed TO-3's baseline-diff obligation off as "covered by the full sweep" — G-01 — preventable: yes
- **MIN003** (right-nested `a % (b % c)`) — GAP-02 — A-9 chose `Subtraction + 1` from `Precedence.cs` without walking `Wrap` for an equal-precedence right operand; critic round 7 found it and the plan carried it "open … to the round-1 review walk" against work-plan.md:322 — — — preventable: yes
- **MIN004** (Issue4336 Details stamped alpha.4) — GAP-10 — correct when written (`12f449283`, alpha.4); beta.1 arrived with the rebase; A-8 and round 6 recorded it stale and left it open for the review walk — — — preventable: partly
- **SUG001** (missing `a - b % c` arm) — GAP-05 — TO-19 witnessed the drop-parentheses direction for `+` only; critic round 7 named the arm and the plan deferred it against work-plan.md:322 — — — preventable: yes
- **NIT001** (`=>` column misaligned) — GAP-10 — a one-space slip in a block written aligned in one commit (`a04aa46a4`); no gate checks alignment on new lines — — — preventable: no
- **NIT002** (`MathFunctionTests.cs:469-470` one-line chains) — GAP-08 — G-01's sweep line recorded them and left them "open, dispositioned in the round-1 review walk", wording that passes `work-plan.ps1:511`'s literal "review item" check; second class GAP-07: the test predates its amendment A-9 — G-01 — preventable: yes
- **NIT003** (`WindowFunctionsTests.RowNumber.cs:175` chain) — GAP-08 — same G-01 sweep row and deferral wording; second class GAP-07: written 2026-09-24, before amendments carried a conventions line — G-01 — preventable: yes
- **OBS-AGG** (promoted: aggregate DISTINCT left off for LibRed) — GAP-02 — P4 U-4 marked `resolved-by probe` while its probe was deferred and never ran (an OPEN row worded resolved, against work-plan.md:80); E-9's aggregate DISTINCT never built; second class GAP-05/GAP-08: TO-9 could not go red (the emulation passes) and G-01 folded it into "covered by the full sweep" — G-01 — preventable: yes

### Aggregate

GAP-02 ×3, GAP-05 ×2, GAP-08 ×2, GAP-10 ×2. One mechanism dominates: in 5 of 9 (MIN003, SUG001, MIN004, NIT002, NIT003) the plan had recorded the defect before review and handed it to "the review walk"; work-plan.md:322 is prose-only and `work-plan.ps1:511` matches one literal phrase. Two more (MIN002, OBS-AGG) were probes deferred to triage and labelled resolved, whose SQL-shape obligations a pass count then signed off. Out-of-scope observations not attributed.

### Recommended durable fixes

- GAP-08 ×2 + the deferral pattern (MIN003, SUG001, MIN004) → `work-plan.ps1 -Validate` (`:511`; rule work-plan.md:322): widen "review item" to any deferral wording ("review walk", "open for the review", "carried to … review", "left open") across G-01, P11 and P12 objection lines; an error before `/review-pr` dispatch (5 findings).
- GAP-02 ×2 (MIN002, OBS-AGG) → work-plan.md P4/P9 semantics plus a `-Validate` check: a `resolved-by probe` row whose text defers the probe is OPEN; a baseline-diff TO-n is signed off in G-01 by citing the baseline line, never "covered by the full sweep" (2 findings).
- GAP-05 ×1 (MIN001) → work-plan.md P8: a D-n/A-n that turns on a lowering relying on another layer's range (a 32-bit `DateAdd` count) owes one TO-n per emitted unit at the counter's boundary, citing any corpus witness (1 finding).
