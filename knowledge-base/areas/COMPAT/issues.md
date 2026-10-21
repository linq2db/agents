---
area: COMPAT
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-10-21
last_verified_sha: 89b5ce16278728b9936ba374827fea002c76e962
---

# COMPAT -- GitHub themes

## Open themes
- **netstandard2.0 asset gaps on modern runtimes** -- The netstandard2.0 build is compiled without the net8+ branches (`NET8_0_OR_GREATER`, `SUPPORTS_DATEONLY`, `#if` provider-type conversions, probe lists). An app on a modern runtime that loads that asset (through a netstandard2.0 library, or on a runtime whose TFM is dropped) then hits a missing translation, a missing type conversion, or a provider assembly that is never probed. The same source compiles on net462 and binds to an overload or type the ns2.0 build lacks. Translation gaps: #6075 (`TrimStart()` / `TrimEnd()` no-arg and char overloads; draft fix PR #6082) and #6067 (C# 14 span `Contains` IN form; draft fix PR #6074). Type and probe gaps: #6076 (SAP HANA client probes only `Sap.Data.Hana.Core.v2.1`; draft PR #6083), #6077 (Npgsql 10 `DateOnly` / `TimeOnly` / `NpgsqlRange<DateOnly>` not converted; draft PR #6092), #6084 (DuckDB `TIMETZ` to `TimeSpan` reader only under `SUPPORTS_DATEONLY`), #6085 (MySQL `VECTOR` to `float[]` conversion only under `#if`). Driver behaviour: #6086 (ClickHouse.Driver parameterised insert fails with unbound `p1` on the ns2.0 build; cause not yet recorded).

## Resolved themes
- **x86 .NET Framework JIT faults under FP-unmasking hosts** -- C++Builder and Delphi hosts unmask the overflow, divide-by-zero and invalid-operation FP exceptions. The x86 .NET Framework JIT then faults on methods that use `double` special values: `QueryCache.ToStopwatchTicks` (#6042, stack overflow in clrjit on 4.8.1) and the NaN / Infinity constants in ten provider methods (#6051). Fixed by PR #6053 (merged 2026-10-15, fixes #6042) and PR #6058 (merged 2026-10-19, fixes #6051; adds the `Tests.FpuJit` x86 CI gate). x64 is not affected.

## Active discussions
- None in the index for this area.

## Stats
- Open issues: 7
- Closed issues: 2
- Open PRs: 4
- Total PRs: 6
- Discussions: 0
- Last fetched: 2026-10-21

<details><summary>Coverage</summary>

- Index entries scanned: 15 (9 issues + 6 PRs + 0 discussions)
- Themes extracted: 2 (1 open, 1 resolved)
- Basis: index area tag COMPAT covers #6051 and #6075 only. The other entries are cited by theme: label `area: compatibility` on #6076, #6077, #6084, #6085, #6086; body and linked fix PR on #6067, #6042, PRs #6053, #6058, #6082, #6083, #6092, #6074. Their index area tags (PROV-*, LINQ, CORE, EXPR-TRANS) are kept as indexed; per-item tags are lossy.
- Not cited: #5942 and #5944 (.NET 11 TFM work; 2 items, below the theme threshold).
</details>
