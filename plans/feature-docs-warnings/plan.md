# Work plan: feature-docs-warnings — Fix the Source-side docfx warnings

**Tier:** M  ·  **Status:** approved  ·  **Approved-at:** 2026-11-08 (user; after critic round 1 `weak`, objections folded)  ·  **Branch:** feature/docs-warnings
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

Base: `origin/master` @ `73dc8e871`. Worktree `C:\Worktrees\linq2db\docs-warnings`. Companion of `feature/docs-in-repo` (plan `feature-docs-in-repo`, D-6): that branch builds the docs with `--warningsAsErrors`, which needs this branch merged first. The docs build exists only on that branch, so the docs-build obligation here runs in the `docs-in-repo` worktree with this branch's diff applied there uncommitted.

## P1 Problem

The docs build (measured on `feature/docs-in-repo`, build 3 log `docs-in-repo-build3.log`, fork docfx tag `linq2db-20261107-cd2bf10`) reports 70 warnings, all from `Source/**`:
- 64× `Duplicate source file '…AnalyzerReleases.{Shipped,Unshipped}.md' in project '…CodeGenerators.csproj' / '…LinqToDB.Analyzers.csproj'` (4 per docfx entry × 16 entries). Cause, measured after restore: `dotnet msbuild <csproj> -getItem:AdditionalFiles` lists each file **2×** — `Source/CodeGenerators/CodeGenerators.csproj:31-32` and `Source/LinqToDB.Analyzers/LinqToDB.Analyzers.csproj:25-26` add them explicitly, and `Microsoft.CodeAnalysis.Analyzers` 5.9.0 `buildTransitive/Microsoft.CodeAnalysis.Analyzers.targets:334-340` adds them again when the files exist.
- 5× `InvalidFileLink` + 1× `InvalidBookmark` in `api/linq2db.tools` (SqlServer system-view schema docs): MS Docs markdown links copied into `Source/LinqToDB.Tools/DataProvider/SqlServer/Schemas/Schemas.xml` with targets relative to the MS Docs tree (`../../relational-databases/…md`, `./sys-objects-transact-sql.md?…`, `#remarks`) and from there into `Schemas.generated.cs`.

Not warned: 9 root-relative targets (`](/previous-versions/…)`, `](/fabric/…)`, `](/entra/…)`, `](/troubleshoot/…)`), `[permissions](#permissions)` and a relative `sys-server-resource-stats-azure-sql-database.md` link. Measured in the rendered tag-1 site (critic): links inside `<column>` text render as `<a>` (e.g. `ObjectSchema.Table.html:1090` `<a href="/previous-versions/…">` → 404 on linq2db.github.io; the six warned sites are all column text), while links inside a table `<description>` (XML `:227`, `:299`, `:2608`, `:3628`, `:3865`, `:5850`, and the column at `:1580`) render as literal markdown text, so docfx never sees them as links.

## P2 Success criteria

- SC-1 Each of the two analyzer projects carries each `AnalyzerReleases.*.md` once as `AdditionalFiles`, and release tracking (RS2000-series) still sees them. → TO-1, TO-2
- SC-2 `Schemas.xml` and `Schemas.generated.cs` contain no markdown link whose target is relative, root-relative or an in-page anchor; every rewritten target is an absolute `https://learn.microsoft.com/…` URL that resolves. → TO-3, TO-4
- SC-3 `Schemas.generated.cs` changes only in link targets (no other text). → TO-5
- SC-4 The docs build (docs-in-repo worktree, this diff applied) reports zero `Duplicate source file`, `InvalidFileLink` and `InvalidBookmark` warnings. → TO-6

## P3 Constraints & anti-goals (M/L)

- No change to any compiled code, public API, or analyzer behaviour; `Schemas.generated.cs` changes only inside XML doc comments.
- `Schemas.generated.cs` is not regenerated (`Schemas.tt` needs a live SQL Server and the VS T4 host; U-2). The same target map is applied to the XML (the generator's input) and the generated file, so a future regeneration reproduces the fix.
- Other absolute `docs.microsoft.com/en-us/…` links in those files are left alone (they redirect and do not warn).
- User-visible deltas vs master: none at runtime; XML-doc links in `linq2db.Tools` point at absolute MS Learn URLs; on the published API pages the column-hosted links (6 warned + the root-relative column links) become working absolute links, description-hosted ones stay literal text with an absolute target (P10).

## P4 Unknowns (M/L)

- U-1 Does release tracking still read the files after the explicit items go — the package adds them whenever they exist in `$(MSBuildProjectDirectory)` (`Microsoft.CodeAnalysis.Analyzers.targets:334-340`), both projects reference the package (`CodeGenerators.csproj:18`; `LinqToDB.Analyzers` via `Source/Analyzers.Common.props`), measured 2× before → expected 1× after; TO-1/TO-2 prove it — resolved-by probe (TO-1, TO-2)
- U-2 Can `Schemas.generated.cs` be regenerated instead of edited — no: `Schemas.tt:31` `LoadSqlServerMetadata(".", "master", SqlServerVersion.v2012)` needs a live server, the generator is the VS `TextTemplatingFileGenerator` (`LinqToDB.Tools.csproj:23-26`), not run by the build — resolved-by scout
- U-3 Are the generated-file occurrences copies of the XML text — measured: `[permissions](#permissions)` and the `sys-server-resource-stats` link appear once in the XML (`:227`, `:299`) and twice each in the generated file (`:702`/`:1097`, `:738`/`:1369`) with identical text (class + property docs), so a target-keyed map is position-independent — resolved-by probe
- U-4 Do the absolute targets exist — measured HTTP 200 for all 14 distinct target URLs (list in D-2) — resolved-by probe
- U-5 Does anything else consume the explicit `AdditionalFiles` lines — searched `AnalyzerReleases` across `Build/**`, `.github/**`, `Source/**/*.{props,targets,csproj}`, `Tests/**/*.csproj`: only `Build/Azure/scripts/verify-analyzer-delivery.ps1:136`, which reads the files from disk, not items; `.claude/knowledge-base/areas/CODEGEN/INDEX.md:30,102` describes them (KB, skill-maintained) — resolved-by scout

## P5 Decisions (M/L)

### D-1 — Drop the explicit `AdditionalFiles` items

- **chosen:** delete the `<ItemGroup>` with the two `AdditionalFiles` lines in both csprojs.
- **rejected:** `Remove` before `Include` — keeps two lines whose only effect is to undo the package; changing the package's include — not ours.
- **why this:** the package is the canonical source of the items; the explicit copy is redundant.
- **failure mode of the choice:** a future `Microsoft.CodeAnalysis.Analyzers` that stops auto-including would silently disable release tracking until the next rule change; TO-2's mutation is the check that tracking still reads the files today.

### D-2 — Target-keyed rewrite map applied to both Schemas files

- **chosen:** one map, applied by exact string replacement of the `](target)` text in both files:
  - `](#permissions)` → `](https://learn.microsoft.com/sql/relational-databases/system-dynamic-management-views/sys-dm-hs-database-log-rate#permissions)`
  - `](sys-server-resource-stats-azure-sql-database.md?view=azuresqldb-mi-current&amp;preserve-view=true)` → `](https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-server-resource-stats-azure-sql-database?view=azuresqldb-mi-current)`
  - `](#remarks)` → `](https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-column-store-segments-transact-sql#remarks)`
  - `](../../relational-databases/system-dynamic-management-views/sys-dm-pdw-nodes-transact-sql.md)` → `](https://learn.microsoft.com/sql/relational-databases/system-dynamic-management-views/sys-dm-pdw-nodes-transact-sql)`
  - `](../system-dynamic-management-views/sys-dm-pdw-exec-sessions-transact-sql.md)` → `](https://learn.microsoft.com/sql/relational-databases/system-dynamic-management-views/sys-dm-pdw-exec-sessions-transact-sql)`
  - `](../system-dynamic-management-views/sys-dm-pdw-exec-requests-transact-sql.md)` → `](https://learn.microsoft.com/sql/relational-databases/system-dynamic-management-views/sys-dm-pdw-exec-requests-transact-sql)`
  - `](./sys-objects-transact-sql.md?view=azure-sqldw-latest&amp;preserve-view=true)` → `](https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-objects-transact-sql?view=azure-sqldw-latest)`
  - `](/` → `](https://learn.microsoft.com/` (root-relative: stretch-database ×2 shapes, fabric ×3, entra, troubleshoot)
- **rejected:** resolving relative links against each table's `uri` in the `.tt` fix-up chain (`Schemas.tt:190-225`) — the right long-term home, but it changes the generator and still needs a regeneration that cannot run here (U-2).
- **why this:** mechanical, reviewable as a fixed map, identical in input and output.
- **failure mode of the choice:** a link target the map does not name survives; TO-3's sweep is the guard. `](/` is a prefix match, so the SQL text `]([wing], [startTime], [endTime])` (`Schemas.xml:3756`) — which does not start with `/` — is untouched.

## P6 Edit-points

- E-1 `Source/CodeGenerators/CodeGenerators.csproj` — remove the `AdditionalFiles` ItemGroup (`:30-33`).
- E-2 `Source/LinqToDB.Analyzers/LinqToDB.Analyzers.csproj` — remove the `AdditionalFiles` ItemGroup (`:24-27`).
- E-3 `Source/LinqToDB.Tools/DataProvider/SqlServer/Schemas/Schemas.xml` — D-2 map.
- E-4 `Source/LinqToDB.Tools/DataProvider/SqlServer/Schemas/Schemas.generated.cs` — D-2 map, doc comments only.

## P7 Impact map (M/L)

- Consumers of the `AdditionalFiles` items — searched `AnalyzerReleases` in `Build/**`, `.github/**`, `Source/**/*.{props,targets,csproj}`, `Tests/**/*.csproj`: `verify-analyzer-delivery.ps1:136` reads the files from disk — out-of-scope
- Corpus/KB prose describing the explicit items — searched `AdditionalFiles.*AnalyzerReleases` in `.claude/`: `knowledge-base/areas/CODEGEN/INDEX.md:30,102` — deferred: `/kb-refresh` (KB is skill-maintained)
- `LinqToDB.Analyzers.CodeFixes` — has no AnalyzerReleases files — out-of-scope
- `feature/docs-in-repo` (uncommitted working-tree edits in its worktree) edits the first lines of `LinqToDB.Analyzers.csproj` (`TreatAsLocalProperty`, `@@ -1,4 +1,5 @@`) and `Source/Analyzers.Common.props` (`@@ -11,6 +11,8 @@`); this branch edits `:24-27` — non-overlapping hunks — covered by E-2
- Markdown link targets in the Schemas files — searched `\]\([^h][^)]*\)` in both files: 18 hits in XML (17 links + the SQL text at `:3756`) — covered by E-3
- the same search in the generated file: 24 hits (23 links + the SQL text at `:25068`) — covered by E-4
- `Schemas.tt` link handling (`:190-225`, `:323`, `:422`) — unchanged (D-2 rejected) — out-of-scope

## P8 Test obligations (M/L)

- TO-1 SC-1: after restore, `dotnet msbuild <csproj> -p:Configuration=Release -getItem:AdditionalFiles` lists each `AnalyzerReleases.*.md` exactly once for `CodeGenerators` and `LinqToDB.Analyzers`; separates: on master the same command lists each 2× (measured) — providers: n/a — proof: red→green
- TO-2 SC-1: `dotnet build Source/CodeGenerators/CodeGenerators.csproj -c Release` and `dotnet build Source/LinqToDB.Analyzers/LinqToDB.Analyzers.csproj -c Release` green; control: mutation "delete the LINQ2DB0001 row from `Source/CodeGenerators/AnalyzerReleases.Unshipped.md`" turns the CodeGenerators Release build red, and mutation "delete the L2DB1004 row from `Source/LinqToDB.Analyzers/AnalyzerReleases.Shipped.md:20`" turns the LinqToDB.Analyzers Release build red, each with an RS2000-series release-tracking diagnostic, proving tracking still reads the files in both projects — providers: n/a — proof: control
- TO-3 SC-2: `Grep` `\]\([^h][^)]*\)` over both Schemas files returns only the SQL text at `Schemas.xml:3756` / `Schemas.generated.cs:25068` — providers: n/a — proof: red→green
- TO-4 SC-2: every distinct new target URL returns HTTP 200 (measured before editing, U-4; re-run after), and the fetched HTML of the three fragment targets contains `id="permissions"`, `id="remarks"`, `id="EnableTSQLServer"` (case-insensitive) — providers: n/a — proof: characterization
- TO-5 SC-3: a script compares old vs new `Schemas.generated.cs` line by line: same line count, every differing line differs only in a `](…)` target of the D-2 map — providers: n/a — proof: characterization
- TO-6 SC-4: in the docs-in-repo worktree, record `git diff --stat`, apply this branch's diff with `git apply <patch>` only, run `Docs/build.ps1`; assert 0 `Duplicate source file`, 0 `InvalidFileLink`, 0 `InvalidBookmark` and the docfx summary `0 warning(s)` (baseline build 3: 64 / 5 / 1, `70 warning(s)`); rendered-page checks: `api/linq2db.tools/*ObjectSchema.Table.html` contains `href="https://learn.microsoft.com/previous-versions/sql/sql-server/stretch-database/stretch-database"` (column-hosted, now a link) and `*SecuritySchema.ServerPrincipal.html` contains the literal `](https://learn.microsoft.com/entra/` (description-hosted, still text); revert with `git apply -R <patch>` and assert the recorded `git diff --stat` is unchanged — providers: n/a — proof: red→green

## P9 Verification gates

- G-01: pass (2026-11-08, working tree on `73dc8e871`, uncommitted) — TO-1: after restore, `-getItem:AdditionalFiles` lists each `AnalyzerReleases.*.md` 1× for both projects (2× on master, measured) · TO-2: Release builds of CodeGenerators and LinqToDB.Analyzers green; mutation "delete the LINQ2DB0001 row from `Source/CodeGenerators/AnalyzerReleases.Unshipped.md`" → `SqlBuilderAliasAnalyzer.cs(48,4): error RS2000: Rule 'LINQ2DB0001' is not part of any analyzer release`, exit 1; mutation "delete the L2DB1004 row from `Source/LinqToDB.Analyzers/AnalyzerReleases.Shipped.md:20`" → `ServerSideOnlyContractAnalyzer.cs(60,4): error RS2000: Rule 'L2DB1004' is not part of any analyzer release`, exit 1; both files restored with `git restore` (a byte-restore with a relative path had resolved against the primary clone's cwd and rewritten its identical copies — no change there, verified clean) · TO-3: `\]\([^h][^)]*\)` → only the SQL text at `Schemas.xml:3756` / `Schemas.generated.cs:25068` · TO-4: 14 targets HTTP 200; `id="permissions"`, `id="remarks"`, `id="EnableTSQLServer"` present · TO-5: generated file 28,707 lines before/after, 23 lines changed, all `///`, differing only in `](…)` targets; XML 17 replacements, generated 23 (= the measured link counts) · TO-6: patch applied with `git apply` in the docs-in-repo worktree (clean at `d219c5822` before), `Docs/build.ps1 -WarningsAsErrors` → `0 warning(s)`, 0 duplicate / InvalidFileLink / InvalidBookmark (build 3 baseline 64 / 5 / 1); `ObjectSchema.Table.html` has `href="https://learn.microsoft.com/previous-versions/sql/sql-server/stretch-database/stretch-database"`, `SecuritySchema.ServerPrincipal.html` keeps the literal `](https://learn.microsoft.com/entra/`; reverted with `git apply -R`, worktree clean again
- G-05: pass (2026-11-08) — `dotnet build Source/LinqToDB.Tools/LinqToDB.Tools.csproj -c Release -f netstandard2.0` → 0 warnings, 0 errors (XML-doc validation in Release included)
- G-06: pass — `git diff --stat`: 4 files, the E-1…E-4 edits only (csprojs −5 each, Schemas.xml 17 lines, Schemas.generated.cs 23 lines)
- G-07: n/a — no playground files
- G-09: pass (2026-11-08) — independent read (fable) of `origin/master...16b971877`: no defect; re-checked the package's `Exists()`-conditioned items, the only other `AnalyzerReleases` consumer (`verify-analyzer-delivery.ps1:136`, disk), the residual-link sweep, every relative target's resolution against `system-catalog-views/`, the two anchors' pages, `///`-only changes, no `<see cref>` exposure, disjoint hunks vs `feature/docs-in-repo`

## P10 Adjudicated (M/L)

- `Schemas.generated.cs` is hand-edited (doc comments only) rather than regenerated — regeneration needs a live SQL Server and the VS T4 host (U-2); the same map is applied to the generator's XML input.
- Markdown inside a table `<description>` renders as literal text on the API site (critic, measured) — making it render is a `Schemas.tt` / docfx XML-doc formatting matter, out of scope; this branch only makes its targets absolute.
- Absolute `docs.microsoft.com/en-us/…` links elsewhere in the Schemas files are not migrated to `learn.microsoft.com` — they redirect and do not warn.

## P11 Amendments (M/L)

_None._

## P12 Critic verdict (M/L)

- Round 1 (fable, 2026-11-08): **weak**. Objections folded: (1) the "11 silently broken links" delta is false for description-hosted links, which render as literal text → P1, P3 rewritten, P10 line, TO-6 rendered-page checks; (2) TO-6's revert could wipe the companion's uncommitted edits in the same files → `git apply` / `git apply -R` only, `git diff --stat` before = after; (3) TO-2's control covered one project → L2DB1004 mutation for LinqToDB.Analyzers; (4) TO-6 asserts the `0 warning(s)` summary too; (5) TO-4 checks fragment ids. Critic confirmed D-1 by construction: the package's two `Exists()`-conditioned items are static, spelled like the explicit ones, no other consumer of the items; RS2008 + `TreatWarningsAsErrors` make D-1's failure mode loud. Searched: package targets, `AdditionalFiles` / `AnalyzerReleases` / `RS20\d\d` across the tree, all link shapes in both Schemas files (no blind spot in `[^h]`), enclosing tables of every relative link, rendered `_site-tag1` pages.
