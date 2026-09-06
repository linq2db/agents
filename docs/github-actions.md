# GitHub Actions

Behaviour of the GitHub Actions side of CI that cost a run to discover. Azure Pipelines specifics live
in [`ci-tests.md`](ci-tests.md); the workflows themselves are `.github/workflows/build.yml` (DB-free
checks, per PR), `tests.yml` (the provider legs) and `tests-comment.yml` (the `/azp run` trigger).

## Which copy of a workflow runs, and against which ref

Three separate questions, and getting them confused wastes a full run.

| Trigger | Workflow file comes from | Code under test |
|---|---|---|
| `workflow_dispatch` | the **dispatched ref** | `inputs.ref`, else the dispatched ref |
| `issue_comment` | the **default branch**, always | whatever the jobs check out |
| `workflow_call` (`uses: ./…`) | the **caller's commit** | the caller's inputs |

Consequences:

- **`workflow_dispatch` needs the workflow on the default branch to be addressable at all.** Before it
  is merged, `gh workflow run tests.yml --ref <branch>` fails with
  `HTTP 404: workflow tests.yml not found on the default branch`. Once it exists there, `--ref <branch>`
  runs **that branch's version** — verified by dispatching with an input that exists only on the branch
  and getting `204` where the default branch's definition would have rejected it as unexpected. That is
  the way to test a workflow change before merging it.
- **`issue_comment` always runs the default branch's copy**, so a PR cannot alter its own trigger (a
  useful security property) and changes to the trigger only take effect once merged. A local
  `uses: ./.github/workflows/x.yml` resolves from that same commit, so the *called* workflow is the
  default branch's too — only the checkout inside it follows the ref you pass.
- **`workflow_dispatch` takes only a branch or tag.** A pull ref is rejected —
  `422 No ref found for: refs/pull/<n>/head` — even though `git ls-remote` shows the ref exists, so it
  is the endpoint refusing the *kind*. Fork PRs therefore cannot be dispatched. A workflow *called*
  from an `issue_comment` handler can, because the ref is an ordinary input and `actions/checkout`
  fetches `refs/pull/<n>/merge` happily.
- **An `issue_comment` run is not attached to the PR.** It is associated with the default branch's
  commit, so GitHub has nothing to hang a check on and the run appears only in the Actions tab. To
  surface it, post a commit status against the PR's head sha (`POST /repos/{o}/{r}/statuses/{sha}`);
  a PR renders its head commit's statuses in the checks list.

## `upload-artifact` silently drops dotfiles

`actions/upload-artifact` v4+ excludes hidden files by default, **with no warning in the log**. This
repo stages `.runsettings` beside each test app, so without `include-hidden-files: true` every leg
downloads an artifact missing it and the test host refuses to start:

    Option '--settings' has invalid arguments:
    runsettings file './net8.0/efcore/x64/.runsettings' does not exist

The build job stays green while producing unusable artifacts, and the failure surfaces one job later
as MTP exit code **5** ("zero tests ran"). Set `include-hidden-files: true` on any upload whose payload
might contain a dotfile.

## Token permissions actually required

Checked against GitHub's REST metadata rather than assumed — the three used here differ, and
`pull-requests: write` does not imply the others:

| Call | Accepted permissions |
|---|---|
| `POST /repos/{o}/{r}/issues/{n}/comments` | `issues: write` **or** `pull-requests: write` |
| `POST /repos/{o}/{r}/issues/comments/{id}/reactions` | `issues: write` **only** |
| `POST /repos/{o}/{r}/statuses/{sha}` | `statuses: write` |

A reaction on a PR comment therefore needs `issues: write` even though the comment it reacts to was
posted with `pull-requests: write`.

## `pwsh -Command` loses a script's exit code

`pwsh -NoProfile -Command "& 'x.ps1'"` collapses a non-zero exit code from the called script to **1**;
`pwsh -NoProfile -File x.ps1` propagates it faithfully. GitHub's `shell: pwsh` uses the `-Command`
form (it dot-sources the step script), so a script's documented exit codes are not distinguishable
from a step result — `report-trx.ps1` exits 2 for "no results" and 1 for "tests failed", and both read
as 1 in the step. Azure's `PowerShell@2` with `filePath:` runs it as a file and preserves the code.

Test harnesses that assert on a script's specific exit code must invoke it with `-File`, or they are
measuring the harness rather than the script.

## `gh` output captured in PowerShell is a string array

`$body = gh pr view <n> --json body --jq '.body'` yields a **string array**, one element per line — so
`-split` applies per element and `[0]` is the first *line*, not the first section. This silently
deleted two sections of a PR body that then had to be rebuilt. Join first (`-join "\n"`), or better,
round-trip through a file: `gh … | Set-Content <path>` then edit the file.
