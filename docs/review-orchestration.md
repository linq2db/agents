## Review orchestration — shared skeleton

Common orchestration reused by `/review-pr` and `/verify-review`. Everything in this doc is skill-agnostic: the mode-specific logic (scope confirmation, prior-findings parsing, per-finding action table, etc.) lives in each skill's own `SKILL.md`. This doc is the single source of truth for the steps that are word-for-word identical between the two skills.

### Permission-prompt discipline

Every Bash call is evaluated against the allowlist in `.claude/settings.local.json`. Pipes, redirects, inline `pwsh -Command`, `cat` / `head` / `tail`, or `ls` on directories whose layout is already documented each fire a prompt. Before writing a helper script to extract data from a JSON file, ask whether `Grep` on the dumped JSON or `Read` on the file would return the same information — the answer is almost always yes. See [`windows-gotchas.md`](windows-gotchas.md) → **Permission-friendly Bash patterns** for the full table.

### Resolving the target PR

Follow [`pr-resolver.md`](pr-resolver.md). The resolver returns the PR **number** only — no standalone `gh pr view` call, because the subsequent context load returns full metadata as part of its main response. If the input branch has no PR:

- `/review-pr`: stop and propose creating one (per `agent-rules.md` → **Pull request rules**).
- `/verify-review`: stop — there's nothing to verify.

### Re-review at an unchanged (or master-merge-only) HEAD already reviewed by `currentUser`

After the context load, if the PR already carries a `reviews[]` entry authored by `currentUser`, check whether the PR's *own* code actually changed since that review **before** spawning reviewers — a blind fresh run re-derives near-identical findings and risks posting duplicate threads for findings already open on the PR. Two triggers:

- **Exact-SHA match** — `headRefOid` equals the prior review's `commit_id`. **But `commit_id` is unreliable after a force-push**, so don't trust the match alone: a review's `commit_id` can come back equal to the *current* head even though the review predates it by days. Cross-check the review's `submitted_at` against the head commit's own committer date (`git log -1 --format=%cI <headRefOid>`) — when the review is **older** than the commit it claims to be on, the branch was rewritten under it and the review is **stale**, not current, so proceed with the fresh pass instead of offering "verify open-only". (Surfaced on #5720: an `APPROVED` review submitted 2026-07-26 reported the SHA a rebase created on 2026-07-29, three days later; taken at face value the exact-SHA check reads "already reviewed at this HEAD" for a branch whose every commit had been rewritten.)
- **Master-merge-only advance** — `headRefOid` moved, but the advance is only a `Merge branch 'master'` (or equivalent) with the PR's *own* files unchanged. Confirm by diffing the PR's `nameStatus` files between the prior review's `commit_id` and HEAD (`git diff <commit_id> <headRefOid> -- <the PR's changed paths>`) and discarding entries that are pure master churn (unrelated files, or `PublicAPI.Unshipped.txt` / `Directory.Build.props` lines the merge pulled in). If nothing feature-relevant differs, the reviewed code is unchanged even though the SHA moved — the common case the exact-SHA check misses. (Surfaced on PR #5681: HEAD `6e415ef` was a master-merge over the reviewed `cb31dba2`; the feature code was byte-identical, so an exact-SHA check would not have caught it.)

Offer the user three paths:

- **fresh re-review** — run the full pipeline anyway (the user may want a clean pass).
- **verify open-only** — re-check just the still-open prior findings against HEAD (since the code is unchanged, they'll all confirm "still actual"); cheaper, no duplicate threads.
- **summarize & stop** — report the current open-findings + CI state, no subagents, no new review.

Carry the choice forward (a fresh re-review still walks `initial`-mode normally). This is orientation, not a hard gate — proceed on the user's pick. (Surfaced on PR #5525: "review 5525" targeted a HEAD identical to the prior `currentUser` review's commit with three findings still open.)

**If `currentUser` already has a PENDING draft review on the PR**, a fresh `post-pr-review.ps1` will collide — GitHub allows only one pending review per user per PR. Surface the delivery choice before posting: **replace** (verify the old review is still `PENDING` via `--jq '{state,submitted_at}'`, then `gh api -X DELETE …/reviews/<id>`, then post fresh — carry over any still-relevant observations from the old draft yourself, since the delete drops them), **append** (add only the new findings as `replyComments[]` / comments onto the existing draft), or **report-only** (hand the findings to the user, no GitHub write). (Surfaced on PR #5681: a pre-existing PENDING draft over unchanged code forced a delete-first replace.)

### Loading PR context

One call does all of it:

```
pwsh -NoProfile -File .claude/scripts/pr-context.ps1 -Pr <n>
```

Execute the three sections of [`pr-context-prep.md`](pr-context-prep.md) in order: **Context load** (the one script call), **Change summary**, **Baselines clone setup**. Both skills need all three — draft PRs are no different from ready-for-review PRs.

**Check the PR's build CI result.** After the context load, query CI status on the PR head: `gh pr checks <n> --repo linq2db/linq2db`. If the required Azure Pipelines `build` check is **failing / errored** (not merely pending or running), surface it to the user before spawning reviewers and record it as a `## Review notes` item in the review body — a red build means the diff may not compile, so some findings can be noise and the PR may be mid-flight. Don't block the review on it (draft and in-progress branches legitimately carry red CI); the build state is review-relevant context the human reader should see. Applies to both `/review-pr` and `/verify-review`.

**When the `build` check is red but `test-all` is green, suspect a Release-only failure the code-reviewer passes cannot see** — a Meziantou/Roslyn analyzer error (`MA*` / `RS*`), a banned-API hit, or an API-missing-on-older-TFM break (`net462` / `netstandard2.0`). The `test-all` matrix builds a non-analyzer config, so it stays green while the dedicated Release `build` fails. Don't stop at "build is red": fetch the actual diagnostic with [`azp-build-failures.ps1`](../scripts/azp-build-failures.ps1) (resolve the build ID from `gh pr checks`'s `details_url`; full recipe in [`ci-tests.md`](ci-tests.md) → *Reading failed CI test runs*) — its `buildFailures[]` array carries exactly these compile/analyzer messages when `failedTaskCount` is `0` (a non-test build break). **Do not hand-roll the Azure DevOps timeline API** — the script does the timeline + log fetch + parse in one call. Surface the extracted diagnostic as a finding (BLK when it blocks merge), not just an FYI — the code-reviewer passes won't have caught it, since they neither compile nor run analyzers. (Surfaced on PR #5525: a red `build` with green `test-all` was an `MA0186` analyzer error in a new file; the timeline API was hand-rolled three times before recalling the existing script.)

### Spawning the subagents in parallel

Launch every applicable subagent in a **single assistant turn with parallel Agent tool calls** so they run concurrently. Never sequence them.

- `/verify-review` always spawns two: `code-reviewer` (single-pass, `focus: "all"`) and `baselines-reviewer`.
- `/review-pr` spawns 1, 2, or 4: one or three `code-reviewer` invocations depending on its multi-pass gate (see [`review-pr/SKILL.md`](../skills/review-pr/SKILL.md) step 6), plus `baselines-reviewer` unless the user opted out. All `code-reviewer` invocations share the same `writeDir: .build/.agents/pr<n>` so the diff cache is populated once.

Common fields across both modes, supplied by either skill:

- **`code-reviewer` briefing** (one per pass when multi-pass)
  - PR metadata, linked issues + comments, prior reviews/comments (from the context load). When a prior review carries verbatim content a pass will need — a maintainer-supplied test, exact suggested wording, a guard snippet — paste that review's **full body** into the relevant pass's briefing rather than summarizing it; otherwise the `api-and-test` pass re-fetches it via `gh`, duplicating the context load.
  - Change summary (from the context load).
  - Head ref / base ref (`origin/pr/<n>`, `origin/master`) and the file list from `nameStatus`. The subagent reads content via `.claude/scripts/diff-reader.ps1` — do not paste the diff into the briefing.
  - `writeDir: .build/.agents/pr<n>` — mandatory on the first `diff-reader.ps1` call so full file bodies land on disk for `Read` / `Grep` navigation. **When the session runs in a git worktree, also spell out the absolute worktree-prefixed cache root in the briefing** (e.g. `<worktree-root>/.build/.agents/pr<n>`): subagents that guess the main-repo prefix get permission-denied on `Read`/`Grep`, burn calls rediscovering the path, and in the worst observed case fell back to degraded `Grep`-only access that produced a false finding (PR #5450 review, 2026-06-12).
  - `focus` — `"all"` for single-pass / verify-mode runs; one of `"code-correctness"` / `"sql-and-provider"` / `"api-and-test"` per pass in multi-pass mode.
  - ID-continuation floor per severity (see [`review-conventions.md`](review-conventions.md) → **ID-continuation floor**), or a disjoint ID **window** `[floor, ceiling]` per severity for each multi-pass pass.
  - **Work plan**, when the branch has one — `P1`–`P3`, `P7`, `P10`, `P11`, `P12` from `.claude/plans/<key>/plan.md`, where `<key>` is `headRefName` with `/` → `-`. See [`work-plan.md`](work-plan.md) → *Consumers*. **Pass it whole to every pass** — never slice it by focus, because a `P7` row's job is often to answer a cross-area question that another pass's slice owns. An absent plan is normal (external contributors, pre-mechanism branches) and is never a finding.
- **`baselines-reviewer` briefing**
  - PR number and head branch.
  - Baselines clone path: `../linq2db.baselines`.
  - Baselines branch: `baselines/pr_<n>`.
  - Change summary.

Mode-specific additions — `scope` for `initial`, `prior_findings` for `verify` — are the only per-skill differences. Each skill adds its own `mode: initial` or `mode: verify` field.

**Briefing-hypothesis discipline.** When a briefing raises a specific concern for a subagent to check, distinguish "**verify whether** X holds" from "**X is likely a bug — investigate rigorously**." The second framing drives the subagent to over-invest (e.g. an out-of-repo `dotnet run` compile, an extra `verify-lines` round) chasing a concern that may be unfounded. If the concern is a cheaply-checkable language / library / framework rule — C# escape semantics, a BCL method's documented behavior, an operator's precedence — verify it yourself before planting it as a likely-bug in the briefing; pass it as a neutral "confirm X" at most. (Surfaced on PR #5544: a briefing framed C#'s variable-length `\x` hex escape as a "real correctness bug to investigate rigorously"; the per-pass agent burned a compile to confirm it was a non-issue.)

**Multi-pass consensus is not verification.** When several `code-reviewer` passes flag the *same* finding, that is not independent confirmation if they reason from the same incomplete evidence — multi-pass agreement amplifies a shared blind spot rather than cross-checking it. Before **acting** on such a finding (applying a fix in `interactive` mode, or posting it at BLK/MAJ) when its resolution requires real code change, independently verify its **load-bearing technical claim** against the actual call site / source, not just the line numbers. (Line-number verification — trusted per `review-pr` step 7 — is cheap positional data; this is about the *claim*, e.g. "this method info is the one the call site emits".) Surfaced on PR #5627: all three passes flagged an "async path unhandled" MAJ from the existence of an `*Async` method info; checking the call site showed the async extension builds the *sync* info, so the finding was a shared false positive — dropped before posting.

### Classifying public-API surface changes

Apply the decision tree in [`api-surface-classification.md`](api-surface-classification.md) to the `api_changes` returned by `code-reviewer`, using the PR's milestone title and file list from the context load. Produces the deduplicated refresh note and any milestone-gated findings. Both skills run this against **fresh** `api_changes` — never reuse classification from an earlier cycle.

Compute the `suppressions_updated` flag by filtering the in-memory `nameStatus` array for entries matching `Source/**/CompatibilitySuppressions.xml`. Do **not** re-run `git diff --name-only | grep` — the data is already in hand and the pipe would prompt on the allowlist.

**The primary clone is on its own branch during a review — not the PR branch.** `/review-pr` is read-only and works from `origin/pr/<n>` via the diff cache; it never checks out the PR. So a plain `Grep` / `Read` / `Glob` against the working-tree `Source/` reflects **whatever branch the clone sits on** (normally `master`), giving false negatives for PR-added files (they don't exist there) and stale content for PR-modified ones. **The clone can also be on the *right* branch and still be stale** — a local `master` that is merely behind `origin/master` produces an identical false negative, and that case is the more surprising one because nothing about the branch name signals it. Treat "not found in the working tree" as evidence about your checkout, never about the PR. (Surfaced on #5801: a working-tree `Grep` for `QueryCacheTest` returned no matches even though `Tests/Base/Attributes/QueryCacheTestAttribute.cs` exists on `origin/master`, which briefly read as "the PR's new tests reference an attribute that doesn't exist and cannot compile" — a near-miss BLK against a PR that was fine.) To inspect PR code, read the diff cache at `writeDir` — but that holds only the PR's *changed* files. For a repo-wide "is symbol X still referenced anywhere" check (e.g. before confirming a type is safe to delete), the diff cache is insufficient — but a worktree usually isn't needed either: **`git grep -n '<pattern>' origin/pr/<n> -- <path>` searches the ref's tree directly**, in one call, with no checkout. Prefer it for any read-only sweep; reserve the worktree for sweeps that must build or run. To read a *specific* known non-diff file from the PR ref (a sibling `.csproj`, `Directory.Build.props`, `Directory.Packages.props`), add its path to a `diff-reader.ps1` manifest with `include.content: true` — the reader resolves it against `origin/pr/<n>`. Never trust a primary-working-tree grep as evidence about PR code. (Surfaced on #5711: a working-tree `Grep Source/ Lfu` returned nothing and the file read as "does not exist" because the clone was on `infra/agents-curation`, briefly reading as a contradiction of a confirmed finding.)

### Posting via the wrapper

All posting (initial review, verification follow-up, body PUTs, thread resolves) goes through scripts under `.claude/scripts/`. Mechanics — manifest-script format, invocation, manifest-to-finding mapping, verify semantics, heredoc caveats, and the stdout reporting shape — are defined in [`review-posting.md`](review-posting.md). Each skill supplies only the per-review content that fills the manifest template:

- `/review-pr` → `.build/.agents/pr<n>-manifest.ps1` via `post-pr-review.ps1`.
- `/verify-review` → `.build/.agents/pr<n>-verify-manifest.ps1` via `post-pr-review.ps1`, plus `.claude/scripts/apply-verify-writes.ps1` for prior-review in-place edits.

### Mode-choice gate (initial / verify)

After the preview is shown and the user has seen the assembled review body + counts + any baselines `compressionFeedback`, both skills ask one question:

> How should we proceed?
> 1. **interactive** (default) — walk every reviewable item (findings, **out-of-scope observations**, baselines anomalies, audited threads) one-by-one with `prove-with-test+fix | fix | reject | accept-for-post` (out-of-scope observations additionally offer **promote-to-finding / track-issue / leave-as-FYI**). Items accepted for post accumulate into a final draft review at the end.
> 2. **submit-all** — bulk-post the review draft with all findings; bulk-disposition every audited thread from step 2b (reply+resolve for Fixed/Inaccurate; reply+unresolve for Still-actual threads that were resolved by someone other than `currentUser`).
> 3. **save-for-later** — write the whole review to a state file and stop; another session picks it up with `resume`. No GitHub write.
> 4. **cancel** — abort; no writes.

Wait for explicit choice — do not assume a mode on silence.

**Interactive is the default in this repo**, and the ordering above reflects that: the maintainer has repeatedly chosen the per-item walk and has a standing preference for it. Listing `submit-all` first invited a mismatch between this doc and that preference, which the agent then had to reconcile per session. Offer interactive as option 1; `submit-all` stays available for a bulk pass the user explicitly asks for.

#### submit-all mode

One bundle of writes, single allowlist prompt per script. **Order matters — post the thread dispositions *before* creating the draft review:**

- `post-pr-thread-replies.ps1` — **run this first.** Every entry from the step-2b disposition table in one call:
  - `{ resolve: true }` for Fixed and Inaccurate verdicts.
  - `{ unresolve: true }` for Still-actual + resolved-by-other-user (reopen the thread with an explanatory reply).
- `post-pr-review.ps1` — the full manifest (body + lineComments + fileComments + replyComments).
- `/verify-review` only: `apply-verify-writes.ps1` for prior-review in-place edits (body PUTs + comment PATCHes + resolve mutations).

**Why this order.** `post-pr-thread-replies.ps1` posts each reply via REST `POST …/comments/{id}/replies`, and `post-pr-review.ps1` creates a **PENDING** draft review. GitHub allows only **one pending review per user per PR**, so a standalone thread reply attempted *while a fresh draft is pending* fails with HTTP 422 `user_id can only have one pending review per pull request` (observed on PR #5558, 2026-05-30 — the reply 422'd, leaving the thread untouched; it succeeded on re-run after the draft was submitted). Thread dispositions are public, immediate actions independent of the draft, so posting them first sidesteps the collision. If the draft has *already* been created this run, don't retry-loop the thread replies — either post them after the user submits the draft, or fold the reply into the review manifest's `replyComments[]` (scoped to the pending review via GraphQL, so it doesn't collide).

The review itself remains a **PENDING draft** (`event` omitted on the REST review create) per each skill's `Don'ts`. `submit-all` controls walking style, not draft-vs-submit — the user submits the draft manually after inspection.

#### interactive mode

**An item qualifies only when the answer changes what gets posted.** Walk decisions the user must adjudicate — a finding's severity, whether it ships at all, how an out-of-scope observation is dispositioned, whether an anomaly is real. Do **not** spend a walk turn on how the review *renders*: the `## Baselines` cluster table's wording, which rows carry an editorial note, section ordering, and phrasing are the reviewer's call, and offering them as options with "keep as drafted" recommended just asks the user to ratify a default. Decide those yourself and let the pre-post body preview be where they're seen. (Surfaced on #5750: two consecutive baselines-presentation questions were answered `skip` — every option was a rendering variant.)

Walk every reviewable item in this order:

1. Body-section findings (severity order: BLK → MAJ → MIN → SUG → NIT).
2. Line-level findings (file order, line order within file).
3. File-level findings.
4. Out-of-scope observations (each with the fuller action set below).
5. Baselines anomalies (cross-provider distinctions the `baselines-reviewer` flagged).
6. Still-actual prior-review findings from step 2b — other authors' review **body-summary** claims *and* inline threads that reproduce at HEAD (see the note below).
7. Thread dispositions from step 2b (Fixed/Inaccurate replies; Still-actual unresolve actions).

**Out-of-scope observations are walked here in interactive mode** — the up-front out-of-scope disposition gate (`review-pr` step 7b) is *deferred* into this walk rather than done before the mode choice. Each observation is dispositioned one-by-one with the same testable-first options as findings, plus the three OOS-specific terminal choices: **promote-to-finding** (assign a severity + ID, it joins the accept-for-post set), **track-issue** (invoke `/create-issue`, then keep it as an FYI line with the issue number), or **leave-as-FYI** (unchanged FYI entry). A promoted observation is eligible for **prove-with-test+fix** / **fix** exactly like any other finding. (In `submit-all` / non-interactive mode, step 7b still runs up-front instead.)

**Still-actual prior-review findings are walk items, not just audit lines.** A prior review by another author (a human `CHANGES_REQUESTED`, a bot) whose findings still reproduce at HEAD — whether posted as inline threads or **only in the review body** — enters the walk with the same `prove-with-test+fix | fix | reject | accept-for-post` action set, so the user can resolve them in-session instead of only reading them under `## Prior-review audit`. This is easy to miss for **body-summary** findings, because a human's `CHANGES_REQUESTED` review often has no inline threads (item 6 above exists to catch exactly that). **Do not re-post another author's finding as your own comment** — that duplicates their open review (`github-authoring.md` → *never edit / duplicate others' content*); when a still-actual finding is fixed, its disposition is the pushed commit plus a reply on the author's thread/review, and the audit line flips to `Fixed`. `reject` here means "disagree with the prior reviewer" — record the reasoning as a reply, never a silent drop. (Surfaced on #5703: igor's three still-actual body findings were kept audit-only and fell out of the walk, so the one the user wanted fixed had to be pulled into scope by hand.)

**Verify a code-reviewer OOS observation's control-flow claim before surfacing it.** An observation that asserts a *mechanism* — "path X bypasses Y", "code is dead / a no-op", "flag is never set" — carries the same from-summary imprecision as a baselines anomaly (`review-pr` SKILL step 8 → *verify each anomaly against the actual file*): the subagent's *conclusion* (usually "moot / low-risk") can be right while its *mechanism wording* is wrong. Before presenting such an observation, trace the actual call graph (`Grep`/`Read` the cited sites); present the verified conclusion, not the subagent's mechanism phrasing. The same applies to your own restatement — don't add a stronger claim ("dead", "no-op by design") than the trace supports. (Surfaced on #5600: a "bulk-copy bypasses `CreateParameter`" OOS was traced to bulk copy routing its `DataParameter`s through `CommandInfo`→`CreateParameter` after all — the spotted `SetParameter` call was a value-converter, not command-parameter creation; and an "`IsDbDataTypeExplicit` LINQ leg is dead" framing was corrected to "used by the raw-SQL path, correctly `false` on LINQ". Both were caught only because the user probed the mechanism.)

**Confirm where a `fix` lands when the PR is another author's.** The `fix` / `prove-with-test+fix` actions edit files. When the target PR is authored by someone else — even a **same-repo, non-fork** branch — confirm the destination before editing: their PR branch (worktree checkout + push, which needs its own explicit go-ahead), a local edit for the user to fold in, or a review comment for the author to apply. Don't default to pushing onto their branch. Pushing commits to another author's PR branch isn't covered by the "never edit others' bodies/comments" rule, but it's still an outward action on their work — get the target confirmed. (Surfaced on #5721: the fix target — sdanyliv's `infra/skills-review` — was confirmed with the user before the worktree checkout and push.)

Walk **one finding per prompt**, even when the finding count is small (< 5). **Never merge several findings into a single questionnaire without an explicit user request to do so** — the general *ask-ask-do-all* batching rule in [`agent-rules.md`](agent-rules.md) → **Batching and user interaction** does **not** apply to interactive issue review; default to one-by-one. Batching here defeats the per-item action choice and the per-item severity/scope reconsideration the walk is for. The only sanctioned merge is the >20-item grouping below, and it applies only after the user accepts the proposed grouping. (Repeated correction; reinforced on PR #5657, where batched disposition prompts were redirected to one-by-one each time.)

**Lead each item with its mechanism, not with its action menu.** A walk item's first presentation must explain *what goes wrong and why* — the causal chain, named in the code — before any `fix | reject | accept-for-post` choice is offered. Presenting the options first asks the user to adjudicate a defect they have not been shown, and the menu itself silently encodes an answer to a question that was never posed. This is [`agent-rules.md`](agent-rules.md) → *Explain the mechanism before proposing the fix* applied to the walk, restated here because the walk is where it is easiest to skip: the per-item contract below ("the finding, its context, your recommendation" plus an action set) reads as licence to lead with the actions. (Corrected on #5786 — the same PR whose review *generated* the general rule then violated it during its own finding walk: a BLK was presented as a four-option menu and the maintainer's entire reply was *"explain issue"*.)

**A walk turn is still a reply, so it still takes the three-section structure.** The always-loaded reply rule (`CLAUDE.md` → *Reply structure*: **Prose** → **Questions** → **Next actions**, each doing only its own job) does not lapse because the turn is a walk item, but the per-item contract below — "the finding, its context, your recommendation" plus an action set — reads as licence to write one continuous block, and that is what gets written. Split it: the mechanism and evidence are Prose, the single disposition ask is the Question, and the action set is Next actions. The failure is silent, because a one-block item *looks* complete and the user answers it anyway — what degrades is every turn after it, since a question tacked onto the end of a prose block is not asked and gets lost the moment a background notification lands (see *An unanswered question outranks a background notification* in [`agent-rules.md`](agent-rules.md)). Restated here for the same reason as the two rules above: the walk is where an always-loaded rule is easiest to skip. (Surfaced on #5817, where six consecutive items were written as single blocks — an out-of-scope question had to be re-asked three times and was still unanswered when the walk moved on — and the maintainer's correction was *"because you forgot your instructions to structure response"*.)

**Build each item's option list from the action set above — don't improvise it per item.** The walk's actions are fixed (`prove-with-test+fix | fix | reject | accept-for-post`, plus promote-to-finding / track-issue / leave-as-FYI for an out-of-scope observation), and the prompt you render must offer *those*, not a menu invented from what the finding happens to feel like. The failure is silent and one-directional: an improvised menu drops the **expensive** end — `prove-with-test+fix` and `fix` — because a just-written finding suggests its cheap dispositions (post it, downgrade the severity, drop it) and those are what fill the option slots. The user then has to reinstate the real action by hand, and that reinstatement is the tell. Note this is not the same failure as leading with the menu instead of the mechanism (above): the mechanism can be explained perfectly and the options still be wrong. (Surfaced on #5831, where all four walk items got improvised menus with `fix` absent: the maintainer answered *"apply here"* on the first, then chose past the recommendation on the next three. Both probes they had to ask for changed the answer — one turned a leave-as-FYI observation into a proven defect with a shipped fix and a regression test, the other refuted a finding as inert.)

**State what the fix would change: behaviour, or only the diagnostic.** An item whose remedy improves an *error message* while leaving the query exactly as broken is a different decision from one that makes something work, and the mechanism explanation alone does not distinguish them — a vivid causal chain reads as a correctness fix regardless of what the fix actually does. Say which, at the item, in the commit message, and in the closing tally. The tell is a finding phrased around an **internal** invariant — "emits a tree with an unbound parameter", "leaves the cache inconsistent", "produces an ill-formed node": name the **observable** consequence instead (throw / silent wrong data / wrong SQL), because that is what sets the severity and what the user is actually adjudicating. An internal-invariant violation whose consequence is always a loud failure is a diagnosability finding, and calling it anything else oversells it. (Surfaced on #5701: a MIN was written up as "the flatten can emit a tree containing an unbound parameter", fixed, committed and reported — and the maintainer had to ask *"so we didn't fixed in terms 'made them work', but fixed to produce better error message?"* to establish that #5790's shape still fails either way and only the message changed.)

Per item, **always surface prove-with-test+fix as an offered action** — not just `accept-for-post` / `reject`. For a testable finding (reproducible wrong result, wrong SQL, or throw) offer **prove-with-test+fix**; for a non-testable one (a design / style / doc / naming point with no reproducible runtime symptom) offer plain **fix**. **prove-with-test** and **fix** may be chosen together (see *Sequencing* below); **reject** / **accept-for-post** are terminal:

- **prove-with-test** — when the finding is testable (a reproducible wrong result, wrong SQL, or throw), write a regression test that reproduces it on a worktree branched from PR HEAD and run it to confirm it goes **red** against PR HEAD. Run the PR's own / newly-added tests **yourself, not via `test-runner`** (see [`worktree.md`](worktree.md) → *Running tests from a worktree*). The red test is the empirical proof the finding is real, per [`agent-rules.md`](agent-rules.md) → *Before coding a fix or feature* (define the red regression test first). **If the test cannot reproduce the finding, do not fix on speculation** — reframe it as a "could not reproduce" FYI to the author with the repro details and a test pinning the current (correct) behaviour, per the same rule. **Attribute before acting — and before *saying* — by running the same repro on a fresh `origin/master` worktree.** An identical failure on master proves the defect is *pre-existing* — not introduced or worsened by this PR — so it is a tracking issue (cite "verified failing identically on master" in the issue and the review FYI), not a PR finding to fix here. Only a failure that reproduces on PR HEAD but **not** on master is a regression the PR caused. (Surfaced on PR #5680: a Convert-wrapped-branch recursive-CTE column drop reproduced on both PR HEAD and master → filed #5683 as pre-existing rather than blocking the PR.)

  **The master control is required for *any* probe whose result you will characterise as PR-caused — not only for out-of-scope observations.** This rule was originally written for the OOS case, which is exactly why it fails to fire on the one that bites: an **in-scope** finding, where the PR demonstrably introduced the *mechanism*, so a red probe on PR HEAD feels like proof of a regression. It isn't. A PR-introduced mechanism is not evidence of a PR-introduced *outcome* — the pre-existing behaviour may already produce the same wrong answer by a different route, and then the mechanism change is inert. Run master before writing the word "regression", "introduced", or "proven", not merely before applying a fix. (Surfaced on #5750: a `Contains` probe returned `[1, 2]` where the CLR answer was none, and the PR had visibly narrowed the emitted literal from `toDecimal128('0.00005', 10)` to `(…, 4)` — reported as a proven wrong answer. The master control returned `[1, 2]` too: ClickHouse truncates the probe against the column's scale inside `IN` regardless of the width we declare. Pre-existing, filed as #5789, and the finding was dropped.)
- **fix** — apply the suggested fix on a worktree branched from the PR HEAD (per [`agent-rules.md`](agent-rules.md) → *Creating a new branch* + [`worktree.md`](worktree.md)). **Base it on `origin/pr/<n>`** — the context load already fetched that ref, so no second fetch is needed: `git worktree add <worktrees-root>/pr<n> origin/pr/<n>`, commit on the detached HEAD, push with `git push origin HEAD:<headRefName>`. Don't `-b` the PR's own branch name and don't fetch the branch separately: a session that already pushed this PR leaves that branch behind *locally*, so `git worktree add --track -b <headRefName> …` dies with *"a branch named … already exists"*, and the branch fetch that looks like the fix has its own destructive short-refspec trap ([`windows-dev-gotchas.md`](windows-dev-gotchas.md) → *Fetch a PR head*). (Surfaced on #5720: four calls spent on a worktree that `origin/pr/5720` would have produced in one.) For PRs the current user owns or fork PRs with `maintainerCanModify: true`, commit per concern (no push yet — see test-batching rule below); after the walk completes, push the accumulated commits and append a `## Follow-up commit(s)` subsection to the PR body per `agent-rules.md` → *Push to remote rules*. Otherwise stop and propose filing a follow-up issue instead. Commits are grouped per concern, not bundled into one giant fix commit.
- **reject** — drop from the draft. Record the rejection reason inline so a future `/verify-review` can see it; never silently drop.
- **accept-for-post** — keep for the final draft review accumulated at the end of the walk.

**Default the recommendation to a pushed fix, not a posted comment.** The standing maintainer preference is for a review to leave the PR closer to mergeable: a proven red→green regression test and an applied fix on the branch beat a comment the author must act on. Across #5450 and #5525 the answers were consistently `prove-with-test` → `fix` → "keep root-causing" when a fix proved incomplete → push → sync with master. So recommend that path for any reproducible finding rather than offering `accept-for-post` as the neutral default. The closing sequence, each step its own explicit go-ahead: push the fixes (one commit per concern) → on someone else's PR convey via a **new comment** plus reply-resolve on your own threads (never edit their body) → `git merge origin/master` → push → propose the CI run → clean up the worktree. Guardrails still bind: don't reshape cross-cutting internals to force a fix (raise it instead), and gate an unfixable-in-review defect with `[ActiveIssue]` rather than leaving the branch red. When a finding turns out to rest on a false premise, **withdraw** it — don't hand-fix.

**A test-coverage finding leads with its discriminator.** For a "this has no test" item, state up front the two things that decide it: **would existing consumers go red if it regressed**, and **does the test back a user-visible claim** (a release note, documented behaviour, a stated contract)? On #5750's walk three test-only asks were rejected and one accepted, and that pair predicted every outcome — rejected: a test for a helper verified correct twice whose two consumers would redden, a test for a method following a framework-wide convention, a node-level pin verified on three axes; accepted and fixed: a set-operation refusal tested for only one of the five operations the **release note** claims, where the untested pair is where a mis-stated predicate would silently corrupt a row set. Raise the finding either way — this is not a suppression rule and licenses no coverage-noise budget — but leading the *Why* with the discriminator makes the disposition one read instead of a discussion. Where neither condition holds, prefer `accept-for-post` over `fix`: writing the test yourself spends diff on someone else's PR for a guard they may not want.

**A documentation finding leads with what the reader does wrong without it.** For a "the docs don't say X" item, the deciding question is not whether X is true — you verified that — but whether a reader who doesn't know X takes a *wrong action*. An omission that costs **precision** (a bound is approximate, a figure is rounded, an edge case is unstated) is usually declined; one that costs an **action** (the reader sets the option, nothing happens, and nothing explains why) is usually fixed. On #5828's walk both fired minutes apart, on the same doc block: a +25-character overshoot past a 384 KB cap was rejected, while an undocumented `MaxBatchSize` row clamp — which silently makes the whole option inert for rows under ~65 characters — was fixed on the spot. Raise either way; leading the *Why* with the discriminator is what makes the disposition one read instead of a discussion. This is the doc-finding sibling of the test-coverage rule above.

**Sequencing when both prove-with-test and fix are chosen.** Run **prove-with-test first**, and proceed to **fix only after the test reproduces the issue** (goes red against PR HEAD). The failing test is what confirms the fix targets a real defect; the fix then flips it green. If prove-with-test fails to reproduce, the fix is **not** executed — the finding becomes a could-not-reproduce FYI instead (per the reframe rule in the prove-with-test action above).

**Test batching during interactive walks.** Do not build or run tests after each individual `fix` action during the walk — the per-fix build cycle dominates wall time (≈3 min/build on this repo) and serializes the walk needlessly. Default flow:

1. Apply each fix → commit per concern (no build, no test, no push).
2. After the walk completes, before pushing or finalizing the draft review, run **one batched `dotnet build` + filtered test pass** on the worktree covering every fix applied during the session.
3. Push only after the batched build + tests pass. If they fail, identify the breaking change(s) and propose a fix commit before pushing.

Exception — when the user says "run tests now" / "build now" / similar mid-walk, build + run the filtered tests for the in-progress fix immediately, report results, then resume the walk on the user's direction.

At the end of the walk, run the thread-disposition bundle **first** (`post-pr-thread-replies.ps1`), then post the accumulated `accept-for-post` set as one draft review — the same one-pending-review ordering constraint as `submit-all` above (a standalone thread reply 422s while a fresh draft is pending).

When every finding was dispositioned `fix` (the `accept-for-post` set is empty), **no draft review is posted** — the pushed commits plus the PR-body `## Follow-up commit(s)` subsection are the entire outcome. Still run the thread-disposition bundle if any prior-review threads were audited; skip the empty draft-review POST.

**Grouping for high item counts (>20).** Before walking, compute clusters on the most-discriminating axis: by file path, by severity, or by shared wording (first 12 words of `why` lowercased — the same dedup key the multi-pass merge uses). Propose the most-clustered axis as a grouping: each group is dispositioned in one step (group-level `fix | reject | accept-for-post` applies to every item in the cluster). The user can accept the group disposition or expand a group to per-item walking. Single-item clusters are flattened back to per-item walking automatically — never wrap one finding in a "group of 1" prompt.

#### save-for-later mode

The review is finished; the disposition isn't. This hands the whole result to a **later session** — usually the one that owns the PR's worktree and will do the fixing — without re-deriving it. That re-derivation is the cost being avoided: a fresh pass is a context load plus two to four subagent runs, and it produces *different* findings, so "just review it again over there" is not the same review.

**Location — always the primary clone**, never the worktree the review ran in:

```
<primary-clone>/.build/.agents/pr<n>-review-state.json
```

Resolve the primary clone from anywhere with `git rev-parse --path-format=absolute --git-common-dir` and strip the trailing `/.git`. From inside a worktree that command still returns the **primary** clone's git dir, which is exactly the property this needs — a worktree's own `.build/.agents/` is a different directory that no other session will think to look in. The `pr<n>-` prefix matches the naming convention in [`agent-rules.md`](agent-rules.md) → *Temp files*, so the file is also safe from another session's prefix-scoped cleanup. It is still gitignored scratch, not durable storage: a wiped `.build/` takes the saved review with it. For a handoff that has to outlive the clone, post the PENDING draft instead — that lives on GitHub and `/verify-review` reads it back.

**Print the absolute path back to the user on its own line**, with the per-severity / OOS / thread counts beside it, so the handoff message is copy-pasteable into the next session as-is.

**Never clobber another session's saved review.** `.build/.agents/` is shared across concurrent sessions. If the target file already exists with `status: "open"`, show its `savedAt`, `reviewedHeadSha` and counts and ask overwrite / keep-and-abort — a silent overwrite destroys a review that cost several subagent runs, and nothing about the filename says whose it was.

**What the file carries.** Everything a fresh session needs to walk and post without re-running a single reviewer:

```
{
  "schemaVersion": 1,
  "status": "open",                       // "open" | "consumed"
  "skill": "review-pr",                   // or "verify-review"
  "mode": "initial",                      // or "verify"
  "savedAt": "<ISO-8601>",
  "savedFrom": "<abs path of the clone or worktree the review ran in>",
  "pr": { "number": 5791, "title": "…", "url": "…", "headRefName": "…", "baseRefName": "…", "milestone": "…" },
  "reviewedHeadSha": "<the sha the findings were derived from>",
  "scope": "<confirmed scope from the pre-review gate>",
  "idFloor": { "BLK": 1, "MAJ": 1, "MIN": 5, "SUG": 2, "NIT": 1 },
  "body": "<the assembled review body, verbatim>",
  "findings": [ { "id", "severity", "file", "line", "line_end", "why", "fix", "suggestion", "disposition" } ],
  "outOfScopeObservations": [ … ],
  "priorClaimAudit": [ { "threadId", "verdict", "plannedAction", "replyText" } ],
  "plannedInPlaceEdits": [ … ],           // verify only — /verify-review step 7's update plan
  "baselines": { "status", "summary", "anomalies": [ … ] },
  "apiChanges": [ … ],
  "ciStatus": "…",
  "posted": { "draftReviewId": null, "threadRepliesPosted": [] }
}
```

`disposition` is `pending` on a straight save from the gate. When `save-for-later` is chosen partway through an interactive walk it carries what the walk already settled (`accept-for-post`, `rejected` + reason, `fixed` + commit sha), so the resuming session walks only what is actually left.

**`posted` is the idempotency record, and it is not optional.** Everything already written to GitHub by the saving session goes here — the pending draft's id, every thread reply already posted. A resuming session that re-posts them duplicates public comments on someone's PR and then hits the one-pending-review-per-user 422 described under *Mode-choice gate* above.

#### Resuming a saved review

Entry point: `/review-pr resume <n>` / `/verify-review resume <n>`. Both read the same file. If the state's `skill` doesn't match the skill that was invoked, say so and resume under the **saved** skill's rules — a `verify` state reinterpreted as an `initial` one loses the prior-findings mapping that verify mode exists for.

1. **Locate** via the same path recipe. No file → say so plainly and offer a fresh review; never fall back to silently re-reviewing, which looks identical to the user and is not.
2. **Already consumed?** `status: "consumed"` → report when, and stop. A second consumption re-posts what the first already posted.
3. **Validate against current HEAD — the load-bearing step.** Compare `reviewedHeadSha` against the PR's current `headRefOid`. Equal → straight into the preview and the walk. **Different → the line anchors are no longer trustworthy**: the findings were derived against a tree the PR has moved past, so posting them as line comments can anchor them onto unrelated code, and some are likely already fixed. Offer **`/verify-review`** (the tool built for exactly this — re-verify the saved findings against the new HEAD), **resume body-only** (body-section findings only, line/file anchors dropped), or **fresh review**. Never resume line comments across a moved HEAD on your own initiative.
4. **Re-enter at the preview**, not at step 1. The state file *is* the reviewers' output — re-running `code-reviewer` / `baselines-reviewer` / the full context load defeats the whole point. Fetch only what validation needs: the current `headRefOid` and whether a pending review already exists.
5. **On completion, mark rather than delete** — set `status: "consumed"` and `consumedAt` in place. A third session then reads "already consumed on <date>" instead of "not found", and the `posted` record survives. Deleting the file is what makes an accidental double-post indistinguishable from a first run.

### Command-usage audit (closing step)

After the draft review (and, for `/verify-review`, its in-place edits) have been reported, ask the user (single prompt):

> Run a command-usage audit for this session? Identifies unnecessary/duplicate commands, opportunities to fold calls into existing scripts, and allowlist/guardrail gaps. [y/N]

On `y`: walk back through the Bash / `gh` / `git` / `pwsh` calls the skill issued in this session. Both `code-reviewer` and `baselines-reviewer` return `callLog[]` — include their entries too, tagged with the subagent name. For each call, classify as:

- **Necessary** — no-op, leave as-is.
- **Redundant** — already covered by a prior call's output or an existing script's output; recommend removing.
- **Batchable** — multiple calls with the same shape that could fold into a single manifest-driven script call; recommend the new / extended script.
- **Guardrail gap** — a call that should have been blocked by `agent-rules.md` or the allowlist but wasn't; recommend the guardrail update.

Report as a table plus a prioritised follow-up list. Do **not** implement fixes in this turn — propose, then wait for a second explicit go-ahead. Multi-file edits to skills / scripts / docs are not something to batch into a review run.

On `N` (or silent): end without further action.
