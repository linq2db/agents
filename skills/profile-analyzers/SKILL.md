---
name: profile-analyzers
description: Measure Roslyn analyzer build-time cost across the linq2db solution. Runs a dedicated rebuild with `/reportanalyzer`, parses the detailed log, and produces top-N rankings (analyzer x project, analyzer totals, project totals). Use when the user asks to profile analyzers, says "analyzers got slow", "which analyzers are slowest", "why is the build slow", or as part of `/release-deps` after an analyzer-package bump to spot regressions.
---

# /profile-analyzers

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

Defaults: `-SolutionPath linq2db.slnx`, `-Target Rebuild`. The script:
- Shuts down build servers (`dotnet build-server shutdown`) to force a fresh `csc.exe` run.
- Runs `dotnet build` with the four flags above.
- Writes the full log to `-LogPath`.
- Returns `{ logPath, exitCode, elapsedMs }`.

If the rebuild halts on a pre-existing analyzer error on an unrelated file, pass `-ExtraArgs '-p:TreatWarningsAsErrors=false'`. Then fix the underlying error in a separate change — do not commit `TreatWarningsAsErrors=false` to the repo.

### 3. Parse the log

```
pwsh -NoProfile -File .claude/scripts/analyzer-profile-report.ps1 -LogPath .build/.agents/analyzer-build.log -Top 10
```

Output: three pretty tables on stdout, plus a one-line diagnostics header (per-analyzer rows / project reports / distinct analyzers).

For programmatic consumption: `-AsJson` returns `{ slowestPairs, busiestAnalyzers, projectTotals, diagnostics }` to stdout (see the script's comment header).

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

## Scripts

- `.claude/scripts/analyzer-profile-build.ps1` — shuts down the build servers, runs `dotnet build -t:Rebuild` with the four non-obvious flags, writes the log, returns `{ logPath, exitCode, elapsedMs }`.
- `.claude/scripts/analyzer-profile-report.ps1` — parses the log, emits the three rankings as pretty tables (or JSON via `-AsJson`).

Both follow [`.claude/docs/script-authoring.md`](../../docs/script-authoring.md) conventions.

## Don'ts

- Do **not** auto-run this skill — it's a 10-25 min build and dominates the session.
- Do **not** disable analyzer rules without explicit user approval; `.editorconfig` changes affect every project in the repo.
- Do **not** commit `TreatWarningsAsErrors=false` or any other temporary unblock flag.
- The report is **CPU time across analyzer executions**, not wall-clock. Analyzers run concurrently, so sum-of-times exceeds elapsed build time. The ranking is still valid for comparing rules against each other.
- Expect ~50-70 project reports (not every csproj reaches `CoreCompile` — reference-assembly projects, multi-target with skipped TFMs, etc.). Don't re-invoke the build trying to "get" the missing ones.

## Related

- [`/release-deps`](../release-deps/SKILL.md) — invokes this skill (with user confirmation) after an analyzer-package bump.
- [`/release`](../release/SKILL.md) → step 4 (Test matrix) — wall-clock cost of this skill is comparable to a single test-matrix track.
