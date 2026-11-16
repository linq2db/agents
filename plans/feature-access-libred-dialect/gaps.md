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

## Round 2 — reviewed HEAD 2d0ac39ad

Plan judged at A-10 and critic round 8. Attributed by `review-gap-attributor`, 2026-11-16. One finding, raised MIN → MAJ after a red probe on `Access.Ace.OleDb`.

- **MIN005** (native `^` binds below the raised `MOD`: `Math.Pow(ID % 3, 2)` → `ID MOD 3 ^ 2`) — GAP-03 — the P7 A-9 row, re-derived by A-10, censused only `MOD` producers (`git grep '"MOD"\|Precedence.Additive\|Precedence.Subtraction' -- …/Access`, keyed on the moved operator's own tokens), so it could not reach `AccessMemberTranslator.cs:218` (`factory.Binary(type, x, "^", y)`, no `Precedence.` token: the factory hard-codes Additive outside the Access directory); A-9's failure-mode line and A-10 reasoned about `MOD`'s neighbours as `+`/`-` and `*`/`/` only, although the plan records a native `^` producer (E-18, A-3's E-9 line "native `x ^ y`", critic round 2); second class: critic rounds 7–8 recorded "no `\` or native `^` producer" as sound against the plan's own E-18; no corpus test put a `MOD` operand under `Pow`, so G-01/G-02 saw no baseline move — — — preventable: yes

### Aggregate

GAP-03 ×1. It is the third finding on the one-line E-30 change (round 1 MIN003, SUG001; now MIN005): each time `MOD`'s precedence moved, the plan reasoned against a hand-picked neighbour set instead of an enumerated table of every binary producer the dialect emits and its precedence. That table would also have exposed the pre-existing `Math.Pow(ID * 2, 2)` / `Math.Pow(ID + 1, 2)` defects, fixed by the same change (A-11).

### Recommended durable fixes

- GAP-03 ×1 (+ round 1 MIN003, SUG001, same mechanism) → `work-plan/SKILL.md` step 5 scout brief and P7 semantics in `work-plan.md`: a change to an operator's `Precedence` owes a P7 operator table — every binary producer for the dialect, its effective precedence, and the `Wrap` outcome for each child position — found by call shape (`factory.Binary(`, `new SqlBinaryExpression(`, `ConvertSqlBinaryExpression` arms), because factory helpers apply a default precedence a token grep cannot see.
- Critic second class → `plan-critic.md`, worked example under the internal-contradiction rule (`:172`): a "found sound: no X producer" claim is checked against the plan's own P6/P11 before it is recorded.

### Continuity

- Round 1 MIN003 (right-nested `a % (b % c)`) was fixed by moving `MOD` to `Multiplicative` (A-10), and that move created MIN005 — the fix was again checked only against `MOD`'s known neighbours.
- Round 1 SUG001 (missing `a - b % c` arm) is the same blind spot from the test side: TO-19's arms came from the same partial neighbour set, so no arm put `MOD` under `^`. TO-22 closes this instance only.
- Round 1's top recommendation (deferral wording as a `-Validate` error) would not have prevented MIN005: the `^` case was never deferred, it was recorded as sound.
