# GitHub Actions

Behaviour of the GitHub Actions side of CI that cost a run to discover. Azure Pipelines specifics live
in [`ci-tests.md`](ci-tests.md); the workflows themselves are `.github/workflows/build.yml` (DB-free
checks, per PR), `tests.yml` (the provider legs) and `tests-comment.yml` (the `/azp run` trigger).

## `build.yml` is a superset of Azure's `build` pipeline — gate on it, don't wait for both

`.github/workflows/build.yml` is a port of `Build/Azure/pipelines/build.yml`, which instantiates
`templates/build-job.yml` with `with_tests: false` / `with_release: false`. On a PR that Azure job runs
exactly six things, and each has a GH leg:

| Azure `build` step | GH leg |
|---|---|
| Build Examples (Debug) | Examples build |
| Run Analyzer Tests | Analyzer tests |
| PublishSingleFile Smoke Test | PublishSingleFile smoke test |
| Build Solution for Nuget (Release) | Build and pack |
| Pack Solution for Nuget | Build and pack |
| third-party notices check + verify | Build and pack |

GH runs **more**: `verify-nuget-sizes.ps1` and `verify-analyzer-delivery.ps1` (Azure has those only in
`nuget-job.yml`, which the `build` pipeline never includes) plus CLI tests on both OSes (Azure's
`test-cli.yml` runs only from `default` / `test-all`). It is also far faster — measured 7–15 min against
Azure's queue, which on the same commits had not started.

So when the gate you need is the DB-free one, wait on the six GH legs (`Build and pack`, `Examples build`,
`Analyzer tests`, `PublishSingleFile smoke test`, `CLI tests (ubuntu-24.04)`, `CLI tests (windows-2025)`)
and ignore `build` / `build (Build)` / `default`. [`wait-pr-checks.ps1`](../scripts/wait-pr-checks.ps1)
does exactly that.

Two things the GH legs do not cover. Azure pins SDKs with `UseDotNet@2` 9.x/10.x while GH uses
`setup-dotnet` + `global.json` `rollForward`, so an SDK-resolution break could differ between them; and the
Azure `default` pipeline is what publishes nugets on a master push, so a break there surfaces post-merge.
Note also that `build` is the **only required** status check on `master` (with `strict: true`), so a merge
that skips it needs `--admin` — see [`pr-and-push.md`](pr-and-push.md) → *A sync push dismisses the
approval it needs*.

`tests [all]` is a commit status posted by the dispatch-only `tests` workflow against a specific head sha,
so it does **not** carry forward when a PR is synced — a uniform `FAILURE` on every open PR is that
workflow's own state, not a per-PR defect, and it disappears from the rollup after the next push.

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

## `${{ … }}` is evaluated everywhere in a workflow file — comments included

The expression parser runs over the **whole file** before anything executes, not just over the
fields you think of as expressions. A `${{ … }}` inside a `run:` block — inside a heredoc, inside a
*comment* in that heredoc — is still parsed, and if it isn't a valid GitHub expression the entire
workflow fails to load.

This bites when a workflow quotes some *other* system's syntax that happens to collide. Azure
Pipelines template conditionals are spelled the same way, so a Python comment reading
`a key literally named '${{ if eq(parameters.full_run, true) }}'` produced:

    HTTP 422: failed to parse workflow: (Line: 105, Col: 14): Unrecognized named-value: 'if'

Two things make it expensive. The file is perfectly valid YAML, so a local `yaml.safe_load` check
passes; and the position reported is the start of the `run:` block scalar, not the offending line.
A push also creates a **synthetic failed run attributed to a `push` trigger the workflow does not
have** — GitHub validates workflow files on push regardless of triggers — so the run list shows a
failure for an event you never configured.

Assemble the literal instead of writing it: `azure_expr = '$' + '{{'`. There is no escape sequence
that helps inside a `run:` body.

## An empty `matrix` fails the run — it is not "no jobs"

`matrix: ${{ fromJSON(needs.prepare.outputs.legs) }}` resolving to `{"include": []}` does **not**
skip the job. It fails the **run**, and it does so invisibly:

- no failed job — `gh run view` lists every job as ✓ or `-`, under a red run;
- no failed check run — `gh api …/check-suites/<id>/check-runs` shows only successes;
- nothing in the annotations.

So the tell is a run whose conclusion is `failure` while everything in it is green, which reads like
a GitHub glitch rather than a configuration error. Gate any dynamically-populated matrix job on its
own list being non-empty (`if: needs.prepare.outputs.any == 'true'`) so it is *skipped* rather than
instantiated with nothing in it. Worth doing for the upstream build job too, or a surface with
nothing to run still pays for it.

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
