## PR and push procedures

Detail-heavy mechanics for creating PRs and pushing follow-ups. The summary in [`agent-rules.md`](agent-rules.md) → *Push to remote rules* / *Pull request rules* keeps the principles and one-line triggers; this doc is what you load when one of those triggers fires.

### Before the first push of a branch: check for commits you didn't make, then sync

Two checks, both cheap, both before `git push`:

1. **`git log --oneline origin/master..HEAD`** — is anything on this branch that you didn't put there? The user may have committed to it between sessions, or in a parallel session, or from their editor. Pushing without looking risks force-shaped surprises later and, worse, a PR whose description you wrote describing only *your* half of the work. If commits you didn't author appear, stop and say so before pushing.
2. **`git fetch origin master`, then sync** — a branch cut hours or days ago is behind. Fast-forward when the branch has no commits; otherwise follow the merge-vs-rebase rule in [`agent-rules.md`](agent-rules.md) → *Creating a new branch*. Syncing before the first push means CI's first run is against current master, so a red leg is about your change rather than about drift you hadn't merged.

Do the same before opening the PR when the branch was pushed earlier in the session — master moves. (Surfaced 2026-09-01 on #5840, at the user's prompting: *"first check if there were no other user commits to branch and sync with master"* — the branch turned out clean and three commits behind, and the sync was a fast-forward.)

### After every successful push: PR body check

Check for a PR on the branch (`gh pr list --head <branch> --json number,title,body,url`):

- If **no PR exists**, propose creating one (see [`Creating a PR`](#creating-a-pr)) and wait for confirmation.
- If **a PR exists**, diff the newly pushed commits against the current PR body. If the body no longer accurately describes the work (new summary bullets, new linked issues, etc.), propose a concrete edit and wait for confirmation before calling `gh pr edit`. **Show the proposed change as a diff between the current body and the new one** (e.g. a unified diff or `- old line` / `+ new line` markers) — do not just paste the new body in full. If the body is still accurate, say so and move on — don't edit gratuitously.
- **When the body update follows a follow-up commit on the user's own PR, append — don't rewrite.** Add a new subsection (typically `## Follow-up commit` or similar) summarising the new commit's deltas and leave the original prose verbatim. Don't paraphrase, restructure, or "neutralise" content the human author already wrote. The "preserve, don't rewrite" rule is suspended only when the user explicitly asks for a tone or structure change to the existing body.
  - **Use `.claude/scripts/pr-body-edit.ps1` to do the append** — it inserts text at an ASCII anchor (e.g. a heading or trailer line near the PR-body footer, to land a section above it) in a single allowlisted, UTF-8-safe call. Do **not** hand-roll a fetch-body → mutate → `gh pr edit` loop (Python/pwsh): that re-hits the cp850 encoding garble the script exists to avoid, and a `gh … > .build/.agents/x.json` redirect lands in the Bash cwd (which may be a **worktree**, not the primary clone) so a follow-up reader using the primary-clone path fails with `FileNotFound`.
  - **`pr-body-edit.ps1` only *inserts* at anchors — it can't remove or replace existing lines.** To edit a body that already has content (e.g. drop stale bullets when a change is split out), run it once with `"dryRun": true` to fetch the pristine body to `<workDir>/pr<n>-body-before.txt` (UTF-8, encoding-safe — note it writes under the pwsh cwd, i.e. the primary clone, not a worktree), `Edit` that file, then `gh pr edit <n> --body-file <path>`. `gh pr edit --body-file` reads the file directly (no console-codepage capture), so this round-trips cleanly; verify the whole stored body afterward. **Never** pipe a multi-line body string to `Set-Content` (with or without `-NoNewline`) — the pipeline splits it into per-line array elements and rejoins them without separators, collapsing every newline.
  - **Verify the post-edit body from the script's `bodyAfter` file, not a fresh `gh` capture.** A `pr-body-edit.ps1` run (dryRun `false`) writes `<workDir>/pr<n>-body-after.txt` = the exact UTF-8 bytes it pushed; `Read` that to confirm heading/blank-line structure over the whole body. Do **not** re-fetch with `gh api … --jq .body` captured into a pwsh variable — Git-Bash/pwsh returns a **line-array** (`.Length` is the line *count*, not chars, and `WriteAllText` on the array collapses newlines) and code-page-mangles emoji, so it's a misleading verification source. If you must re-fetch independently, use `pr-context.ps1` (UTF-8 pipes). (Surfaced on #5643: a raw `--jq .body` capture reported `chars=37` — the line count — and a newline-flattened file.)

### After every successful push: re-request Copilot review

Copilot's automatic trigger is unreliable — it sometimes doesn't fire on follow-up pushes — so re-request after each successful push (and after the PR-body check above):

```
gh pr edit <N> --repo linq2db/linq2db --add-reviewer copilot-pull-request-reviewer
```

Two slug / endpoint gotchas:

- `gh pr edit --add-reviewer` routes through GraphQL with the bot's user-login (`copilot-pull-request-reviewer`). Passing `Copilot` to `gh pr edit --add-reviewer` errors with `Could not resolve user with login 'copilot'`.
- The REST equivalent (`gh api -X POST repos/.../requested_reviewers -f 'reviewers[]=Copilot'`) accepts the `Copilot` slug, but **silently no-ops when Copilot already reviewed an earlier commit on the same PR** — it returns 200 yet the bot is not re-queued. Always prefer `gh pr edit` for follow-up requests.

After the review lands, fix or reply per thread and resolve via the existing helpers — `gh api repos/.../pulls/<N>/comments` for inline bodies, `gh pr view <N> --json reviews,latestReviews` for the review-level overview. Bulk reply + resolve goes through `.claude/scripts/post-pr-thread-replies.ps1` (see [`github-review-api.md`](github-review-api.md) → **Batch reply + resolve**); GitHub doesn't auto-resolve threads when a follow-up commit fixes the line.

### After every successful push: refresh the release-notes draft

If the PR already has a release-notes draft comment (the marker `<!-- release-notes:draft:`), the pushed commits may have changed what ships. Refresh it via [`/release-notes`](../skills/release-notes/SKILL.md) → mode `refresh <pr>`:

- `release-notes-draft.ps1 -Action find -Pr <n>` reports `present` + the `lastSha` the draft was generated from. If `present: false`, **do nothing** — drafts are created on explicit request (`/release-notes draft`), never auto-created on a stray push. If `lastSha` equals the new PR HEAD, it's a no-op.
- When HEAD moved, regenerate the proposed text, **show the user the change and confirm**, then `upsert`. The maintainer verifies correctness on every update — so regeneration is safe, but it's still gated by that confirm.

Fold this into the push bundle alongside the PR-body check, Copilot re-request, and baselines cleanup.

### Stale CHANGES_REQUESTED reviews after follow-up commits

Despite branch protection's `dismiss_stale_reviews: true`, GitHub's auto-dismissal sometimes lags or doesn't fire on rebase-merges from a different actor. After pushing follow-up commits to address a `CHANGES_REQUESTED` review, check `gh pr view <n> --json reviewDecision`. If it still shows `CHANGES_REQUESTED`, the stale review must be dismissed manually before `gh pr merge --admin` will succeed (without it, the merge fails with `Repository rule violations found / 1 review requesting changes by reviewers with write access`).

Manual dismissal:

```
pwsh -NoProfile -File .claude/scripts/dismiss-stale-reviews.ps1 -Pr <n>          # add -DryRun to preview
```

It resolves the numeric REST review ids (GraphQL ids from `gh pr view --json reviews` won't work for the PUT) and dismisses each `CHANGES_REQUESTED` review with a non-empty `-Message` (default `Stale`).

Two gotchas on the dismissal call:

- `-f message=""` is **rejected** with HTTP 422 — GitHub mandates a non-empty message. Use a one-word placeholder like `"Stale"` if there's nothing more to say (per [`github-authoring.md`](github-authoring.md) → *Wording discipline*: terse > apologetic).
- The dismissal is a metadata change, not a content edit, so it's exempt from the `never edit content authored by others` rule (per [`github-authoring.md`](github-authoring.md) → *Never edit content authored by others*). Still, ask the user before dismissing — visible action on someone else's review.

### After test renames / moves / deletes: clean up stale baselines

`linq2db.baselines` files are keyed by the fully-qualified test name (`<Namespace>.<Fixture>.<Method>(<Provider>).sql`). When follow-up commits rename a test method, rename its fixture class, change its namespace, or delete the test, the existing baselines PR for the linq2db PR — typically `linq2db/linq2db.baselines#<m>`, linked from the bot comment "Test baselines changed by this PR" — carries files keyed to the *old* names and never auto-prunes. Leaving it open means the next CI run produces a second baselines PR while the stale one lingers; the diff between the two is hard for a reviewer to read.

After pushing follow-up commits that rename / move / delete any test:

Run **`pwsh -NoProfile -File .claude/scripts/close-stale-baselines.ps1 -Pr <n>`** (add `-DryRun` to preview). It finds the baselines PR keyed to head `baselines/pr_<n>`, closes it with an explanatory comment, deletes the branch ref (treating an already-gone ref as success), and `git fetch --prune`s the local `../linq2db.baselines` clone. The next CI run (e.g. `/azp run test-all` on the renamed commit) then produces a fresh baselines PR under the up-to-date names — no further manual action.

The same applies when a follow-up commit changes a test's projection shape / SQL output without renaming it — the old PR's files no longer match the new expected output. Out of scope: pure test *additions* that don't rename anything (the existing baselines PR is incremental — new files just get added on the next CI run), and bug-fix commits that update SQL but leave both names and structure untouched (the existing baselines PR's diff updates in-place).

**Also covers the case where the baselines PR became `CONFLICTING` because *other* source PRs landed on master first.** The baselines PR is keyed against a specific source-PR commit; once master moves, the baselines diff often no longer applies cleanly even if the source PR's tests didn't change. Same close+delete-branch action — the next CI run on the now-merged source PR (or its squashed master commit) regenerates fresh baselines under master's current state. Don't try to merge-resolve a baselines PR; the cost of regenerating is much lower than the cost of getting the resolution wrong.

**Do a review-requested rename immediately, not at the end of the walk.** Every CI run between the request and the rename regenerates baselines under the doomed names, so batching the rename with the rest of the review fixes multiplies the stale set for no benefit — and a rename is usually a one-line mechanical change that needs no discussion. Push it on its own, then continue the walk. (Surfaced 2026-09-01 on #5840: a reviewer asked for an `Issue<N>_` prefix to be dropped from six tests, and the user's follow-up was *"I don't want polluted baselines"* — the rename went out as its own commit within the same turn.) This is about not *creating* stale baselines; it does not conflict with [`agent-rules.md`](agent-rules.md) → orphaned baselines, which says existing orphans from a superseded run need no cleanup and are never a review finding.

Both `/review-pr` (in interactive-mode `fix`-path post-walk) and `/verify-review` (when a partial-fix follow-up renames a test) trigger this cleanup. Make it part of the publish bundle that pushes the follow-up commits — push, body update, Copilot re-request, baselines close+delete-branch, `/azp run test-all`.

### On PR merge

When merging a PR (or right after the user reports having merged one), two release-bookkeeping tasks run — both user-confirmed:

1. **Milestone consistency.** A merged PR and the issues it closes should share a milestone. Run `pwsh -NoProfile -File .claude/scripts/milestone-consistency.ps1 -Action check -Pr <n>`. If it reports `laggards`, propose assigning the PR's milestone to them and, on confirmation, run `-Action assign -Pr <n>` (REST PATCH by numeric milestone id; verifies after). Laggards flagged `likelyIntentional` (issue on an earlier/closed milestone — fix shipped in a past release, this PR is a follow-up) are skipped by default; don't reassign them unless you really mean to (`-IncludeReleased`). Milestone is metadata so it's exempt from "never edit content authored by others", but the change is visible — **propose, then confirm**. (Same check fires from `/review-pr` when a discrepancy surfaces and from `/release-milestone-check`.)
2. **Release notes draft** — ensure the PR has a draft comment (`/release-notes draft <pr>` if missing). This always happens; the wiki write does not.
3. **Release notes → wiki (optional, explicit).** The team often updates the wiki right after merge so users can preview what's coming — but it's an **opt-in step the user requests explicitly**, not automatic on merge. The authoritative full-section generation is at release prep (`/release` task 5 → `sweep`/`harvest`/`apply`). When the user asks, run [`/release-notes`](../skills/release-notes/SKILL.md) → mode `apply` (wiki strategy B: regenerate the whole version section in the local `linq2db.wiki` clone → show the diff → push on confirm). Skip `omit`-flagged drafts. Because the section is regenerated wholesale, assemble the cumulative bullet set via `/release-notes harvest --milestone <ver>` rather than a single bullet when more than one PR has merged into the version.

If the PR was merged **by the user outside the agent**, both tasks are missed — they're backfilled later by `/release-notes sweep` (release prep task 5, or ad-hoc).

### Creating a PR

When creating a PR on `linq2db/linq2db`:

- **Always open as draft** (`gh pr create --draft`). Never publish a ready-for-review PR unless the user explicitly asks.
- **Confirm title and body with the user before running `gh pr create`.** Propose both, wait for approval, then create.
- **Link referenced issues/tasks as closed on merge.** If the work targets a known issue or task, include `Fixes #<n>` / `Closes #<n>` in the PR body so GitHub auto-closes it when the PR merges. One keyword per issue.
- **Assignee.** Assign the PR to the current GitHub user (`gh pr create --assignee @me`) unless the user specifies someone else. If `@me` resolution fails with a transient `502 Bad Gateway` (it does a live API call during create, and the PR is **not** created when it fails), resolve the handle explicitly — `gh api user --jq '.login'` — and pass it as `--assignee <login>` on the retry.
- **Milestone.**
  - If the linked issue/task has a milestone, reuse it.
  - Otherwise ask the user to pick one. Fetch open milestones via `gh api repos/linq2db/linq2db/milestones?state=open` and present a **numbered list** (so the user can reply with just a number) in this order:
    1. The **next-version milestone** (matching `<Version>` in `Directory.Build.props`, or the closest upcoming version) — always first.
    2. Remaining **versioned** milestones (titles starting with a digit, e.g. `6.x`, `7.0.0`), sorted by version.
    3. **Non-versioned** milestones (e.g. `Backlog`, `In-progress`), sorted alphabetically by title.
- **CI run proposal.** After `gh pr create`, propose running the full provider matrix on Azure Pipelines via a `/azp run test-all` comment. See [`ci-tests.md`](ci-tests.md) for the trigger syntax and when a narrower `/azp run test-<dbname>` makes more sense. Wait for the user to confirm before posting the comment.

### Setting a PR's project-board lane

linq2db PRs are tracked on org **Project #8 "PR Review Queue"** (id `PVT_kwDOAA01hc4BZqGZ`). The `Status` field (id `PVTSSF_lADOAA01hc4BZqGZzhUnP5s`) has options: `Todo` · `In Progress` (`47fc9ee4`) · `Waiting For Review` · `In Review` · `Done`. "Work In Progress" lane = **In Progress**. When the user asks to put a PR in a lane:

```
gh project item-add 8 --owner linq2db --url <pr-url> --format json   # returns the project item id
gh project item-edit --id <item-id> --project-id PVT_kwDOAA01hc4BZqGZ \
  --field-id PVTSSF_lADOAA01hc4BZqGZzhUnP5s --single-select-option-id <option-id>
```

Re-fetch option ids via `gh project field-list 8 --owner linq2db --format json` if they ever drift.

### Extending an open PR

Commits that extend an open PR's scope go on that PR's branch, not a new parallel branch. When a review session surfaces an ancillary fix (apostrophe-escape bug found while reviewing #5463, a test regression caused by the PR, a missing guardrail) and the user asks for it as a follow-up, push it onto the PR's existing head branch — don't create a sibling `feature/*` branch and propose a second PR. Mechanics:

- Check `gh pr view <n> --json maintainerCanModify,headRepository,headRefName`. If `maintainerCanModify: true` and `headRepository` is a fork, add the author's fork as a git remote if not already present (`git remote add <owner> https://github.com/<owner>/<repo>.git`) and push via refspec: `git push <owner> <local-branch>:<headRefName>`. The PR auto-updates with the new commit. Propose a body update when the new commit extends the PR's originally described scope (follow the [After every successful push: PR body check](#after-every-successful-push-pr-body-check) flow above).
- If `maintainerCanModify: false`, stop and ask — either the author has to apply the change themselves, or the work needs a separate PR. Don't unilaterally open a parallel branch when the intent was a follow-up commit.
- **An org-owned fork can never enable `maintainerCanModify`.** GitHub offers the "allow edits by maintainers" checkbox only for forks owned by a *user*, so on an organization's fork the flag is `false` permanently and "ask the author to turn it on" is not one of the two options above — the separate PR is the only route. Confirm with `gh pr view <n> --json isCrossRepository,headRepositoryOwner`: cross-repo plus an organization head owner settles it. Recipe: branch off `origin/master`, `git cherry-pick <their-sha>` (keeps their authorship in `git log`), add the follow-up work as further commits, open the PR with `Supersedes #<n>`, and comment on the original explaining *why* it moved — otherwise it reads as the maintainer quietly taking the work over. Leave the original open; the author or the merge closes it. (Surfaced on #5804, from the `TLabWest` org fork → #5813.)
- **`maintainerCanModify` only gates *fork* PRs.** Check `isCrossRepository` (`gh pr view <n> --json isCrossRepository,headRepositoryOwner`) first: for a **same-repo** PR branch (`isCrossRepository: false`, head owner `linq2db`), `maintainerCanModify` is irrelevant — anyone with repo write pushes straight to `origin <headRefName>` (with user approval). Don't apply the "stop and ask" rule above to a same-repo branch. (PR #5604: `maintainerCanModify: false` but same-repo — a regression-test commit pushed directly to `feature/prefer-client-calculation`.)
- When pushing to someone else's fork, neutralize accidental pushes afterward if the remote is no longer needed (`git remote set-url --push <owner> no_push` as a guard, or `git remote remove <owner>` if you want it gone). Confirm with the user which — "disable" can mean either.

### Renaming a branch that is the head of an open PR closes the PR

GitHub's branch rename (UI, or `POST repos/<o>/<r>/branches/<b>/rename`) updates the *base* branch of open PRs but **closes** a PR that uses the renamed branch as its *head* — it does not retarget head-side PRs. The old name then resolves only as a redirect, so the closed PR **cannot be reopened** (`reopenPullRequest` fails with "Could not open the pull request"). Recovery is a fresh PR from the renamed branch (reuse the old PR's title/body via `pr-body-edit.ps1`, link back), which loses the original review thread. So **defer a curation / feature branch rename until after its open PR merges** — no head-side PR to close then — or accept the new-PR cost. (Surfaced renaming `infra/claude-curation` → `infra/agents-curation`: it closed PR #5521; #5670 replaced it.)

### Amending a commit on a non-checked-out branch with a dirty current tree

Don't `stash` → `switch` → `--amend` → `switch -` → `stash pop` — the pop can conflict on overlapping files. Use **`pwsh -NoProfile -File .claude/scripts/amend-branch-commit.ps1 -Branch <branch> -Message <text>`** (`-MessageFile <path>` for multi-line; `-Sign` if the original was GPG-signed). It reuses the branch tip's tree (a message/metadata amend — content unchanged), rebuilds the commit object preserving the original author, and atomically retargets the ref with the old-SHA safety check — all while staying on the current branch.

### Splitting two logical changes that share a file into separate commits

`git add -p` / `git add -i` are unavailable (interactive flags aren't supported in this environment), so "one change = one commit, explicit pathspec" needs a non-interactive route when both changes land in the same file. Snapshot-and-replay:

1. Copy the finished file to `.build/.agents/<task>-<file>.bak` (PowerShell tool — `Copy-Item`).
2. `git checkout -- <file>` to return it to `HEAD`.
3. Re-apply **only** change A with `Edit` (a `Read` first — the checkout invalidates the harness's file state).
4. `git commit -F <msg> -- <paths-for-A>` — the explicit pathspec form commits those paths only, no staging step.
5. Copy the snapshot back over the file, then `git commit -F <msg2> -- <paths-for-B>`.
6. `git status --short` to confirm the tree is clean and nothing was left behind.

Cheaper than reordering the work, and it keeps each commit's diff reviewable on its own. Used on #5761 to separate a dependency-pin rescope from an unrelated removal, both in `Directory.Packages.props`.

### Merging master into a feature PR — recurring conflict recipes

When syncing `origin/master` into a long-lived feature PR, three collisions recur:

- **`LinqOptions` (positional record) params: update all five sites.** A master-vs-PR collision on its parameter list (both sides add options before the trailing param) recurs on most option-adding PRs. Keeping *all* new params means updating, consistently: (1) the **primary constructor** param list, (2) the **copy constructor** assignments, (3) the **`ConfigurationID`** hash `.Add(...)` calls, (4) **`PublicAPI.Unshipped.txt`** (the full ctor signature *and* the `Deconstruct` signature, in source param order), and (5) the **binary-compat shim** — the `Deconstruct` shim's trailing `out _` discard count must equal the number of params added after the shim's last named one. A Release `net10.0` build of `Source/LinqToDB/LinqToDB.csproj` validates both the ctor/Deconstruct arity and the RS0016 PublicAPI match. (Surfaced on PR #5450: master added `PreferClientCalculation`, the PR added `DefaultEagerLoadingStrategy` + `ImplicitCollectionLoading`.)
- **A merge that inserts a parameter *ahead* of an existing optional one breaks positional callers silently — convert them to named arguments.** When resolving a method-signature conflict by keeping params from both sides (e.g. the PR's pre-build `adjustArguments` hook *and* master's post-build `transform` hook on `TranslateWindowFunction`), an auto-merged caller that passed a *later* argument **positionally** now binds it to the wrong slot. A Release build catches it only when the types differ; a same-type mis-bind compiles and runs wrong. After such a merge, audit every caller of the widened method and switch later positional args to **named** (`transform: f => …`). (Surfaced syncing PR #5468: master's `TranslateRowNumber` passed its ROW_NUMBER-cast lambda positionally, which would have bound to `adjustArguments` after the merge added it ahead of `transform`.)
- **Merging an end-appended serialized enum keeps the master side's members first.** Enums whose ordinals are serialized over the LinqService wire (`QueryElementType`, etc.) get new members appended at the end on both sides. When master and a feature branch both append, order the resolution as *master's members first, then the branch's* — never interleave — so master's already-shipped ordinals don't shift. (Surfaced syncing PR #5468: master's `SqlCteField`/`SqlCteTableField` placed before the PR's `SqlKeepClause`.)
- **`SqlProviderFlags` property + `[DataMember(Order=N)]` collision — keep master's ordinal, renumber the branch's.** When master and a feature branch both add a `SqlProviderFlags` property with `[DataMember(Order = N)]`, they collide on the same `N` (the next free ordinal at each side's branch point). Resolution: keep master's property at its `N`, and renumber the branch's new flag(s) to the next genuinely-free ordinal — `Grep` `DataMember\(Order = ` across the file first (a pre-existing high ordinal may already occupy `N+1`). The same conflict recurs at the `GetHashCode` and `Equals` bodies (both sides add their flag to the XOR / `&&` chain): keep both, order-independent. `PublicAPI.Unshipped.txt` collides as a pure both-sides addition — keep both additive blocks, drop only the `<<<`/`===`/`>>>` markers. A Release `net10.0` build of `Source/LinqToDB/LinqToDB.csproj` validates the result (and catches an MA0029 if the new flag added a second `.Where`). (Surfaced syncing PR #5643: master's `IsDistinctOnSupported` and the PR's `IsUpdateOutputSupported`/`IsAffectedRowsCountSupported` all claimed `Order = 75`.) **The collision does not always present as a conflict, so treat it as a post-merge check rather than a resolution step.** When the two properties land in different regions of the file, git auto-merges cleanly, and the duplicate ordinal then survives a green Release build *and* a green non-remote test run — nothing local reads the ordinals. protobuf-net refuses to build the contract at runtime, so every remote call fails: the fingerprint is a `test-all` where roughly a third of all tests fail, all of them `.LinqService`, all `Grpc.Core.RpcException : Status(StatusCode="Unknown", Detail="Exception was thrown by handler.")`, with the server-side frame in `ProtoBufMarshallerFactory.ContextualSerialize`. After *any* master merge touching `SqlProviderFlags`, assert it directly instead of trusting the absence of conflict markers — `grep -oE 'DataMember\(Order = [0-9]+\)' Source/LinqToDB/Internal/SqlProvider/SqlProviderFlags.cs | grep -oE '[0-9]+' | sort -n | uniq -d` must print nothing. (Surfaced syncing #5725: the branch's `SupportsPredicateInFunctionValuePosition` and master's newer `IsUpdateOutputRowsSupported` both at `Order = 77`, auto-merged without a conflict → build 23183, 218882 failures. Renumbering to the next free ordinal fixed it; confirmed red→green by putting `77` back and re-running two `.LinqService` tests.)
- **A branch forked before the corpus-submodule migration (#5735) collides on the root trampolines, then trips `pre-commit` twice.** Master turned root `AGENTS.md` / `CLAUDE.md` into pointers into the `.claude/` submodule and deleted the in-repo `.agents/` tree, so any older branch hits two things in sequence. **(1) `AGENTS.md` conflicts** — resolve with `git checkout --theirs -- AGENTS.md`; master's trampoline always wins, those files are marked *do not edit*. If the branch had added a *rule* to its copy, that rule moves to the corpus (`.claude/AGENTS.md`, pushed to the agents repo) — never back into the trampoline; check whether `.github/copilot-instructions.md` already carries it before assuming it's lost. **(2) `.githooks/pre-commit` then refuses the merge commit twice** — once for the staged `.claude` gitlink "bump" (the branch had `.claude` as a *symlink*, master has a gitlink, so any merge reads as a bump) and once for the staged `AGENTS.md` / `CLAUDE.md` edit. Both are false positives: the hook has no `MERGE_HEAD` awareness. Confirm the staged entries are byte-identical to master — compare `git ls-files -s -- AGENTS.md CLAUDE.md .claude` against `git ls-tree origin/master -- AGENTS.md CLAUDE.md .claude` — then commit with `--no-verify`. (Surfaced syncing #5678.)
