## MSBuild property override precedence

When overriding a property like `RunAnalyzersDuringBuild` / `EnforceCodeStyleInBuild` / `TreatWarningsAsErrors` against `linq2db` source (consumed as a submodule by `linq2db.docs` for docfx metadata extraction, or as a project reference in any consumer), env vars **don't override** conditional `<PropertyGroup>` reassignments in the project's `Directory.Build.props`. Pattern:

```xml
<RunAnalyzersDuringBuild>false</RunAnalyzersDuringBuild>
<RunAnalyzersDuringBuild Condition="$(Configuration) == 'Release'">true</RunAnalyzersDuringBuild>
```

Env vars are loaded as global properties before evaluation, but the conditional reassignment overwrites them when its condition fires. Only **command-line `-p:` global properties** (or equivalent — docfx's `metadata[].properties` field, MSBuild Tools' `GlobalProperties`) win against conditional project-file assignments.

Practical: when an env-var override "didn't work", reach for `-p:`. When invoking docfx, edit `docfx.json` metadata entries' `properties` field. See [`linq2db.docs:build.ps1`](https://github.com/linq2db/docs/blob/master/build.ps1) + `source/docfx.json` for the canonical pattern.

## Generating a source file from a csproj target

Emitting C# from MSBuild (e.g. surfacing central-package versions to code so they can't drift) hits two traps in a row:

- **An item's `Include` cannot mix literal text with an item reference** — `<_Line Include="const x = &quot;@(PackageVersion->WithMetadataValue('Identity','Npgsql')->'%(Version)')&quot;;" />` fails with **MSB4012** *"Item lists cannot be concatenated with other strings where an item list is expected"*. Properties have no such restriction, so build the whole file body as **one property** (inside the target, so item references are evaluated) and pass it to `WriteLinesToFile`.
- **`;` in that property splits it into multiple task items.** `Lines` is `ITaskItem[]`, so every C# statement terminator becomes an item boundary. Escape each one as `%3B`. An empty `Include=""` is also rejected (MSB4035) — drop blank lines rather than emitting them as items.

Write with `Overwrite="true" WriteOnlyWhenDifferent="true"` into `$(IntermediateOutputPath)` and add the result to `Compile` + `FileWrites` from the same target, gated `BeforeTargets="BeforeCompile"` so it runs per inner build (TFM-conditional `PackageVersion` entries then resolve correctly). Working example: `Source/LinqToDB.LINQPad/LinqToDB.LINQPad.csproj` → `GenerateNuGetPackageVersions` (added on #5786).
