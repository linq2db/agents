# Work plan: infra-baselines-auto-resolve-conflicts — Resolve baselines rebase conflicts in the base branch's favour

**Tier:** S  ·  **Status:** approved  ·  **Approved-at:** 2026-11-10 (user: "ok, own" PR)  ·  **Branch:** infra/baselines-auto-resolve-conflicts
**Schema:** `.claude/docs/work-plan.md`  ·  **Gates:** `.claude/docs/definition-of-done.md`

## P1 Problem

When another PR's baselines merge to baselines master, a PR's existing `baselines/pr_<n>` branch can conflict with it. `Build/Azure/scripts/ensure-baselines-branch.ps1:117` rebases it with a plain `git rebase origin/$base` and on conflict fails the *Create Test Baselines Branch* job ("Delete branch and re-run tests"), skipping every test leg. The policy applied by hand is: accept the base's side of the conflict and let the run regenerate the PR's baselines (the legs push with `-X theirs`, `Build/CI/push-baselines.ps1:156`).

## P2 Success criteria

- SC-1 In a scratch repo where the PR branch conflicts with its base by modify/modify, by base-delete/PR-modify and by base-modify/PR-delete, the rebase step completes, each conflicted path ends with the base's content (or absent where the base deleted it), and a non-conflicting PR change survives; the unchanged plain rebase fails on the same repo  → G-01

## P6 Edit-points

- E-1 `Build/CI/baselines-base.ps1:Invoke-BaselinesRebase` (new) — rebase with `-X ours` (the base wins conflicting hunks), resolve any path still unmerged (modify/delete) to the base's side, continue; a function so the harness exercises the shipped code, not a copy
- E-2 `Build/Azure/scripts/ensure-baselines-branch.ps1:rebase loop` — call `Invoke-BaselinesRebase` instead of the plain rebase; failure message updated

## P9 Verification gates

- G-01: pass — `.build/.agents/baselines-autoresolve-harness.ps1` (scratch repo, git 2.56): `-Plain` control stops with a content conflict on a and modify/delete on b, c (rebase left in progress); `Invoke-BaselinesRebase` returns true with a=base, b absent (base deleted), c=base (PR deleted), d=PR's later edit, e=PR's new file, f=base, g absent, the wholly-conflicting commits dropped (log `pr-4,pr-1`), ~5-10 s. The "continue fails with nothing unmerged" exit is not exercised: git 2.56 drops a commit emptied by resolution itself. Caller `ensure-baselines-branch.ps1` parses with 0 errors; not run end-to-end (needs the baselines PAT)
- G-06: pass — diff confined to the new function and the rebase call plus its header sentence
- G-07: n/a — nothing under `Tests/Tests.Playground/`
