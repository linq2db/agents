# Known unknowns to resolve on first release run

The release skill set was built from documentation, not from running an actual release end-to-end. This file lists every spot where a sub-skill is going to ask the user for first-run details. Each item lists the **owning skill / step**, the **question to ask**, and the **doc to update** when answered.

When the first real release surfaces an answer, update the corresponding doc and tick the row here. A `/session-reflect` pass at end-of-release should drain this list.

## Open questions

### Baselines repo anchor commit verification (skill: /release-publish, step 3)

- **Question:** is `f6b4f6278e5e53f38b6a26350f80b0609b37e86e` still the right reset target for the baselines repo before each release, or does this evolve as the baselines repo gets re-anchored?
- **Doc to update:** [`overview.md`](./overview.md) (Phases diagram references this anchor) and the publish skill itself if the value moves.

### Ad-hoc task dispatch (skill: /release, step 4 task type 7.x)

- **Question:** what's the right pattern for executing a user-supplied ad-hoc task (e.g. "audit IDataProvider surface")? Direct conversation, dispatch to `/review-pr` against a specific file, dispatch to `find-issues`, ...
- **Doc to update:** new section in `/release` skill once a pattern stabilizes.

## Resolved

<!-- moved from "Open questions" above as each first-run answer comes in -->

### T4 build prerequisite (skill: /release-test-matrix, step 4.0) — resolved on 6.3.0

`dotnet build linq2db.slnx -c Debug`. Solution-level Debug build emits net462 outputs alongside other TFMs (the slnx rejects single-TFM `-f net462`). Recorded in [`linqpad-test-checklist.md`](./linqpad-test-checklist.md) → **T4 build prerequisite**.

### Per-provider DB init invocations (skill: /release-test-matrix, step 4.1) — partially resolved on 6.3.0

[`provider-db-init.md`](./provider-db-init.md) carries the db2 entry (last verified 2026-05-16 on release 6.3.0). Still accruing one entry per provider as each is first exercised — keep appending there rather than re-opening this row.

### Docs PR submodule sync step (skill: /release-postpublish, step 2) — resolved on 6.4.0

`git -C <docs-path> submodule update --remote submodules/linq2db`. Scoped to that one path on purpose: the repo also has `submodules/LinqToDB.Identity` (tracking `master`), which a release sync must not bump. `submodules/linq2db` tracks branch `release`, so `--remote` lands on the release-branch head with no explicit SHA. Full step, plus the vendored-docfx Roslyn dependency it sits next to, is written up in [`/release-postpublish`](../../skills/release-postpublish/SKILL.md) step 2.

### GitHub release creation (skill: /release-postpublish, step 3) — resolved on 6.4.0

There is no manual `gh release create` — **CI already made the draft**. `build-job.yml`'s *Create Release Draft* step runs on the release-branch build with `--draft --fail-on-no-commits --generate-notes --latest`, attaching the `.lpx` (the `.lpx6` attachment was dropped for 6.5.0 onward). Step 3 therefore PATCHes that draft's body and the user publishes it. Tag form is `v<ver>`, and the tag **must** end up on a commit reachable from `master` — see the warning in the skill, and the `tag_name`-strip trap when PATCHing a draft.

### Local NuGet test feed (skill: /release-test-matrix, step 4.4) — resolved

Recorded in [`external-repos.md`](./external-repos.md) → **User-specific paths** as `user-local.nuget-server`: machine-specific, kept in user auto-memory (not committed). Shape `{ingestionFolder, feedUrl, wakeProtocol, ingestionIndicator}`; behavior contract — drop `.nupkg` into the ingestion folder, the server consumes + removes them in ~10s; folder emptiness = ingestion complete.
