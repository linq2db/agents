# Work plan: issue-6118-enable-ci-analyzers — Re-enable Roslyn analyzers in CI

**Tier:** S  ·  **Status:** approved  ·  **Approved-at:** 2026-10-24 (user, E-1..E-4)  ·  **Branch:** issue/6118-enable-ci-analyzers
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

CI runs no Roslyn analyzers ([#6118](https://github.com/linq2db/linq2db/issues/6118)): Azure `build.yml` / `default.yml` pass `with_analyzers: false` to `templates/build-job.yml:237,246`, and `.github/workflows/build.yml:98,115,118,233` pass `-p:RunAnalyzersDuringBuild=false`. Violations merge green and surface only at release prep (#6114 hit `MA0008` / `NUnit4001`). The original blocker, the extension-lookup NRE fixed by dotnet/roslyn#80621, is shipped: measured, fix commit `16883a5` is contained in tag `Visual-Studio-2026-Version-18.3` (Roslyn 5.3, SDK 10.0.2xx) and absent from `…-18.0`; `CodeGenerators` builds against Roslyn 5.6 (`Directory.Packages.props:108-109`) and fails CS9057 on an older compiler, so every SDK that can build the repo carries the fix.

## P2 Success criteria

- SC-1 A full `dotnet build linq2db.slnx -c Release` with analyzers on (the Release default, `Directory.Build.props:122`) is clean on SDK 10.0.402 — measured on `9516c1cb8`: 0 errors, 0 warnings, 33 min, so no analyzer backlog needs clearing (#6114 cleared it); test projects are in the Release solution build, so no separate analyzer leg is needed → G-01
- SC-2 `Tests.FpuJit` (excluded from the Release solution build, `linq2db.slnx:413-417`) builds clean in Release with analyzers on → G-01
- SC-3 The GitHub `build` workflow and Azure `build` pipeline run analyzers and go green on the PR; failure observation: a red `Build solution` / `Build Solution for Nuget` step, or a CI log whose csc lines lack analyzer execution → G-01

## P6 Edit-points

- E-1 `Build/Azure/pipelines/build.yml:with_analyzers` — `false # …80621` → `true`
- E-2 `Build/Azure/pipelines/default.yml:with_analyzers` — `false # true` → `true`
- E-3 `.github/workflows/build.yml:build` — drop `-p:RunAnalyzersDuringBuild=false` from the hot-spot pre-build (kept property-identical with the solution build, per the step's own comment), `Build solution` and `Pack solution`; rewrite the `Analyzers stay off…` comment to keep only the API-analyzer rationale
- E-4 `.github/workflows/build.yml:fpu-jit-sweep` — drop `-p:RunAnalyzersDuringBuild=false` (the project is outside the solution's Release build, so this is its only analyzer run)

## P9 Verification gates

- G-01: pass — no test code changes. SC-1: `dotnet build linq2db.slnx -c Release -p:RunApiAnalyzersDuringBuild=false` on `9516c1cb8`, 0 errors / 0 warnings; SC-2: `dotnet build Tests/Tests.FpuJit/Tests.FpuJit.csproj -c Release -p:RunApiAnalyzersDuringBuild=false`, 0 errors / 0 warnings. SC-3 on `972114bb2` (#6130): GitHub run 40112962420 all legs green, `Build and pack` 20.3 min (14.4 min on master run 40108371444 with analyzers off, timeout 60); Azure `build` 24646 succeeded, 39.3 min (timeout 120)
- G-06: pass — `git diff --stat`: 3 files, 6+/8-, only the E-1..E-4 lines
- G-07: n/a — nothing under `Tests/Tests.Playground/` touched
