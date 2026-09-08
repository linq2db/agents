---
name: merge-milestone
description: Merge every open PR on a milestone, one at a time — sync each with master, wait for its GitHub Actions gate, squash-merge it, then merge its baselines PR on linq2db.baselines. Handles the conflict cascade that sequential merges produce (each PR inherits the previous ones). Use when the user says "merge milestone", "/merge-milestone", "merge all PRs in <ver>", or wants a milestone cleared before release prep. Every merge is gated on one up-front authorization; the skill never widens the set it was given.
---

# /merge-milestone

## What this skill is (and isn't)

**Is:** the write counterpart to [`/release-milestone-check`](../release-milestone-check/SKILL.md). That
skill audits whether a milestone is clear and asks the user to resolve what isn't; this one *clears* it,
by driving each open PR through sync → gate → merge → baselines-merge in sequence.

**Isn't:**

- Not a review. It does not read diffs or assess whether a PR should merge — the milestone membership is
  the decision, and the user made it. If a PR looks like it needs review, say so and let the user decide;
  don't review it inline.
- Not a way to merge red CI. The gate is a gate.
- Not authorized to touch PRs outside the milestone, or baselines PRs whose source PR is not in the set
  (see *Don'ts*).

## Why sequential, and what that costs

Each merge moves master, so every remaining PR goes `BEHIND` again — the syncs cannot be batched, and a
PR synced before an earlier merge lands has to be synced twice. Sequential is also what surfaces
conflicts one at a time instead of as a pile. Budget roughly 15–25 min per PR: the gate is ~7–15 min, and
any PR that conflicts adds a worktree round.

## Required reading

- [`.claude/docs/github-actions.md`](../../docs/github-actions.md) → *`build.yml` is a superset of
  Azure's `build` pipeline* — which legs to gate on, and why waiting for Azure buys nothing.
- [`.claude/docs/pr-and-push.md`](../../docs/pr-and-push.md) → *A sync push dismisses the approval it
  needs* (why the batch needs `--admin`) and *Merging master into a feature PR — recurring conflict
  recipes* (the collisions sequential merges produce, and the both-sides build check).
- [`.claude/docs/baselines-repo-layout.md`](../../docs/baselines-repo-layout.md) → the baselines repo
  disallows merge commits and its PRs arrive as drafts.
- [`.claude/docs/worktree.md`](../../docs/worktree.md) → *Base an existing-branch worktree on
  `origin/<branch>`* — a local branch left by a prior session is routinely stale.

## Procedure

### 0. Survey

```
gh pr list --repo linq2db/linq2db --search "milestone:<ver>" --state open \
  --json number,title,isDraft,mergeable,mergeStateStatus,headRefName,author,reviewDecision
gh pr list --repo linq2db/linq2db.baselines --state open --json number,title,headRefName
```

Pair each source PR with its baselines PR by head ref `baselines/pr_<n>`. Not every PR has one — a change
that emits no SQL (CLI, build, docs) produces none, and its absence is not a problem to investigate.

Report the set as a table before doing anything: PR, title, `mergeStateStatus`, `reviewDecision`,
baselines PR. Note any PR still `isDraft` — those need the user's call on whether they belong in the run.

Then read the protection shape once, because it determines whether the whole run needs `--admin`:

```
gh api repos/linq2db/linq2db/branches/master/protection --jq '{strict: .required_status_checks.strict, checks: [.required_status_checks.checks[]?.context], enforce_admins: .enforce_admins.enabled, reviews: .required_pull_request_reviews}'
```

### 1. Get authorization once, up front

Ask in a single turn, with the survey table already shown:

1. **Merge authorization.** State plainly which PRs lack a live approval *and* that syncing dismisses the
   approvals the rest have, so the run needs `gh pr merge --squash --admin`. Offer "stop on any red leg"
   as a distinct option — bypassing a review requirement and bypassing a failed check are different
   things and the user may want only the first.
2. **Gate depth.** The six GH legs (~15 min/PR) vs also `/azp run test-all` per PR (hours/PR) vs
   test-all only for engine-touching PRs. Give the per-PR cost of each so the choice is real.

Do **not** ask per PR afterwards. One authorization covers the run; a *new* question only arises if the
run's shape changes (a PR turns out to need review, a conflict needs a judgement call).

### 2. Per-PR loop, ascending by number

Oldest first, so the longest-lived branches take the fewest re-syncs.

**a. Sync.** `gh pr update-branch <n> --repo linq2db/linq2db`.

- Success → step b.
- `Cannot update PR branch due to conflicts` → resolve locally. Get the file list without a checkout
  first: `git merge-tree --write-tree --name-only origin/master origin/<branch>`. Then create a worktree
  per [`worktree.md`](../../docs/worktree.md) (and **verify the local branch matches `origin/<branch>`
  before working** — check ahead/behind, don't blind-reset), `git merge origin/master`, resolve, commit,
  push. The collisions to expect are in [`pr-and-push.md`](../../docs/pr-and-push.md); for a batch like
  this the additive rule-registry one is the most common by far.
- **Before pushing a resolved merge, run the both-sides check** — intersect
  `git diff --name-only $(git merge-base HEAD origin/master) origin/master` with the same against `HEAD`.
  Anything in that set beyond the files that conflicted auto-merged silently and may not compile; build
  the projects it names locally. This is the step that pays for itself: it is one ~90 s build against a
  full CI round.

**b. Gate.** `& .claude/scripts/wait-pr-checks.ps1 -Pr <n>` with `run_in_background`, then wait for the
completion notification — do not poll its output file. Exit 0 = green, 1 = non-green, 2 = timed out.

On non-green, read the failure before touching anything:
`gh run view --repo linq2db/linq2db --job <job-id> --log-failed`, with the job id from the check's
`detailsUrl`. Fix, verify locally, push, re-gate. Cap re-attempts per
[`agent-rules.md`](../../docs/agent-rules.md) → *Cap same-failure retry loops*.

**c. Merge.** `gh pr merge <n> --repo linq2db/linq2db --squash --admin`, then confirm it actually landed
(`gh pr view <n> --json state,mergeCommit`) — the merge command is often silent on success.

**d. Baselines.** If the PR has one, its PR is a draft and the repo rejects merge commits:

```
gh pr ready <b> --repo linq2db/linq2db.baselines
gh pr merge <b> --repo linq2db/linq2db.baselines --squash
```

Then move to the next PR. Report each PR's outcome as it completes rather than saving a summary for the
end — the run is long and the user needs to see it progressing.

### 3. Verify the milestone is clear

```
gh pr list --repo linq2db/linq2db --search "milestone:<ver>" --state open --json number,title
gh issue list --repo linq2db/linq2db --milestone <ver> --state open --json number,title
gh run list --repo linq2db/linq2db --branch master --limit <count+1> --json headSha,workflowName,conclusion
```

Both lists empty is the success condition. The third call is the honest part of the report: if the run
merged PRs before Azure `build` finished on their heads, say which, and give master's own per-commit
result rather than implying the merged heads were fully verified.

Close by reporting the leftover state the run created: worktrees still on disk, local branches whose
upstream the merge deleted, and any baselines PR left open because its source PR was out of scope.

## Don'ts

- **Do not widen the set.** Merge exactly the milestone's open PRs. A tempting adjacent PR — a sibling
  fix, something the user mentioned earlier, a baselines PR for an out-of-milestone source PR — is not in
  the authorization. Name it and leave it.
- **Do not review inline.** If something about a PR looks wrong, surface it as a one-line note and let
  the user decide whether to pause the run; don't turn the merge into a review walk.
- **Do not bypass a red gate on the strength of the `--admin` authorization.** That authorization was
  about the review requirement. A failed leg needs its own decision.
- **Do not delete the local branches or worktrees the run leaves behind without asking.** Squash-merge
  means `git branch -d` refuses them, and they are the only local handle on the conflict-resolution
  commits.
- **Do not touch a baselines PR whose source PR is still open** — it belongs to live work, and per
  [`agent-rules.md`](../../docs/agent-rules.md) orphaned baselines are never a cleanup task anyway.
