---
area: INTERCEPTORS
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# INTERCEPTORS -- GitHub themes

## Open themes

- **Command-level interceptors are bypassed by batched execution** -- Registering an `ICommandInterceptor` switches the `DbBatch` backend off. `ICommandInterceptor` is `DbCommand`-typed and cannot observe a `DbBatch`, so a combined-command group (`LinqOptions.UseCombinedCommands`, #5673) runs as one concatenated command when `LinqOptions.UseDbBatch` is on. Registering an interceptor therefore changes the execution shape it is meant to observe. Open: #6230. Same recurring shape as the dispatch gaps resolved by #5813 below.

## Resolved themes

- **Interceptors skipped on custom IDataContext and compiled queries** -- Dispatch was driven by `IInterceptable<T>` type tests, so interceptors did not fire for custom `IDataContext` implementations (#5803 asked for `IInterceptable<T>` to be public again). `CompiledQuery` also skipped `IEntityServiceInterceptor.EntityCreated()` (#4365). Fixed by [#5813](https://github.com/linq2db/linq2db/pull/5813), merged 2026-08-25, which also fixes compiled queries over `ToList()`.
- **Interceptor API surface and its extension points** -- Hooks were added as needed: the v4 interceptor migration (#2927, #2941, the #267 original request, #3518), reader dispose hooks (#3724 `BeforeReaderDispose` / `BeforeReaderDisposeAsync`), expression and query-expression interception (#3510 closed unmerged, replaced by [#4479](https://github.com/linq2db/linq2db/pull/4479), which added `IQueryExpressionInterceptor` and `IMemberTranslator` via `DataOptions`), exception customization (#4552 `IExceptionInterceptor`, merged 2024-07-09), and connection setup options (#3939). A reader-completed hook was requested because SQL Server output parameters are only available after the reader is consumed (#3595, closed). Remote context now rejects unsupported interceptor types with a clear exception (#3861, merged 2022-12-06). Test coverage came with #2640 and #5294.

## Active discussions

- No active discussions. CLI scaffolding discussions that mention interceptors are excluded (see Coverage).

## Stats

- Open issues: 1
- Closed issues: 3
- Open PRs: 0
- Total PRs: 5
- Discussions: 0
- Last fetched: 2026-11-11

<details><summary>Coverage</summary>

- Index entries scanned: 24 (11 issues + 11 PRs + 2 discussions), matched by keyword or area tag; 17 cited.
- Themes extracted: 3 (1 open, 2 resolved)
- Excluded as scaffolding or other areas: #3568, #3820, #5014, #4707 (SCAFFOLD interceptors); discussions #3693 and #4703 (CLI scaffolding); PR #6025 (F# static let entity binding, mapping not interceptors).
</details>
