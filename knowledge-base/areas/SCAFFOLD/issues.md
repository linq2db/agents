---
area: SCAFFOLD
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# SCAFFOLD -- GitHub themes

## Open themes

- **Naming and identifier control** -- Requests to shape generated names: aliased table and class names (#3739), dropping the leading `t` prefix from table classes (#3786), and removing the schema segment from generated names (#4211). Closed precedents: #3578 and #3583 (drop database name from schema by default), #3673 (DefaultSchema option).
- **Member and type shape customization** -- Requests to override generated member shapes: declarative column type overrides (#3603), generic return types for functions (#4282), `required` modifier on generated properties (#4901), and inheritance-friendly output (#4583). All sit in the code-generator epic cluster.
- **Generated-file output and T4 parity** -- Custom code generation hooks (#3682), file header comments (#4096), and features missing versus the T4 BaseDataContextClass template (#4713). A related defect, CodeAttribute ambiguous reference (#4384), is tagged needs-tests and area: types.
- **Database object coverage at scale** -- Sequence configuration (#3749) and model combination for databases with many tables, functions and procedures (#5620). ClickHouse scaffold support is requested in open discussion #5089.

## Resolved themes

- **T4 to CLI migration and CLI option fixes** -- Early CLI defects in help text and option parsing (#3567, #3612, #3678) and the invalid T4 output from the CLI (#3564, fixed by PR #3566) closed during 2022. Transformation option parsing and help were fixed in PR #3723.
- **Scaffold framework rewrite and association naming** -- The new scaffolding framework landed via PR #3098 (2022-04-29). Later association and backreference naming defects (#3810, #3762, #4061) are closed, with the naming fix in PR #4087.
- **SQLite and PostgreSQL metadata gaps** -- SQLite primary key metadata for without-rowid tables (#5014, has-pr), foreign keys without referenced columns (#5116, closed with needs-tests still tagged), and PostgreSQL duplicate identity with nextval defaults (#5628, closed 2026-06-27).

## Active discussions

- [Linq2Db.Cli scaffold for ClickHouse](https://github.com/linq2db/linq2db/discussions/5089) -- [Q&A] `-p ClickHouse` rejected as an unknown provider value; asks whether scaffold supports ClickHouse.
- [Scaffolding TypeScript support](https://github.com/linq2db/linq2db/discussions/5148) -- [Q&A] Feedback on the new scaffolding tool and questions on the v6 migration.
- [Is there an option to generate Context in a separate folder from generated entities?](https://github.com/linq2db/linq2db/discussions/5374) -- [Q&A] Asks for a separate output folder or project for the context class.
- [Version 6 migration Q&A](https://github.com/linq2db/linq2db/discussions/5023) -- [General] Central thread for v6 migration questions (linq2db.AspNet renamed to linq2db.Extensions; some T4 nugets renamed or discontinued).

## Stats

- Open issues: 13
- Closed issues: 77
- Open PRs: 0
- Total PRs: 51
- Discussions: 14 (4 open)
- Last fetched: 2026-10-09

<details><summary>Coverage</summary>

- Index entries scanned: 155 (90 issues + 51 PRs + 14 discussions, all tagged SCAFFOLD)
- Themes extracted: 7 (4 open + 3 resolved)
</details>
