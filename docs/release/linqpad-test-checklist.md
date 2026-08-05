# LINQPad smoke + targeted-change checklist

What to actually click in LINQPad 5 / 7+ when testing a release. Filled as the skill learns the structure of each release's test surface.

## T4 build prerequisite

Before any T4 / NuGet-T4 / CLI track in `/release-test-matrix`, the solution must be built in Debug targeting net462 to populate the T4 binaries under `.build`. Exact command:

```
dotnet build linq2db.slnx -c Debug
```

Solution-level Debug build emits net462 outputs alongside other TFMs (the slnx rejects single-TFM `-f net462`). Recorded on 6.3.0.

**This output must survive until tracks 4.5, 4.6 and 4.7 are all finished — do not clear `.build/bin` between them.** The dependency is not generic "T4 needs a build"; it is a hard-coded path:

- `Tests/Tests.T4.Nugets/Directory.Build.props` defines `<TestBinaries>…\.build\bin\Tests\Debug\net462\</TestBinaries>`,
- and `Tests/Tests.T4.Nugets/Templates/ConnectionStrings.ttinclude` opens with `<#@ assembly name="$(TestBinaries)linq2db.Tests.Base.dll" #>`.

So **track 4.5 loads a Debug/net462 assembly out of the *main* test tree** — even though it is otherwise a nuget-only validation — purely to reuse the harness's config-driven `GetConnectionString(<name>)` resolver instead of hard-coding connection strings. Deleting that output (e.g. to reclaim disk between tracks) makes every 4.5 template fail in Visual Studio with a T4 compile error rather than anything that names the real cause:

```
System.IO.FileNotFoundException: Could not find a part of the path
'…\.build\bin\Tests\Debug\net462\linq2db.Tests.Base.dll'
```

Recovery without redoing the whole solution build:

```
dotnet build Tests\Linq\Tests.csproj -c Debug -f net462
```

**Build `Tests/Linq/Tests.csproj`, not `Tests/Base/Tests.Base.csproj`** — even though the latter is what *produces* `linq2db.Tests.Base.dll`. Under the repo's artifacts layout each project writes to `.build/bin/<ProjectName>/<config>/<tfm>/`, so `Tests.Base` builds to `.build/bin/Tests.Base/Debug/net462/`, while `$(TestBinaries)` points at `.build/bin/Tests/Debug/net462/` — the output folder of `Tests/Linq/Tests.csproj`, where the assembly only appears as a *copied dependency*. Building the producing project alone exits 0 and still leaves the T4 templates broken.

(Hit on 6.4.0: `.build/bin` was cleared for disk space after 4.7 on the assumption 4.5 was nuget-only.)

## Tests.T4.Nugets version property

`Tests/Tests.T4.Nugets/Directory.Packages.props` has a single `<Version>` property at the top of its `<PropertyGroup>`. Every `<PackageVersion>` for the linq2db family (`linq2db`, `linq2db.SqlServer`, `linq2db.t4models`, etc.) references it as `Version="$(Version)"`. Update that one property to the just-built local nuget version before `dotnet restore` of `Tests.T4.Nugets.slnx`.

Plain release version (e.g. `6.3.0` matching `dotnet pack`'s default output) works as the value when iterating once; for multiple iterations use `<version>-local.<N>` and bump N + re-pack to invalidate the NuGet cache. **Re-pack with `-p:PackageVersion=<version>-local.<N>`, not `-p:Version=`** — `Version` propagates the prerelease suffix into `AssemblyVersion` and fails the build with CS7034/CS7035.

Recorded on 6.3.0.

### The feed needs 16 packages, not 15 — `linq2db.Analyzers` is easy to miss

Since [#5720](https://github.com/linq2db/linq2db/pull/5720), core `linq2db` declares `<dependency id="linq2db.Analyzers" … exclude="Build" />` in **every** TFM group. `Tests/Tests.T4.Nugets/nuget.config` maps the `linq2db*` pattern to the local feed only, so a missing `linq2db.Analyzers` doesn't fall back to nuget.org — restore fails outright on every project:

```
error NU1101: Unable to find package linq2db.Analyzers. No packages exist with this id in
source(s): linq2db-testing. PackageSourceMapping is enabled, the following source(s) were
not considered: nuget.org.
```

Note `Directory.Packages.props` still lists only the 15 `<PackageVersion>` entries — the 16th arrives transitively, so the file gives no hint it's needed.

**It is packed by `Source/LinqToDB.Analyzers.CodeFixes/`, which carries `<PackageId>linq2db.Analyzers</PackageId>`** and ships both the analyzer and code-fix assemblies. `Source/LinqToDB.Analyzers/` is `IsPackable=false`, so packing *that* exits 0 and silently produces nothing — an easy wrong turn.

Also note **`dotnet pack -c Release` writes straight to `.build/package/release/`** (the .NET artifacts layout lowercases the configuration pivot), which is exactly the folder `nuget.config`'s `linq2db-testing` source points at — so there is no copy step. Same applies to the LINQPad local-push closure in track 4.4: it is now five packages, not four, because `linq2db.Analyzers` must be pushed at the same `-local.<N>`.

Recorded on 6.4.0.

## T4 nuget pack: dynamic content via Target injection

Some content in the `tools/` directory of a scaffold nuget (notably `clidriver/` for `linq2db.DB2` and `linq2db.t4models`) is populated by a dependent build (`NuGet.csproj` via `IBM.Data.DB.Provider`'s build/restore step), **after** the consuming `linq2db.DB2.csproj` / `linq2db.t4models.csproj`'s static `<None Include>` globs are evaluated at project-load time.

**The trap:** a declaration like

```xml
<None Include="$(ToolsPath)/clidriver/**" Pack="true" PackagePath="tools/clidriver" />
```

evaluates the glob at project-load (when `$(ToolsPath)/clidriver/` doesn't exist yet), matches zero files, and silently ships an empty section. `dotnet pack` reports success — but the nupkg is missing the entire native folder. Symptom (downstream): `DllNotFoundException: db2app64.dll` when the IBM provider is instantiated.

**The fix:** inject items into Pack's internal `_PackageFiles` collection from a Target that runs after the build but before pack's content gathering:

```xml
<Target Name="IncludeClidriverInPack" BeforeTargets="_GetPackageFiles">
    <ItemGroup>
        <_PackageFiles Include="$(ToolsPath)\clidriver\**\*">
            <BuildAction>None</BuildAction>
            <PackagePath>tools\clidriver\%(RecursiveDir)%(Filename)%(Extension)</PackagePath>
        </_PackageFiles>
    </ItemGroup>
</Target>
```

`BeforeTargets="_GetPackageFiles"` is the canonical hook — `_GetPackageFiles` is what runs the content collection. `_PackageFiles` is Pack's internal item; populating it inside a Target gets dynamic evaluation. The static `<None>` approach with `Pack="true"` doesn't work even from inside a Target — by the time the Target runs, Pack's collection is already closed for `<None>` items, but `_PackageFiles` is still open.

Verify post-pack:

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
$z = [System.IO.Compression.ZipFile]::OpenRead('<nupkg-path>')
($z.Entries | Where-Object FullName -like '*clidriver*').Count
$z.Dispose()
```

Pattern broadly applicable to any pack-time content populated by a dependent build, not just clidriver. Recorded on 6.3.0 (commit 1c7d083c9 applied this fix to `NuGet/DB2/linq2db.DB2.csproj` + `NuGet/t4models/linq2db.t4models.csproj`).

## LINQPad NuGet driver must ship `lib/net8.0`, not `lib/net8.0-windows7.0`

The `linq2db.LINQPad` driver is a WPF assembly (compiled `net8.0-windows7.0`), but LINQPad installs drivers via NuGet on **every** OS. A `net8.0-windows7.0`-only package is rejected by NuGet's compatibility resolver on macOS/Linux → *"No compatible assemblies found"* (issue #5497; broke in 6.2.0 when #5279 replaced the hand-authored nuspec with csproj `dotnet pack`, which honors the project's `net8.0-windows7.0` TFM).

The package must present the platform-neutral `net8.0` moniker in **both** the lib folder and the dependency group. That's why `LinqToDB.LINQPad.Pack.csproj` is a **`net8.0` packaging-only** project: it references the `net8.0-windows7.0` build of `LinqToDB.LINQPad.csproj` for build-ordering only (`ReferenceOutputAssembly=false`, `SetTargetFramework`) and packs that built assembly into `lib/net8.0/` from a `BeforeTargets="_GetPackageFiles"` target. **Do not** collapse it back into a single `net8.0-windows7.0` pack project — that reintroduces #5497.

Why a single project can't just relabel the folder: NuGet derives the **dependency-group** TFM from the restore graph (`project.assets.json`), not a free-text label. A `net8.0-windows7.0` project can move the lib folder via `_BuildOutputInPackage` metadata, but its deps group stays `net8.0-windows7.0` (→ `NU5128`, and unresolved dependencies on a macOS consumer). Hence the compile/pack split. Trade-off: the package no longer declares the WPF `<frameworkReferences>` (a net8.0 project can't) — no practical effect on LINQPad's driver loading.

Post-pack verification — the produced nupkg must have a `net8.0` lib folder, not `net8.0-windows7.0`:

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
$z = [System.IO.Compression.ZipFile]::OpenRead('<linq2db.LINQPad nupkg path>')
$z.Entries.FullName | Where-Object { $_ -like 'lib/*' }   # expect lib/net8.0/..., NOT lib/net8.0-windows7.0/...
$z.Dispose()
```

Recorded on 6.4.0 (issue #5497, fix in PR #5571).

## LINQPad driver install automation

Neither LINQPad 5 nor LINQPad 9 exposes a CLI for driver install/update — both are UI-only by default. File-copy workarounds:

### LINQPad 5 (.lpx, .NET Framework)

Extract the `.lpx` (a renamed zip) directly into LINQPad 5's per-user driver folder. Close LINQPad 5 first — it locks DLLs while running.

```powershell
$target = Join-Path "$env:LOCALAPPDATA\LINQPad\Drivers\DataContext\4.6" 'linq2db.LINQPad (no-strong-name)'
if (Test-Path $target) { Remove-Item -Recurse -Force $target }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory('.build/lpx/linq2db.LINQPad.lpx', $target)
```

The `(no-strong-name)` suffix is LINQPad 5's convention for unsigned drivers (linq2db's .lpx is unsigned).

### LINQPad 9 (.lpx6 / NuGet driver)

LINQPad 9 reads NuGet sources from a `NuGetSources.xml` next to `LINQPad9.exe` (or `LPRun9.exe`); after configuring it the UI's NuGet Manager shows the local feed's versions:

```xml
<NuGetSources><Source Name="local" URI="<path-or-feed-url>"/></NuGetSources>
```

For full no-UI install/update, drop the `.nupkg`'s `lib/<TFM>/` contents into LINQPad 9's driver-cache folder (close LINQPad 9 first):

```
%LocalAppData%\LINQPad\Drivers\DataContext\NetCore\linq2db.LINQPad\
```

LINQPad 9 doesn't poll the feed for new versions — manual click "Update" in NuGet Manager OR re-do the file-copy when iterating with bumped `-local.N` versions.

## LINQPad 5 (.lpx) smoke

Default checklist (extended on first run):

- [ ] LINQPad starts with no error dialog.
- [ ] linq2db connection wizard appears under Add Connection.
- [ ] Connect to one provider (default: SQL Server) — schema browsable, sample query runs.
- [ ] Run a simple LINQ query → expected results.
- [ ] Run a more complex query that touches the changed surface (release-specific).

## LINQPad 7+ (nugets) smoke

Same as above plus:

- [ ] Nuget installs from the local test feed (recorded path in [`external-repos.md`](./external-repos.md)).
- [ ] Schema browser does not throw for any enabled provider.

## Targeted-change rows

Filled in per release when changes touch the LINQPad driver, scaffold library, or provider surface.

### Release <version>

<!-- entries appended by /release-test-matrix 4.8 on a per-release basis -->

### Release 6.4.0

Rows below are worth re-running in future releases, not just 6.4.0 — each exists because something
broke or was silently untested.

| Row | Surface | Outcome on 6.4.0 |
|---|---|---|
| Build a model in LINQPad **5** against any provider | net472 driver | **Found 2 regressions** — see *netfx assembly-binding* below |
| Build a model in LINQPad 5 against **PostgreSQL** specifically | net472 driver + Npgsql | Second binding regression surfaced only here |
| Dynamic-connection tab: *Database Type* / *Provider* combos fill the row ([#5579](https://github.com/linq2db/linq2db/pull/5579)) | LINQPad UI | pass |
| YDB appears as a provider and scaffolds ([#5564](https://github.com/linq2db/linq2db/pull/5564)) | driver + CLI | pass (CLI 5/5 zero-diff, after adding the missing matrix row) |
| `linq2db.LINQPad` nupkg ships `lib/net8.0`, not `lib/net8.0-windows7.0` ([#5571](https://github.com/linq2db/linq2db/pull/5571)) | packaging | pass — mechanical check, no LINQPad needed |
| SQL Server decimal-overflow scaffold output ([#5605](https://github.com/linq2db/linq2db/pull/5605)) | scaffold | pass via 4.5/4.6/4.7 |

**netfx assembly-binding regressions — check this whenever a dependency's major version moves.**
LINQPad 5 is .NET Framework, which binds assemblies by *exact* version. The driver ships 10.0.x of
several BCL-ish assemblies while netfx-era providers still reference 8.0.0.0, so any version bump can
produce `FileLoadException: … manifest definition does not match the assembly reference` at model
build. `DriverHelper.Init()` compensates with a list of per-assembly `AssemblyResolve` handlers
(`RegisterResolver`), which is **only as complete as the last release that hit a failure**. 6.4.0
needed two additions:

- `System.Reflection.Metadata` — the entry existed but had been commented out as *"not needed
  anymore?"*; the Roslyn 5.3.0 → 5.6.0 bump made it necessary again (Microsoft.CodeAnalysis 5.6
  references 10.0.0.0, driver ships 10.0.0.1).
- `System.Threading.Channels` — Npgsql 8.0.9 references 8.0.0.0, driver ships 10.0.0.3.

Each is discoverable **only** by connecting with the provider that trips it, so a release that bumps
dependencies should build a model against several providers, not just one. CI cannot catch these at
all: it never loads the driver into LINQPad.
