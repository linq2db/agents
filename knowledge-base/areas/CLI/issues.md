---
area: CLI
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# CLI -- GitHub themes

## Open themes
- **T4 model generation gaps** -- Recurring requests to extend T4 model generation from the database schema: sequence attributes (#2766), default property values (#835), PostgreSQL stored procedures and window functions (#1444), table functions as UDFs (#449), function overloads in templates (#3352), F# record output (#1553), DTO generation (#2850), unique constraint metadata in the schema API and T4 model (#2037), user-friendly association names for MS Access relations (#2331), a File Scoped Namespace option (#5183), and migration of `.tt` instructions to the CLI scaffolder (#3957). Bugs in the same generator remain open: Postgres multi-schema output generated twice (#3203). The `scaffold --customize` path has an open draft fix (PR #6036) that reports T4 template compile errors instead of crashing with a NullReferenceException.
- **Scaffold command customization and code-model gaps** -- Requests to customize `dotnet linq2db scaffold` output that the CLI cannot express yet, mostly carried over from T4 features: multiple base classes or interfaces for the data context (#4713), inheritance in generated code (#4583), file header comments (#4096), `required` modifiers (#4901), custom code generation (#3682), generic return types for functions (#4282), CodeAttribute ambiguous reference errors (#4384), and declarative column type customization (#3603, reported as working in its last comment, still open). Sequence configuration in the JSON model (#3749) overlaps with the sequence-attribute request (#2766).
- **Scaffolder F# output and generated-code testing** -- F# data-model generation for `dotnet linq2db scaffold --target-language f#` is in draft as PR #5707 (refs #1553): records, option columns and a DataConnection-derived context. Its test harness, draft PR #6037 (fixes #6021, based on #5707), feeds a predefined schema through the generator, compiles the C# and F# output and executes it, replacing committed golden output that CI never regenerates. Issue #6021 is open.
- **linq2db.cli credentials and impersonation** -- Handling of database credentials and identity in `linq2db.cli`: credentials CLI stores and a built-in AES-256-GCM local store (PR #5991, open). A macOS Keychain store for the credentials CLI is requested (#6205, open); Windows and Linux stores exist. Limiting `--impersonate` to connection and execution so SQL validation and code loading run under the caller identity (PR #5995, open). Secret input masking in the credentials prompt (#5889) is merged.

## Resolved themes
- **linq2db.cli release and command surface** -- Per-RID tool packages and nupkg size gate (#5539), query/execute/schema and MCP server infrastructure (#5678), NU5118 pack failure on .NET SDK 10.0.400 that broke the build job on every PR from 2026-08-11 until #5775 merged on 2026-08-12, and 6.5.0 preparation for MCP Registry publication (#5894). Prerelease packages are published to the MCP Registry as well (PR #6278, merged 2026-11-09). All merged. CLI test coverage: a macOS leg was added to the CLI tests job (PR #6017, merged 2026-10-10) for macOS-specific credential store behaviour. NuGet audit fix pins System.Security.Cryptography.Pkcs in linq2db.cli (PR #6043, merged 2026-10-14).
- **Scaffolder stored-procedure return value** -- With `--mssql-enable-return-value-parameter`, the procedure `@return` was generated as an Output parameter, so every procedure wrapper failed with "too many arguments". Fixed by mapping it as ReturnValue (PR #6026, merged 2026-10-12, refs #4718; #4718 itself is still open in the index). The same generator feeds the F# output in PR #5707.
- **T4 relationship detection** -- One-to-one relationship generation for SQL Server (#1339) was requested as a question and closed on 2026-06-14 without a linked PR in the index.

## Active discussions
- [Linq2Db.Cli scaffold for ClickHouse](https://github.com/linq2db/linq2db/discussions/5089) -- [Q&A] Scaffolding ClickHouse with the linq2db.cli tool; last activity 2025-08-11.
- [Is there an option to generate Context in a separate folder from generated entities?](https://github.com/linq2db/linq2db/discussions/5374) -- [Q&A] Layout of the scaffolded context versus entities; last activity 2026-03-19.

## Stats
- Open issues: 23
- Closed issues: 1
- Open PRs: 6
- Total PRs: 15
- Discussions: 2
- Last fetched: 2026-11-11

<details><summary>Coverage</summary>

- Index entries scanned: 56 candidates (title, summary or body keyword match on linq2db.cli, scaffold, T4, impersonation or credentials, or area CLI, T4 or SCAFFOLD; open or updated since 2026-10-21) across issues, PRs and discussions
- Stats count the items cited in this file, not the whole index
- Themes extracted: 7 (4 open, 3 resolved)
- Not clustered: #5376 (open PR, Agent Skill shipped in the NuGet package and installed by `linq2db-cli skill install`; single item, no theme yet). Provider-specific scaffold reports (#1864, #3501, #4695, #4707, #4708, #3313, #2365, #4195, #4447, #4606) stay with their PROV areas. #3739, #3786 and #4211 are single questions with no recurring pattern.
- Dropped: #5621 and #5648 carry area CLI but are not CLI work (test executable options, Sql.NewGuid7). Discussions #4432, #4703, #5148 are provider or TypeScript scaffold questions and not CLI work.
</details>
