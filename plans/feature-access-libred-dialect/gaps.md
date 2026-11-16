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

## Round 3 — reviewed HEAD 203e2852d

Plan judged at A-11 and critic round 9. Findings include Igor Tkachev's review at 2d0ac39ad (MAJ001, MIN005-igor, SUG002-igor). Attributed by `review-gap-attributor`, 2026-11-16.

## Attribution

- **MAJ001** — GAP-02 — A-3 (2026-09-23) put E-16's `^` → `BXOR` arm at `Precedence.Bitwise - 1` (`BOR`'s level), unprobed; `findings.md:283` grammar survey lists `MOD`/`BAND`/`BOR`/`^`, no `BXOR`; A-10's probe (`findings.md:53`) ran only `a BOR b BXOR c`, which both candidate orders answer alike, and P11 A-10 (plan.md:517) filed it "Out-of-scope" on #6243 although the defect is E-16's own (no `BXOR` on master); A-11's P7 operator table (plan.md:276) was scoped to native `^` and omitted LibRed's arm — — — preventable: yes
- **MIN005-igor** — GAP-08 — P9 G-03 (plan.md:322) recorded "pass — all new types and overrides … with `PublicAPI.Unshipped.txt` entries" from two examples, not an enumeration; A-5's `IsOrderedSetWindowedSupported` override (`dc283da76`) never got a line; RS0016 only runs under `RunApiAnalyzersDuringBuild` — G-03 — preventable: partly
- **SUG002-igor** — not-a-gap: reviewer-disagrees-with-P10 — P11 A-9 (plan.md:502) records the user's "keep the `MOD` fix on #5969"; it is in P11 only and belongs in P10 as an adjudicated override of AGENTS.md's separable-fix rule
- **MIN006** — GAP-07 — `testing.md:105`'s single-assertion criterion (`0925691`, 2026-11-03) postdates the gate (`562513a85`, 2026-09-24); A-8/A-9/A-10's `conventions:` lines (plan.md:501, :508, :521) never carried it, so the gate was not re-checked; second class GAP-08: G-01 sweep records (plan.md:317, :319) list only chains / nested chains / narrowed sets while `test-diff-sweep.ps1` reported the gate under `typeOnlyShouldlyGates` — G-01 — preventable: yes
- **NIT004** — GAP-10 — prose: `AccessSqlExpressionConvertVisitor.cs:71`/`:97` were true when written; A-3/D-5's `IsTickArithmeticSupported` left them unscoped while the new member's summary was scoped correctly — — — preventable: no
- **OBS-XOR** — GAP-02 — A-3's E-16 comment "LibRed has the bitwise operator Jet lacks" and the E-1-narrowed `AllNativeAccess` exclusions on `WhereTests.BinaryXor`/`BinaryAnd`/`BinaryOr` were never probed on a native flavour (one `Access.Ace.OleDb` statement refutes both); A-3's own E-9 line records `^` is power in Access; P7 E-34 and critic round 9 recorded "CLR XOR is untouched" as sound; second class GAP-08: G-01 (plan.md:317) passed 262 reason-less narrowed sets as E-1 instances — — — preventable: yes

## Aggregate

GAP-02 ×2, GAP-07 ×1, GAP-08 ×1, GAP-10 ×1, one not-a-gap. Both GAP-02s, including the only MAJ, trace to one unprobed A-3 line, the LibRed `ConvertSqlBinaryExpression` arm, which assumed both `BXOR`'s precedence and native Jet/ACE's lack of it. This is the fourth precedence finding on the PR in three rounds (round 1 MIN003/SUG001, round 2 MIN005). Round 2's operator-table rule landed (`5ee6bd7`), but it fires only on a change to an operator's `Precedence`. A newly registered operator, and the flavours sharing the visitor, fall outside it.

## Recommended durable fixes

- GAP-02 ×2 (MAJ001, OBS-XOR) → `work-plan.md` P7 operator-table bullet + `skills/work-plan/SKILL.md` step 5 scout brief — trigger on any `ConvertSqlBinaryExpression` arm added, renamed or moved; one table per flavour sharing or overriding the visitor; probe each adjacent operator pair in both nestings with shapes whose readings disagree (`evidence-discipline.md:140`); an engine-has/lacks-operator claim is a P4 row with a per-flavour probe, never a code comment.
- GAP-07 ×1 (MIN006) → `work-plan.ps1 -Action validate`: a G-01 or `conventions:` sweep record names every `test-diff-sweep.ps1` category with its count, zeros included.
- MAJ001 second link → `work-plan.md:281` — extend the "pre-existing cites a master run" rule to "out-of-scope" and umbrella-issue hand-offs; when master cannot run the shape, the defect is the branch's.

## Corpus trace

- MAJ001 · rule: `docs/evidence-discipline.md:140`; `docs/work-plan.md:281` (`4f10b87`); P7 operator-table bullet `docs/work-plan.md:132` (`5ee6bd7`) · why it did not fire: E-16 predates all three; A-10's probe was a side probe into `findings.md`, not a `U-n`, so no critic checked that its one shape could disagree; "Out-of-scope" wording dodges `:281`; the operator-table trigger names `Precedence` changes only · correction: widen the P7 trigger and scout brief (above); cover out-of-scope / umbrella hand-offs at `:281`; fix `plans/feature-access-libred/findings.md:53` · recurs: this ledger round 1 MIN003, round 2 MIN005
- MIN005-igor · rule: `docs/definition-of-done.md:14` (non-`Internal.*` only); `code-reviewer.md` drift ban · why it did not fire: RS0016 runs only with `RunApiAnalyzersDuringBuild` (`Source/Directory.Build.props:14`); G-03 recorded from examples · correction: `docs/work-plan.md` P9 semantics — a `pass` gate cites the command or full enumeration, never "e.g." · recurs: —
- SUG002-igor · rule: AGENTS.md *Creating a new branch* · why it did not fire: it did; the user overrode it at A-9 · correction: `docs/work-plan.md` P10 semantics — a user override of an AGENTS.md rule gets a P10 line, not only P11 · recurs: —
- MIN006 · rule: `docs/testing.md:105` (`0925691`) · why it did not fire: test predates rule; the rule's own paragraph cited `ContainsOverADifference` as the type-only example; `ActiveIssueAttribute.cs:132-134` said "pinned by type" unconditionally; work-plan and review-pr told readers to cite only chains and narrowed sets · correction: applied this session (testing.md citation, review-pr step 6, work-plan step 4 sweep counts, ActiveIssueAttribute doc on the PR); remaining: `-Validate` every-category check · recurs: `plans/issue-5843-compare-cache-constants-by-content/gaps.md:70-71`; `plans/feature-net11-support/gaps.md:12`
- NIT004 · rule: `docs/evidence-discipline.md:214` · why it did not fire: loaded for probes and write-ups, not implementation; targets prose made false, not prose made unscoped · correction: optional — one sentence at `:214` on re-scoping parent summaries when a virtual switch lets a subclass take the base path · recurs: —
- OBS-XOR · rule: `docs/agent-rules.md:99` → `evidence-discipline.md` *Claims you have not run*; `agents/plan-critic.md:174` · why it did not fire: the comment was triage rationale, never treated as a claim; critic round 9's "CLR XOR is untouched" checked only that the producer was unchanged · correction: `agents/plan-critic.md` near `:174` — an "X is untouched" line about a producer whose operator the dialect reads differently is checked against what each flavour renders · recurs: round 2 second class (critic "no native `^` producer")

### Continuity

- Round 2's recommended operator-table rule landed (`5ee6bd7`) and still missed: its trigger is a precedence change, while round 3's defect is an operator arm registered without one, on a different flavour. Fourth precedence finding on E-16/E-30-adjacent code.
- Round 1's type-only gate class (#6185 TO-27, recorded in issue-5843's ledger) produced the rule and the sweep category; neither consumer read the category until this round.
