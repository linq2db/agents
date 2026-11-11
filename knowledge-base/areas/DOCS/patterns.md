---
area: DOCS
kind: patterns
sources: [code, conventions]
confidence: medium
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# DOCS -- Patterns

## Applicable conventions

- No entries in [conventions/](../../conventions/) cite files in this area (no C# types here).

## Recurring structural patterns

- **Assembly-qualified UIDs.** Every API reference link and `uid` uses the `<assembly>::<FullName>` form, e.g. `xref:linq2db::LinqToDB.ProviderName`. File names turn `::` into `--`. Source: top-level `assemblyUids` plus per-entry `assemblyUidOverride` in `docs/source/docfx.json`.
- **One metadata entry per Source project, mirrored in nav.** Each of the 17 `metadata` entries has `filter: filter.yml`, its own `output` `api/<name>`, and a matching item in the "API Documentation" dropdown of `docs/source/toc.yml`. Adding one requires both edits.
- **Single-TFM documentation.** `TargetFramework=net10.0` is passed globally, F# is read from the built netstandard2.0 DLL, and the EF Core entries override the assembly UID because all four build `linq2db.EntityFrameworkCore`.
- **Pinned, hash-verified tool download.** `docs/docfx-version.json` (`tag`, `url`, `sha256`, `sourceCommit`) drives `docs/build.ps1`. The zip is cached under `.build/docfx/<sha256>/` and a hash mismatch deletes it and throws. The CI cache key is the pin file.
- **Same script locally and in CI.** `./docs/build.ps1` runs from the repo root, and CI adds `-WarningsAsErrors`.
- **Section-per-folder TOC.** `articles/toc.yml` plus a nested `toc.yml` per section (merge has its own). `uid:` front matter marks articles meant to be cross-linked (`Interceptors`, `databases`, `Metrics`, `Bulk-Copy`, `CTE`, `cli`).
- **Root files reused as pages.** `docs/source/index.md` is an `[!include]` of the root `README.md`, and the Contributing article includes `CONTRIBUTING.md`. Edits to those root files trigger the docs workflow.
- **Gated CI with always-reporting check.** A `changes` job decides whether the build runs, so a skipped docs check still satisfies branch protection. Deploy happens only on non-prerelease releases or a manual `v*` dispatch.
- **NoTargets visibility project.** `docs/Docs.csproj` (`Microsoft.Build.NoTargets`) exists only so the folder shows in Solution Explorer. It strips injected `PackageReference`/`Compile` items.
- **Hand-maintained reference mirrors.** `cli.md` duplicates `Source/LinqToDB.Scaffold` schema/model/metadata types by hand and is prone to drift (see [tech-debt.md](tech-debt.md)).

## Recorded decisions affecting this area

- No area-scoped `decisions.md` exists yet. Decisions evidenced in code: move the site into the repo (#6265), use a custom docfx fork until dotnet/docfx#11090 ships, leave `linq2db.Identity` out of `assemblyUids`, document one TFM per project.

## See also

- [INDEX.md](INDEX.md) -- area architecture
- [tech-debt.md](tech-debt.md) -- detected debt (DI-6260..DI-6263)
- [BUILD](../BUILD/INDEX.md) -- docs workflow owner

<details><summary>Coverage</summary>

Derived from `areas/DOCS/INDEX.md` (read in full) and the detected-issues entries for DOCS. `issues.md` and `decisions.md` were not found on disk for this area. No conventions reference DOCS files.
</details>
