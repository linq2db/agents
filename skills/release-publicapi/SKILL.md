---
name: release-publicapi
description: PublicAPI.Shipped / PublicAPI.Unshipped reconciliation for the release-prep workflow. Runs a whole-solution Release build with -p:RunApiAnalyzersDuringBuild=true (the analyzers are off in every ordinary build, so this is the only gate before the master→release PR) to surface RS0016/RS0017/RS0025 drift, bulk-fixes it via -Action fix-drift, then moves every project's PublicAPI.Unshipped.txt content into PublicAPI.Shipped.txt across all per-TFM and flat layouts. Distinct from `/api-baselines` (which handles `CompatibilitySuppressions.xml` — a different tool, different files). Invoked by `/release` step 2 or directly when running release prep.
---

# /release-publicapi

## What this skill is (and isn't)

**Is:** the per-release PublicAPI shipped/unshipped reconciliation. For every `PublicAPI.Shipped.txt` / `PublicAPI.Unshipped.txt` pair under `Source/`, moves Unshipped entries into Shipped (sorted union), then truncates Unshipped to just the `#nullable enable` directive. Runs across ~36 file pairs spanning multi-TFM (per-`net{TFM}/` subfolder) and single-TFM (flat) layouts.

Also owns the **analyzer release-tracking** move for the `linq2db.Analyzers` package — `AnalyzerReleases.Unshipped.md` → `AnalyzerReleases.Shipped.md` — the same release-time Unshipped→Shipped reconciliation for a different file family (Roslyn's RS2000–RS2002 release tracking). See step 8.

**Isn't:**

- Not [`/api-baselines`](../api-baselines/SKILL.md) — that skill handles `CompatibilitySuppressions.xml` (Microsoft.DotNet.ApiCompat). PublicAPI.*.txt is a different system (Microsoft.CodeAnalysis.PublicApiAnalyzers) tracking the declared public surface. Both run during a release prep, but on independent files.
- Not a Roslyn codefix reimplementation. It doesn't *compute* the declared API — it transcribes what the analyzer already reported. Every entry `fix-drift` writes comes verbatim from a diagnostic message, and every write is asserted against the current tree first. For a handful of diagnostics, IDE quick-fix is still the nicer path; for the several-hundred-symbol backlog a release typically opens with, it isn't viable.

## When to run

- During release prep as task 2 (called by `/release` orchestrator), **after** task 6 (`/release-verify`) has produced a clean build. Task 6's build addresses any RS0016/RS0017 diagnostics that step 1 here would normally surface, so when invoked post-task-6 the build step (1) is **skip-able** — go straight to step 3 (plan).
- Manually when the user wants to roll Unshipped into Shipped outside of a release (rare).

## Required reading

- [`.claude/docs/code-design.md`](../../docs/code-design.md) → **Never hand-edit API baseline files** still applies to `CompatibilitySuppressions.xml`. PublicAPI.*.txt is **not** under that rule — it's editable by the analyzer's codefixes and by this skill's apply step.
- [`.claude/docs/agent-rules.md`](../../docs/agent-rules.md) → **Git commit rules** (each commit is its own user request).

## Procedure

### 1. Run a Release build with the API analyzers explicitly enabled — never skip it

**This step is not skip-able, and task 6 does not satisfy it.** `Source/Directory.Build.props` gates the *`Microsoft.CodeAnalysis.PublicApiAnalyzers` PackageReference itself* on `RunApiAnalyzersDuringBuild`, which defaults to `false`. So an ordinary `dotnet build -c Release` — including `/release-verify`'s verification build — never loads the API analyzers at all and emits zero RS0016/RS0017 regardless of how much drift exists. A clean task-6 build is **no evidence** about PublicAPI state.

CI is the same story: `Build/Azure/pipelines/default.yml` sets `with_api_analyzers: true` only when a PR targets the `release` branch, so the analyzers run once per release cycle, on the master→release PR. That is the intended trade-off (they're expensive), but it means **this skill is the only gate before that PR** — drift accumulated over the whole cycle surfaces here or it detonates there.

```
pwsh -NoProfile -File .claude/scripts/release-publicapi-reconcile.ps1 -Action build -Version <ver>
```

The script passes `-p:RunApiAnalyzersDuringBuild=true` for exactly this reason — don't hand-roll the build without it. It builds the **whole solution** (not just the changed project) and captures stdout+stderr to `.build/.agents/release-<ver>-publicapi-raw.txt`. Build the solution because drift hides in projects the reconciliation didn't touch: on 6.4.0 the core project came back clean while `LinqToDB.Scaffold` and `LinqToDB.EntityFrameworkCore` still carried their own.

If the build fails on compile errors unrelated to PublicAPI, stop and surface those — they need fixing before reconciliation makes sense. One known false alarm: `LinqToDB.LINQPad` can fail with `CS2001: Source file '...*.g.cs' could not be found` from its WPF `_wpftmp` markup-compile pass under a parallel solution build. Re-build that one project alone to confirm it's transient rather than chasing it.

### 2. Discover RS0016 / RS0017 / RS0025

```
pwsh -NoProfile -File .claude/scripts/release-publicapi-reconcile.ps1 -Action discover -Version <ver>
```

Parses the raw build log for three diagnostic classes, grouped by symbol + project + TFM:

| Code | Meaning | Fix |
|---|---|---|
| RS0016 | symbol in code, not declared | add the line to `Unshipped` |
| RS0017 | declared, no longer in code | add a `*REMOVED*<symbol>` tombstone to `Unshipped` |
| RS0025 | symbol declared more than once across the API files | tombstone the *duplicate* copy, keeping one declaration |

**Expect volume, not a handful.** Because step 1's build is the only time these analyzers run in the whole cycle (see above), a release can open with hundreds or thousands of diagnostics — 6.4.0 opened with 7970. The original "surface a numbered list, user fixes via IDE quick-fix" flow does not scale to that and is only appropriate for a handful. For bulk, use `-Action fix-drift` (step 2a); the diagnostic message carries the exact PublicAPI line, so the transformation is mechanical and verifiable rather than 800 hand-edits.

**RS0025 masks RS0016.** While the declared set is malformed by duplicates the analyzer stops reporting missing symbols, so clearing RS0025 *reveals* a further RS0016 set. Expect the loop to converge over several passes (6.4.0: 7970 → 74 → 48 → 0) — that is the analyzer seeing further each time, **not** the fix regressing. Don't read a rising or newly-appearing count as a mistake, and don't stop before a pass reports zero.

**If zero:** proceed to step 3.

### 2a. Bulk-fix the drift

```
pwsh -NoProfile -File .claude/scripts/release-publicapi-reconcile.ps1 -Action fix-drift -Version <ver> [-Apply]
```

Dry-run by default; prints the planned per-file `Unshipped` edits. Placement rules it applies:

- **RS0016** goes in the per-TFM `Unshipped` file for each flagging TFM — promoted to the flat file *only* when every per-TFM directory the project has flagged it. This matters: `LinqToDB.EntityFrameworkCore`'s EF3/EF8/EF9/EF10 projects share one flat file, so declaring an EF10-only symbol flat converts one RS0016 into three RS0017s.
- **RS0025** tombstones the per-TFM copy the diagnostic points at, and **asserts the symbol is also declared in the flat file first** — otherwise the tombstone would delete the only declaration.
- **RS0016/RS0017** are asserted against the current tree (must be absent / must be present respectively). A mismatch means the log and the tree disagree — a stale log, or a partial build — and the script refuses to write rather than corrupting the files.

Then re-run `plan`/`apply` (steps 3–5) so the new `Unshipped` entries land in `Shipped`, and loop back to step 1 until a build reports zero. `-Force` is needed on `apply` whenever the pass includes non-`LinqToDB.Internal.*` tombstones; RS0025 duplicate-removals always trip that gate even though nothing leaves the declared API, so read the removal list before waving it through.

### 3. Compute the move plan

```
pwsh -NoProfile -File .claude/scripts/release-publicapi-reconcile.ps1 -Action plan -Version <ver>
```

Walks every `PublicAPI.Shipped.txt` + sibling `PublicAPI.Unshipped.txt` pair under `Source/`. Per pair, computes:

- `newShipped = sorted(dedup(union(currentShipped-entries, currentUnshipped-entries)))` (the `#nullable enable` directive is preserved as the first line)
- `newUnshipped = "#nullable enable\n"` (just the directive — Unshipped is reset to empty)

Writes the plan as JSON to `.build/.agents/release-<ver>-publicapi-plan.json`. The plan lists every file pair with `noOp: true|false`, line counts, and per-file before/after.

### 4. Review the diff

```
pwsh -NoProfile -File .claude/scripts/release-publicapi-reconcile.ps1 -Action diff -Version <ver>
```

Prints a per-file unified diff (only the changed files). Surface this to the user.

**Deletion check:** if any line is being removed from `Shipped` (which only happens when Unshipped contains a tombstone like `*REMOVED*` — uncommon), flag it for separate scrutiny per `code-design.md` → API removals outside `LinqToDB.Internal.*` need explicit user sign-off.

### 5. Apply

```
pwsh -NoProfile -File .claude/scripts/release-publicapi-reconcile.ps1 -Action apply -Version <ver>
```

Reads the plan file and writes both files per project/TFM. UTF-8 encoding mirrors each file's existing BOM state (71 of the 72 PublicAPI files in `Source/**` currently start with a UTF-8 BOM, so most output keeps the BOM); line endings are normalized to LF (the analyzer is whitespace-tolerant; CRLF inputs would be rewritten as LF, but no PublicAPI file in the repo uses CRLF today).

### 6. Verify

Re-run step 1 (whole-solution build **with the flag**) and step 2 (discover) to confirm zero RS0016/RS0017/RS0025 after the move. Surface the result. Loop back through 2a → 5 for each pass that still reports diagnostics; a pass reporting zero is the only acceptable exit.

Two verification points worth proving rather than assuming:

- **The move is declaration-preserving** — reconciliation must not change *what* is declared, only which file declares it. Prove it directly: for every (project × TFM), the declared set (flat ∪ per-TFM, Shipped ∪ Unshipped, tombstoned symbols subtracted) must be identical before and after. That single check exonerates the move from any diagnostic the build reports, independently of the tombstone accounting, and is what lets you attribute a wall of RS0016 to pre-existing drift with confidence instead of arguing from the plan's `removed[]` list.
- **Idempotence** — re-running `plan` at the end must report `totalChanges: 0` with every `PublicAPI.Unshipped.txt` holding only `#nullable enable`.

### 7. Update state + commit

1. Tell `/release` orchestrator: task 2 → `done` via `release-state.ps1 -Action update -Version <ver> -TaskId 2 -Status done -Annotation "<N files updated>"`.
2. Stage the modified files: `git add Source/**/PublicAPI.{Shipped,Unshipped}.txt` (or per-project paths from the plan).
3. Confirm commit message + commit. Suggested message:
   ```
   Release <ver>: PublicAPI reconciliation

   Move Unshipped entries to Shipped across <N> PublicAPI file pairs
   (multi-TFM and flat layouts). Verified zero RS0016/RS0017 post-apply.
   ```
4. Push on user confirmation (push semantics rule in `/release` Conventions).

### 8. Reconcile AnalyzerReleases.*.md (linq2db.Analyzers package)

The `linq2db.Analyzers` package tracks its shipped rules with Roslyn's release-tracking files — `Source/LinqToDB.Analyzers/AnalyzerReleases.{Shipped,Unshipped}.md`, enforced by the RS2000–RS2002 analyzers. This is a **separate file family** from `PublicAPI.*.txt` (different system, no `release-publicapi-reconcile.ps1` support), but it has the **same release-time Unshipped→Shipped move**, so it belongs in this skill. Do it by hand — it's a handful of rule rows, no script:

1. In `AnalyzerReleases.Shipped.md`, append a release section under the header comment (`; Shipped analyzer releases` + help-link line), moving the tables verbatim from `Unshipped.md`:

       ## Release <version>

       ### New Rules

       Rule ID | Category | Severity | Notes
       --------|----------|----------|-------
       <every row from Unshipped.md's "### New Rules" table>

   For a rule whose **severity/category changed** this release, use a `### Changed Rules` table (adds `Old Category | Old Severity` columns); for a **removed/deleted** rule, `### Removed Rules`. Format reference is the ReleaseTrackingAnalyzers help URL linked at the top of both files.
2. Reset `AnalyzerReleases.Unshipped.md` to just its two header-comment lines (`; Unshipped analyzer release` + the help-link line) — drop the moved tables.
3. The verify build (step 6) must stay clean of **RS2000/RS2001/RS2002** — the release-tracking analyzers fail the build if the move is inconsistent (e.g. a rule in code but absent from both files, or an Unshipped row not carried to Shipped).

**Skip this step** when `Source/LinqToDB.Analyzers/AnalyzerReleases.Unshipped.md` has no pending rule rows (only the header comment) — the common case, since most releases add no analyzer rules. Stage the two files with the step-7 commit when they do change (`git add Source/LinqToDB.Analyzers/AnalyzerReleases.{Shipped,Unshipped}.md`).

## Don'ts

- Do **not** run the build without `-p:RunApiAnalyzersDuringBuild=true`, and do **not** treat `/release-verify`'s clean build as satisfying step 1. Without the flag the analyzer package isn't even referenced, so zero diagnostics means nothing was checked.
- Do **not** hand-edit `PublicAPI.*.txt` to clear a diagnostic. Use `fix-drift`, which asserts before writing — a hand-added line with a typo'd nullability annotation (`string!` vs `string?`) silently trades one RS0016 for another.
- Do **not** write an entry the analyzer didn't report. `fix-drift` transcribes diagnostics; it never infers a declaration from source. If a symbol seems to need declaring but no diagnostic names it, the build didn't analyze that project — find out why.
- Do **not** edit `PublicAPI.*.txt` files individually with `Edit` calls during a reconciliation — that's what the script's `apply` action is for. ~72 files in one batched write avoids burning permission surface.
- Do **not** confuse with `/api-baselines`. Different file family, different generator, different policy check. Both run during release prep but on independent paths.
- Do **not** skip the verify step (6). A clean post-apply build is the only proof the move didn't break the analyzer's view of the declared API.
