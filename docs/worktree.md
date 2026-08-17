# Worktrees

Worktree-workflow notes. The high-level "blocked `git checkout`" rule lives in [`agent-rules.md`](agent-rules.md) → *Creating a new branch* — this doc covers the worktree-specific mechanics once you're inside one.

## When to use a worktree

Only when the user explicitly asks. Do not silently `git worktree add` to work around a blocked `git checkout` / `gh pr checkout` — that hides the state conflict and fragments work across two directories. Ask the user how to proceed (stash, commit, discard) and name the blocking files in the question.

## `<worktrees-root>` — where worktrees go

Every recipe in the corpus writes the location as **`<worktrees-root>/<slug>`**. That is a *placeholder for an environment convention, not a corpus constant*: some setups keep a dedicated worktrees directory outside the clone, others put each worktree beside the primary clone. Take the actual root from auto-memory (or ask) before the first `git worktree add`; don't infer it from another recipe's example.

Two properties every recipe may rely on, whatever the root is:

- The worktree is **never inside** the primary clone, so the primary clone is not an ancestor of it (this is what breaks the `UserDataProviders.json` walk-up below).
- The worktree is **not** an ancestor of the primary clone either, so nothing in the primary clone's tree is picked up implicitly.

## Base an existing-branch worktree on `origin/<branch>`, not the local ref

`git worktree add <path> <branch>` checks out the **local** branch ref — and a plain `git fetch origin <branch>` does **not** fast-forward it (the fetch only advances `origin/<branch>` and `FETCH_HEAD`, leaving any pre-existing local `<branch>` stale). Worktreeing the bare name then bases your work on the stale tip: a `git merge origin/master` lands on old code, and the eventual `git push` is rejected non-fast-forward because the remote branch is actually ahead. For an existing (especially already-pushed PR) branch, create the worktree from the remote-tracking ref — `git worktree add <path> origin/<branch>` — or `git -C <worktree> reset --hard origin/<branch>` immediately after creating it, before doing any work. (Surfaced syncing PR #5648: worktree off the stale local `feature/…` ref → merge on a base 3 commits behind origin → push rejected → full redo after `reset --hard origin/<branch>`.)

**Never base a worktree on `FETCH_HEAD`.** `FETCH_HEAD` is rewritten by the next `git fetch` (any ref, any worktree sharing the clone), so `git worktree add <path> FETCH_HEAD` can land on a stale/base commit even right after the fetch that set it — and `git show FETCH_HEAD:<path>` and `git worktree add FETCH_HEAD` can disagree about which commit that is. Use the remote-tracking ref (`origin/<branch>`) or the explicit head SHA from `gh pr view <n> --json headRefOid`. After creating a **detached** worktree, verify `git -C <worktree> rev-parse HEAD` matches the intended head before editing — a wrong-base worktree shows the PR's changes as *absent* (the file still has pre-PR content, which reads as "the change isn't there" rather than an error). Recovery: `git -C <worktree> checkout <headSHA>` carries clean working-tree edits onto the right commit for any file the PR doesn't touch. (Surfaced on #5710: `worktree add FETCH_HEAD` landed on the PR base #5605; caught because `TestsInitialization.cs` lacked the PR's preload code.)

## Local / gitignored files in the main repo

When working inside an authorized worktree, local / gitignored files in the *main* repo (`UserDataProviders.json`, `.claude/settings.local.json`, etc.) don't need to be stashed — edits in the worktree leave the main repo untouched. They are also *not carried in*: gitignored files don't come with a new worktree, and `.claude/` itself arrives empty (see *Bootstrapping `.claude/` in a worktree* below), so a worktree starts without the primary clone's permission allowlist and without `UserDataProviders.json`.

Once you know you'll *edit* a file in the worktree, do the investigation `Read` / `Grep` against the **worktree** path, not the primary clone. `Edit`'s read-precondition is path-specific, so a read of the primary-clone copy doesn't satisfy it — you'd have to re-read the worktree copy before editing. Reading source the PR doesn't touch from the primary clone is harmless (same bytes), but it costs an extra round-trip the moment you decide to edit.

## `UserDataProviders.json` in a worktree

`TestConfiguration` finds this file by walking **up** the directory tree from the test assembly (`GetFilePath` in `Tests/Base/TestConfiguration.cs`), not from a fixed path — and the walk-up traverses **ancestors only**. A worktree is never placed **inside** the primary clone (see *`<worktrees-root>`* above), so the primary clone is not an ancestor of it. The walk-up from `<worktree>/.build/bin/…` therefore stops at the **worktree root** — which tracks only `UserDataProviders.json.template` — and never reaches the primary clone's `UserDataProviders.json`. A `--provider` run needs nothing from that file; a baseline-sensitive run does (see the second consequence below).

Two consequences:

- **Per-run provider selection: use `--provider`, don't copy/edit the JSON.** `<exe> --provider <name>` (or `/test … on <name>`) replaces the active provider set for that run, so you need neither a worktree-local file nor any `Providers`-array edit. The provider only needs a connection string (already in the tracked `DataProviders.json`) and, for server providers, a running container. See [`testing.md`](testing.md) → *Scoping a run to specific providers*.
  - **But once you *have* copied `UserDataProviders.json` in (per the next bullet), that file's connection set becomes authoritative and this no longer holds.** A provider defined only in the tracked `DataProviders.json` then fails at resolution with `LinqToDBException : Configuration '<name>' is not defined` — not a connection error, so it doesn't look like a container problem. The local file is typically older than the tracked one, so the versions this bites are exactly the newest ones. Check the *copied* file for the config name before spending a run on it, and prefer a provider you have already exercised in the session. (Surfaced 2026-07-30: `--provider PostgreSQL.19` failed this way although `DataProviders.json` defines `PostgreSQL.19` — the copied `UserDataProviders.json` predated PG19 — wasting a test leg and a `docker start`.)
- **Baseline-sensitive runs need `UserDataProviders.json` copied into the worktree root, or they come back vacuously green.** `BaselinesManager.Dump` is gated on `TestConfiguration.BaselinesPath`, which lives only in `UserDataProviders.json` (not the template). The worktree's walk-up never finds it, so `BaselinesPath` is null, the direct-vs-remote `.sql` / `.sql.other` comparison silently no-ops, and a divergence-introducing change passes **undetected** (a green run that never ran the parity check). Copy the primary clone's `UserDataProviders.json` into the worktree root (gitignored scratch) before such runs, and confirm a baseline file's mtime updated during the run. The same copy also lets you set a *different default provider set* for the worktree (adjust the `Providers` list under the TFM, e.g. `NET100` for `net10.0`) — don't edit the primary clone's copy for a worktree-scoped run, it affects every future main-repo run too.

## Running tests from a worktree

`test-runner`, `/test`, and `/test-providers` accept an explicit repo-root override so a worktree can be the test target instead of the primary clone — without it the skills resolve project paths against the inherited primary-clone cwd and build/test the *primary* clone, not the worktree.

**A wrong-clone run can read as a false *green*, not an error.** If the filter also matches a test that exists in the primary clone (typically the injected `CreateData.CreateDatabase` prefix), `test-runner` reports *that* test passed while the worktree's new tests match **zero** — a nonzero pass count with the new tests never executed. So don't trust a bare "N passed": confirm the run's `--project` path is the worktree **and** the specific new test names appear in the summary. (Surfaced on #1553: a `GeneratedShape` run reported *2 passed* — both `CreateDatabase` — because the primary clone had no `GeneratedModel.fs`; re-run with the worktree path showed the two real tests across all TFMs.)

1. **Env** — start the container(s) the test needs (`/test-providers` owns container start/stop). Provider *selection* is per-run via `--provider` (next step), so no worktree-local `UserDataProviders.json` seeding or `Providers`-array enable is required — the provider only needs a connection string in the tracked `DataProviders.json`. A `--provider` naming a **stopped** container fails every `[DataSources]` case with `connection refused`, which looks like a wave of regressions but is just the dead container — start it first.
2. **Run** — `/test run <filter> worktree <abs-worktree-path>`: `/test` passes `repoRoot=<worktree>` to `test-runner`, which runs `dotnet test --project <worktree>/<project> --provider <names>` so the worktree's code is built and exactly those providers run. Prepend `CreateData.CreateDatabase` to the filter only when the test needs the full schema — a self-contained `CreateLocalTable` test doesn't, which avoids rebuilding the target DB.
3. **Scratch** — a `<Compile Include>` link added to the worktree's `Tests.Playground.csproj` for a fast Playground build (and any worktree-local `UserDataProviders.json` you seeded for a different default set) is scratch: keep it out of any commit (stage with explicit pathspec; see [`agent-rules.md`](agent-rules.md) → *Git commit rules*).

**`Set-Location <worktree>` and the `dotnet` call must be a *single* PowerShell tool call.** The PowerShell tool's working directory does **not** survive between invocations in this harness — a standalone `Set-Location C:\…\<worktree>` comes straight back with *"Shell cwd was reset to `<primary clone>`"*, so the following call still runs from the primary clone and `--settings .runsettings` / `global.json` resolve against the wrong tree. Chain them with `;` in one command: `Set-Location <abs-worktree>; dotnet test --project Tests/Linq/Tests.csproj -f net10.0 --filter … -c Debug --settings .runsettings --provider <names> > <abs-log-path> 2>&1`. (The `;` is ordinary PowerShell here — the compound-command restriction in [`agent-rules.md`](agent-rules.md) applies to the **Bash** tool, which is also why this has to go through the PowerShell tool rather than `Bash(pwsh -Command …)`.) Redirect to an absolute log path under the primary clone's `.build/.agents/`, then `Grep` it — the run's own cwd is the worktree, so a relative redirect lands in the wrong tree.

**Run artifacts land in the *primary clone's* `.build/.agents/`, not the worktree's.** The heartbeat
(`test-progress.<tfm>.<pid>.json`) and anything else a test process writes to a relative path resolve
against the *process's* working directory, which for a `--project <worktree>/…` run is still the
inherited primary-clone cwd. So a worktree run's progress file appears under the primary clone even
though the code, build output and `--settings` all come from the worktree — look there before
concluding the run isn't reporting. The same applies to temporary in-library instrumentation: hardcode
an absolute output path or accept that the dump follows the cwd. (Cost two wrong-directory lookups on
2026-08-12, once while waiting on a full-suite run that was in fact heartbeating normally.)

**EFCore single-test runs (EF3 / EF8 / EF9 / EF10).** EF tests live in their own projects (`Tests/EntityFrameworkCore/Tests.EntityFrameworkCore.EF<n>.csproj`), which `test-runner` targets directly via `--project … Tests.EntityFrameworkCore.EF10.csproj`. **Each is single-TFM, and that TFM is not net10.0 for all of them** — `EF3` → `net462`, `EF8` → `net8.0`, `EF9` → `net9.0`, `EF10` → `net10.0`; pass the matching `-f`. The net462/EF Core 3.1 project is what the CI legs named `EF.Core Tests (NETFX …)` run, so a failure appearing only on NETFX legs reproduces only there. Provider resolution differs from the main suite: `[EFDataSources]` / `[EFIncludeDataSources]` yield `TestConfiguration.UserProviders ∩ TestConfiguration.EFProviders`, where `EFProviders` is a curated list (`SQLiteMS`, `SqlServer2016+MS`, `PostgreSQL13+`, …). So the target provider must be both in that curated set **and** passed via `--provider` (or enabled in the worktree's `UserDataProviders.json`) — enabling a non-EF provider like `SQLite.Classic` resolves **zero** EF tests. `SQLite.MS` needs no container, so it's the cheapest EF target for a worktree run. (Surfaced on PR #5525: a single EF10 `IgnoreQueryFilters([])` regression test was run red→green on `SQLite.MS` via `/test … worktree`.)

**Reviewing / verifying a PR's *own* new tests — run them yourself, not via `test-runner`.** When the tests under verification are **added by the PR** (absent from the primary clone's checkout), `test-runner` reports the fixture "doesn't exist" if pointed at the primary clone, and — being Bash-only, it can't `Set-Location` into the worktree — blocks on the worktree's `global.json` runner resolution (MTP-vs-VSTest, exit 2) when pointed there. On the block it tends to **rogue-spawn detached `dotnet` background jobs** that leak processes and lock the worktree directory against later `git worktree remove`. Instead: create the worktree off `origin/pr/<n>`, seed its `UserDataProviders.json`, and run the tests yourself — `Set-Location <worktree>` then `dotnet test --project Tests/Linq/Tests.csproj -f net10.0 --filter "…" -c Debug --settings .runsettings --provider <names>` via the **PowerShell tool**, capturing to a log under `.build/.agents/` and `Grep`-ing the `Test run summary:` + `^(failed|skipped) ` lines (MTP prints only failed/skipped per-test; succeeded ones show in the summary count only). Before `git worktree remove`, kill stray `dotnet`/`testhost` and run `dotnet build-server shutdown` to release the directory lock. (Surfaced on PR #5643; matches the PR #5627 worktree-MTP precedent.)

## Regenerating API baselines from a worktree

`/api-baselines` takes a **`repoRoot` argument** (added 2026-08-04) — pass `repoRoot <abs-worktree-path>` and it addresses the branch check, the suppression-file Glob, the `dotnet pack`, and the diff/revert against that tree. `/release-verify` step 4 passes its worktree automatically. Prefer this over the manual recipe below.

Without it the skill defaults to the session cwd, which is the *primary* clone — usually on `master`, so it regenerates the wrong tree's baselines and produces a diff that is empty or plausible-but-wrong.

The manual equivalent below remains valid (e.g. to regenerate a single project rather than all packable ones). It is the sanctioned action the skill wraps, not a hand-edit (which stays banned, per [`agent-rules.md`](agent-rules.md) → *Agent guardrails* → **Never hand-edit API baseline files**):

1. From the worktree (`Set-Location <worktree>` so `global.json` resolves), run `dotnet pack <Source/Project>/<Project>.csproj -c Release -p:ApiCompatGenerateSuppressionFile=true` for each affected project. `ApiCompatGenerateSuppressionFile=true` overwrites the file with all current suppressions, so the git diff is the minimal delta for the change.
2. Do the `LinqToDB.Internal.*` policy review by hand on the diff (the skill's value-add): any non-`Internal.*` suppression added is a public-contract break needing explicit user sign-off.
3. A **clean** (empty) diff means the change isn't ApiCompat-flagged — no baseline update is needed. (Surfaced on #5639: a shipped public static field→property regen was a no-op — see auto-memory `project_apicompat_field_to_property_noop`.)

## `git worktree remove` always needs `--force` — the corpus is a submodule

Plain `git worktree remove <path>` refuses on **every** linq2db worktree:

```
fatal: working trees containing submodules cannot be moved or removed
```

Since the agent-instruction corpus became a submodule at `.claude/` ([#5735](https://github.com/linq2db/linq2db/pull/5735)), every worktree contains one, so this is unconditional — not a symptom of a dirty tree, an unpushed submodule commit, or a lock. `git` declines to reason about nested `.git` administrative files at all. `--force` removes it fine.

Because the failure mode is a *flat refusal* rather than a warning, don't read it as "something in here is unsaved" and go hunting. Do the check explicitly instead, since `--force` will discard whatever it finds: `git -C <path> status --short` **and** `git -C <path>/.claude status` (the superproject's status is blind to the corpus — `submodule.ignore = all`). Then remove with `--force` and confirm via `git worktree list`.

Surfaced during 6.4.0 release-prep cleanup, on a worktree whose tree was completely clean.

## Removing a worktree blocked by file locks

`git worktree remove --force <path>` may fail with `error: failed to delete '<path>': Permission denied` when the worktree was recently built — VBCSCompiler / MSBuild server still holds file handles inside `.build/bin/` even though git's internal worktree registration was successfully dropped (`git worktree list` no longer shows it).

Most removals don't hit this — `git worktree remove --force <path>` succeeds outright once the worktree's own build has finished, no shutdown needed. And **on a shared / multi-worktree machine, do not lead with `dotnet build-server shutdown`**: it is global per-SDK and kills the VBCSCompiler / MSBuild servers that *other* concurrent worktree builds are using, disrupting them mid-build. (This repo is routinely checked out as a dozen parallel worktrees — `git worktree list`.) Reach for `build-server shutdown` only when removal is genuinely lock-blocked **and** no other builds are running.

Cleanup (only when removal is lock-blocked): **`pwsh -NoProfile -File .claude/scripts/remove-worktree-locked.ps1 -Path <worktree-path>`**. It tries `git worktree remove --force` first (the common, no-shutdown case), then `Remove-Item -Recurse -Force` (succeeds in practice even with the lock-reporting process still around), then `git worktree prune`. Build-server shutdown is **off by default** per the shared-machine guard above — pass `-AllowBuildServerShutdown` only once you've confirmed no other worktree builds are running. Don't loop on `git worktree remove --force` — it'll keep failing on the same locked dll.

## Bootstrapping `.claude/` in a worktree

`git worktree add` internally runs `reset --hard --no-recurse-submodules`, so it **cannot** populate the `.claude/` submodule: the new worktree gets an *empty* `.claude/` directory — and since an unpopulated submodule is not a deletion, `git status` there reads **clean**. An agent working in that worktree loads no `AGENTS.md`, no `CLAUDE.md`, no skills, with nothing signalling the absence. Bootstrap it before doing any work; the one-line trigger is in [`agent-rules.md`](agent-rules.md) → *The corpus is a submodule*.

- **Recipe.** Clone the corpus into the worktree, borrowing the primary clone's objects so it costs no download:
  `git clone --reference <primary-clone>/.claude --dissociate --branch master https://github.com/linq2db/agents.git <worktree>/.claude`
  ~15 MB, near-instant, and independent afterwards: `git -C <worktree>/.claude pull --ff-only` keeps it current and `git worktree remove --force` cleans it up (`git help worktree`: unclean worktrees *or ones with submodules* need `--force`).
- **Don't substitute a directory junction (or symlink) to the primary clone's `.claude/`.** It looks strictly better — one live corpus, no duplication, no per-worktree pull — and it *half* works: files are readable through it and `git -C <worktree>/.claude rev-parse HEAD` resolves. But `Glob` does not traverse a reparse point used as a path component, so `Glob(".claude/skills/*/SKILL.md", path=<worktree>)` returns **zero files** while the same pattern in the primary clone returns 34 — the exact defect the `.claude` → `.agents` symlink used to cause (see [`windows-gotchas.md`](windows-gotchas.md)). Git-level access is broken too: the corpus's relative `gitdir:` resolves against the junction's parent, so `git status` in the worktree reports *"fatal: not a git repository: .claude/../.git/modules/.claude"*. Measured 2026-07-31; a control `Glob` for a real directory in the same worktree worked, so the cause is the junction, not the worktree.
- **Do not run `git submodule update --init` inside a linked worktree.** The submodule's git dir is shared (`$GIT_COMMON_DIR/modules/.claude`) and holds a single `core.worktree`, so initializing from a second worktree repoints the **primary** clone's `.claude` metadata at that worktree. `git help worktree` BUGS is explicit: *"It is NOT recommended to make multiple checkouts of a superproject"* with submodules. Git 2.21+ aborts some of these cases to limit the damage — don't rely on it catching yours.
- **Only the primary clone runs `git submodule …`.** From a worktree, address the corpus directly (`git -C <worktree>/.claude <cmd>`). Git otherwise tries to absorb the worktree's embedded git dir into the shared `modules/.claude` slot the primary already owns.
- **A corpus edit made from a worktree lands in that worktree's copy only.** Push it to the agents repo from there (`git -C <worktree>/.claude push`) and fast-forward the primary clone (`git -C <primary>/.claude pull --ff-only`), or make the edit in the primary clone in the first place. Nothing reconciles the two for you.

## Release-prep orchestration model

When `/release` runs against a `release-prep/<ver>` worktree, the moving parts split between two clones:

| Clone | Branch | Owns |
|---|---|---|
| `<clone-dir>` (primary clone) | whatever it sits on, normally `master` | `.claude/` skills + scripts; orchestrator state file at `.build/.agents/release-<ver>.json`; per-task plan caches; walk-decisions tracker |
| `<worktrees-root>/release-<ver>` (worktree) | `release-prep/<ver>` | source-tree edits (`Directory.Packages.props`, `.editorconfig`, csproj `VersionOverride` sites, code fixes); per-build outputs under `.build/bin/` |

**Cross-clone calling pattern:** sub-skills that need to run a script from inside the worktree invoke `pwsh -NoProfile -File <primary-clone>\.claude\scripts\<name>.ps1 ...` with an absolute path back to the primary clone. The script's `Get-Location` then yields the worktree, so file-system reads (Directory.Packages.props parsing, source globbing) target the right tree. The PowerShell tool's working directory is set explicitly via `Set-Location <worktree>` before each cross-clone call.

**State files** always under the primary clone (`<primary-clone>\.build\.agents\release-<ver>*.json` etc.) — one canonical location regardless of which clone the agent is operating from. Plan caches written by sub-skills running in the worktree should also write there (pass `-WriteDir <abs-path>` if the script defaults to a relative `.build/.agents/`).

**Disk pressure.** Each Release build of `linq2db.slnx` adds ~9 GB of `.build/bin` output. With a worktree, that's two `.build/bin/` trees (the primary clone's may be empty if no builds run there; the worktree's accumulates per release-prep cycle). When iterating against a near-full C: drive, clean per the *Iterative-build gotchas* section in [`windows-dev-gotchas.md`](windows-dev-gotchas.md).

**Session resume primer.** Without the orchestration-model context above, the agent rediscovers the dual-clone setup from scratch each session — costs 10-20 turns. Resume prompts for /release should explicitly state: "orchestrator runs from the primary clone; worktree at `<path>`; state file at `<path>`".
