# Gap ledger — feature-fix-string-args-varchar-type

## Round 1 — reviewed HEAD e9e949911

Own delta `6ed227947..e9e949911` (stacked on #6186). Attributed against the plan as it stood before A-4 (last amendment A-3, 2026-10-31).

- **MAJ003** (REPLACE declared type hides its Unicode result) — GAP-03 — D-4's failure mode already said "the function's declared type stays the value's VarChar while SQL Server returns nvarchar", but P7 listed only one reader of that type (`CorrelateValueTypes`); A-3 added a second reader (`WidenLongNonUnicodeBesideUnicode` reading each concat operand's type, later `MeasureStringOperand`) and fixed the same hiding for REPLICATE (`GetReplicateType`), while its `class:` sweep searched REPLICATE producers and the widening's callers, not readers of REPLACE's declared type, and its `re-derives:` said "D-4 unchanged"; secondary GAP-02: D-4's "as on master (critic round 1: no regression found)" was checked against master, not the stacked #6186 base that brought the reader — — — preventable: yes
- **MIN002** (TO-12 no longer discriminates) — GAP-09 — unplanned `5a353b206` retyped ASCII pad literals VarChar with no P11 entry, so nothing re-derived TO-12, whose `'b'` pad depended on D-2 leaving an ASCII literal Unicode; file-keyed `-Reconcile` passed because the commit touched only E-5/E-6/E-7 files, and the post-critic edit-point check only warns — G-01 — preventable: partly
- **MIN003** (`[ActiveIssue(6212)]` can never flip) — GAP-02 — P10 L-5 named #6212 as the tracker for Replace/PadLeft while saying "measured there, not for Replace / PadLeft"; nobody checked that #6212's remedy (a MAX-sized parameter) lifts REPLACE's truncation, which one raw-SQL probe shows follows the first argument; `5a353b206` copied the tracker into the gate — — — preventable: yes
- **MIN004** (Cyrillic-literal tests narrowed without a measured failure) — GAP-06 — U-7 and TO-1c/TO-1d scoped Cyrillic literals to SQL Server + SQLite citing "as the concat plan's TO-3" with no run behind it, while A-1's `conventions:` line had embedded testing.md "A narrowed provider set is a claim"; #6186 withdrew the same rationale in `aedb296e8`; secondary GAP-02: U-7 resolved by citing a sibling plan, not a probe — — — preventable: yes
- **SUG001** (TO-11 Literal arm became a control) — GAP-09 — same chain as MIN002: `5a353b206` made the ASCII "b" literal VarChar so the arm emitted no widening cast; no A-n re-derived it and mutation M2 went unrun until after the review — G-01 — preventable: partly
- **SUG002** (TO-3 PadLeft arm no longer separates D-3) — GAP-09 — D-3's only separating input was the ASCII '0' literal (m5); after unplanned `5a353b206`, `AsNonUnicodeAsciiLiteral` pins its type whatever the scope, and a char parameter is NChar(1) on master and PR alike; no P11 entry re-derived D-3 or TO-3 — G-01 — preventable: partly
- **NIT001** (one-line chain at StringFunctionTests.cs:1204) — GAP-07 — the unplanned `c3792f145` (TO-17) was written outside `/work-plan`, so the amend step's conventions embed and `test-diff-sweep.ps1` never reached its author; secondary GAP-09: no A-n until A-4 — — — preventable: partly
- **NIT002** (TO-6 narrowed set at :868 has no reason comment) — GAP-06 — A-1's `conventions:` line recorded the sweep's narrowed sets and listed only `:1037`/`:1057`/`:1080` as lacking a reason; TO-6's `IncludeDataSources(AllSqlServer, AllPostgreSQL)` had none either — the rule was embedded and the sweep run, but its `lineAbove` output was misread — — — preventable: yes

### Aggregate

Two groups. Four findings (MIN002, SUG001, SUG002, NIT001) come from co-author commits `5a353b206` / `c3792f145` made without an amendment: they touched only authorized files, so file-keyed `-Reconcile` passed, and nothing re-derived the TO proofs they emptied. The single change that would have prevented most of them: when unreconciled commits touch E-n files, re-run the plan's recorded mutation set and `test-diff-sweep.ps1` on the delta before review. The major (MAJ003) is a separate, preventable impact-map miss: A-3 fixed declared-type hiding for REPLICATE but never listed the REPLACE reader D-4's own failure mode had named. No finding is GAP-10. The DB2 `Char(col, n)` padding (#6237) is a pre-existing master defect with no plan block to attribute; P8/P9 being stale for the round-delta tests is the same GAP-09 chain.

### Recommended durable fixes

- GAP-09 × 3 + GAP-07 × 1 (MIN002, SUG001, SUG002, NIT001) → `review-pr/SKILL.md` second-round reconcile: when unreconciled commits touch files `P6` already authorizes, `-Reconcile` passing is not enough — before dispatching the passes, re-run the G-01-recorded mutation set for each TO-n whose E-n those commits touch, and `test-diff-sweep.ps1 -Base <last A-n head>`; report any TO-n that stopped going red at the scope gate.
- GAP-03 × 1 (MAJ003) → `work-plan/SKILL.md` amend step 3 re-derive rule: an A-n whose E-n adds a reader of a node's declared type must name, in `re-derives:`, every D-n failure mode and P7 row stating a declared-vs-actual divergence for that node, and apply the fix to every producer of the class.
- GAP-02 × 1 (MIN003) → `work-plan.md` P10 semantics: an `L-n` naming an existing issue as its tracker records a probe or citation that the issue's remedy lifts this branch's shape; otherwise the L-n files its own issue.
- Not owed: MIN004's rule already landed in testing.md (`593a6f2`, 2026-11-01). NIT002 would be caught mechanically if `test-diff-sweep.ps1` flagged narrowed sets whose `lineAbove` is not a `//` comment.

## Round 2 — reviewed HEAD c4fbb5d4f

Round delta `008fd34b9..c4fbb5d4f` (sdanyliv's implementation of the handed A-6 design); fix head `ac26ede6c`. Attributed against the plan as handed (corpus `3de88f1`); A-7 and critic round 9 as evidence.

- **MAJ004** (mixed default-typed function with a Unicode MAX argument cut at 4000) — GAP-02 — the handed E-8 row set the over-4000 branch to `{NU, Length: longest}` "(null for a MAX argument)", justified by SC-15's "ISNULL returns that varchar", without checking what `WidenLongNonUnicodeBesideUnicode` does with a null length (`:276` casts only `> 4000`, `:291` stops summing), though P7 A-6 listed that reader; the `_` arm in `c4fbb5d4f` is that row verbatim, so the out-of-plan commit is not the cause. Secondary GAP-05: critic round 7 objection 3's witness arms covered `Unicode: any`, `Length: longest`, `none → 8000`, not the null/MAX clause — — — preventable: yes
- **SUG003** (REPLACE over a short mixed argument gains a cast to `NVarChar(Max)`) — GAP-05 — critic round 8 objection 2 named the exact input before implementation; P12 dispositioned it "posted to the author as a case to check", with no TO-n arm and no P10 line, so the author's commit had nothing red to answer; no D-n designs the per-function rule (`ISNULL` first-argument-typed vs `STUFF` precedence-typed) `:343` would need. Secondary GAP-02: P7 A-6 readers row called the REPLACE lowering unchanged, reasoning only about the Unicode-only case — — — preventable: partly
- **OOS-6261** (`Remove()` → `Stuff(value, …, N'')` cut inside STUFF, master-equal, filed #6261) — GAP-02 — SC-15 / P3 applied "over 4000 … cast on its own" to STUFF (P7 A-6 producer row), a rationale that holds only for first-argument-typed functions; critic round 7 objection 4 asked for producers by result-type regime and was answered in prose, with no arm per regime, until critic round 9. The cut predates the branch (P10 L-11), so the plan could only have filed it earlier — — — preventable: partly
- **CRIT9-4** (A-7 `class:` null-producer claim wrong) — GAP-02 — counted a `DataType = NVarChar` + `DbType = "nvarchar(max)"` column as null-length from `ColumnDescriptor.cs:71` without `:63-68` (schema-default Length 4000 fill); the round's own first probe contradicted it; `work-plan/SKILL.md` already requires probing the "CLR default completed by MappingSchema" shape — applying an existing rule; critic round 9 caught it before it bound an E-n — G-09 — preventable: yes

### Aggregate

GAP-02 is 3 of 4 rows; MAJ004 and OOS-6261 share one SC-15 "because" clause (ISNULL, long argument first) that was never checked against the reader's handling of a null length or against other result-type regimes. No GAP-09: the author implemented the handed design faithfully, so the defects were in the plan. No GAP-10. The critic raised SUG003 (round 8) and the regime question behind OOS-6261 (round 7) before code existed; the loss was in dispositions answered as prose or a PR comment rather than as arms.

### Continuity

- All three round-1 recommendations landed (`review-pr/SKILL.md` mutation re-run for unreconciled commits, `work-plan/SKILL.md` declared-type readers / re-declarers sweep, `work-plan.md` tracker L-n proof); none would have caught this round — no TO-n or mutation existed for the MAX shape, and the catch-all's readers are measure readers, not declared-type readers.
- Round 1's GAP-09 (co-author commits emptying TO-n) did not recur; the co-author pattern did (A-1, A-4, A-6, A-7), this time carrying the plan's own design.
- GAP-02 on the string-default catch-all recurs: #6186's round-5 ledger recorded GAP-02 ×3 on the same "any other" row; A-6 enumerated its producers by route but not its readers' handling of a sentinel length.

## Recommended durable fixes

- GAP-02 × 2 (MAJ004, OOS-6261) + secondary GAP-05 → `agents/plan-critic.md`, a vector under P8 provability: when a rule's output includes a sentinel (a null length meaning MAX / unknown) or its rationale names one member as why a branch is safe, demand one arm per input regime reaching the branch (long/MAX argument first vs not, a function converting its argument internally, MAX through a widened concat) and a P7 note per reader on the sentinel; a regime objection answered in prose stays open.
- GAP-05 × 1 (SUG003) → `docs/work-plan.md` P12 disposition semantics: when an amendment is handed to an external author, each open critic objection naming a concrete input ships as a TO-n arm (asserting the intended answer) in the handed test set, or as a P10 L-n; "posted as a case to check" leaves nothing red against the author's commit.
- Not owed: CRIT9-4 — the probe rule exists, and G-09 caught it.

## Round 3 — reviewed HEAD 34d1318a4

Round delta `ac26ede6c..34d1318a4` (sdanyliv's `c8820d6a5`, implementing igor-tkachev's MIN001, plus a master merge); fix head `034854fb0`. Attributed against the plan as it stood at A-7; A-8 and critic round 10 as evidence.

- **MIN005** (Unicode-only default-typed function with a MAX argument but a non-MAX result cut the concatenation after it at 4000) — GAP-05 — A-7's `class:` line held the MAJ004 fix up with a prose invariant ("`{ NonUnicode: false } => {U, 1}` never returns null either") that `:291`'s premise depends on, while A-7's `re-derives:` added MAX arms for the mixed `_` arm only; no `TO-n` sent a MAX argument through the Unicode-only arm, which received the sentinel and discarded it by returning a constant, so when `c8820d6a5` changed it to `=> shape` nothing went red. TO-24, written afterwards, is that arm. Secondary GAP-09: `c8820d6a5` rewrote an arm the A-7 E-8 row spelled out, with no `A-n`; file-keyed `-Reconcile` passed, and the `review-pr` mutation re-run had no recorded mutation for this regime — G-01 — preventable: partly
- **MIN001** (igor-tkachev: a Unicode-only function counted one character with a known argument length) — not-a-gap: reviewer-disagrees-with-P10 — L-10 adjudicated "1 vs 4000" (the A-6 fork, critic round 8 objection 1) and never listed the argument's own length, which was already in the arm's input; settled in the finding's favour by `c8820d6a5` and A-8.

### Aggregate

One attributable finding. MIN005 is the third null-length (MAX-sentinel) defect in this file in two rounds (MAJ004, CRIT9-4, MIN005): each round fixed the arm it found and wrote the other arms' null-freedom into a `class:` line no test defends. No GAP-10.

### Continuity

- Round 2's plan-critic sentinel vector landed (`26533f0`) and fired on A-7's readers side; it did not fire for the Unicode-only arm because it triggers on a rule that *outputs* the sentinel, and that arm output the constant `{U, 1}`.
- Round 2's handed-amendment rule does not apply: `c8820d6a5` was a co-author implementing another reviewer's suggestion, not a handed amendment.
- The co-author-without-amendment pattern recurs for the third round (`5a353b206`, `c4fbb5d4f`, `c8820d6a5`); the corpus cannot reach that author, so the defence is arms that go red.

### Recommended durable fixes

- GAP-05 × 1 (MIN005) → `agents/plan-critic.md`, extend the `26533f0` sentinel bullet: cover a sentinel a rule *receives* — a branch that replaces it with a constant or `?? n` is an input regime and needs a `TO-n` arm that goes red if the branch passes its input through; a `class:` sentence asserting a negative invariant a fix relies on ("no arm returns null") names the arm or G-01 mutation pinning it per branch, or stays an open `weak`.
- Not owed: the GAP-09 secondary (`review-pr/SKILL.md` already runs the reconcile and mutation re-run; the fix above gives it something to run); MIN001 drives no fix.
