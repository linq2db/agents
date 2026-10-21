---
area: CORE
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-10-21
last_verified_sha: 89b5ce16278728b9936ba374827fea002c76e962
---

# CORE -- GitHub themes

## Open themes

- **TFM matrix and netstandard2.0 asset on modern runtimes** -- .NET 11 support is in flight (#5942 drops net8/net9, #5944 raises C# to 15 and enables runtime async on net11.0). The netstandard2.0 asset, which modern runtimes also load, has recognition and translation gaps: C# 14 span `Contains` is rejected (#6067 issue, #6074 PR), and `TrimStart()`/`TrimEnd()` no-arg and char overloads are not translated (#6075 issue, #6082 PR). Provider-specific netstandard2.0 probes (SAP HANA #6076, #6083) are owned by PROV-SAPHANA.
- **Parameter naming and sizing** -- a generated parameter can claim the name of an explicitly named `DataParameter` first, which renames the explicit one (#6040, open). Earlier parameter work is closed (#1628 parameter size, #5493 duplicate parameter optimization).
- **Query cache: raw SQL and captured-argument reuse** -- cached work built from raw SQL formats or closures is reused where it should be rebuilt: `CompiledQuery` keeps the first build's raw SQL format or closure arguments (#6045), and `[SqlQueryDependent]` values that are Equals-equal but render differently share one cache entry (#6059). Open PR #6033 caches command text for constant TAKE/SKIP, which widens the reuse path. Related closed PR: #6008 (skip raw SQL arguments the format never references).

## Resolved themes

- **Query cache served stale SQL** -- nested `FromSqlScalar`/`FromSql`/`Sql.Expr` inside a query returned cached SQL for another shape (#6000, closed; fixed by #6003). `Sql.Expr(FormattableString)` was rebuilt on every execution because the registered format was compared by reference (#5857, closed). A cached-query mutation in the IN-to-EXISTS conversion corrupted later executions (#6007, closed).
- **x86 .NET Framework hosts that unmask FP exceptions** -- JIT faults in provider code using NaN/Infinity constants (#6051, closed), and a QueryCache crash on the same hosts (#6053, closed). The JIT-fault fix is #6058 (closed).
- **Type support additions (historical)** -- NodaTime support (#1432), `nvarchar(max)` AddScalarType (#1555), and `DATETIME(2)FROMPARTS` in MERGE (#3644). All closed; the only shared trait is the `area: types` label.

## Active discussions

- No active discussions.

## Stats

- Open issues: 5 (#6040, #6045, #6059, #6067, #6075)
- Closed issues: 6 (#1432, #1555, #3644, #5857, #6000, #6051)
- Open PRs: 5 (#5942, #5944, #6033, #6074, #6082)
- Total PRs: 12 (5 open; 7 closed: #1628, #5493, #6003, #6007, #6008, #6053, #6058)
- Discussions: 0
- Last fetched: 2026-10-21

<details><summary>Coverage</summary>

- Index entries scanned: 11 (3 issues + 8 PRs + 0 discussions), all CORE-tagged entries in the existing indexes
- Fetched items reviewed for CORE membership: all titles in kb-refresh-fetch-issues.json and kb-refresh-fetch-prs.json (fetch files carry no area field)
- Query-cache themes rely on the index CORE tags; by path the cache code sits under LINQ / EXPR-TRANS. Borderline, kept because the index tags them CORE.
- Themes extracted: 6 (3 open, 3 resolved)
</details>
