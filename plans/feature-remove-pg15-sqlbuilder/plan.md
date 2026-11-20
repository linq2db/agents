# Work plan: feature-remove-pg15-sqlbuilder — Remove the never-constructed PostgreSQLSql15Builder

**Tier:** S  ·  **Status:** approved  ·  **Approved-at:** 2026-11-20 (user, plan mode)  ·  **Branch:** feature/remove-pg15-sqlbuilder
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

`Source/LinqToDB/Internal/DataProvider/PostgreSQL/PostgreSQLSql15Builder.cs` (emits `InsertOrUpdate` as `MERGE`) is dead code. It was added in #3705 (65b2af29e, 2022-08-15), which announced that the `v15` dialect "enables MERGE in InsertOrReplace/Update APIs". However, `PostgreSQLDataProvider.CreateSqlBuilder` (`PostgreSQLDataProvider.cs:276-281`) only ever creates `PostgreSQL12SqlBuilder` / `PostgreSQLSqlBuilder`, and `git log -S PostgreSQLSql15Builder -- Source` shows only 65b2af29e and 56edce9f4 (API baselines). PG15+ emits `ON CONFLICT` (every PG15/PG18 `InsertOrUpdate*` baseline on linq2db.baselines `origin/master`). User decision: keep `ON CONFLICT`, which is atomic under Read Committed, and remove the class.

## P2 Success criteria

- SC-1 The class is gone and the Release build of `Source/LinqToDB` reports 0 errors (PublicAPI RS0016/RS0017 included) on net10.0 and netstandard2.0 → G-05
- SC-2 Generated SQL is unchanged: the class has no instantiation site, so no baseline moves → G-02

## P6 Edit-points

- E-1 `Source/LinqToDB/Internal/DataProvider/PostgreSQL/PostgreSQLSql15Builder.cs` — delete the file
- E-2 `Source/LinqToDB/PublicAPI/PublicAPI.Unshipped.txt` — add 4 `*REMOVED*` lines copying the shipped entries for the class, its constructor and its two overrides (Shipped lines 3235, 3236, 10570, 10571), as #6134 did

## P9 Verification gates

- G-01: n/a — no behaviour change and no new test: the deleted class had no instantiation site (`git grep Sql15Builder` outside PublicAPI returns nothing). The `test-postgresql` CI run after the push is a smoke check only.
- G-02: n/a — no SQL can move because the class was never constructed. PG15/PG18 `InsertOrUpdate*` baselines on linq2db.baselines `origin/master` already emit `ON CONFLICT`.
- G-03: pass — no surface added. The removals are recorded as 4 `*REMOVED*` lines in `PublicAPI.Unshipped.txt`, under `LinqToDB.Internal.*` (no stability contract).
- G-04: skipped — `CompatibilitySuppressions.xml` regeneration is a release-prep task (user policy). Unverified until release: ApiCompat CP0001/CP0002 entries for the removed type.
- G-05: pass — `dotnet build Source/LinqToDB/LinqToDB.csproj -c Release -f net10.0` and `-f netstandard2.0`: Build succeeded, 0 warnings, 0 errors (PublicAPI analyzers included).
- G-06: pass — the diff is one deleted file plus 4 added lines.
- G-07: pass — nothing under `Tests/Tests.Playground/` is touched.
