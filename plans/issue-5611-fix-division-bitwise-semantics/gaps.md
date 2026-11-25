# Gap ledger — PR #6450 (issue/5611-fix-division-bitwise-semantics)

## Round 1 — reviewed HEAD 8eec2820d (2026-11-24)

No plan on this branch (split out of #6427 without one); attribution names the #6427 block the item came from (`.claude/plans/issue-5527-provider-operator-precedence/plan.md`) or a block only a split plan would have carried.

- **BLK001** (mixedWidths arm red on T-SQL/SqlCe/Sybase) — GAP-02 — split premise "none needs the new precedence mechanism" never probed; arm green in #6427 only via its T-SQL table; local runs had no T-SQL provider; second class GAP-08 (no test-all on the port head before opening) — G-01 — preventable: yes
- **MAJ001** (RangeUnion Additive; `a.Union(b.Except(c))` → `a + b - c`) — GAP-05 — no TO-n for #6390's own counterexample; #6427 P7 "covered by E-17", TO-6 test-defined templates only; classes chosen for #6427's rule kept under master's `Wrap`; second class GAP-02 — — — preventable: yes
- **MIN001** (HANA/Informix `ulong` fractional) — not-a-gap: reviewer-disagrees-with-P10 — A-3 Risk "P10" note (never in the P10 block), reversed by the user in A-5; did not travel to the split body
- **ITEM12** (`ulong` → DECIMAL providers without override) — GAP-02 — E-22 asserted default-`null` providers truncate, keyed on CLR type only; TO-14 `ulong` arm projection-only — G-01 — preventable: yes
- **ITEM13** (DECIMAL-stored `int` on providers without override) — GAP-02 — same E-22 assumption; A-3 Risk covered the override providers only — — — preventable: yes
- **ITEM14** (MySQL `~` on uint/ushort/byte) — not-a-gap: reviewer-disagrees-with-P10 — A-3 Risk recorded `uint` only (GAP-03 residue for the other widths); reversed under A-5
- **MIN002** (MySQL `DIV` template nullability Undefined) — GAP-03 — E-22 reused the interval-only template for every integer `/` without re-checking its construction contract — — — preventable: yes
- **MIN003** (YDB `string.Join` mixed types untested) — GAP-05 — change absent from #6427's plan; "failed on master too" unbacked — G-01 — preventable: yes
- **SUG001** (SQLite local `IsFloating`) — GAP-04 — `NumberTypeExtensions` cited by A-3 itself; reuse rule covers `DataType` predicates only — — — preventable: partly
- **SUG002** (YDB `UnsignedOf` / MySQL `IsSignedInteger`) — GAP-04 — composition of existing `NumberTypeExtensions` members written locally — — — preventable: partly
- **SUG003** (cast-once only in `Component`, not `Composed`) — GAP-03 — A-4 scoped the collapse to one path; second class GAP-08: G-02 recorded "cast once" as pass against contradicting baselines — G-02 — preventable: yes
- **SUG004** (template-class changes untested, HANA `CharIndex*2`) — GAP-05 — "covered by E-17"; TO-6 lacks in-repo template arms — — — preventable: yes
- **SUG005** (`Issue4469Test2` split vestigial) — GAP-01 — testing.md says split for per-arm gates, no inverse rule — — — preventable: partly
- **NIT001** (nested NUnit chain) — GAP-07 — rule exists (testing.md rule 1) but no plan `conventions:` line; second class GAP-08 (sweep lists `nestedChains`) — G-01 — preventable: partly
- **ITEM16** (SQLite cast-of-cast) — GAP-02 — E-27's "does not re-match" checked the node, not a parent whose operand is its output — — — preventable: yes
- **OOS-ISEMPTY** (`isempty((a * b))`) — not-a-gap: reviewer-disagrees-with-P10 — P10 accepted churn, reversed by A-5
- **CORPUS-SCALAR** (testing.md scalar rule stale since #6131) — not-a-gap: out-of-plan-scope — #6099 plan deferred the edit with no owner/trigger

### Aggregate

13 of 17 trace to a plan block; 10 inherited from #6427 blocks (E-22 ×2, E-27, A-3 DIV reuse, A-4 Component, E-17/TO-6 ×2, three reversed carve-outs), 2 split-specific (BLK001, MIN003), 4 code conventions, 1 stale corpus deferral. Dominant: GAP-02 ×4 ("server already does X" / "won't re-match" settled from CLR type or the node itself, unprobed on the differing case); then GAP-05 ×3.

### Recommended durable fixes (proposed, not applied)

1. `pr-and-push.md` port recipe: re-prove a port under its new base (one provider per dialect family incl. T-SQL, or test-all on the port head), probe body premises, carry the parent's carve-outs touching moved code into the port body.
2. `code-design.md` (~:277) + `plan-critic.md`: a "dialect already gives C# semantics" default is checked per CLR type against the provider's mapped DB type; a rewrite must not fire in a parent whose operand is its own output.
3. `work-plan.md` / `work-plan/SKILL.md` operator-table trigger: include a template's declared class; every in-repo template whose class changes gets a TO-n; a closed issue's counterexample goes in verbatim.
4. `code-design.md` (~:281): "a wrapper template" → "any template over operands"; sweep sibling sites when a rule is written from one instance.
5. `code-design.md` (~:388): reuse rule generalized to CLR-type predicates, home `NumberTypeExtensions`.
6. `code-reviewer.md` rubric: a PR-body SQL-shape claim ("once", "no X") is verified by grepping baselines for the forbidden shape.
7. `testing.md` (~:111): removing the gates that justified a split merges the split back or records why not.
8. `test-diff-sweep.ps1` (~:80): qualify the nested-chains note — an NUnit constraint chain in `Assert.That` is a rule-1 defect.
9. `work-plan.md` P7: a `deferred:` corpus edit names the step that executes it.
