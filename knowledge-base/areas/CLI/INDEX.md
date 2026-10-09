---
area: CLI
kind: area-index
sources: [code]
confidence: high
last_verified: 2026-10-09
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
coverage_tier_1: 14/14
coverage_tier_2: 59/76
---

# CLI

`dotnet-linq2db` -- the scaffolding dotnet tool. Invoked as `dotnet linq2db <command>` or `dotnet-linq2db <command>`. Ships as the `linq2db.cli` NuGet package (package type: `DotnetTool`). Targets `net8.0`, `net9.0`, `net10.0`. Besides scaffolding it is now also an agent-facing database tool: read-only `query`, write-capable `execute`, `schema` inspection, a credential-profile store, and an STDIO MCP server (`mcp`) that exposes the same machinery as model-controlled tools (published to the MCP Registry as `io.github.linq2db/linq2db.cli`, `server.json`).

Assembly name is `dotnet-linq2db` (set by `<AssemblyName>` in `LinqToDB.CLI.csproj:5`). The project uses `PackAsTool=true` with `ToolPackageRuntimeIdentifiers` in the csproj SDK-pack pipeline (a .NET 10 SDK feature). This replaces the prior approach of a custom `.nuspec` file and a `MultiArchPublish` MSBuild target. `dotnet pack` now produces a thin pointer package plus one sub-package per RID; `dotnet tool install -g linq2db.cli` selects the sub-package matching the SDK architecture. RIDs covered: `win-x64`, `win-x86`, `win-arm64`, `linux-x64`, `linux-arm64`, `osx-arm64`, `osx-x64` (`LinqToDB.CLI.csproj:18,35`). Installation requires .NET 10 SDK; runtime requires .NET 8+. The csproj also packs a generated `THIRD-PARTY-NOTICES.linq2db.cli.txt` twice (package root + `CopyToPublishDirectory` so it lands in the tool payload) and suppresses `NU5118` for the RID-less pointer package (`LinqToDB.CLI.csproj:57`, SDK 10.0.400 collision workaround). `Microsoft.CodeAnalysis.PublicApiAnalyzers` is removed from the project (`LinqToDB.CLI.csproj:87`) and `PublicAPI.Shipped.txt` / `PublicAPI.Unshipped.txt` were deleted: the tool assembly is not a referenceable library API, even though `CliController`, `ICliEnvironment`, `QueryExecutionExecutor`, `ReadOnlySqlGuard`, `ExternalProviderLoader`, `WindowsImpersonation`, `SecretConsoleReader` and `LinqToDBHost` remain `public` (consumed by tests).

## Subsystems

### Entry point and dispatch (`CommandLine/`)

`Program.cs:11` -- `Main` is now `async Task<int>`: wires `Console.CancelKeyPress` to a `CancellationTokenSource`, then `await new LinqToDBCliController().Execute(args, SystemCliEnvironment.Instance, cancellation.Token)`. `OperationCanceledException` -> `"Command cancelled."` + `StatusCodes.EXPECTED_ERROR`; any other exception prints message, inner messages and stack, returns `StatusCodes.INTERNAL_ERROR`.

`CliController` (abstract) -- command registry and parser. `Execute` now has three overloads (`args`; `args, ICliEnvironment`; `args, ICliEnvironment, CancellationToken`, `CliController.cs:56-79`); the first two default to `SystemCliEnvironment.Instance` / `CancellationToken.None`. arg[0] is the command name; if not found, falls to `_defaultCommand`. Option parsing supports `--long-name value` and `-x value` forms; `ImportCliOption` (JSON file) values are merged first, then CLI values override. Commands with `AcceptsArguments` (e.g. `credentials`) receive non-option tokens in `unknownArgs` instead of an "Unrecognized argument" error. Repeated `AllowMultiple` options concatenate `string[]` values (`CliController.cs:225`); required options are validated after merge (`CliController.cs:250`).

`LinqToDBCliController` (sealed) -- registers ten commands: `HelpCommand`, `ConfigInitCommand`, `CredentialsCommand`, `ExecuteCommand`, `McpCommand`, `QueryCommand`, `SchemaCommand`, `SkillCommand`, `ScaffoldCommand`, `TemplateCommand` (`LinqToDBCliController.cs:28-37`). `HelpCommand` is the default.

`ICliEnvironment` (public interface, `CommandLine/ICliEnvironment.cs`) -- the runtime seam every command uses instead of `Console`/`File`/`Environment`: `Out`/`Error` writers, `BufferWidth`, `CredentialStore`, file ops (`FileExists`, `ReadAllText`, `WriteAllText`, `SetOwnerOnlyFilePermissions`, `CreateTextWriter`, `MoveFile`, `DeleteFile`, `CreateDirectory`), `GetEnvironmentVariable`, `TryReadSecret`, `ReadLine`. `SystemCliEnvironment` is the production implementation (credential store = `WindowsCredentialStore.Instance`, `SystemCliEnvironment.cs:97`). `McpQueryEnvironment` wraps it for MCP tool calls: `Out` is `TextWriter.Null`, `Error` is a per-call `StringWriter`, and file writes / secret / line input throw `NotSupportedException`. `SecretConsoleReader.Read` implements masked secret entry (`*` echo, Backspace, Esc/Ctrl+U clear).

### Command abstractions (`CommandLine/Commands/`)

`CliCommand` (abstract) -- owns option registries; ctor gained `acceptsArguments`; `Execute(controller, ICliEnvironment environment, rawArgs, options, unknownArgs, CancellationToken)` returns `ValueTask<int>`. `AddMutuallyExclusiveOptions(category, ...)` registers option groups (used for `--sql` / `--sql-file`). `CommandExample` and the option types moved namespaces: `LinqToDB.CommandLine.Commands.CommandExample`, `LinqToDB.CommandLine.Options.*` (namespace-only changes; `StringCliOption` optional-parameter defaults added so call sites can omit the help/examples tail args).
`HelpCommand` (singleton, now `Commands/Help/HelpCommand.cs`) -- default command and `help` command. Width-aware line wrapping; fallback 80 when `Console.BufferWidth` unavailable (issue #3612). On Windows, `PrintGeneralHelp` emits an expanded bitness-guidance section: 32-bit-only providers (Jet OLE DB), bitness-must-match providers (ACE OLE DB, SQL CE, SAP HANA), and instructions for installing the x86 variant or maintaining parallel x86/x64 tool paths (originally `HelpCommand.cs:404-432`; line numbers drifted with the move).
`TemplateCommand` (singleton, now `Commands/Template/TemplateCommand.cs`) -- extracts `Template.tt` from embedded resource.
`SkillCommand` (`Commands/Skill/`, no options) -- prints the embedded `SKILL.md` (resource `LinqToDB.CLI.SKILL.md`, read by `SkillResource.ReadMarkdown`) to `environment.Out`; rejects any extra argument. The same text is served by the MCP tool `linq2db_skill`.
`CommandOutput` (`Commands/CommandOutput.cs`) -- shared output sink for `query`/`execute`/`schema`: stdout when no `--output-file`, otherwise a hidden `.<name>.<guid>.tmp` sibling written first and moved into place by `Commit(overwrite)`; `DisposeAsync` deletes the temp file when not committed.

### Query / execute / schema / MCP stack

All four data commands share one resolution pipeline (profile -> connection -> executor), so behaviour is identical whether invoked from the shell or from MCP.

- **Configuration** -- `QueryExecutionCliOptions` (static option descriptors in categories Configuration / Connection / Output): `--config`, `--profile`, `--provider`, `--provider-location|-l`, `--connection-string[-env]`, `--user[-env]`, `--password[-env]`, `--credentials`, `--impersonate`, `--impersonate-mode`, `--command-timeout`, `--lock-timeout`, `--max-rows`, `--output`/`--output-file`/`--overwrite`, `--sql`/`--sql-file`. Three `--output` variants exist: `Output` (json default; json, json-table, csv), `McpOutput` (json, json-table; json-table default) and `ExecuteOutput` (json-table default; all three). Config file is a JSON object of named profiles (`QueryExecutionDefaults.DefaultProfileName = "default"`, reserved `mcp` section name, `DefaultMaxRows = 1000`); profiles carry `provider`, `providerLocation`, `connectionString`/`connectionStringEnv`, `user`/`password` (+Env), `credentials`, `maxRows`, `output`, `enableExecute`, timeouts, impersonation.
- **`ConnectionSettingsResolver`** (`Commands/Connection/`) -- merges command values over the selected profile (command > env var > config > config env var), expands `%NAME%` / `${NAME}` in path-like options (`MissingEnvironmentVariable = "\u0000"` sentinel signals an already-reported missing variable), reads `--credentials` from `ICredentialStore` (mutually exclusive with user/password options, `ConnectionSettingsResolver.cs:59-80`), formats the connection string with `string.Format(cs, user, password)` (`{0}` user, `{1}` password), validates timeouts, and maps `impersonate-mode` names/codes (`2`, `3`, `8`, `9`) to `WindowsImpersonationMode`. `ErrorStatusCode` defaults to `INVALID_ARGUMENTS`.
- **`ConnectionExecution.RunAsync`** -- single choke point: `ExternalProviderLoader.LoadExternalProvider`, `DataConnection.GetDataProvider`, build `DataOptions` (`UseConnectionString`, `UseCommandTimeout`), then run the action either directly or inside `WindowsImpersonation.RunAsync`. A provider name that looks like a test data-source alias (e.g. `Oracle.11.Managed`) produces a hint to use `Oracle.Managed`.
- **`ExternalProviderLoader`** -- IBM DB2 / Informix are not bundled; without `--provider-location` they fail with download instructions. With it, loads the assembly into a non-collectible `ExternalProviderLoadContext` (dependency resolver + provider dir + app base probing), sets `DB2Tools.AutoDetectProvider` for DB2 and registers `DB2Factory` / `IfxFactory` in `DbProviderFactories`.
- **`QueryExecutionSettingsResolver`** -- builds `QueryExecutionSettings` from `QueryExecutionOptionValues` + the connection; enforces `enableExecute` for `QueryExecutionMode.Execute` (error: profile does not enable execute mode), requires `--sql` or `--sql-file`, validates output format.
- **`QueryExecutionExecutor`** (public) -- runs SQL through `ConnectionExecution`. Query mode: `ReadOnlySqlGuard.ValidateSingleStatement` then `ReadOnlySqlGuard.Validate`; Execute mode: single-statement check only plus a diagnostic that write-capable SQL is running. Optional session `lock-timeout` is applied via provider-specific command (SQL Server `SET LOCK_TIMEOUT`, PostgreSQL `lock_timeout`, MySQL `innodb_lock_wait_timeout`, SQLite `PRAGMA busy_timeout`; others print a diagnostic, `QueryExecutionExecutor.cs:648-661`). Streams rows as `json` (array of objects, requires unique column names), `json-table` (`columns` metadata with fieldType/providerSpecificFieldType/dataTypeName + `rows` + `rowCount`/`truncated`/`truncationReason`/`maxOutputBytes`/`recordsAffected`) or `csv`. Truncation by `MaxRows` or, when `MaxOutputBytes` is set (MCP), by byte budget via `BoundedQueryRowReader`/`BoundedQueryOutputSegmentWriter` (reserves footer bytes; binary/text reads are limited at the source). Values are normalized to strings via `QueryValueFormatter.ForProvider`; special cases for Oracle BFILE (placeholder), MySQL wide DECIMAL (`GetMySqlDecimal` by reflection), and Oracle/SqlServer/Firebird/DB2/Npgsql provider-specific types (`CreateOutputColumn`, `QueryExecutionExecutor.cs:818-873`).
- **SQL guards** -- `ReadOnlySqlGuard` (public) dispatches on provider name: SQL Server uses `SqlServerReadOnlySqlGuard` (ScriptDom `TSql180Parser`; exactly one `SelectStatement`, rejects `EXECUTE`, `SELECT INTO`, OPENQUERY/OPENROWSET/ad-hoc references); every other provider uses `GenericReadOnlySqlGuard` (hand tokenizer; rejects forbidden tokens such as INSERT/UPDATE/DELETE/DROP/EXEC/SET/CALL, `INTO` except directly after FROM/JOIN, first token must be SELECT or WITH; ambiguous `--x` and MySQL `/*! */` comments are rejected as provider-dependent). The generic guard is best-effort, not a security boundary; SQL Server is AST-level.
- **`WindowsImpersonation`** (public static partial) -- `LogonUser` P/Invoke + `WindowsIdentity.RunImpersonatedAsync`; Windows-only (`PlatformNotSupportedException` elsewhere). Default logon type is network-cleartext (8). Only database access is impersonated; config/file access stays under the original account (`CommandOutput` is created before impersonation).
- **Credentials** -- `CredentialsCommand` (`credentials set|list|remove|clear`, `AcceptsArguments`): profile names are stored under target `linq2db/<profile>`; `set` prompts twice via `TryReadSecret`; `clear` asks `[y/N]` unless `--force`. `ICredentialStore` abstracts storage; `WindowsCredentialStore` uses Credential Manager (`CredRead`, DPAPI-protected payload with `linq2db.Credential.v1` marker, `TargetPrefix = "linq2db/"`); other platforms report "not supported" via `CheckPlatform`.
- **`ConfigInitCommand`** (`config-init`) -- creates/updates a profile in a JSON config (default `.agents/linq2db-query.json`, default output `json-table`), always seeds a `default` profile with `maxRows`/`output`/`enableExecute=false`, `--if-exists error|replace|skip`, rejects the reserved name `mcp`, requires exactly one of connection string / connection string env, writes atomically (temp file + `SetOwnerOnlyFilePermissions` + move) and warns when a literal connection string is stored.
- **`QueryCommand` / `ExecuteCommand`** -- thin adapters over the pipeline (`QueryExecutionMode.Query` vs `Execute`; defaults json vs json-table); `--output-file` exists-check, `CommandOutput.Commit`, and a stderr truncation notice for non-json-table output.
- **`SchemaCommand`** + `SchemaInspection/` -- provider-independent schema dump as camelCase JSON (`SchemaInspectionDto` tree: tables, columns, primary/foreign keys, object-name DTOs). Options: `--detail-level full|names`, `--prefer-provider-specific-types`, `--get-tables`, `--get-foreign-keys`, `--generate-char1-as-string`, `--ignore-system-history-tables`, `--default-schema`, repeatable `--filter-schema/--filter-catalog/--filter-table` (regex via `regex:`/`rx:` prefix; a regex timeout is reported as an expected error). `SchemaInspectionExecutor` uses `LinqToDB.SchemaProvider` through `ConnectionExecution`; `BoundedMemoryStream` enforces `MaxOutputBytes` with a hint to use filters. Procedures/functions are not supported.
- **`McpCommand`** (`mcp`) -- STDIO MCP server built on `Microsoft.Extensions.Hosting` (`Host.CreateEmptyApplicationBuilder`, console logging forced to stderr) and `ModelContextProtocol`. Registers `McpQueryTool` always and `McpExecuteTool` only with `--enable-execute-tool`. Extra option: `--max-response-bytes` (default `McpServerConfiguration.DefaultMaxResponseBytes` = 8 MiB; the config file `mcp` section can also set it plus title/description/instructions). Tools: `linq2db_info` (non-secret profile/provider/dialect discovery; `McpInfoTool` lists supported providers and requirements; `ProviderDialectCatalog` maps provider name -> SQL dialect), `linq2db_skill`, `linq2db_schema`, `linq2db_query` (read-only, json/json-table only, `MaxOutputBytes` from startup options), and `linq2db_execute` (destructive; requires both the server flag and `enableExecute=true` in the profile). `McpQueryExecutionResult.Create` appends a second text block with a pagination hint when output was truncated.
- **Registry publishing** -- `server.json` (schema 2025-12-11, nuget package, `runtimeHint: dnx`, positional `mcp`, `--config` required) and `MCP-REGISTRY.md` (ownership marker lives in `readme.md`; version fields are `0.0.0` placeholders populated by `.github/workflows/publish-mcp.yml` on release; 6.5.0 is the first registrable version).

### ScaffoldCommand (5-file partial class)

Files moved to `Commands/Scaffold/` (namespace `LinqToDB.CommandLine.Commands.Scaffold`); content otherwise stable (renames at 82-99% similarity). `Execute` now receives `ICliEnvironment` (`ScaffoldCommand.Execute.cs:28`).

- `ScaffoldCommand.cs` -- registers all ~80 options into four `OptionCategory` groups.
- `ScaffoldCommand.Options.cs` -- option static fields. `General.Provider` is a required `StringEnumCliOption` over `DatabaseType` (17 values: Access, DB2, Firebird, Informix, SQLServer, MySQL, Oracle, PostgreSQL, SqlCe, SQLite, Sybase, SapHana, ClickHouseMySql, ClickHouseHttp, ClickHouseTcp, DuckDB, Ydb). `DatabaseType` is a private enum at `ScaffoldCommand.Options.cs:1929`; the `Instance` singleton is at line 1951. The `--provider` `StringEnumOption` list carries a matching `Ydb` entry with description "YDB".
- `ScaffoldCommand.Configuration.cs` -- `ProcessScaffoldOptions(options)` builds a `ScaffoldOptions` object.
- `ScaffoldCommand.Execute.cs` -- `Execute` override: processes settings, handles `--architecture` restart, opens a `DataConnection`, then calls `Scaffold(...)`. Provider-specific connection setup: `ProviderName.DuckDB` and `ProviderName.Ydb` both require no special setup (fall through the `break` case alongside ClickHouse and SQL Server; `case ProviderName.Ydb` at `ScaffoldCommand.Execute.cs:197`). The `DatabaseType.Ydb` -> `ProviderName.Ydb` mapping is at line 73 (DuckDB mapping adjacent). Architecture restart spawns a child process from the same assembly directory.
- `ScaffoldCommand.Interceptors.cs` -- interceptor loading. T4 path: `PreprocessTemplate` uses `Mono.TextTemplating.TemplateGenerator`, then Roslyn `CSharpCompilation` compiles in-memory. Assembly path: `Assembly.LoadFrom` + `DependencyContext`-based resolver.

### Option type system (`CommandLine/Options/`)

`CliOption` (abstract record) -- base for all options; namespace is now `LinqToDB.CommandLine.Options`. Concrete option types: `BooleanCliOption`, `StringCliOption`, `StringEnumCliOption`, `NamingCliOption`, `ObjectNameFilterCliOption`, `StringDictionaryCliOption`, `ImportCliOption`.

`OptionType` enum -- `String`, `StringEnum`, `StringDictionary`, `Boolean`, `DatabaseObjectFilter`, `Naming`, `JSONImport`.

`NameFilter` -- compiled filter over database object names. Supports exact names, compiled regex patterns, 1-second `RegexOptions.Compiled` timeout.

### T4 host (`T4Host/`)

`LinqToDBHost` (public abstract) -- base class that user T4 templates inherit from. The class is public because the mono.t4 codegen references it by name.

`Template.tt` -- the starter T4 template shipped as an embedded resource (`LinqToDB.CLI.Template.tt`). The CLI extracts it verbatim when the user runs `dotnet linq2db template`.

## Key types

| Type | File | Role |
|---|---|---|
| `LinqToDBCliController` | `CommandLine/LinqToDBCliController.cs` | Concrete controller; registers 10 commands |
| `CliController` | `CommandLine/CliController.cs` | Abstract base; arg dispatch + option parsing |
| `ICliEnvironment` | `CommandLine/ICliEnvironment.cs` | Console/file/env/credential seam used by all commands |
| `SystemCliEnvironment` | `CommandLine/SystemCliEnvironment.cs` | Production `ICliEnvironment` |
| `ScaffoldCommand` | `CommandLine/Commands/Scaffold/ScaffoldCommand*.cs` | Core scaffold logic (5 partials) |
| `HelpCommand` | `CommandLine/Commands/Help/HelpCommand.cs` | help command + default handler |
| `TemplateCommand` | `CommandLine/Commands/Template/TemplateCommand.cs` | template extraction command |
| `QueryCommand` / `ExecuteCommand` | `CommandLine/Commands/Query/`, `Execute/` | read-only / write-capable SQL CLI adapters |
| `SchemaCommand` | `CommandLine/Commands/Schema/SchemaCommand.cs` | schema metadata JSON dump |
| `McpCommand` | `CommandLine/Commands/Mcp/McpCommand.cs` | STDIO MCP server host |
| `McpQueryTool` / `McpExecuteTool` / `McpInfoTool` | `CommandLine/Commands/Mcp/` | MCP tool adapters (`linq2db_*`) |
| `CredentialsCommand` | `CommandLine/Commands/Credentials/CredentialsCommand.cs` | credential profile management |
| `WindowsCredentialStore` | `CommandLine/Commands/Credentials/WindowsCredentialStore.cs` | `ICredentialStore` over Windows Credential Manager |
| `ConfigInitCommand` | `CommandLine/Commands/ConfigInit/ConfigInitCommand.cs` | profile file initializer |
| `SkillCommand` | `CommandLine/Commands/Skill/SkillCommand.cs` | prints embedded `SKILL.md` |
| `ConnectionSettingsResolver` | `CommandLine/Commands/Connection/ConnectionSettingsResolver.cs` | profile/option/env/credential merge |
| `ConnectionExecution` | `CommandLine/Commands/Connection/ConnectionExecution.cs` | provider load + DataOptions + impersonation boundary |
| `QueryExecutionExecutor` | `CommandLine/Commands/QueryExecution/QueryExecutionExecutor.cs` | SQL run + json/json-table/csv streaming with limits |
| `ReadOnlySqlGuard` (+ `SqlServerReadOnlySqlGuard`, `GenericReadOnlySqlGuard`) | `CommandLine/Commands/QueryExecution/` | read-only / single-statement validation |
| `ExternalProviderLoader` | `CommandLine/Commands/QueryExecution/ExternalProviderLoader.cs` | DB2/Informix external assembly loading |
| `WindowsImpersonation` | `CommandLine/Commands/QueryExecution/WindowsImpersonation.cs` | LogonUser impersonation |
| `SchemaInspectionExecutor` | `CommandLine/Commands/SchemaInspection/SchemaInspectionExecutor.cs` | schema read + bounded JSON output |
| `CliCommand` | `CommandLine/Commands/CliCommand.cs` | Abstract command base |
| `CliOption` | `CommandLine/Options/CliOption.cs` | Abstract option base |
| `ImportCliOption` | `CommandLine/Options/ImportCliOption.cs` | JSON response-file option |
| `NamingCliOption` | `CommandLine/Options/NamingCliOption.cs` | JSON-only naming config option |
| `NameFilter` | `CommandLine/Options/NameFilter.cs` | DB object inclusion/exclusion filter |
| `LinqToDBHost` | `T4Host/LinqToDBHost.cs` | Public base for user T4 templates |
| `StatusCodes` | `CommandLine/StatusCodes.cs` | Exit code constants (SUCCESS 0, INVALID_ARGUMENTS -1, INTERNAL_ERROR -2, EXPECTED_ERROR -3, T4_ERROR -4) |

## Files (Tier 1 / Tier 2)

**Tier 1** (read in full): `Program.cs`, `CommandLine/CliController.cs`, `CommandLine/LinqToDBCliController.cs`, `CommandLine/StatusCodes.cs`, `CommandLine/Commands/CliCommand.cs`, `CommandLine/Commands/Scaffold/ScaffoldCommand.cs`, `CommandLine/Commands/Scaffold/ScaffoldCommand.Execute.cs`, `CommandLine/Commands/Scaffold/ScaffoldCommand.Interceptors.cs`, `CommandLine/Commands/Scaffold/ScaffoldCommand.Configuration.cs`, `CommandLine/Commands/Scaffold/ScaffoldCommand.Options.cs`, `CommandLine/Options/CliOption.cs`, `T4Host/LinqToDBHost.cs`, `Template.tt`, `LinqToDB.CLI.csproj`. The five ScaffoldCommand partials were relocated by this delta (82-99% similarity renames, `ICliEnvironment` threaded into `Execute`); the `Options/*`, `CliOption.cs`, `CommandExample.cs` and `LinqToDBHost.cs` diffs are namespace/using churn plus `StringCliOption` optional-parameter defaults.

**Tier 2** (read in full unless noted): `Help/HelpCommand.cs` (grep-scanned only after the move), `Template/TemplateCommand.cs`, `CommandExample.cs`, all `CommandLine/Options/*.cs`, `readme.md`, plus the new surface: `CommandOutput.cs`, `ICliEnvironment.cs`, `SystemCliEnvironment.cs` (scanned), `SecretConsoleReader.cs`, `Commands/{ConfigInit,Credentials,Execute,Mcp,Query,Schema,Skill}/*` (most read; see coverage block), `Commands/Connection/{ConnectionExecution,ConnectionSettingsResolver,ProviderDialectCatalog}.cs`, `Commands/QueryExecution/{QueryExecutionExecutor,ReadOnlySqlGuard,GenericReadOnlySqlGuard,SqlServerReadOnlySqlGuard,ExternalProviderLoader,QueryExecutionCliOptions,QueryExecutionDefaults,QueryExecutionSettingsResolver,WindowsImpersonation}.cs`, `Commands/SchemaInspection/*` (executor read; DTO/record files declaration-scanned), `server.json`, `MCP-REGISTRY.md`. `SKILL.md` is the embedded agent guide (documentation text, not read). Removed from the repo: `DotnetToolSettings.xml`, `linq2db.cli.nuspec` (earlier SDK-pack migration), `PublicAPI.Shipped.txt`, `PublicAPI.Unshipped.txt` (this delta), and the old top-level `Commands/HelpCommand.cs` (moved to `Help/`).

## Inbound / outbound dependencies

**Outbound:**
- **SCAFFOLD** -- `Scaffolder`, `ScaffoldOptions`, `ScaffoldInterceptors`, `LegacySchemaProvider`.
- **Core `LinqToDB`** -- `DataConnection`, `DataOptions`, `ProviderName`, provider-specific types; `LinqToDB.SchemaProvider` (schema command); `LinqToDB.Internal.DataProvider.{MySql,PostgreSQL,SQLite,SqlServer}` data-provider types (lock-timeout switch in `QueryExecutionExecutor`); `DB2Tools.AutoDetectProvider`.
- **Mono.TextTemplating** -- T4 parsing.
- **Microsoft.CodeAnalysis.CSharp** -- Roslyn in-memory compilation.
- **ModelContextProtocol**, **Microsoft.Extensions.Hosting**, **Microsoft.Extensions.Logging.Console** -- `mcp` server host.
- **Microsoft.SqlServer.TransactSql.ScriptDom** -- SQL Server read-only guard; **Microsoft.SqlServer.Types** -- SqlGeometry/SqlGeography/SqlHierarchyId value formatting.
- All provider ADO.NET packages bundled in the tool (SQLite, SqlClient, Firebird, MySqlConnector, Oracle.ManagedDataAccess.Core, Npgsql, AdoNetCore.AseClient, ODBC, OleDb, ClickHouse.Driver, Octonica.ClickHouseClient, DuckDB.NET.Data.Full, Ydb.Sdk) -- except IBM DB2/Informix and SAP HANA (too large); DB2/Informix load via `--provider-location`.
- Windows native: `advapi32` (`LogonUser`, Credential Manager), DPAPI.

**Inbound:** standalone tool; no other source project references `LinqToDB.CLI`. External consumers: MCP clients through the MCP Registry entry (`server.json`), agents through `dotnet linq2db skill`, and `.github/workflows/publish-mcp.yml`.

## Known issues / debt

- `ScaffoldCommand.Interceptors.cs:56,138,139` -- unconditional debug log lines marked `// TODO: Verbose logging` (path moved to `Commands/Scaffold/`; line numbers not re-verified).
- `Help/HelpCommand.cs` -- workaround for `Console.BufferWidth` exception (issue #3612); the former `HelpCommand.cs:185,312` line numbers are stale after the move.
- `ScaffoldCommand.Execute.cs:148` -- file name collision/deduplication deferred (`// TODO: add file name normalization/deduplication?`; line not re-verified after the move).
- Architecture restart only works on Windows; `--architecture` silently ignored on Linux/macOS.
- IBM DB2 and Informix providers intentionally excluded from the tool package due to size.
- `CliCommand.cs:19` -- `// TODO: replace with HashSet if not used ...` on `_optionsByName`.
- `GenericReadOnlySqlGuard` is a token heuristic: only SQL Server gets AST validation, so read-only enforcement on other providers is best-effort (database-side permissions remain the real boundary). `McpQueryTool` / `QueryCommand` rely on it.
- Credential storage (`WindowsCredentialStore`) and `WindowsImpersonation` are Windows-only; on Linux/macOS `credentials` operations and `--impersonate` fail with a platform error.
- Four near-identical `ProcessOptions` blocks (`QueryCommand`, `ExecuteCommand`, `McpCommand`, `SchemaCommand`) each remove ~15 shared options by hand; a new shared option must be added in every command and in `McpQueryStartupOptions`.
- `server.json` and `MCP-REGISTRY.md` use `0.0.0` version placeholders by design; publishing the committed file unedited fails at the registry.

## See also

- [SCAFFOLD area](../SCAFFOLD/INDEX.md) -- the scaffolding library this CLI wraps.
- [INTERCEPTORS area](../INTERCEPTORS/INDEX.md) -- the `ScaffoldInterceptors` base class.
- [T4-TEMPLATES area](../T4-TEMPLATES/INDEX.md) -- the T4 template includes.

<details><summary>Coverage</summary>

**Tier 1 -- 14/14 read.**
**Tier 2 -- 59/76 read.** (denominator reflects current on-disk set; `DotnetToolSettings.xml` and `linq2db.cli.nuspec` deleted -- counted as visited with skip reason: file removed from repo; `PublicAPI.Shipped.txt` / `PublicAPI.Unshipped.txt` deleted in the latest delta and dropped from the denominator; 67 new Tier-2 files added by the delta, 16 of them deferred, see DEFERRED-COVERAGE)

**Delta read (prior run -- PR #5451 DuckDB additions):**
- `ScaffoldCommand.Options.cs` -- `DuckDB` added to `DatabaseType` enum and provider value list; provider count 14 -> 15.
- `ScaffoldCommand.Execute.cs` -- `DatabaseType.DuckDB` -> `ProviderName.DuckDB` mapping; no-special-setup case group.
- `LinqToDB.CLI.csproj` -- `DuckDB.NET.Data.Full` package reference added.

**Read (this run -- delta, sha 2e67bafc9):**
- `CommandLine/Commands/HelpCommand.cs` -- `PrintGeneralHelp` extended with Windows bitness-selection guidance block (lines 404-432); no structural change to option rendering.
- `CommandLine/Commands/ScaffoldCommand.Execute.cs` -- no changes beyond DuckDB already noted; `GetConnection` switch stable.
- `CommandLine/Commands/ScaffoldCommand.Options.cs` -- DuckDB already present; option surface otherwise stable.
- `CommandLine/Commands/ScaffoldCommand.cs` -- no changes to option registration structure.
- `LinqToDB.CLI.csproj` -- packaging completely replaced: `PackAsTool=true` + `ToolPackageRuntimeIdentifiers` replaces custom `.nuspec` + `MultiArchPublish` MSBuild target; cross-platform RIDs added (`linux-x64`, `linux-arm64`, `osx-arm64`, `osx-x64`); `DotnetToolSettings.xml` and `linq2db.cli.nuspec` deleted; install now requires .NET 10 SDK, runtime still .NET 8+.
- `PublicAPI.Shipped.txt` -- `LinqToDBHost` surface only; release-promotion churn.
- `readme.md` -- updated install section: `.NET 10 SDK required`, 32-bit vs 64-bit guidance, per-RID install/update/switch examples.
- `DotnetToolSettings.xml` -- DELETED (SDK-pack migration; was Tier-2).
- `linq2db.cli.nuspec` -- DELETED (SDK-pack migration; was Tier-2).

**Read (this run -- delta, sha 36ee4f82f):**
- `CommandLine/Commands/ScaffoldCommand.Execute.cs` -- added `DatabaseType.Ydb -> ProviderName.Ydb` mapping (line 67, alongside the existing DuckDB mapping); the GetConnection no-special-setup `break` case group (`ScaffoldCommand.Execute.cs:186-192`) extended with `ProviderName.Ydb` alongside `ClickHouseMySql`/`ClickHouseDriver`/`ClickHouseOctonica`/`SqlServer`/`DuckDB` -- YDB needs no auto-detect flag, no assembly probing, no bitness check.
- `CommandLine/Commands/ScaffoldCommand.Options.cs` -- `DatabaseType` enum gained a `Ydb` member (`ScaffoldCommand.Options.cs:1932`, after `DuckDB`); the `--provider` `StringEnumOption` list gained a matching `Ydb` / "YDB" entry (`ScaffoldCommand.Options.cs:109`). Provider count 16 -> 17.
- `LinqToDB.CLI.csproj` -- added a `Ydb.Sdk` `PackageReference` to the bundled-providers item group (`LinqToDB.CLI.csproj:74`), so the CLI tool now ships the YDB ADO.NET driver alongside the other bundled providers.

**Read (this run -- delta, sha 05150894e; 97 changed entries):**
- `Program.cs` -- async `Main` with Ctrl+C cancellation, passes `SystemCliEnvironment.Instance` + token to the controller.
- `CommandLine/CliController.cs` -- `Execute` overloads with `ICliEnvironment`/`CancellationToken`; `AcceptsArguments` handling; repeated-option merge for `AllowMultiple`; required-option validation.
- `CommandLine/Commands/CliCommand.cs` -- `acceptsArguments` ctor parameter, `AddMutuallyExclusiveOptions`, new `Execute` signature.
- `CommandLine/LinqToDBCliController.cs` -- ten registered commands (was three).
- `CommandLine/StatusCodes.cs` -- reviewed; constants unchanged (SUCCESS/INVALID_ARGUMENTS/INTERNAL_ERROR/EXPECTED_ERROR/T4_ERROR).
- `LinqToDB.CLI.csproj` -- `SKILL.md` embedded resource, third-party notices item pair, `NU5118` NoWarn, `PublicApiAnalyzers` removed, new package references (`ModelContextProtocol`, `Microsoft.Extensions.Hosting`, `Microsoft.Extensions.Logging.Console`, `Microsoft.SqlServer.Types`, `Microsoft.SqlServer.TransactSql.ScriptDom`).
- `CommandLine/Options/CliOption.cs`, `StringCliOption.cs`, `CommandLine/Commands/CommandExample.cs`, `T4Host/LinqToDBHost.cs` -- diffed: namespace/using changes (`LinqToDB.CommandLine.Options`, `...Commands`) and optional-parameter defaults on `StringCliOption`; the remaining `Options/*.cs` modifications are of the same size class (6-19 lines) and treated as the same churn.
- `CommandLine/Commands/Scaffold/ScaffoldCommand.{cs,Configuration,Execute,Interceptors,Options}.cs` -- renamed (R085-R099) from `Commands/`; `ICliEnvironment` parameter on `Execute`; `DatabaseType` enum now at line 1929, Ydb mapping at `Execute.cs:73`, `case ProviderName.Ydb` at `Execute.cs:197` (grep-verified, bodies not re-read).
- `CommandLine/Commands/Help/HelpCommand.cs` (moved), `Template/TemplateCommand.cs` (moved, R082) -- paths updated; HelpCommand only grep-scanned.
- `CommandLine/ICliEnvironment.cs`, `SystemCliEnvironment.cs` (scanned), `SecretConsoleReader.cs`, `Commands/CommandOutput.cs` -- environment seam, masked secret input, atomic output file sink.
- `Commands/ConfigInit/ConfigInitCommand.cs`, `Credentials/{CredentialsCommand,WindowsCredentialStore}.cs`, `Execute/ExecuteCommand.cs`, `Query/QueryCommand.cs`, `Schema/SchemaCommand.cs`, `Skill/{SkillCommand,SkillResource}.cs` -- new commands (all read; `WindowsCredentialStore` first 80 lines).
- `Commands/Mcp/{McpCommand,McpQueryTool,McpExecuteTool,McpInfoTool,McpQueryEnvironment,McpQueryExecutionResult,McpServerConfiguration}.cs` -- MCP server host and tools (`McpExecuteTool`, `McpInfoTool`, `McpServerConfiguration` read in part).
- `Commands/Connection/{ConnectionExecution,ConnectionSettingsResolver,ProviderDialectCatalog}.cs` -- shared connection pipeline.
- `Commands/QueryExecution/{QueryExecutionExecutor,ReadOnlySqlGuard,GenericReadOnlySqlGuard,SqlServerReadOnlySqlGuard,ExternalProviderLoader,QueryExecutionCliOptions,QueryExecutionDefaults,QueryExecutionSettingsResolver,WindowsImpersonation}.cs` -- execution, guards, provider loading, impersonation (guards and `WindowsImpersonation` read in part).
- `Commands/SchemaInspection/*` -- `SchemaInspectionExecutor` read in part; remaining 16 files declaration-scanned (internal sealed records/DTOs plus `SchemaInspectionCliOptions`, `SchemaInspectionSettingsResolver`, `SchemaFilterConstants`).
- `server.json`, `MCP-REGISTRY.md` -- MCP Registry metadata and publishing notes.
- `PublicAPI.Shipped.txt`, `PublicAPI.Unshipped.txt` -- DELETED (analyzer removed from the tool project).
- `CommandLine/Commands/HelpCommand.cs` (old location) -- DELETED (moved to `Help/`).
- Not read this run: `SKILL.md` (embedded documentation), `readme.md` (111 added lines; install/usage docs), `Template.tt` / `LinqToDBHost.cs` bodies (unchanged apart from `using System;`), and the 16 deferred Tier-2 files listed in DEFERRED-COVERAGE.

</details>
