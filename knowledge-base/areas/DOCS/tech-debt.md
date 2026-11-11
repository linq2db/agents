---
area: DOCS
kind: tech-debt
sources: [code]
confidence: medium
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# DOCS -- Tech debt

Aggregated from [detected-issues/index.json](../../detected-issues/index.json) (DI-6260..DI-6263) and the debt notes in [INDEX.md](INDEX.md). No GitHub issues are linked to these entries (`gh_issue: null`). `issues.md` and `decisions.md` do not exist for this area yet (new area this run).

## Detected issues

| ID | Severity | Title | Files | Status |
|---|---|---|---|---|
| DI-6260 | low | `metrics.md` links to an example on a non-existent `metrics` branch | `docs/source/articles/general/metrics.md:196` | open |
| DI-6261 | med | Docs build depends on a personal docfx fork release | `docs/docfx-version.json:3`, `docs/build.ps1:39`, `docs/source/docfx.json:2` | open |
| DI-6262 | low | `build.ps1` carries docfx/analyzer workarounds and a full F# pre-build | `docs/build.ps1:64`, `docs/source/docfx.json:101` | open |
| DI-6263 | low | Docs link to the GitHub wiki for release notes and migration guidance | `docs/source/articles/toc.yml:2`, `docs/source/articles/general/interceptors.md:332` | open |

### DI-6261 -- unreleased docfx fork (the only med item)

`docs/docfx-version.json` pins a release asset of the MaceWindu/docfx fork (tag, URL, SHA-256, `sourceCommit`) that carries dotnet/docfx#11090 (`assemblyUids` / `assemblyUidOverride`). The site cannot be built with stock docfx: without those options all assemblies that declare the `LinqToDB` namespace collide (dotnet/docfx#8966). Consequences: the pin needs a manual refresh during release prep (`/release-deps`), the fork's Roslyn must be at least the version `Source/CodeGenerators` builds against (else `CS8795` and "No .NET API detected"), and `docs/README.md` says to drop the download once the options ship in a released docfx.

### DI-6262 -- build workarounds

`docs/build.ps1` pre-builds `Source/LinqToDB.FSharp/LinqToDB.FSharp.fsproj` (Release, `RunAnalyzersDuringBuild=false`, `EnforceCodeStyleInBuild=false`) only so docfx can read the F# API from a DLL. This compiles `LinqToDB` across TFMs for one API surface, and the flags dodge IDE0390/IDE0391 on newer Roslyn. `docfx.json` pins `TargetFramework=net10.0` globally (docfx documents one TFM per project) and keeps the two netstandard2.0 analyzer projects via `TreatAsLocalProperty` (dotnet/docfx#10772). Each workaround is removable only when the upstream docfx issue is fixed.

### DI-6260 / DI-6263 -- external link rot risk

Both are links that depend on mutable external state: a `metrics` branch of an example repo that no longer exists, and the GitHub wiki (release notes in `articles/toc.yml`, migration guidance in `interceptors.md`). The wiki sits outside the repo and outside docs CI, so `--warningsAsErrors` cannot catch breakage.

## Debt from INDEX.md (not in detected-issues)

- Build is exercised on Windows only (`windows-2025` job). The F# pre-build adds cost per run.
- `linq2db.Remote.Wcf` and the EF entries do not set `TargetFramework`, so their API pages reflect the project first TFM.
- `LinqToDB.Identity` is outside `assemblyUids` by design. A future reference into it from another metadata entry would silently produce unqualified UIDs and lose links.
- `cli.md` mirrors `Source/LinqToDB.Scaffold` types by hand (schema records, model and metadata classes), with no generation link, so drift is silent. It also contradicts itself on the runtime requirement (".NET 6 or higher" vs "use .net core 3.1+") and has typos (`--custmize`, "multi-stange").
- `asp-dotnet-core/index.md` teaches the pre-.NET 6 `Startup.cs` model and spells the DI namespace two ways (`LinqToDB.Extensions.DependencyInjection` vs `LinqToDB.DependencyInjection.DependencyInjection`).
- `existing-db.md` opens with a T4-obsolete warning linking `xref:cli`, yet teaches T4 with .NET Framework 4.5.1 and `System.Data.SqlClient`, and links `xref:scaffold-t4` (target not verified).
- `faq.md` and `general/video.md` have no `uid` front matter, so they cannot be `xref` targets. `get-started/install/index.md` is an 11-line stub using `nuget install` only.

## Coverage caveat

10 of 25 Tier-2 articles (`links.md`, `t4.md`, 2 how-to, 2 project, 4 sql/merge) were not read, so debt in them is unknown.

## See also

- [INDEX.md](INDEX.md) -- area overview
- [patterns.md](patterns.md) -- area patterns
- [BUILD](../BUILD/INDEX.md) -- owner of `.github/workflows/docs.yml`

<details><summary>Coverage</summary>

Aggregated from `areas/DOCS/INDEX.md` (read in full), `detected-issues/index.json` entries DI-6260..DI-6263 (read), and `docs/` content as summarized by INDEX.md. `areas/DOCS/issues.md` and `decisions.md` were not found on disk. Source files under `docs/` were not re-read beyond the detected-issue citations.
</details>
