---
area: DOCS
kind: area-index
sources: [code]
confidence: high
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
coverage_tier_1: 6/6
coverage_tier_2: 25/25
---

# DOCS

The docfx documentation site (https://linq2db.github.io), moved into the repository by #6265. Hand-written articles under `docs/source/articles/` plus an API reference generated at build time from 17 metadata entries over the `Source/` projects. There are no C# types in this area. Publishing is done by `.github/workflows/docs.yml`, owned by [BUILD](../BUILD/INDEX.md) and read here for context only.

## Key types

None. The artifacts are JSON/YAML/Markdown/PowerShell. Identifiers that matter: `assemblyUids` and `assemblyUidOverride` (docfx options from the custom build), `filter.yml` `apiRules`, `docfx-version.json` (`tag`, `url`, `sha256`, `sourceCommit`).

## Subsystems

### Build pipeline (`docs/build.ps1`)

- Reads the pin `docs/docfx-version.json` (tag `linq2db-20261108-fa89ea9`, SHA-256 verified), downloads `docfx.zip` from the MaceWindu/docfx fork on first use and caches it at `.build/docfx/<sha256>/`. A hash mismatch deletes the zip and throws.
- Cleans `.build/docs/_site` and `docs/source/api` first.
- Pre-builds `Source/LinqToDB.FSharp/LinqToDB.FSharp.fsproj` in Release with `-p:RunAnalyzersDuringBuild=false -p:EnforceCodeStyleInBuild=false`. Docs reads the F# API from the built DLL under `.build/bin/LinqToDB.FSharp/Release/`, and the flags avoid IDE0390/IDE0391 errors on newer Roslyn.
- Runs `dotnet docfx.dll docs/source/docfx.json`, adding `--warningsAsErrors` when `-WarningsAsErrors` is passed (CI mode). Must run from the repo root so `global.json` resolves for docfx's inner `dotnet restore`.

### Why a custom docfx

Many assemblies declare the same namespaces (mostly `LinqToDB`), and docfx UIDs derive from the fully-qualified name alone, so pages collide (dotnet/docfx#8966). The pinned fork carries dotnet/docfx#11090: top-level `assemblyUids` (12 assemblies: `linq2db`, `linq2db.Extensions`, `linq2db.Compat`, `linq2db.FSharp`, `linq2db.Remote.*`, `linq2db.Tools`, `linq2db.Scaffold`) and per-entry `assemblyUidOverride` for the four EF Core entries, which all build an assembly named `linq2db.EntityFrameworkCore`. UIDs look like `linq2db.Tools::LinqToDB.Tools...`. `::` becomes `--` in file names, and displayed namespaces stay unqualified (`assemblyLabel` unset). `linq2db.Identity` is deliberately not in `assemblyUids`. The fork's Roslyn must be at least the version `Source/CodeGenerators` builds against, else `CS8795` and "No .NET API detected". `docs/README.md` says to drop the download once the options ship in released docfx.

### API reference generation (`docs/source/docfx.json`)

17 `metadata` entries, each with `filter: filter.yml` and its own `output` folder `api/<name>`:

| Output | Source | Notes |
|---|---|---|
| `api/linq2db` | `Source/LinqToDB/LinqToDB.csproj` | `TargetFramework=net10.0` |
| `api/linq2db.extensions`, `.compat`, `.tools`, `.scaffold`, `.identity` | matching `Source/LinqToDB.*` csproj | net10.0 |
| `api/linq2db.remote.grpc`, `.httpclient.client`, `.httpclient.server`, `.signalr.client`, `.signalr.server` | `Source/LinqToDB.Remote.*` csproj | net10.0 |
| `api/linq2db.remote.wcf` | `Source/LinqToDB.Remote.Wcf` csproj | no TFM override |
| `api/linq2db.fsharp` | built DLL `.build/bin/LinqToDB.FSharp/Release/netstandard2.0/linq2db.FSharp.dll` | single TFM on purpose. `references` take FSharp.Core and Microsoft.Bcl.AsyncInterfaces from the net462 output |
| `api/linq2db.efcore.3`, `.8`, `.9`, `.10` | `Source/LinqToDB.EntityFrameworkCore/LinqToDB.EntityFrameworkCore.EF{3,8,9,10}.csproj` | `assemblyUidOverride` `linq2db.EntityFrameworkCore.EF<n>` |

docfx documents one TFM per project. The `TargetFramework=net10.0` property is global so it reaches referenced projects, and the two netstandard2.0 analyzer projects keep theirs via `TreatAsLocalProperty` (dotnet/docfx#10772). `filter.yml` has one `apiRules` exclusion: `System.Object` types (`uidRegex: .*System\.Object`).

### Site build and theme

`build.content`: `api/**`, `articles/**`, `toc.yml`, `*.md`. `resource`: `images/**`, png/jpg, `articles/cli-help.txt`, `.nojekyll`. `dest` is `../../.build/docs/_site`. Templates: `default`, `modern`, `templates/custom` (`main.css`, `main.js`). Post-processor `ExtractSearchIndex`, search enabled, contribution links disabled. `docs/source/index.md` is a single `[!include]` of the repo root `README.md`, and the Contributing article (`articles/project/contrib.md`, `uid: contrib`) is a single `[!include]` of the repo root `CONTRIBUTING.md` plus a "See also" link to `xref:newissue`, so edits to those root files affect the site and trigger the docs workflow.

### Navigation

- `docs/source/toc.yml`: top bar "Articles" (`articles/`) and an "API Documentation" dropdown listing the 17 API entries (labels such as "Linq To DB for Entity Framework Core 10"). Adding a metadata entry requires a matching entry here.
- `docs/source/articles/toc.yml`: Release Notes (external wiki link), Get Started, General Topics, SQL, How To, CLI Scaffold Tool (`cli.md`), T4 Templates (Obsoleted, `t4.md`), FAQ, Project. Each section has its own `toc.yml` (merge has a nested one).

### Article taxonomy (`docs/source/articles/`)

| Section | Files | Topic |
|---|---|---|
| get-started | `install/index.md`, `full-dotnet/existing-db.md`, `asp-dotnet-core/index.md` | Install, scaffold from existing DB, ASP.NET Core example |
| general | `databases.md`, `managing-data-connection.md`, `interceptors.md`, `metrics.md`, `video.md` | Provider-name table per database, `DataConnection` vs `DataContext` lifetime, interceptor interfaces (`ICommandInterceptor`, `IConnectionInterceptor`, `IDataContextInterceptor`, `IEntityServiceInterceptor`, `IExceptionInterceptor`, `IUnwrapDataObjectInterceptor`, since 4.0.0), `ActivityService`/`IActivity`/`ActivityID` telemetry (OpenTelemetry compatible), videos |
| sql | `join-operators.md`, `cte.md` (`AsCte`), `bulk-copy.md` (`BulkCopy` overloads), `window-functions-(analytic-functions).md` (`Sql.Ext.*.Over()...ToValue()`), `query-extensions.md` (`QueryExtensionScope`, `TableID`, `Sql.TableAlias/TableName/TableSpec`), `merge/` (4 articles: API, background, description, migration) | SQL feature guides |
| how-to | `using-mapvalue-attribute-to-control-mapping.md` (`uid: mapvalue`), `teach-linq2db-convert-custom-net-code-to-sql.md` (no `uid`) | Mapping and custom-conversion recipes |
| project | `contrib.md` (`uid: contrib`), `issue-reporting.md` (`uid: newissue`) | Contribution and issue reporting |
| top level | `cli.md`, `cli-help.txt`, `t4.md`, `faq.md`, `links.md` | CLI scaffold tool (`cli-help.txt` is a help dump shipped as a resource, not an article), obsolete T4, FAQ, links |

Articles use `uid:` front-matter for `xref` links (`Interceptors`, `databases`, `Metrics`, `Bulk-Copy`, `CTE`, `cli`, `scaffold-t4`, `mapvalue`, `contrib`, `newissue`, `Merge`, `Merge-API-Background`, `Merge-API-Description`, `Merge-API-Migration`). API links use assembly-qualified UIDs such as `xref:linq2db::LinqToDB.ProviderName`.

### Article contents read in full (coverage-fill)

- `cli.md` (`uid: cli`, 755 lines): the `linq2db.cli` dotnet global tool (`dotnet tool install -g linq2db.cli`, invoked as `dotnet linq2db` or `dotnet-linq2db`). Commands: `help`, `help scaffold`, `scaffold <options>`, `template [-o path]` (emits the base T4 template). Options come from the command line, or from a JSON response file via `-i`, and a command-line value wins over the file. Customization is selected by `--customize <file>`: a `.dll` is loaded as an assembly containing a subclass of `LinqToDB.Scaffold.ScaffoldInterceptors` (reference `linq2db.Tools`), and any other extension is compiled as a T4 template. The scaffold pipeline has four stages (schema load, data model, code model, source code) with three interceptor groups: schema load (`GetTables`, `GetViews`, `GetForeignKeys`, `GetProcedures`, `GetTableFunctions`, `GetScalarFunctions`, `GetAggregateFunctions`, each called only if the object type is enabled via `--objects`), type mapping (`GetTypeMapping(DatabaseType, ITypeParser, TypeMapping)`, called once per database type) and data model (`PreprocessEntity(ITypeParser, EntityModel)`). The bulk of the file is a reference dump of the schema records (`Table`, `View`, `ForeignKey`, `Column`, `StoredProcedure`, ...), the model classes (`EntityModel`, `ColumnModel`, `FindTypes` flags, `AssociationModel`, `ClassModel`, `Modifiers`) and the metadata classes (`EntityMetadata`, `ColumnMetadata`, `FunctionMetadata`, `AssociationMetadata`). Those mirror `Source/LinqToDB.Scaffold` types by hand and can drift silently from them (not cross-checked here).
- `faq.md` (no front matter, no `uid`): three topics. Async model: internal awaits use `ConfigureAwait(false)` and `Configuration.ContinueOnCapturedContext = true` flips it. Connection setup hooks: `DataOptions.UseBeforeConnectionOpened` / `UseAfterConnectionOpened` (sync plus async variant), recommended over a connection factory or interceptor because provider auto-detection also uses them. Mapping without attributes: nullability of reference types is lost without NRT annotations, table and column names must match, `.TableName()` overrides the table, all POCO columns are written. Calculated columns need `[Column(SkipOnInsert = true, SkipOnUpdate = true)]`. SQL Server spatial types: package choice per runtime (`Microsoft.SqlServer.Types`, `dotMorten.Microsoft.SqlServer.Types` v1.x for `System.Data.SqlClient` and v2.x for `Microsoft.Data.SqlClient`, `Microsoft.SqlServer.Server`), `SqlServerTools.ResolveSqlTypes`, and the "Can't create ... type" error fixed by a binding redirect on .NET Framework or an `AssemblyLoadContext.Default.Resolving` handler on .NET Core.
- `general/video.md`: two YouTube embeds ("LINQ to SqlServer", "LINQ CRUD Operations"). No `uid`, raw HTML, no prose.
- `get-started/asp-dotnet-core/index.md` (author khahn): walkthrough with `dotnet new webapp`, packages `linq2db.Extensions` and `System.Data.SQLite.Core`, a `DataConnection` subclass taking `DataOptions<T>`, `services.AddLinqToDBContext<T>(...)` with `UseSQLite`/`UseDefaultLogging(provider)`, per-request scope by default (`ServiceLifetime` is the last parameter), `AddLinqToDBContext<TContext, TContextImplementation>` for an interface, and a controller using `ToArrayAsync`, `SingleOrDefaultAsync`, `DeleteAsync`, `Set(...).UpdateAsync`, `InsertAsync`. Registration lives in `Startup.cs` (the pre-.NET 6 hosting model although `dotnet new webapp` generates `Program.cs` only). It carries two different namespace spellings for the same DI API: `LinqToDB.Extensions.DependencyInjection` in the first sample and `LinqToDB.DependencyInjection.DependencyInjection` in the quick-start comments.
- `get-started/full-dotnet/existing-db.md` (author sdanyliv): .NET Framework console app against Northwind, `Install-Package linq2db.SqlServer`, model generated via the T4 template `CopyMe.SqlServer.tt.txt`. Starts with a warning that T4 is obsolete and links `xref:cli`, yet the body still teaches T4 and links `xref:scaffold-t4`. `App.config` uses `System.Data.SqlClient`. Sample code lives in the external `linq2db/examples` repo.
- `get-started/install/index.md`: 11-line stub: install `linq2db` plus an ADO.NET provider. Shows `nuget install linq2db`, no `dotnet add package`.
- `t4.md` (`uid: scaffold-t4`, 589 lines): the obsolete T4 model generator. Opens with a `[!WARNING]` pointing at `linq2db.cli` and `xref:cli`. Flow: `Install-Package linq2db.<PROVIDER_NAME>` installs `linq2db`, the T4 templates, `CopyMe.<DB_NAME>.tt.txt` and the provider package, copy that into a `.tt` file (custom tool `TextTemplatingFileGenerator`), edit schema-load options, call `LoadMetadata()`, customize, call `GenerateModel()`. SDK-style projects get nuget content as references into the nuget cache, so the `.tt` must be created by hand and `*.ttinclude` files must not be edited. The bulk is an option catalog in code blocks: schema load via `LinqToDB.SchemaProvider.GetSchemaOptions` (`GetTables`, `GetForeignKeys`, `GetProcedures`, `IncludedSchemas`, `LoadTable`, `LoadProcedure`, `UseSchemaOnly`, `GetAssociationMemberName`), generation options by group (global/NRT, data context, schemas, table mappings, columns, associations, procedures, pluralization, naming), provider-specific options (SQL Server `AddReturnParameter`, PostgreSQL `GenerateCaseSensitiveNames`, Sybase `GenerateSybaseSystemTables`), customization calls (`GetTable`, `GetColumn`, `GetFK`, `SetTable`, `Model.Usings`), the data structures (`Table`, `Column`, `ForeignKey`, `Procedure`, `Parameter`, `AssociationType`) and `Equatable.ttinclude` (`IsEquatable`, `EqualityPropertiesFilter`, default compares primary-key columns). It is a hand-written mirror of the `LinqToDB.Templates` ttinclude surface and `GetSchemaOptions`, not generated, so it can drift (not cross-checked here). `GenerateSqlServerFreeText` is documented as obsolete in favour of the extensions from PR 1649. Its `GetSchemaOptions` list references `Common.Configuration.SqlServer.UseSchemaOnlyToGetSchema`, a legacy static config name.
- `links.md`: 5 bullets (NuGet profile, Azure DevOps pre-release feed `dev.azure.com/linq2db/linq2db`, GitHub org, source repo, `linq2db/examples`). No `uid`, no front matter.
- `how-to/using-mapvalue-attribute-to-control-mapping.md` (`uid: mapvalue`): `MapValue` on an enum mapped to a `CHAR(1)` status column (single-letter codes O, I, R, C), repeated `MapValue` attributes with `IsDefault = true` for several DB values per member (`Gender`), `MapValue(null)` for NULL, integer-backed enums need no attribute, reading values back via `ConvertTo<string>.From(...)` or `MappingSchema.Default.EnumToValue()`, and a CHECK-constraint note versus a lookup table. The scaffold step still links the `linq2db.t4models` NuGet and tells T4 users to set `Tables["Issue"].Columns["Status"].Type`. Samples use `DataModel`, `db.Issues`, `db.People.Insert(() => ...)` in the pre-`DataOptions` style. A stray `<` ends step 1 of the numbered list.
- `how-to/teach-linq2db-convert-custom-net-code-to-sql.md` (no `uid`, links `xref:mapvalue`): four extension points. `Sql.ExpressionAttribute` (`PreferServerSide`, `ServerSideOnly`, with a `{0} BETWEEN {1} AND {2}` example), `Sql.FunctionAttribute` (method name used when the name is omitted), `ExpressionMethodAttribute` (a static method returning `Expression<Func<...>>`, applicable to properties, with `In` and `AgeInDays` examples), `LinqToDB.Linq.Expressions.MapMember()` (used internally for hundreds of BCL members, example `string.IsNullOrWhiteSpace`) and `MappingSchema.SetValueToSqlConverter()` (Informix bool t/f, `SqlDecimal.IsNull`). Section anchors are `#sqlexpression`, `#sqlfunction-attribute`, `#expressionmethod`, `#mapmember`, `#setvaluetosqlconverter`. The `SqlFunctionAttributeTest` sample defines `IsNumeric` but calls `SqlFunctions.IsNumeric`, and the BETWEEN prose notes `Sql.Between` already exists. Output SQL samples are SQL Server 2012 style.
- `project/contrib.md` (`uid: contrib`): front matter, one `[!include[intro](../../../../CONTRIBUTING.md)]` and a "See also" bullet to `xref:newissue`. Content is the root `CONTRIBUTING.md`.
- `project/issue-reporting.md` (`uid: newissue`): lists what an issue needs (linq2db version, database and version, provider and version, code sample plus SQL, explanation), prefers a PR with a test using the `Tests/Model` data model, and a "Generating the test" recipe: clean the `linq2db` folder under the user Temp directory, set `LinqToDB.Common.Configuration.Linq.GenerateExpressionTest = true`, run the query, attach the generated `ExpressionTest.0.cs`. The property exists in `Source/LinqToDB/Common/Configuration.cs` (line 205, backed by `Options.GenerateExpressionTest`), so the recipe is current.
- `sql/merge/merge-api.md` (`uid: Merge`): overview, "available since linq2db 1.9.0", supersedes the old API. Defines the merge elements (target, source, match rule, ordered operations, operation condition) and three operation groups: matched (`Update`, `Delete`, Oracle-only `Update Then Delete`), not matched (`Insert` only), not matched by source (SQL Server only, `Update By Source` / `Delete By Source`). Within a group order matters and only the last operation may omit its condition. The worked example uses `UsingTarget().OnTargetKey().DeleteWhenMatchedAnd(...).UpdateWhenMatchedAnd(...)`. Links to the other three articles by xref and to per-database anchors in Background.
- `sql/merge/merge-api-background.md` (`uid: Merge-API-Background`): `MERGE INTO` as in SQL:2003 with SQL:2008 extensions (`WHEN MATCHED AND <cond>`, `DELETE`), plus per-provider support and limitations. Covered: SQL Server 2008+ (by-source operations, one operation of each type, max three operations, identity insert), IBM DB2 (LUW only tested, no associations in match), Firebird 2.1-2.5 (SQL:2003) and 3.0 (SQL:2008) with client-source type caveats, Oracle (only two operations: `Insert` plus `Update` or `UpdateWithDelete`, no plain `Delete`, match columns cannot be updated, empty enumerable source sends nothing and returns 0), Sybase/SAP ASE (server crashes on some queries, delete-only merge does not work, affected-count can be too high), Informix (no associations, `BYTE` client-source caveat), SAP HANA 2 (`Update` must precede `Insert`) and PostgreSQL 15+ ("nothing substantial"). The provider list is fixed to these eight and does not mention other providers that implement merge. It contains a hand-maintained table of contents duplicating the headings.
- `sql/merge/merge-api-description.md` (`uid: Merge-API-Description`): the full builder API with signatures for each group: `Merge`, `MergeInto`, `Using`, `UsingTarget`, `On`, `OnTargetKey`, `InsertWhenNotMatched[And]`, `UpdateWhenMatched[And]`, `DeleteWhenMatched[And]`, `UpdateWhenNotMatchedBySource[And]`, `DeleteWhenNotMatchedBySource[And]`, `UpdateWhenMatched[And]ThenDelete`, `Merge` and `MergeAsync(token)`. Builder interfaces named: `IMergeableUsing`, `IMergeableOn`, `IMergeable`, `IMergeableSource`. Each operation method returns a new builder, so a discarded result silently drops the operation. Validation throws `LinqToDBException` before execution. Operations are emitted in call order. Defaults: with no setter, insert skips `SkipOnInsert` members and `IsIdentity` on providers without identity insert, update skips `SkipOnUpdate` and `IsIdentity`. `deleteCondition` of `UpdateWhenMatchedThenDelete` is evaluated against the updated record values.
- `sql/merge/merge-api-migration.md` (`uid: Merge-API-Migration`): maps the four old `Merge` overloads (on `DataConnection` or `ITable<T>`, with `predicate`, `delete` flag, `IEnumerable<T>` source) to `GetTable<T>().Merge().Using(...).OnTargetKey()...` chains, with `TableName`, `DatabaseName`, `SchemaName` replacing the old name parameters. Breaking change: the new API always sends the command even for an empty source (needed for by-source operations), except Oracle, Sybase and SAP HANA which keep the no-op.

## Interactions

- Docs workflow (`.github/workflows/docs.yml`, [BUILD](../BUILD/INDEX.md)): a PR runs the build only when `docs/`, root `README.md`/`CONTRIBUTING.md`, `Directory.Build.props`, `Directory.Packages.props`, `global.json`, `Source/Analyzers.Common.props`, `Source/**/Directory.Build.props` or the workflow changed. The decision is made in a `changes` job so a skipped check still satisfies branch protection.
- Build job: windows-2025, .NET 10.x, cache keyed on `docs/docfx-version.json`, `./docs/build.ps1 -WarningsAsErrors`, uploads the `docs-site` artifact (7 days, hidden files included for `.nojekyll`).
- Deploy job: ubuntu, `docs` environment, `DOCS_DEPLOY_KEY`. It rsyncs to `linq2db/linq2db.github.io` master and commits with a message of the form "Docs: linq2db TAG". Triggers: a non-prerelease release (tags containing a hyphen are skipped) or `workflow_dispatch` with `deploy=true` from a `v*` tag.
- `docs/Docs.csproj` (`Microsoft.Build.NoTargets/3.7.0`) is a Solution Explorer visibility project only. It strips all `PackageReference`/`Compile` injected by `Directory.Build.props`, excludes `source/api/**` and `source/obj/**`, and sets `IsPackable=false`.
- API pages mirror the public surface of the `Source/` projects, so public-API changes flow into the site on the next release.
- `cli.md` documents the `Source/LinqToDB.Scaffold` / `linq2db.Tools` interceptor surface by hand, so changes to those types need a manual article update (no generation link). `t4.md` likewise hand-mirrors `GetSchemaOptions` (`Source/LinqToDB/SchemaProvider/`) and the `LinqToDB.Templates` ttinclude options. The Merge articles hand-mirror the merge builder extension methods and interfaces, and `issue-reporting.md` depends on `Configuration.Linq.GenerateExpressionTest` in `Source/LinqToDB/Common/Configuration.cs`.
- xref graph between articles: `existing-db.md` and `t4.md` link `xref:cli`, `existing-db.md` links `xref:scaffold-t4`, `teach-linq2db-...md` links `xref:mapvalue`, `contrib.md` links `xref:newissue`, `merge-api.md` links the three other merge UIDs.

## Inbound / outbound dependencies

- Inbound: BUILD (workflow, `Directory.Build.props`, the Roslyn pin in `Directory.Packages.props`, `global.json`), and the root `README.md` and `CONTRIBUTING.md` (included).
- Outbound: every `Source/LinqToDB*` project listed above (API generation), the `MaceWindu/docfx` fork release asset, and `linq2db/linq2db.github.io` (deploy target). Articles also link out to the external `linq2db/examples` repo, the NuGet profile and Azure DevOps pre-release feed, and vendor MERGE documentation.

## Known issues / debt

- Depends on an unreleased docfx fork (dotnet/docfx#11090). The pin needs a manual refresh during release prep (`/release-deps`) and a Roslyn-version check.
- Build is tested on Windows only. The F# pre-build compiles `LinqToDB` across TFMs just to read one API surface.
- `linq2db.Remote.Wcf` and the EF entries do not set `TargetFramework`, so their API reflects the project first TFM.
- `LinqToDB.Identity` is outside `assemblyUids` by design. A future reference into it from another entry would produce unqualified UIDs and silently lose links.
- Stale or inconsistent article content found by the coverage-fill read: `cli.md` says "Requres .NET 6 or higher" but also tells users not to target .NET Framework because the tool "use .net core 3.1+", and has typos (`--custmize`, "multi-stange"). `asp-dotnet-core/index.md` uses `Startup.cs` and two namespace spellings for the DI extensions. `existing-db.md` is warned obsolete yet teaches T4 with .NET Framework 4.5.1 and `System.Data.SqlClient`, and links `xref:scaffold-t4`, which resolves to `t4.md` (read in this run). `faq.md` builds `PRAGMA KEY '{key}'` by string interpolation (an encryption-key example, not user input). `faq.md`, `video.md`, `links.md` and the how-to "teach" article have no `uid`, so they cannot be xref targets.
- Merge articles: `merge-api-description.md` and `merge-api.md` contain wiki-style links `[[support|Merge-API-:-Background-Information-and-Providers-Support]]` that docfx does not render (leftover from the GitHub wiki, the correct target is `xref:Merge-API-Background`). `merge-api-description.md` has a garbled sentence in the `setter` section of `InsertWhenNotMatched` (a duplicated paragraph pasted into "set ex...pressions"), its `UpdateWhenMatchedThenDelete` example calls a nonexistent `.From(source)` instead of `.Using(source)`. `merge-api-background.md` has mismatched quotes around `UpdateWithDelete` and lists only eight providers, so it is silent on the other providers that implement merge. `merge-api-migration.md` examples rely on `DeleteWhenNotMatchedBySourceAnd`, which per the Background article is SQL Server only, so the old-to-new mapping is not portable to other databases.
- `t4.md` is a large hand-maintained option list for an obsolete tool and has a documentation-only legacy reference (`Common.Configuration.SqlServer.UseSchemaOnlyToGetSchema`). `using-mapvalue-...md` and the "teach" article still describe T4 scaffolding and the `linq2db.t4models` package, and pair T4 with pre-`DataOptions` sample code (`DataModel`, `InlineParameters`).
- Duplicated-content hazard: `contrib.md` is only an include of `CONTRIBUTING.md`, so its text is reviewed under the root file and links inside it resolve relative to the root, not to `docs/`.

## See also

- [BUILD](../BUILD/INDEX.md), `docs/README.md` (canonical description of the custom docfx build).

## Pointers

- `docs/source/docfx.json`, `docs/build.ps1`, `docs/docfx-version.json`, `docs/source/filter.yml`, `.github/workflows/docs.yml`.
- `docs/source/articles/cli.md` (scaffold CLI and interceptor reference), `docs/source/articles/faq.md`, `docs/source/articles/t4.md` (obsolete T4 option catalog), `docs/source/articles/sql/merge/` (Merge API articles).

<details><summary>Coverage</summary>

Tier 1: 6/6 read in full: `docs/source/docfx.json`, `docs/build.ps1`, `docs/Docs.csproj`, `docs/README.md`, `docs/source/toc.yml`, `docs/source/articles/toc.yml`.

Also read (outside the Tier-1 list): `docs/docfx-version.json`, `docs/source/filter.yml`, `docs/source/index.md`, `.github/workflows/docs.yml` (context), and the section `toc.yml` files (general, sql, sql/merge, get-started, how-to, project).

Tier 2: 9/25 articles (first 30-40 lines each): `general/databases.md`, `general/interceptors.md`, `general/managing-data-connection.md`, `general/metrics.md`, `sql/bulk-copy.md`, `sql/cte.md`, `sql/join-operators.md`, `sql/query-extensions.md`, `sql/window-functions-(analytic-functions).md`.

Not read (listed in DEFERRED-COVERAGE): `cli.md`, `faq.md`, `links.md`, `t4.md`, `general/video.md`, 3 get-started articles, 2 how-to articles, 2 project articles, 4 sql/merge articles. `cli-help.txt` is a resource file and is not counted.

Tier 3 (not read): `docs/source/images/*`, `templates/custom/public/*`, `get-started/full-dotnet/static/*.png`, `.nojekyll`, `.gitignore`.

Coverage-fill (this run) -- Tier 2 now 15/25. Read (this run), each in full:
- `docs/source/articles/cli.md`: CLI commands, response file, `--customize`, interceptor groups and model/metadata reference dump.
- `docs/source/articles/faq.md`: async model, connection hooks, attribute-less mapping, calculated columns, SQL Server spatial types.
- `docs/source/articles/general/video.md`: two YouTube embeds, no prose.
- `docs/source/articles/get-started/asp-dotnet-core/index.md`: DI registration walkthrough, `Startup.cs` era, inconsistent namespaces.
- `docs/source/articles/get-started/full-dotnet/existing-db.md`: T4-based .NET Framework walkthrough with an obsolescence warning.
- `docs/source/articles/get-started/install/index.md`: install stub.

Coverage-fill 2 (this run) -- Tier 2 now 25/25, queue empty. Read (this run), each in full:
- `docs/source/articles/t4.md`: obsolete T4 generator, `GetSchemaOptions` and generation option catalog, customization API, `Equatable.ttinclude`.
- `docs/source/articles/links.md`: five external links, no uid.
- `docs/source/articles/how-to/using-mapvalue-attribute-to-control-mapping.md`: `MapValue` enum mapping recipe (`uid: mapvalue`).
- `docs/source/articles/how-to/teach-linq2db-convert-custom-net-code-to-sql.md`: `Sql.Expression`, `Sql.Function`, `ExpressionMethod`, `MapMember`, `SetValueToSqlConverter` recipes.
- `docs/source/articles/project/contrib.md`: include of root `CONTRIBUTING.md` plus a link to `newissue`.
- `docs/source/articles/project/issue-reporting.md`: issue checklist and `GenerateExpressionTest` recipe (property verified in `Source/LinqToDB/Common/Configuration.cs`).
- `docs/source/articles/sql/merge/merge-api.md`: Merge overview and operation groups.
- `docs/source/articles/sql/merge/merge-api-background.md`: SQL:2003/2008 syntax and per-provider limitations.
- `docs/source/articles/sql/merge/merge-api-description.md`: builder API reference with signatures.
- `docs/source/articles/sql/merge/merge-api-migration.md`: old-to-new Merge API mapping.

Cross-area read for verification only: `Source/LinqToDB/Common/Configuration.cs` (grep of `GenerateExpressionTest`). Article claims about `Source/` types (scaffold models, `GetSchemaOptions`, merge builder interfaces) were not cross-checked against the code.
</details>
