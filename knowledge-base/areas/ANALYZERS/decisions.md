---
area: ANALYZERS
kind: decisions
sources: [git, gh-prs, wiki]
confidence: medium
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# ANALYZERS -- decisions

## Decisions
- **Ship user-facing rules as the `linq2db.Analyzers` package, consumed through a plain linq2db dependency** -- #5703 created the package; #5720 reverted bundling into `linq2db` and restored a packable project with a dependency. Satellite packages keep `analyzers` out of PrivateAssets. Record: [2026-analyzers-package-delivery](../../history/decisions/2026-analyzers-package-delivery.md).
- **Rule ids are `L2DB1xxx` in category `LinqToDB`; opt-out via `EnableLinqToDBAnalyzers=false` or per-rule `.editorconfig` severity** -- Renamed from LINQ2DB1001 before any release. Record: same as above.
- **Roslyn pinned to 4.8.0** -- matches the Roslyn bundled with the lowest supported SDK (.NET 8). Record: same as above.
- **Code fix uses `DocumentBasedFixAllProvider`, not `BatchFixer`** -- BatchFixer dropped clustered edits. Record: same as above.
- **L2DB1001 fix is type-preserving by default** -- withholds itself where the `Sql.Window` return type differs from the legacy `ToValue<TR>()` slot; opt-in via `linq2db.L2DB1001.apply_fix_on_return_type_mismatch`. Source: wiki L2DB1001.
- **L2DB1001 targets genuine window chains only** -- fires on chains containing `.Over()`, not on legacy `Sql.Ext` calls that are not window functions. Source: wiki L2DB1001.
- **L2DB1002 has no code fix** -- the intended duration cannot be inferred (1.5 s against a whole-second column could mean 1 s, 2 s, or a column re-declared in milliseconds). Source: wiki L2DB1002; PR #5873.
- **L2DB1002 reads the unit only from the member attribute** -- accepted limitation; mapping-schema and custom `IMetadataReader` units are not read. Source: wiki L2DB1002.
- **L2DB1002 assumes a linq2db queryable** -- not provider-aware; projects querying through another LINQ provider or in-memory `Compile()` are told to set severity `none`. Source: wiki L2DB1002.
- **Two analyzer hosts stay separate by design** -- the user-facing `L2DB1xxx` rules (Source/LinqToDB.Analyzers) and the repo-internal `LINQ2DB0001` rule (Source/CodeGenerators) are not shared; internal rules do not ship. Boundary: corpus rule in AGENTS.md / agent-rules.md.
- **Repo IDE analyzers and xml-doc validation run in Release only** -- PR #5516 gated `EnforceCodeStyleInBuild`, `GenerateDocumentationFile` to `== 'Release'`. Boundary (build config, not shipped rules). Record: [2026-release-only-analyzers](../../history/decisions/2026-release-only-analyzers.md).

## Promotion status
- Decision-flavored PRs in scope: #5703, #5720, #5770 (new package and wiring), #5870 and #5873 (new rules). Only the delivery shape has a `history/decisions/` record. Not evaluated: "breaking" label, `## Decision` body section, and the >30-files rule, since the index holds body_excerpt and no file counts. None of the six carries a breaking label in the index.

## Dead ends (not decisions; from auto-memory, not re-verified)
- Decimal-overflow variant of the L2DB1002 idea judged unreachable.
- "#5870 ServerSideOnly markers inert" recorded as a dead end.

<details><summary>Coverage</summary>

- Decisions listed: 10 (2 linked to history/decisions records)
- PRs checked for decision signals: 6
</details>
