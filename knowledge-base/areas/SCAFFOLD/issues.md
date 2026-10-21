---
area: SCAFFOLD
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-10-21
last_verified_sha: 89b5ce16278728b9936ba374827fea002c76e962
---

# SCAFFOLD -- GitHub themes

## Open themes

- **Naming and identifier control** -- Requests to shape generated names: aliased table and class names (#3739), dropping the leading `t` prefix from table classes (#3786), and removing the schema segment from generated names (#4211). Closed precedents: #3578 and #3583 (drop database name from schema by default), #3673 (DefaultSchema option).
- **Member and type shape customization** -- Requests to override generated member shapes: declarative column type overrides (#3603), generic return types for functions (#4282), `required` modifier on generated properties (#4901), and inheritance-friendly output (#4583). All sit in the code-generator epic cluster.
- **Generated-file output and T4 parity** -- Custom code generation hooks (#3682), file header comments (#4096), and features missing versus the T4 BaseDataContextClass template (#4713). A related defect, CodeAttribute ambiguous reference (#4384), is tagged needs-tests and area: types. CLI handling of T4 template compile errors (crash instead of a diagnostic) is fixed in draft PR #6036 (CLI-tagged in the index).
- **Database object coverage at scale** -- Sequence configuration (#3749) and model combination for databases with many tables, functions and procedures (#5620). ClickHouse scaffold support is requested in open discussion #5089.
- **F# code generation** -- Long-standing request for F# output from the scaffolder: #1553 (opened 2019, labels area: T4, area: fsharp, area: scaffold) asks whether F# records can be generated. Draft PR #5707 adds F# data-model generation to the CLI scaffolder (`--target-language f#`, AST and code-generation path only; the T4 template mode stays C#-only) and uses head branch feature/1553-fsharp-codegen.
- **Generated-code test coverage** -- Generated code is checked only against committed golden baselines that CI does not regenerate (#6021, labels area: tests, area: scaffold). Draft PR #6037 (fixes #6021) adds a harness that feeds a predefined schema through the generator, compiles the generated C# and F# and executes it, for SQLite, SQL Server and PostgreSQL profiles. Its base branch is the #1553 F# branch, so it depends on PR #5707.

## Resolved themes

- **T4 to CLI migration and CLI option fixes** -- Early CLI defects in help text and option parsing (#3567, #3612, #3678) and the invalid T4 output from the CLI (#3564, fixed by PR #3566) closed during 2022. Transformation option parsing and help were fixed in PR #3723.
- **Scaffold framework rewrite and association naming** -- The new scaffolding framework landed via PR #3098 (2022-04-29). Later association and backreference naming defects (#3810, #3762, #4061) are closed, with the naming fix in PR #4087.
- **SQLite and PostgreSQL metadata gaps** -- SQLite primary key metadata for without-rowid tables (#5014, has-pr), foreign keys without referenced columns (#5116, closed with needs-tests still tagged), and PostgreSQL duplicate identity with nextval defaults (#5628, closed 2026-06-27).
- **SQL Server procedure return value mapping** -- With `--mssql-enable-return-value-parameter`, the procedure's `@return` was generated as a `ParameterDirection.Output` parameter, so every wrapper failed with "too many arguments" (pre-existing since PR #3098). Fixed as ReturnValue in PR #6026 (merged 2026-10-12), which refs #4718 and also covers the F# generator in #5707.

## Active discussions

- [Linq2Db.Cli scaffold for ClickHouse](https://github.com/linq2db/linq2db/discussions/5089) -- [Q&A] `-p ClickHouse` rejected as an unknown provider value; asks whether scaffold supports ClickHouse.
- [Scaffolding TypeScript support](https://github.com/linq2db/linq2db/discussions/5148) -- [Q&A] Feedback on the new scaffolding tool and questions on the v6 migration.
- [Is there an option to generate Context in a separate folder from generated entities?](https://github.com/linq2db/linq2db/discussions/5374) -- [Q&A] Asks for a separate output folder or project for the context class.
- [Version 6 migration Q&A](https://github.com/linq2db/linq2db/discussions/5023) -- [General] Central thread for v6 migration questions (linq2db.AspNet renamed to linq2db.Extensions; some T4 nugets renamed or discontinued).

## Stats

- Open issues: about 13 (approximate: the index state field is missing on some SCAFFOLD entries)
- Closed issues: about 78 (approximate, same caveat)
- Open PRs: 1 (#6037; draft PRs #5707 and #6036 are tagged to FSHARP and CLI in the index)
- Total PRs: 53
- Discussions: 14 (4 open)
- Last fetched: 2026-10-21

<details><summary>Coverage</summary>

- Index entries scanned: 158 (91 issues + 53 PRs + 14 discussions, all tagged SCAFFOLD) plus 3 cross-tagged items cited (#1553 T4-TEMPLATES, #5707 FSHARP, #6036 CLI)
- Themes extracted: 10 (6 open + 4 resolved)
</details>
