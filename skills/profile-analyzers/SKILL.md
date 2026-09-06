---
name: profile-analyzers
description: Measure Roslyn analyzer build-time cost. Two modes - `solution` runs a whole-solution rebuild with `/reportanalyzer` and ranks every analyzer (release-time regression check after an analyzer-package bump); `rules` measures linq2db's *own* analyzers (internal LINQ2DB0xxx against Source/LinqToDB, shipped L2DB1xxx against Tests/Linq) and reports a per-rule table of times, a total, and a verdict against a committed baseline. Use when the user asks to profile analyzers, says "analyzers got slow", "which analyzers are slowest", "why is the build slow", "how expensive is this rule", or as part of `/create-analyzer` / `/dogfood-analyzer` / `/release-deps`.
---

# /profile-analyzers

## Two modes — pick one before doing anything else

| Mode | Question it answers | Target | Cost |
|---|---|---|---|
| **`solution`** | did an analyzer-*package* bump regress the build? | `linq2db.slnx`, whole-solution rebuild | 10-25 min |
| **`rules`** | how expensive is *our* analyzer, and did an existing one regress? | one project (`Source/LinqToDB` or `Tests/Linq`) | ~20 min |

Different measurements against different targets, with **separate baselines** — never diff one against the other. `solution` is the release-prep check invoked by `/release-deps` / `/release-verify`; `rules` is the authoring check invoked by `/create-analyzer` / `/dogfood-analyzer`. When the ask is ambiguous ("profile the analyzers"), ask which.

---

# Mode: `solution`

## What this skill is (and isn't)

**Is:** the analyzer-perf-profiling phase. One full Release rebuild with `-p:ReportAnalyzer=true -v:detailed` produces a per-project per-analyzer time table; the parser ranks (analyzer x project) pairs, total per-analyzer time, and total per-project time. Used to decide whether an analyzer-package bump regressed the codebase's build time.

**Isn't:**
- Not the verification build. The verification build (`dotnet build linq2db.slnx -c Release`) only checks that compilation passes; this skill is on top of that, with extra MSBuild flags to surface the analyzer report. Wall-clock cost: 10-25 min on `linq2db.slnx`.
- Not for CI. CI already runs the full matrix; this is local diagnostic work.
- Not auto-triggered. Always explicit user request — including from `/release-deps`, the orchestrator must ask before invoking.

## When to run

User-invoked. Good triggers:

- `analyzers got slow`
- `which analyzers are slowest`
- `profile the build`
- `why is the build slow`
- explicit `/profile-analyzers`
- after `/release-deps` bumped any analyzer package (Meziantou.Analyzer, NUnit.Analyzers, Microsoft.CodeAnalysis.*Analyzers, AsyncFixer, Lindhart.Analyser.MissingAwaitWarning, etc.) — `/release-deps` proposes invoking this skill at the end of the verification-build phase. The user still confirms.

Skip if the user only wants to measure one project — a plain `dotnet build <project.csproj> -p:ReportAnalyzer=true -p:UseSharedCompilation=false -v:detailed` gives the same report for that one project without the full rebuild.

## Non-obvious MSBuild flags

Roslyn emits the `/reportanalyzer` summary through `csc.exe`'s stdout. Four things interact to make the report invisible at defaults:

1. **MessageImportance.Low** — MSBuild logs each line from csc at Low importance, which `-v:normal` filters out. **Use `-v:detailed`**.
2. **VBCSCompiler (shared compilation)** can swallow the report (the output is returned in the compile response, not written to stdout MSBuild captures). **Use `-p:UseSharedCompilation=false`**.
3. **Incremental** skips `CoreCompile` for up-to-date projects and no report is emitted for them. **Use `-t:Rebuild`** to measure the whole solution.
4. **Enable the report itself:** `-p:RunAnalyzersDuringBuild=true -p:ReportAnalyzer=true`.

The provided scripts already pass all four.

## Required reading

- [`.claude/docs/agent-rules.md`](../../docs/agent-rules.md) → **Bash command rules**, **Running tests** (we're not running tests here, but the build-vs-test separation is the same).
- [`.claude/docs/release/nuget-package-notes.md`](../../docs/release/nuget-package-notes.md) → analyzer-package rules (when an analyzer regresses, the per-package note may capture the workaround).

## Procedure

### 1. Confirm the user wants the long run

Tell the user: "this is a full Release rebuild with `-v:detailed`, expected wall-clock 10-25 min on `linq2db.slnx`. Continue?" Wait for explicit yes. The skill never auto-launches.

### 2. Run the instrumented rebuild

```
pwsh -NoProfile -File .claude/scripts/analyzer-profile-build.ps1 -LogPath .build/.agents/analyzer-build.log
```

Defaults: `-SolutionPath linq2db.slnx`, `-Target Rebuild`, `-Configuration Release`. The script:
- Runs `dotnet build` with the four flags above.
- Writes the full log to `-LogPath`.
- Returns `{ logPath, exitCode, elapsedMs }`.

It does **not** shut the build servers down, and must not be made to. `dotnet build-server shutdown` is machine-global — parallel sessions, other worktrees and the user's IDE share the node pool — and is prohibited outright. It is also unnecessary: `-p:UseSharedCompilation=false` makes MSBuild spawn `csc.exe` directly instead of talking to VBCSCompiler, so a resident server cannot swallow the report.

If the rebuild halts on a pre-existing analyzer error on an unrelated file, pass `-ExtraArgs '-p:TreatWarningsAsErrors=false'`. Then fix the underlying error in a separate change — do not commit `TreatWarningsAsErrors=false` to the repo.

### 3. Parse the log

```
pwsh -NoProfile -File .claude/scripts/analyzer-profile-report.ps1 -LogPath .build/.agents/analyzer-build.log -Top 10
```

Output: three pretty tables on stdout, plus a one-line diagnostics header (per-analyzer rows / project reports / distinct analyzers).

For programmatic consumption: `-AsJson` returns `{ slowestPairs, busiestAnalyzers, projectTotals, diagnostics }` to stdout (see the script's comment header).

**Expect a possible `CS2012` on the *next* build in the same tree.** `-p:UseSharedCompilation=false` gives every project its own `csc.exe` instead of reusing the compiler server, and those processes can outlive the run holding handles on the analyzer and source-generator assemblies — exactly the DLLs every other project loads as an analyzer. The next `dotnet build` then dies with `CS2012: Cannot open '…LinqToDB.Analyzers.dll' (or CodeGenerators.dll) for writing`, which reads like a corrupt tree rather than a stale lock.

Retry once — the handles are released as those processes exit. Do **not** reach for `dotnet build-server shutdown` or kill `dotnet` / `csc` / `VBCSCompiler`: both are machine-global on a box shared with parallel sessions, other worktrees and the user's IDE, and both are prohibited (`agent-rules.md`; global CLAUDE.md → *Shared build server*). Running the profiling build in a **throwaway worktree** confines the locks to a tree you are about to delete, which is the actual fix and is what `rules` mode mandates; for `solution` mode, if a retry doesn't clear it, say what is blocked and let the user decide (see [`worktree.md`](../../docs/worktree.md) → *Removing a worktree blocked by file locks*).

### 4. Present the three rankings

The agent reads the tables and presents to the user, flagging the dominant offender(s):

- **Top N slowest (analyzer x project) pairs** — where one analyzer is particularly painful in one project.
- **Top N busiest analyzers** — sum across projects; uniformly expensive analyzers rise.
- **Top N projects by total analyzer time** — which projects dominate the build cost.

### 5. Compare against the previous baseline, then re-save it

The baseline lives at **`.claude/docs/release/analyzer-perf-baseline.json`** — in the corpus, so it persists across releases and across clones. Shape:

```json
{
  "capturedOn": "<iso-date>",
  "release": "<version the capture was taken during>",
  "analyzerPackages": { "Meziantou.Analyzer": "3.0.138", "NUnit.Analyzers": "4.14.0" },
  "busiestAnalyzers": [ { "analyzer": "<id>", "totalSeconds": 0 } ],
  "projectTotals":    [ { "project": "<name>", "totalSeconds": 0 } ]
}
```

Procedure:

1. **If the file exists**, diff the current run's `busiestAnalyzers` against it and report, per analyzer: `totalSeconds` now, then, and the delta (absolute + %). Sort by regression size, not by absolute cost — a rule that went 40s → 400s matters more than one that has always cost 500s. Rules absent from the baseline are `new`; rules absent from the current run were disabled or removed since.
2. **If the file does not exist** (first capture, or the analyzer set changed shape), say so plainly and treat the whole run as the initial baseline — do **not** silently present absolute numbers as if they were deltas.
3. **After the user finishes their disable decisions** (step 6), write the run back as the new baseline, including the analyzer package versions it was measured at. Without this write-back, the next release has nothing to diff and the regression check degrades to eyeballing.

The baseline is a corpus file, so the write is a `.claude/` submodule commit pushed to the agents repo — never onto a linq2db branch (see [`agent-rules.md`](../../docs/agent-rules.md) → *The corpus is a submodule*). Because the measurement is machine-dependent (CPU count, disk), treat cross-machine deltas as directional only; a baseline captured on a different machine than the current run should be flagged as such rather than reported as a regression.

### 6. Disable rules (if user agrees)

Editing `.editorconfig` is a repo-wide change. Before touching it:

- Confirm with the user which rules to disable.
- Only propose disabling rules that are **(a) disproportionately expensive AND (b) not pulling their weight** (false-positive heavy, or redundant with another rule). Expensive-but-valuable rules stay.

Present the outcome as an explicit **disable-candidate table**, not as "here are the three rankings, you decide". One row per candidate:

| Rule | Total | Δ vs baseline | Newly enabled? | Verdict |
|---|---|---|---|---|
| `MA0xxx` | 812s | +770s (new) | yes, this release | candidate — cost is 18% of analyzer time, rule is redundant with CAxxxx |
| `CAxxxx` | 640s | +25s | no | accepted cost — high value, no regression |

Rules that are expensive but staying belong in the table too, marked *accepted cost* — that record is what stops the next release from re-litigating the same rule.

When disabling, follow the existing convention in `.editorconfig` (numerically ordered under `###### Meziantou.Analyzers` and the corresponding sections for other analyzer families). Add a short reasoning suffix on the `severity = none` line:

```editorconfig
# CA2000: Dispose objects before losing scope
dotnet_diagnostic.CA2000.severity = none # disabled: slow (~791s/build)
```

Keep the reason terse (slow / noisy / redundant); the total-seconds figure from the report is the durable evidence. After disabling, offer to re-run steps 2-4 to measure the delta.

---

# Mode: `rules`

## What it answers

"How much does *our* analyzer cost on the code it actually runs over, and did any of our existing rules regress?" Output is a single table — one row per linq2db-authored analyzer with its time, share of the target project's analyzer CPU, rank among all analyzers there, delta vs baseline and a verdict — plus a **TOTAL (ours)** row.

Rationale, the two-target asymmetry, the traps and the threshold provenance are canonical in [`authoring-analyzers.md`](../../docs/authoring-analyzers.md) → *Measuring a rule's build-time cost*. Read it once; this section is the procedure.

## When to run

Last step of authoring or changing an analyzer rule — `/create-analyzer` step 8, `/dogfood-analyzer` step 6 — or on explicit request ("how expensive is this rule", "did L2DB1001 get slower"). Still user-confirmed: **`Source/LinqToDB -f net10.0 -t:Rebuild` measured 20 min** in a cold worktree, and `Tests/Linq` is the larger project. "One project" is not the same as "quick" — `-p:UseSharedCompilation=false` gives up the compiler server, and Release runs the whole IDE/CA/Meziantou set (565 analyzers on `Source/LinqToDB`).

## Inputs

- **family** — internal (`LINQ2DB0xxx`) or shipped (`L2DB1xxx`); this picks the target, and it is the whole decision.
- **worktree** — a throwaway one. `/dogfood-analyzer` already has one live with the analyzer attached; reuse it rather than making a second.

## Procedure

### 1. Pick the target

| Family | Target project | `-Project` (csproj leaf) | `-Target` (baseline key) |
|---|---|---|---|
| internal `LINQ2DB0xxx` | `Source/LinqToDB/LinqToDB.csproj` | `LinqToDB` | `LinqToDB` |
| shipped `L2DB1xxx` | `Tests/Linq/Tests.csproj` | `Tests` | `Tests.Linq` |

Measuring a shipped rule against `Source/LinqToDB` reports **nothing** — that csproj deliberately omits `OutputItemType="Analyzer"` on the analyzer reference, so the rules never run there. An empty table is the symptom.

`-Project` is effectively mandatory: the log carries a report per *dependency* that also compiled, so a `Source/LinqToDB` build produced four (`LinqToDB`, `LinqToDB.Analyzers`, `LinqToDB.Analyzers.CodeFixes`, `CodeGenerators`). The script refuses to guess and lists what it found.

### 2. Attach the analyzer (shipped rules only)

Internal rules need nothing — `CodeGenerators` is already wired as an analyzer. For a shipped rule, in the worktree: build `Source/LinqToDB.Analyzers/LinqToDB.Analyzers.csproj -c Release`, then add to the worktree's `Tests/Linq/Tests.csproj` (scratch, never committed):

```xml
<ItemGroup>
	<Analyzer Include="<worktree>\.build\bin\LinqToDB.Analyzers\Release\LinqToDB.Analyzers.dll" />
</ItemGroup>
```

**Remove any `.editorconfig` left over from `/dogfood-analyzer` step 3 first.** Its `dotnet_analyzer_diagnostic.severity = none` makes Roslyn prune every suppressed analyzer, which deletes both the third-party yardstick and your other rules from the report — the table comes back with one row and a 100 % share, which reads as a catastrophic result rather than a broken measurement.

### 3. Build

```
pwsh -NoProfile -File .claude/scripts/analyzer-profile-build.ps1 -ProjectPath <target.csproj> -LogPath .build/.agents/analyzer-perf-<target>.log -ExtraArgs '-f','net10.0'
```

Run it with the worktree as the working directory. For `Tests/Linq` add `-ExtraArgs '-f','net10.0','-p:TreatWarningsAsErrors=false'` so a pre-existing Release analyzer warning can't stop the build before `CoreCompile` emits the report.

**`Tests/Linq` from cold is the run that gets OOM-killed**, because `-t:Rebuild` walks every dependency first and each one gets its own `csc` (no compiler server) with the full Release analyzer set loaded. Two killed attempts on a box with ~4-6 GB free. Do it in two phases instead:

```
dotnet build Tests/Linq/Tests.csproj -c Release -f net10.0 -m:1 -p:RunAnalyzersDuringBuild=false -p:EnforceCodeStyleInBuild=false -p:TreatWarningsAsErrors=false
```

then the step-3 command with `'--no-dependencies','-m:1'` appended. The warm-up keeps the compiler server and loads no analyzers, so it is cheap; the instrumented pass then compiles exactly one project (~7 min). **Don't skip the warm-up on the assumption a previous killed run left the graph built** — it dies with `CS0006: Metadata file … could not be found` for whichever dependencies it never reached.

**On `Tests/Linq` the instrumented build exits 1, and that is the expected outcome.** Analyzer severities come from `.editorconfig`, and `-p:TreatWarningsAsErrors=false` cannot lower a rule already declared `error` there (`MA0206`, and `L2DB1001` itself once attached). The measurement is unaffected: `CoreCompile` ran, so the report is in the log. Judge the run by whether step 4 finds a report for the target, **not** by the exit code — `analyzer-profile-build.ps1` reports `ok:false` here and is right to.

A partial log is *not* silently wrong either: a killed run still parses, and step 4 refuses it because the target project has no report in the list it prints back. Read that error as "the build died before reaching the target", not as a bad `-Project` name.

### 4. Report

```
pwsh -NoProfile -File .claude/scripts/analyzer-profile-report.ps1 -LogPath <log> -Own -Project <leaf> -Target <key> -BaselinePath .claude/docs/analyzer-own-perf-baseline.json
```

The table is emitted as markdown so it can be pasted verbatim into the PR body. `-Top` still controls the three whole-log rankings printed underneath as context.

The script fails loudly rather than guessing: multiple project reports in the log without `-Project` is an error, and so is a `-Project` name absent from the log. Both hand back a `next_action:` line.

### 5. Judge, then write the baseline back

Present the table. For each `investigate` row, the author either optimizes (the first two *Performance checklist* bullets — resolve symbols once in `RegisterCompilationStartAction`, cheap string gate before symbol comparison — are what usually move a rule off the list) or records why the cost is justified, in the PR body next to the table.

Then re-run step 4 with `-UpdateBaseline -BuildCommand '<the exact command from step 3>'`. Without the write-back the next rule's run has nothing to diff and the regression half of this mode silently degrades to "here is a number".

**Skip the write-back when the existing baseline is the pre-change control for the run you just did.** The default assumes the baseline is older than the work; it is exactly wrong when someone captured it on `master` *for* this measurement, because overwriting it replaces a clean one-variable control with a feature-branch run and there is no way back. The tell is a baseline whose `commit` is the branch's merge base and whose `capturedOn` is the same day. Report the delta, leave the file, and re-capture after merge. **Read the share and the rank, not the seconds, whenever the project total moves between runs** — the figure is CPU time summed across concurrent analyzer executions, so it tracks machine load: a same-box, same-day pair measured 574.7 s and 1572.3 s for the same target, while the normalised share and rank stayed stable and agreed. A sub-second rule drifting ±50 % with no code change is the noise floor, not a regression. (Surfaced on [#5877](https://github.com/linq2db/linq2db/pull/5877): `ProjectFlagsAnalyzer` measured 4.469 s / 0.28 % / rank 50 of 566 against a `LINQ2DB0001` control that itself moved +50 %.) The baseline is a corpus file — the write is a `.claude/` submodule commit pushed to the agents repo, never onto a linq2db branch.

Rules in the baseline but absent from the run are reported as such; check whether that is a rename (update the baseline) or an analyzer that failed to load (fix that first — an unloaded analyzer measures 0 s and looks like a triumph).

### 6. Tear down

Remove the worktree (confirm first, per [`worktree.md`](../../docs/worktree.md)). Since no build server was shut down, `-p:UseSharedCompilation=false` may have left `csc` holding `CodeGenerators.dll` / `LinqToDB.Analyzers.dll` — containing that is why the measurement runs in a worktree. If the next build in the primary clone hits `CS2012`, retry once; do **not** reach for `build-server shutdown`.

---

## Scripts

- `.claude/scripts/analyzer-profile-build.ps1` — runs `dotnet build -t:Rebuild` with the four non-obvious flags, writes the log, returns `{ logPath, exitCode, elapsedMs }`. Never shuts the build servers down. `-ProjectPath` is an alias for `-SolutionPath` and accepts a `.csproj`; `-Configuration` defaults to `Release`.
- `.claude/scripts/analyzer-profile-report.ps1` — parses the log, emits the three rankings as pretty tables (or JSON via `-AsJson`). `-Own` adds the linq2db-authored table with totals, verdicts and baseline deltas; `-OwnPattern`, `-SharePct`, `-TopRank`, `-TopRankMinAnalyzers`, `-RegressionPct`, `-RegressionFloorSeconds` tune it.
- `.claude/scripts/testdata/analyzer-profile-report.fixture.{log,-baseline.json}` — a hand-built two-project log whose numbers make each verdict arm fire alone. **Re-run it after touching any threshold or the `-Own` logic**; the script's comment header carries the commands and the expected verdict per row. A change that makes every row `ok` — or every row `investigate` — has destroyed the discrimination rather than improved it, and that is invisible without the fixture (the median-based arm the first draft shipped looked fine until real data showed it firing on a rule costing 0.07 %).

Both follow [`.claude/docs/script-authoring.md`](../../docs/script-authoring.md) conventions.

## Don'ts (both modes)

- Do **not** auto-run this skill — even `rules` is a multi-minute rebuild. Confirm first.
- Do **not** disable analyzer rules without explicit user approval; `.editorconfig` changes affect every project in the repo.
- Do **not** commit `TreatWarningsAsErrors=false` or any other temporary unblock flag.
- The report is **CPU time across analyzer executions**, not wall-clock. Analyzers run concurrently, so sum-of-times exceeds elapsed build time. The ranking is still valid for comparing rules against each other.
- The numbers are **machine-dependent**. A baseline captured elsewhere gives a directional comparison, not a regression.
- `solution` mode: expect ~50-70 project reports (not every csproj reaches `CoreCompile` — reference-assembly projects, multi-target with skipped TFMs, etc.). Don't re-invoke the build trying to "get" the missing ones.
- `rules` mode: do **not** cross-compare with the `solution` baseline, and do **not** read an empty table as "the rule is free" — it almost always means the analyzer never ran (wrong target, or a leftover bulk-`none` `.editorconfig`).

## Related

- [`/release-deps`](../release-deps/SKILL.md) — invokes `solution` mode (with user confirmation) after an analyzer-package bump.
- [`/release-verify`](../release-verify/SKILL.md) — invokes `solution` mode after the clean Release build when any analyzer package moved.
- [`/create-analyzer`](../create-analyzer/SKILL.md) → step 8, [`/dogfood-analyzer`](../dogfood-analyzer/SKILL.md) → step 6 — invoke `rules` mode as the closing step of authoring a rule.
- [`authoring-analyzers.md`](../../docs/authoring-analyzers.md) → *Measuring a rule's build-time cost* — canonical rationale, targets and thresholds for `rules` mode.
- [`/release`](../release/SKILL.md) → step 4 (Test matrix) — wall-clock cost of `solution` mode is comparable to a single test-matrix track.
