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

## Round 4 — reviewed HEAD bcefe37bb

Plan judged at A-12 and critic round 10 (corpus rule state `5ee6bd7`; round-3 widenings `bbee068`/`f4cdac2` postdate the reviewed commits). Attributed by `review-gap-attributor`, 2026-11-16. "Casts are elided, so operands reach `^` bare" is critic round 9's found-sound line (plan.md:724-725).

### Attribution

- **MIN007** (decimal `Sql.Power` exponent loses E-40's grouping) — GAP-02 — E-40 (plan.md:238) assumed a right-nested exponent reaches `MathMemberTranslator.Power` as a bare `SqlBinaryExpression { Operation: "^" }`, reusing critic round 9's "casts are elided" (plan.md:725), true at `Wrap` time but not at translation, before `ConvertConversion` drops the cast; P7 row 281 names both `Sql.Power` overloads as callers but TO-26 (plan.md:310) has only `Math.Pow(double)` arms; second class GAP-04: the check sat in the translator while the operand shape is final only in the builder, where the fix went — — — preventable: yes
- **MIN008** (negative literal base/exponent on LibRed unprobed; probed green, withdrawn, pin kept) — GAP-02 — P7 row 281 extended A-11's native-only probe (critic round 9 lead, plan.md:714) to LibRed ("Since A-12 (E-37) this table is LibRed's too") without re-running it; no defect, the gap is the unrun claim — — — preventable: yes
- **SUG003** (no pin for engine `BOR` > `BXOR` on bare `a BXOR b BOR c`) — GAP-05 — precedences 40/39/38 (P7 row 281) leave a `BOR` operand of `BXOR` bare on engine order; TO-23's two shapes (plan.md:307) are both wrapped after the fix; the evidence (LibRed beta grammar, unkept `Bitwise - 1` mutation, P11 A-12 plan.md:549) was not a kept TO-n; critic round 10 caught the `BAND`/`BXOR` pair only (TO-27) — — — preventable: yes
- **OBS-BANDBOR** (promoted: native `BAND` vs `BOR` order unpinned) — GAP-05 — same P8 hole: a `BAND` operand of `BOR` (40 under 39) is bare on every flavour and no TO-n pins it; TO-27 (plan.md:311) covers `BAND`/`BXOR` only — — — preventable: yes
- **OBS-BNOT** (promoted: Access `~x` lowering `-1 - x` at precedence 0) — GAP-03 — P7 row 281 claims producers found by call shape (`new SqlBinaryExpression(`) but has no row for `AccessSqlExpressionConvertVisitor.cs:493`, a hit for that exact grep in the file E-36 edited; precedence-0 expressions treated only as operands of `^`, never as parents of `BAND`/`BOR`/`BXOR`; pre-existing (red identically on master) — — — preventable: yes
- **NIT005** (`DistinctTests.cs:361-362` chains on rewritten lines) — GAP-08 — G-01 carried this sweep hit since `cd009d488` (plan.md:327); A-10 (plan.md:329) dispositioned it "cleared in the review walk (re-indents / no chain)", A-12 (plan.md:331) "cleared in round 1"; both wrong — G-01 — preventable: yes
- **NIT006** (`WindowFunctionsTests.RowNumber.cs:215` chain on a re-indented master line) — GAP-08 — same G-01 row and "cleared … (re-indents)" wording at plan.md:329/:331; a re-indented line is PR-modified under `review-conventions.md:131`; the user overrode the reviewer's reject in the walk — G-01 — preventable: yes
- **NIT007** (four new `WhereTests.Binary*` tests use hand-duplicated `AreEqual`) — GAP-06 — P11 A-12's `conventions:` line (plan.md:558) embeds `testing.md` *Test layout* and in the same line directs "new tests follow `BinaryOr`'s `AreEqual` form", contradicting rule 3 (`testing.md:682`) and `testing.md:626`; the tests followed the plan — — — preventable: yes
- **CI-SYBASE** (`WhereTests.BinaryXorUnderOr` red on Sybase, gated on #6243) — GAP-02 — P10 plan.md:346 left Sybase to CI, but the gate's own `Details` names the mechanism "T-SQL evaluates `|` and `^` left to right"; critic round 10's "gate narrower than its mechanism" was answered by widening to `AllSqlServer` only; one CI round trip, no shipped defect — — — preventable: partly

Not attributed: the shared-engine unary `~` precedence defect (`ExpressionBuildVisitor.cs:2784`, `SqlExpressionFactoryExtensions.cs:170`, Oracle `-1 - x` at 0) — pre-existing, outside the diff, filed as #6340.

### Aggregate

GAP-02 ×3, GAP-05 ×2, GAP-08 ×2, GAP-03 ×1, GAP-06 ×1. Five of nine (MIN007, MIN008, SUG003, OBS-BANDBOR, OBS-BNOT) come from the E-34/E-36/E-40 operator table — the fourth round running with precedence findings. The table is prose: its cells carry no kept test, its census is not one row per grep hit, and it does not say at which pipeline stage an operand's shape holds. One change prevents four (SUG003, OBS-BANDBOR, MIN008, MIN007's decimal arm): every cell where `Wrap` leaves a child bare, and every caller overload of the changed operator, owes a kept characterization TO-n per flavour.

### Recommended durable fixes

- GAP-05 ×2 + GAP-02 ×2 (SUG003, OBS-BANDBOR, MIN008, MIN007) → `docs/work-plan.md:132` operator-table bullet + P8 semantics: "probe each adjacent operator pair" → "keep a characterization TO-n for each cell where `Wrap` leaves a child bare and engine order or a literal's sign decides the reading, per flavour; an unkept mutation or a grammar file is not the evidence"; each caller overload of the producer gets its own arm.
- GAP-03 ×1 + GAP-02 second link (OBS-BNOT, MIN007) → `skills/work-plan/SKILL.md` step 5 scout brief + `agents/plan-critic.md` near `:174`: paste the call-shape grep into P7 as one row per hit with every child position, including `ConvertSqlUnaryExpression` lowerings that emit a binary node; a node-type grouping rule is made where `Wrap` runs or names the convert-pass rewrites in between; a critic found-sound about node shape names its pipeline stage.
- GAP-08 ×2 + GAP-06 ×1 (NIT005, NIT006, NIT007) → `scripts/work-plan.ps1` (`:517`, `:527`): a G-01 sweep hit marked cleared must cite the finding id or user disposition; reject a "re-indent" reason per `review-conventions.md:131`. Add a `handDuplicatedAreEqual` category to `scripts/test-diff-sweep.ps1` (no category covers rule 3 today).

### Corpus trace

- MIN007 · rule: `docs/work-plan.md:132` (`5ee6bd7`) · why it did not fire: the rule is about `Wrap` at the builder; E-40 tested node type in the translator, a stage the rule never mentions; critic round 9's found-sound carried into round 10 without naming its stage; TO-26 copied `Math.Pow` only · correction: `docs/work-plan.md:132` — a node-shape test made before the convert pass is checked against that pass's rewrites (`ConvertConversion` cast elision) or moved to the builder; `agents/plan-critic.md` near `:174` — a found-sound on operand shape states its stage · recurs: round 2 second class, round 3 OBS-XOR (third consecutive critic found-sound miss; `bbee068`'s `:174`/`:176` rules would not catch it)
- MIN008 · rule: `docs/work-plan.md:132` per-flavour table (`bbee068`) · why it did not fire: added after the reviewed code · correction: none beyond the first durable fix · recurs: round 3 OBS-XOR
- SUG003 · rule: `docs/work-plan.md:132` "probe each adjacent operator pair in both nestings" (`bbee068`) · why it did not fire: postdates the code; even now "probe" is satisfied by the unkept mutation and the beta grammar · correction: "probe" → "keep a TO-n" for bare-by-engine-order cells · recurs: round 3 MAJ001
- OBS-BANDBOR · rule: same as SUG003 · why it did not fire: critic round 10 named the `BAND`/`BXOR` pair, not the class · correction: same as SUG003 · recurs: round 3 MAJ001
- OBS-BNOT · rule: `docs/work-plan.md:132` "every binary and unary producer … by call shape" (`5ee6bd7`) · why it did not fire: table written from `^`'s point of view; the `:493` hit was folded into "precedence-0 expressions … operand of `^`"; nothing requires one row per grep hit · correction: `skills/work-plan/SKILL.md` step 5 — paste the call-shape grep, one row per hit · recurs: round 2 MIN005
- NIT005 · rule: `docs/testing.md` *Test layout* rule 1; `docs/review-conventions.md:131` · why it did not fire: sweep reported it every round; G-01 dispositioned it "cleared … (re-indents / no chain)" and `work-plan.ps1:517` skips lines containing `cleared` · correction: `scripts/work-plan.ps1:517`/`:527` — "cleared" needs a cited disposition · recurs: round 1 NIT002/NIT003; `plans/feature-access-libred/gaps.md:46`
- NIT006 · rule: `docs/review-conventions.md:131` · why it did not fire: "re-indents" treated as untouched; reviewer rejected, user overrode · correction: same as NIT005, plus an example at `review-conventions.md:131` · recurs: round 1 NIT003 (same file)
- NIT007 · rule: `docs/testing.md:682`, `:626` · why it did not fire: A-12's `conventions:` line named `BinaryOr`'s `AreEqual` as the form to follow; no sweep category for rule 3 · correction: `scripts/test-diff-sweep.ps1` `handDuplicatedAreEqual`; `agents/plan-critic.md` — a "follow <sibling>'s form" line is checked against `testing.md:626` · recurs: `plans/issue-6024-fix-oracle11-isnotnull-validator/gaps.md:29`
- CI-SYBASE · rule: `agents/plan-critic.md` round-10 "gate narrower than its mechanism" (plan.md:734) · why it did not fire: widened by provider name, not by the `Details` mechanism ("T-SQL") · correction: optional — `docs/testing.md` *Gating*: a gate's configuration list covers every provider its `Details` mechanism names, or lists the rest as CI-verdict · recurs: —

### Continuity

- Round 3's top recommendation landed in `bbee068`/`f4cdac2` after the reviewed commits, so round 4 measures the `5ee6bd7` rule. The new wording would have forced MIN008's per-flavour table and the SUG003 probe, but its verb "probe" still lets an unkept mutation stand as evidence, so SUG003/OBS-BANDBOR would recur under it.
- Round 1's deferral `-Validate` check (`work-plan.ps1:516-517`) is why NIT005/NIT006 got through: the hit was re-worded from "open for the review walk" to "cleared in round 1", which the `cleared` exemption accepts.
- Critic found-sound misses: round 2 "no native `^` producer", round 3 "CLR XOR is untouched", round 4 "casts are elided, so operands reach `^` bare". Each round's critic rule targets the previous wording, so the class (a found-sound claim reused outside the scope it was checked in) recurs.
- Precedence findings: round 1 ×2, round 2 ×1, round 3 ×2, round 4 ×4 (plus MIN008 withdrawn), all on the E-16/E-30/E-34/E-36/E-40 chain.
