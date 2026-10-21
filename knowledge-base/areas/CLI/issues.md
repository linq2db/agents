---
area: CLI
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-10-21
last_verified_sha: 89b5ce16278728b9936ba374827fea002c76e962
---

# CLI -- GitHub themes

## Open themes
- **T4 model generation gaps** -- Recurring requests to extend T4 model generation from the database schema: sequence attributes (#2766), default property values (#835), PostgreSQL stored procedures and window functions (#1444), function overloads in templates (#3352), F# record output (#1553), DTO generation (#2850). All carry `area: T4`. Six are open. One-to-one relationship detection (#1339) is closed (2026-06-14) and appears under Resolved themes. The `scaffold --customize` path has an open draft fix (PR #6036) that reports T4 template compile errors instead of crashing with a NullReferenceException.
- **Scaffolder F# output and generated-code testing** -- F# data-model generation for `dotnet linq2db scaffold --target-language f#` is in draft as PR #5707 (refs #1553): records, option columns and a DataConnection-derived context. Its test harness, draft PR #6037 (fixes #6021, based on #5707), feeds a predefined schema through the generator, compiles the C# and F# output and executes it on every PR, replacing committed golden output that CI never regenerates. Issue #6021 is open.
- **linq2db.cli credentials and impersonation** -- Handling of database credentials and identity in `linq2db.cli`: credentials CLI stores and a built-in AES-256-GCM local store (PR #5991, open), and limiting `--impersonate` to connection and execution so SQL validation and code loading run under the caller identity (PR #5995, open). Secret input masking in the credentials prompt (#5889) is merged.

## Resolved themes
- **linq2db.cli release and command surface** -- Per-RID tool packages and nupkg size gate (#5539), query/execute/schema and MCP server infrastructure (#5678), NU5118 pack failure on .NET SDK 10.0.400 that broke the build job on every PR from 2026-08-11 until #5775 merged on 2026-08-12, and 6.5.0 preparation for MCP Registry publication (#5894). All merged. CLI test coverage: a macOS leg was added to the CLI tests job (PR #6017, merged 2026-10-10) for macOS-specific credential store behaviour. NuGet audit fix pins System.Security.Cryptography.Pkcs in linq2db.cli (PR #6043, merged 2026-10-14).
- **Scaffolder stored-procedure return value** -- With `--mssql-enable-return-value-parameter`, the procedure `@return` was generated as an Output parameter, so every procedure wrapper failed with "too many arguments". Fixed by mapping it as ReturnValue (PR #6026, merged 2026-10-12, refs #4718). The same generator feeds the F# output in PR #5707.
- **T4 relationship detection** -- One-to-one relationship generation for SQL Server (#1339) was requested as a question and closed on 2026-06-14 without a linked PR in the index.

## Active discussions
- None. No discussions are classified to CLI in `github/discussions-index.json` as of 2026-10-21.

## Stats
- Open issues: 7
- Closed issues: 1
- Open PRs: 6
- Total PRs: 16
- Discussions: 0
- Last fetched: 2026-10-21

<details><summary>Coverage</summary>

- Index entries scanned: 24 (8 issues + 16 PRs + 0 discussions)
- Themes extracted: 6 (3 open, 3 resolved)
- Not clustered: #5376 (open PR, Agent Skill shipped in the NuGet package and installed by `linq2db-cli skill install`; single item, no theme yet). #5621 (test executable --provider / --test-progress options, merged) and #5648 (Sql.NewGuid7 / UUIDv7, merged) carry area CLI in the index but are not CLI work; they are left out of themes. 14 discussions carry the SCAFFOLD tag, not CLI, and are not included.
</details>
