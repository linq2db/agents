# Gap ledger — fix/ydb-round-decimal-precision (#5943)

## Round 1 — reviewed HEAD c9a48fb70

No work plan on this branch; attribution names the block a Tier M plan would have needed.

### Attribution

- **MIN001** — GAP-05 — needed a `P8` `TO-n` for "non-constant precision **below** the source scale" naming the input that discriminates the two branches (work-plan.md → *a fixture per element is not coverage unless the element's input can separate the arms*). `Tests/Linq/Linq/MathFunctionTests.cs:404-406` uses `p.ID % 2 + 2` (always ≥ 2) over `MoneyValue` rows that all carry scale 2, so `Round16` went red only for 0721546's scale-drop bug (`1.11` → `1.00`), never for the scaled round-and-divide path. Secondary: GAP-02 — the fixture's data scale was never checked against the precision expression. — G-01 — preventable: yes
- **MIN002** — GAP-09 — needed `P11` amendments for the two edits outside a YDB-only `P6`: `MathMemberTranslatorBase.cs` (7ebfb103: precision translated without column descriptor, all providers) and `PostgreSQLSqlExpressionConvertVisitor.cs:270` (c9b9f69: `%` rewrite casts to the expression's own type; 786 PG baselines across 13 versions; `Round16` excluded on DuckDB); plus 913370f84's no-op-for-p≥scale behaviour change. The body's follow-up sections are what an amendment log becomes; without one, three of six substantive commits never reached the body. Secondary: G-08 (cross-cutting core change surfaced). — G-08 — preventable: partly

### Aggregate

2 of 2 findings trace to blocks a Tier M plan would have required; neither is GAP-10. The four earlier review rounds (result type leaking into `+`/`IF`; non-constant precision dropping scale; near-limit clamp dropping scale; negative precision shrinking integer digits) are cells of one unenumerated input space for a single sizing decision — constant vs non-constant p; p ≥ s / 0 ≤ p < s / p < 0; P near 35; result type as consumed by the parent. GAP-01 (`P2` never stated "result type = value type, scale never lost") with GAP-05 fallout (no `P5` partition table expanded to one `TO-n` per cell). Writing that table with one discriminating fixture per cell before the first commit would have collapsed four review rounds and MIN001 into the initial implementation.

### Recommended durable fixes

- GAP-01/GAP-05 × 5 → `plan-critic.md` attack vector: any change computing a SQL type (precision/scale/length sizing, emulated numeric functions) requires a `P5` partition table (argument constness, sign, relation to source scale, provider limit, consuming parent expression) with one `TO-n` per cell whose fixture data is shown to fall in that cell.
- GAP-02 × 1 → `testing.md`: shared fixture tables (`Types`/`LinqDataTypes`) have fixed precision/scale and value ranges; a test depending on argument-vs-data-scale must say which rows reach the path, or use `CreateLocalTable` with declared `Precision`/`Scale` (as `Round17`/`Round18` do).
- GAP-09 × 1 → `definition-of-done.md` gate (or G-08 clarification): every commit changing behaviour outside the PR's stated provider/scope, and any baseline move of > ~50 files in an unrelated provider, gets a PR-body follow-up section; without a plan, reconcile the commit list against the body.
