# Work plan: infra-baselines-retarget-exit-code — Keep a failed baselines-PR retarget non-fatal

**Tier:** S  ·  **Status:** approved  ·  **Approved-at:** 2026-11-10 (user: "own PR")  ·  **Branch:** infra/baselines-retarget-exit-code
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

`Update-BaselinesPrBase` (`Build/CI/baselines-base.ps1:66`) reports a failed `gh api -XPATCH` retarget with `Write-Host` only, as a non-fatal condition, but leaves the non-zero `$LASTEXITCODE` set. `Build/Azure/scripts/ensure-baselines-branch.ps1:151` calls it last, so the Azure PowerShell task exits 1, the `Create Test Baselines Branch` job fails and every Win/Lin test leg is skipped. Observed on Azure build 25464 (#5944): GitHub answered 422 retargeting baselines PR #2282 to `baselines/pr_5942`, because `baselines/pr_5944` is identical to it (compare: ahead 0, behind 0). `Build/CI/push-baselines.ps1:182` exits 0 explicitly after the call and is unaffected.

## P2 Success criteria

- SC-1 With `gh` failing the PATCH, `$LASTEXITCODE` is 0 after `Update-BaselinesPrBase` returns and the log line carries the error code and gh output; with the edit reverted the same harness reports 1  → G-01

## P6 Edit-points

- E-1 `Build/CI/baselines-base.ps1:Update-BaselinesPrBase` — capture the PATCH output into the failure message and reset `$global:LASTEXITCODE` to 0 after logging

## P9 Verification gates

- G-01: pass — scratch harness (`.build/.agents/baselines-retarget-harness.ps1`, stub `gh` failing the PATCH with exit 1): before the edit `LASTEXITCODE after call: 1`, after it `0` with the 422 text in the log line; no linq2db test reaches CI scripts
- G-06: pass — `git diff --stat`: 1 file, 5+/2-, all inside `Update-BaselinesPrBase`
- G-07: n/a — nothing under `Tests/Tests.Playground/`
