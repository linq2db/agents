---
name: split-pr
description: Split ready-to-ship work out of a large in-flight PR into its own PR off master, so it can be reviewed, CI'd and merged independently — or, in stacked mode, split a PR's dependent fixes into a GitHub stack of PRs on top of it. Use when the user says "split into dependent/stacked/chained PRs", or when the user says "split this out", "copy X to a separate PR", "reduce the PR surface", or when a long-lived feature branch has accumulated fixes that don't depend on the feature.
---

# /split-pr

A long-lived feature branch accumulates fixes that have nothing to do with the feature: a test-hygiene fix
found while debugging, a CI change, an attribute the feature needs but that stands on its own. Each one
inflates the PR's diff, delays the fix, and entangles its review with the feature's.

This skill lifts such a change onto its own branch off `origin/master` and opens a draft PR for it. The
originating branch keeps its copy — deconflicting happens later, on the next merge from master, and is
usually trivial because the content is identical.

**Why it's worth doing beyond diff size:** a change on its own branch can be CI'd in isolation. On a
feature branch whose own CI is red or slow, a small fix's signal is unreadable.

## When to use

- The user asks to split something out, or to reduce a PR's change surface.
- You are about to add an unrelated fix to a branch whose PR is already large.
- A fix on a feature branch is ready to ship while the feature is not — most often a **separable** fix per
  [`AGENTS.md`](../../AGENTS.md) → *A distinct shared-engine fix discovered mid-task gets its own branch/PR*.

Don't use it for a **tightly-coupled** enabling change — one with no observable effect without the
originating work. That stays put, and splitting it needs an explicit request.

## Steps

### 1. Establish what is actually separable

Read the candidate's diff on the feature branch. It qualifies when it stands alone: it compiles, it means
something without the feature, and its tests pass without the feature's code. If it depends on a type,
option or test helper the feature introduces, stop and say so — that's the coupled case above.

Ask the user which parts to take when the candidate spans several commits or mixes concerns (a fix plus its
temporary diagnostics, say — the diagnostics usually stay behind).

### 2. Branch off master, in a worktree

```
git fetch origin master
git worktree add -b <type>/<slug> <worktrees-root>/<slug> origin/master
```

Naming follows [`agent-rules.md`](../../docs/agent-rules.md) → *Creating a new branch*. Never branch from the
feature branch — the point is to carry none of its history.

### 3. Move the change

**Cherry-pick** when the change is already an isolated commit on the feature branch (`git cherry-pick <sha>`)
— it keeps authorship and message. Expect it to apply cleanly if the touched files haven't diverged.

**Take whole files** when the split is defined by a *file list* rather than by commits — a long-lived branch's
changes are usually smeared across dozens of commits, so cherry-picking is the wrong unit. Per file, diff it
against master first (`git diff origin/master <feature-branch> -- <path>`) and sort it into one of two piles:

- **only the wanted change** → `git checkout <feature-branch> -- <paths>`, which copies *and* stages it. Batch
  the whole pile in one call, then `git commit -F- -- <pathspec>` per logical change; the files for the later
  commits stay staged meanwhile (which is exactly why an amend here needs `--only`, see
  [`agent-rules.md`](../../docs/agent-rules.md) → *Git commit rules*).
- **wanted and unwanted deltas in the same file** (a metrics removal plus a temporary CI toggle; a refactor
  plus a matrix field the split doesn't carry) → hand-apply, and re-check the file afterwards for references
  to anything left behind. Splitting a large file this way is easier as *copy the branch's version, then
  remove what shouldn't travel* than as a from-scratch re-application — a `${{ each }}` loop or similar is
  hard to retype faithfully. Park the removed block in a scratch file under `.build/.agents/` if a later
  commit in the same PR re-adds it.

**Adapt the prose, not just the code.** A comment or commit message copied from the feature branch often
justifies itself with that branch's premises ("jobs now bundle several providers", "under a full parallel
run's contention"). On master those clauses are false. Rewrite them to the reason that holds without the
feature, or the split PR ships a claim its own diff doesn't support.

**Re-apply by hand** when the commit also contains things that shouldn't travel (temporary diagnostics,
feature-coupled edits), or when the feature branch's version of the file has drifted far from master's. Read
master's copy of each file first: line numbers and surrounding code differ, and the fix may need adjusting
to master's shape.

### 4. Build, then commit

Build the affected project. A cherry-pick that merges cleanly can still fail to compile on master, which is
exactly the risk the split is meant to expose.

Commit with the standard rules ([`agent-rules.md`](../../docs/agent-rules.md) → *Git commit rules*). Separate
commits per logical change — reviewers of a split PR are seeing this work for the first time, without the
originating discussion, so the message carries the evidence: what failed, where it was observed, what the
fix does.

### 5. Open the draft PR

Per [`AGENTS.md`](../../AGENTS.md) → *Pull requests*: `--draft`, `--assignee @me`, confirmed title and body,
`Fixes #<n>` when an issue exists. Milestone: reuse the linked issue's; if it has none, **ask** — don't
assume the feature PR's.

The body should state that it's split out of the originating PR and why it stands alone, then the evidence.
Reviewers need the causal story that lived in the other PR's discussion.

### 6. Tell the user what it means for the originating PR

Say plainly: the feature branch still contains this change, so the next `git merge origin/master` will meet
it. Identical content merges cleanly; where it doesn't, master's side wins. Name the commits on the feature
branch that are now redundant, so they can be dropped when that PR is next tidied.

Choose CI for the new PR by its content, not habit — a provider-scoped fix wants that provider's pipeline,
not `test-all` ([`ci-tests.md`](../../docs/ci-tests.md)).

## Stacked mode — fixes that depend on the PR's own change

Steps 1–6 assume the split change stands alone on master. When a PR carries several fixes that **depend**
on its main change (typically defects its new tests surfaced), split it into a GitHub stack instead: the
originating PR keeps only the main fix, and each discovered fix becomes a PR based on the one below it.
(#6003 → #6006 → #6007 → #6008.)

1. **Propose the split first** — one table row per layer (fix, code files, tests) and the stack order; wait
   for approval.
2. **No force-push.** On the originating branch, add one commit that moves the discovered fixes out:
   restore their source files to the merge base (`git checkout <merge-base> -- <paths>`), drop their tests
   and their `PublicAPI.Unshipped.txt` lines. Build, and check `git diff --stat origin/master...HEAD`
   shows only the main fix.
3. **Build each layer from the original head** — `git switch -c <child>` on top of the layer below, then
   `git checkout <original-head-sha> -- <that fix's files>` and re-add its tests. A GitHub stack is linear,
   so independent fixes still go one above the other. The top layer's tree must equal the original head's
   (`git diff --stat <original-head-sha>` empty, bar intentional additions).
4. **Close the old baselines PR** with its branch (`gh pr close <n> --repo linq2db/linq2db.baselines
   --delete-branch`) — CI regenerates per layer.
5. **Push all branches, then open each PR** with `--base <the layer below's branch>`; reference the parent
   PR number in each body and rewrite the originating PR's body to the main fix plus a *Stack* list. Check
   each PR's diff shape (`gh pr view <n> --json files,commits`). The user links the stack in the GitHub UI —
   don't install `gh-stack`.
6. **Gate from evidence, not prediction.** Run `test-all` on the originating PR; the tests that fail without
   a child's fix get `[ActiveIssue]` citing the **child PR number** (no tracking issue needed), scoped to the
   failing providers. Merge the gate commit up the stack; each child removes its own gates.
7. **Children's `test-all` runs only after the parent's `baselines/pr_<n>` branch exists**, so their
   baselines build on it rather than on master (`Build/CI/baselines-base.ps1`).
8. **Syncing with master** goes bottom-up: merge `origin/master` into the base layer, then merge each layer
   into the one above. Expect `PublicAPI.Unshipped.txt` conflicts at every layer that touches it — resolve as
   the sorted union.

## Don'ts

- Don't branch from the feature branch (stacked mode excepted — there each layer sits on the one below).
- Don't carry temporary diagnostics or scaffolding into the split PR unless asked — they belong to the
  investigation, not the fix.
- Don't remove the change from the originating branch as part of this skill. That branch may need it to stay
  green, and dropping commits from a pushed branch is the user's call. Stacked mode is the exception: there
  the user asked for the split, and the move-out is a new commit, not dropped history.
- Don't split a tightly-coupled enabling change, and don't offer to, without an explicit request.
- Don't assume the milestone.
