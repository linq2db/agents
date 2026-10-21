# Work plan: bugfix-closure-collection-count — Regression tests: closure collection Count evaluated client-side

**Tier:** S  ·  **Status:** approved  ·  **Approved-at:** 2026-10-22 (user: "add")  ·  **Branch:** bugfix/closure-collection-count
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

On 6.0.0–6.3.0, `.Count` of a captured `Collection<T>` whose element type is an unmapped, non-`IConvertible` class was translated to `SELECT COUNT(*) FROM (VALUES (@value))` instead of being evaluated on the client. The element was bound as a scalar parameter and execution failed (`InvalidCastException` on SqlClient, `No mapping exists from object type …` on Microsoft.Data.Sqlite); an empty collection produced a dead subquery. Measured with NuGet probes (SQLite execution + SQL Server `ToSqlQuery`): broken on 6.0.0 and 6.3.0, fixed from 6.4.0. `git bisect` over v6.3.0..v6.4.0 → `7733aead8` (#5557), which added `CanBeEvaluatedOnClient` early-outs to `AggregateFunctionsMemberTranslatorBase.TranslateCount` and the Min/Max/Sum/Average path. #5557's tests (`Tests/Linq/Linq/AggregationTests.cs:170-237`) cover only an empty `List<int>` in `Where` on SQLite — not a non-empty collection, a non-scalar element, `Collection<T>`, or an insert setter, which is the reported shape.

## P2 Success criteria

- SC-1 Insert setter `EmptyCount = empty.Count, ItemsCount = items.Count` (captured `Collection<Payload>`, 0 and 2 elements) stores 0 and 2 with no `COUNT(` in the SQL, on every provider. Proof: green on master; red with #5557's two `CanBeEvaluatedOnClient` lines reverted locally (control).
- SC-2 `Where(t => t.ItemsCount == items.Count && t.EmptyCount == empty.Count)` returns the row with no `COUNT(` in the SQL, on every provider. Same proof.

## P6 Edit-points

- E-1 `Tests/Linq/Linq/AggregationTests.cs` — model (`Payload`, `PayloadCollection`, `CountTarget`) and tests `ClosureCollectionCountInInsertSetter`, `ClosureCollectionCountInWhere`, `[DataSources]`.
- E-2 `Tests/Linq/Linq/ClosureCollectionCountTests.cs` — delete (session probe file, never committed).

## P9 Verification gates

- G-01: pass — `worktree-test.ps1`: on master the 2 new tests are green ×6 (SQLite.MS, SQLite.Classic, SqlServer.2022 + `.LinqService`); control: #5557's two `CanBeEvaluatedOnClient` lines removed → 12/12 red (syntax error from the zero-column VALUES source, #6102); same mutation with `Payload` given a member → 8/8 red on `ShouldNotContain("COUNT(")` (SQLite.MS, SqlServer.2022) — both arms discriminate; mutation and member reverted (`git restore`, `git status` clean apart from E-1). Whole `AggregationTests` on the 3 providers: 45/45. `test-diff-sweep.ps1`: 0 chains, 0 narrowed sets. `Tests/Linq` Release net10.0: 0/0 after fixing MA0206 (empty type bodies → `class X;`).
- G-02: pass — only new `AggregationTests.ClosureCollectionCount*` baselines under `c:\GitHub\linq2db.bls`; tests only, no product SQL change.
- G-03: n/a — tests only, no public surface (the gate fires on any non-`Internal` path; `Tests/` is not API).
- G-04: n/a — same.
- G-05: n/a — no product code; `Tests/Linq` Release net10.0 build covers test-code analyzers.
- G-06: pass — diff is E-1 only (+ one `using`).
- G-07: pass — no playground files; probe file E-2 deleted.
