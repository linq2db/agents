---
area: CLI
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# CLI -- GitHub themes

## Open themes
- **T4 model generation gaps** -- Recurring requests to extend T4 model generation from the database schema: sequence attributes (#2766), default property values (#835), PostgreSQL stored procedures and window functions (#1444), function overloads in templates (#3352), F# record output (#1553), DTO generation (#2850). All carry `area: T4`. Six are open. One-to-one relationship detection (#1339) is closed (2026-06-14) and appears under Resolved themes.
- **linq2db.cli credentials and impersonation** -- Handling of database credentials in the `linq2db.cli` tool: credential helpers and a built-in local store (#5991, open), and limiting `--impersonate` to connection and execution so SQL validation and code loading run under the caller identity (#5995, open). Secret input masking in the credentials prompt (#5889) is merged.

## Resolved themes
- **linq2db.cli release and command surface** -- Per-RID tool packages and nupkg size gate (#5539), query/execute/schema and MCP server infrastructure (#5678), NU5118 pack failure on .NET SDK 10.0.400 that broke the build job on every PR from 2026-08-11 until #5775 merged on 2026-08-12, and 6.5.0 preparation for MCP Registry publication (#5894). All merged.
- **T4 relationship detection** -- One-to-one relationship generation for SQL Server (#1339) was requested as a question and closed on 2026-06-14 without a linked PR in the index.

## Active discussions
- None. No discussions are classified to CLI in `github/discussions-index.json` as of 2026-10-09.

## Stats
- Open issues: 6
- Closed issues: 1
- Open PRs: 2
- Total PRs: 9
- Discussions: 0
- Last fetched: 2026-10-09

<details><summary>Coverage</summary>

- Index entries scanned: 16 (7 issues + 9 PRs + 0 discussions)
- Themes extracted: 3
- Not clustered: #5621 (test executable --provider / --test-progress options) and #5648 (Sql.NewGuid7 / UUIDv7 translation). Both carry area CLI but match no theme; #5648 may belong to a GUID or SQL-function area.
</details>
