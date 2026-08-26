## MSBuild property override precedence

When overriding a property like `RunAnalyzersDuringBuild` / `EnforceCodeStyleInBuild` / `TreatWarningsAsErrors` against `linq2db` source (consumed as a submodule by `linq2db.docs` for docfx metadata extraction, or as a project reference in any consumer), env vars **don't override** conditional `<PropertyGroup>` reassignments in the project's `Directory.Build.props`. Pattern:

```xml
<RunAnalyzersDuringBuild>false</RunAnalyzersDuringBuild>
<RunAnalyzersDuringBuild Condition="$(Configuration) == 'Release'">true</RunAnalyzersDuringBuild>
```

Env vars are loaded as global properties before evaluation, but the conditional reassignment overwrites them when its condition fires. Only **command-line `-p:` global properties** (or equivalent — docfx's `metadata[].properties` field, MSBuild Tools' `GlobalProperties`) win against conditional project-file assignments.

Practical: when an env-var override "didn't work", reach for `-p:`. When invoking docfx, edit `docfx.json` metadata entries' `properties` field. See [`linq2db.docs:build.ps1`](https://github.com/linq2db/docs/blob/master/build.ps1) + `source/docfx.json` for the canonical pattern.

## A `-p:` override *replaces* a list property — it does not append to it

`-p:` winning against conditional project assignments (above) is the same mechanism that makes it dangerous for **list** properties like `NoWarn`, `DefineConstants` or `Polyfill`. A global property cannot be appended to from inside the project, so every `<NoWarn>$(NoWarn);CS0649</NoWarn>` in the tree evaluates `$(NoWarn)` to *your* value and the project's own additions are discarded — silently, because the build fails on something unrelated to what you were suppressing.

Suppressing one analyzer rule to get past a pre-existing failure is where this bites:

- `-p:NoWarn=MA0206` on `Tests/Linq/Tests.csproj` wiped `Directory.Build.props:43`'s list (which carries `1591`) and produced **several hundred CS1591s** across the public test helpers. The one rule was suppressed correctly; the collateral was the whole suppression policy.
- **`WarningsNotAsErrors` is not a substitute.** It demotes warnings that `TreatWarningsAsErrors` promoted — it cannot touch a rule whose `.editorconfig` severity is already `error` (`dotnet_diagnostic.MA0206.severity = error`). The build fails identically.
- The shape that works is the **full union**, with `%3B` separators — a bare `;` inside `-p:NoWarn="a;b"` is parsed as a switch separator and dies with `MSB1006: Property is not valid. Switch: <second item>`:

```
dotnet build <proj> -c Release -f net10.0 -p:NoWarn=1573%3B1591%3B…%3BMA0206
```

Collect the union from `Directory.Build.props`'s `<NoWarn>` plus every `<NoWarn>$(NoWarn);…</NoWarn>` on the project's props chain (`Tests/linq2db.TestProjects.props`, `Tests/linq2db.Providers.props`). Before reaching for any of this, check whether the failing site is pre-existing (`git diff origin/master...HEAD -- <file>`) — if it is, and it sits in a *dependency* project, it aborts the build of everything downstream, which is a different problem from one extra error in the project you care about.

## Scoping a shared property or override — sweep the consumers first

A property defined in `Directory.Packages.props` (or any shared props file) reaches a project only where that project *opts in*, and the opt-in shape decides the blast radius. Before adding, narrowing or widening one, enumerate every consumer and state which are affected — don't reason from the project you happen to be editing.

- **`VersionOverride` is opt-in per `PackageReference`.** A plain `<PackageReference Include="X" />` elsewhere keeps the central `PackageVersion`, so a driver-specific pin like `$(RoslynLinqPadVersion)` cannot leak into `linq2db.cli`, the source generators or the analyzers. Confirm with a `Grep` for the property name plus one for the package id across `**/*.csproj` — two searches, and the answer is definitive.
- **An unconditional `ItemGroup` in a multi-TFM project is not "the project's" scope, it is every TFM's.** This is where a well-intentioned pin does damage; see [`agent-rules.md`](agent-rules.md) → *A comment a change has falsified is often the symptom*.
- **Verify the resulting split empirically**, not by reading conditions: `project.assets.json` lists the resolved version per target, so a two-line `Grep` proves each TFM got what was intended.

(Prompted on #5786, where the maintainer asked "ensure other roslyn users not affected, like linq2db.cli" — the sweep was two greps and confirmed the pin was opt-in, but it had not been done until asked.)

## Generating a source file from a csproj target

Emitting C# from MSBuild (e.g. surfacing central-package versions to code so they can't drift) hits two traps in a row:

- **An item's `Include` cannot mix literal text with an item reference** — `<_Line Include="const x = &quot;@(PackageVersion->WithMetadataValue('Identity','Npgsql')->'%(Version)')&quot;;" />` fails with **MSB4012** *"Item lists cannot be concatenated with other strings where an item list is expected"*. Properties have no such restriction, so build the whole file body as **one property** (inside the target, so item references are evaluated) and pass it to `WriteLinesToFile`.
- **`;` in that property splits it into multiple task items.** `Lines` is `ITaskItem[]`, so every C# statement terminator becomes an item boundary. Escape each one as `%3B`. An empty `Include=""` is also rejected (MSB4035) — drop blank lines rather than emitting them as items.

Write with `Overwrite="true" WriteOnlyWhenDifferent="true"` into `$(IntermediateOutputPath)` and add the result to `Compile` + `FileWrites` from the same target, gated `BeforeTargets="BeforeCompile"` so it runs per inner build (TFM-conditional `PackageVersion` entries then resolve correctly). Working example: `Source/LinqToDB.LINQPad/LinqToDB.LINQPad.csproj` → `GenerateNuGetPackageVersions` (added on #5786).
