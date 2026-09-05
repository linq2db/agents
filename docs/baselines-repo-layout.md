## linq2db.baselines repository layout

External repository: <https://github.com/linq2db/linq2db.baselines>. Expected local path (relative to this repo's working directory): `../linq2db.baselines`.

### Two kinds of baselines

**SQL baselines** — one folder per test-provider configuration at the repo root:

```
Access.Ace.Odbc/      Access.Ace.OleDb/       Access.Jet.Odbc/    Access.Jet.OleDb/
ClickHouse.Driver/    ClickHouse.MySql/       ClickHouse.Octonica/
DB2/                  Informix.DB2/           DuckDB/
Firebird.2.5/         Firebird.3/             Firebird.4/         Firebird.5/
MariaDB.11/           MariaDB.11.EF8/         MariaDB.11.EF9/
MySql.5.7/            MySql.8.0/              MySqlConnector.5.7[.EF8|.EF9]/     MySqlConnector.8.0[.EF8|.EF9]/
Northwind.SQLite/     Northwind.SQLite.MS/
Oracle.{11,12,18,19,21,23}.Managed/
PostgreSQL.{13,14,15,16,17,18}[.EF8|.EF9|.EF10]/
SQLite.Classic[.MPM|.MPU]/  SQLite.MS[.EF8|.EF9|.EF10|.EF31]/
SapHana.Odbc/         SqlCe/
SqlServer.{2005,2008,2012,2014,2016,2017,2019,2022,2025}[.MS][.EFn]/
SqlServer.{Contained,Northwind,SA}[.MS][.EFn]/
Sybase.Managed/
```

Inside each provider folder, the subpath mirrors the test namespace split by `.`, then a folder per test class, then files named:

```
<full.namespace.path>.<ClassName>.<MethodName>(<Provider>[,<param1>[,<param2>...]]).sql
```

Example: `SqlServer.2022.MS/Tests/Data/DataConnectionTests/Tests.Data.DataConnectionTests.TestDisposeFlagCloning962Test1(SqlServer.2022.MS,False).sql`.

First line of every SQL baseline is the comment: `-- <Provider> <ConfigurationName>`. The SQL follows.

A special `a_CreateData/a_CreateData.CreateDatabase(<Provider>).sql` per provider seeds DB state.

**Metrics baselines** — one folder per TFM at the repo root: `NET100/`, `NET90/`, `NET80/`, `NETFX/`. Files are named `<Provider>.<OS>.Metrics.txt`, e.g. `SqlServer.2022.MS.Unix.Metrics.txt`, `SqlServer.2022.MS.Win32NT.Metrics.txt`. These are plain-text performance-metric captures. Review them as their own group — the cross-provider SQL-distinctions logic does not apply.

### Branch naming

PR baselines live on `baselines/pr_<pr_number>`. Absence of the branch means the PR produced no baseline changes.

**Confirm that absence with `ls-remote`, not with a `fetch` that reports a deletion.** A short-refspec fetch of one of these branches can print a *spurious* `[deleted]` line even though the branch is alive on the remote:

```
$ git -C ../linq2db.baselines fetch origin baselines/pr_5678:refs/remotes/origin/baselines/pr_5678 --force
 - [deleted]         (none)     -> origin/baselines/pr_5678          # ← wrong
$ git -C ../linq2db.baselines ls-remote origin refs/heads/baselines/pr_5678
8fa8049893b1289d6198d860046d2c57cba6a7ae  refs/heads/baselines/pr_5678   # ← branch exists
$ git -C ../linq2db.baselines fetch origin refs/heads/baselines/pr_5678:refs/remotes/origin/baselines/pr_5678 --force
 * [new branch]      baselines/pr_5678 -> origin/baselines/pr_5678    # ← full ref form works
```

Use the **fully-qualified source ref** (`refs/heads/baselines/pr_<n>:refs/remotes/...`) for these fetches, and treat a `[deleted]` report as unproven until `ls-remote` agrees. This matters because the review flow reads a missing branch as "no baseline changes" and skips the whole baselines pass — so a spurious deletion silently routes a review past real baselines. (Surfaced on PR #5678, where the short-refspec fetch reported the branch deleted while it in fact carried 83 added baselines.)

**Never use `FETCH_HEAD` as a diff endpoint — always the tracking ref.** A destination-less `git fetch origin baselines/pr_<n>` updates only `FETCH_HEAD`, so `origin/master...FETCH_HEAD` looks like a working range and is the shape you reach for right after fetching. But `FETCH_HEAD` is rewritten by the **next** fetch of any ref in that clone — including one issued by a helper script (`baselines-pr-scan.ps1` fetches `master`) or by a concurrent session sharing the clone. The range then silently describes a different comparison, with no error: every command keeps succeeding and returns a coherent-looking answer for the wrong pair of commits. Fetch into the tracking ref and diff against that:

```
$ git -C ../linq2db.baselines fetch origin "+refs/heads/baselines/pr_<n>:refs/remotes/origin/baselines/pr_<n>"
$ git -C ../linq2db.baselines diff --name-status origin/master...origin/baselines/pr_<n>
```

The failure is worse than a stale read because the wrong answer is *self-consistent*: file lists, per-file diffs and `show` all agree with each other. The tell is a path that should exist and doesn't — cross-check the changed test names against the PR's own `nameStatus` before trusting any count. (Surfaced on PR #5727: mid-review `FETCH_HEAD` moved from the baselines branch to baselines `master`, and the same `--name-only` command that had correctly reported the PR's 136 `EagerLoadingTests` files then reported 183 `ConcurrencyRefreshTests` files — unrelated baselines that master had gained. Caught only because a sample path 404'd; on the counts alone it would have produced a confidently wrong Baselines section.) The `worktree.md` → *Never base a worktree on `FETCH_HEAD`* rule is the same hazard on the checkout side.

### A baseline file's path carries the provider and nothing else — no TFM, no OS

`<Provider>/Tests/…/<FQN>(<Provider>).sql` is the whole key. One CI job runs the same tests across several
target frameworks (and, historically, several operating systems), and **every one of those legs writes the
same file**, so the committed content is whichever leg finished last. Nothing in the artifact records which
leg won.

Two consequences, and the second is the expensive one:

- Legs can disagree and only one answer survives. A shape produced by a single TFM is indistinguishable in
  the branch from one every TFM produces.
- **When the matrix changes, a baseline can describe SQL no current leg emits.** Trimming a TFM or an OS out
  of a job doesn't rewrite the files that leg wrote; they persist until some surviving leg overwrites them.
  So a delta can show a change that the code no longer produces anywhere — and no amount of local
  reproduction will find it, because the leg that produced it is gone.

The tell is a baselines delta whose shape resists reproduction across every axis you *can* vary. Before
concluding a defect, check whether the matrix moved between the run that wrote the file and now
(`git log --oneline <baseline-commit-date>..origin/master -- Build/`), and re-check the delta after a fresh
run. (Surfaced on #5737: 47 provider baselines showed a duplicated literal column in every `UNION ALL`
branch. It reproduced under no local provider set, concurrency level, configuration, settings node, suite
scope or TFM, and an instrumented CI probe on the PR's own head showed the trace identical to local. The
content came from legs a macOS-drop / TFM-trim commit had removed from the matrix; the next `test-all`
regenerated the delta from 47 net-positive files to zero.)

### A "modified" cluster your PR can't explain — diff against the *pre-collision* baselines-master state

A branch's baselines are recreated on top of whatever baselines master holds at run time, so any *other* PR whose baselines merged in the interim shifts the comparison point. Your branch then shows that PR's files as "modified" — not because it changed them, but because it faithfully reproduced the values master used to have. The cluster looks alarming and unattributable: large, spread across tests the PR never touches, and untouched by any file in the diff.

Settle it by comparing against the **previous** baselines-master state rather than the current one. Find the interim merge (`git -C ../linq2db.baselines log --format="%h %aI %s" -n 12 origin/master -- '<one file from the cluster>'` names the PR in its subject), take the commit *before* it, and diff your branch against that:

```
git -C ../linq2db.baselines diff --name-status <pre-collision-sha>...origin/baselines/pr_<n> --diff-filter=MD
```

Files that vanish from that list are byte-identical to the pre-collision state — i.e. your branch reproduced the historical values and the delta belongs to the other PR. A cluster that *survives* is genuinely yours. Cross-check by confirming the interim PR is among the commits your branch lacks (`git log --oneline origin/pr/<n>..origin/master`), and read its subject: a CI-fixes PR often names the clusters outright.

Two consequences worth reporting. The finding is "not attributable to this PR" with a measurement behind it rather than a plausible story — and the baselines PR itself then carries N files that are *reverts* of the other PR's values, which matters to whoever merges it. Do **not** phrase either as an instruction to sync with master (see [`review-conventions.md`](review-conventions.md) → *Notes vs findings*).

(Surfaced on #5844: 387 modified files across `CharTest2/11/12`, `LeftJoin5`, `CheckField6`, three `MergeTests` and more. All but one were byte-identical to `ae40ecc3b84`, the state before #5864's baselines merged 17 minutes after the branch's own master merge — and #5864's subject named two of the clusters: *"merge-source order, CharTest isolation"*. `LeftJoin5` and `CheckField6` returned literally empty diffs.)

### Merging a baselines PR

`linq2db.baselines` **disallows merge commits** — `gh pr merge --merge` fails with *"Merge commits are not allowed on this repository. (mergePullRequest)"*. Use `gh pr merge <n> --squash` (mark the CI-created draft ready first with `gh pr ready <n>`; `--admin` bypasses any pending check). This comes up when cleaning up a lingering baselines PR whose source linq2db PR has already merged (the baselines PR doesn't auto-close).

### Commit granularity

Baselines commits on `baselines/pr_<n>` are scoped **per CI run per provider** — one commit per `[Linux / Oracle 19c] baselines` run, etc. They are NOT scoped per linq2db PR commit. The commit subject is the CI job name in square brackets, body empty.

Practical implication: the baselines repo can answer "when did this baseline change against master?" but cannot answer "which linq2db PR commit introduced the change?". A runtime bisect against the linq2db source tree (`git worktree` + `git checkout <sha>` per candidate, run `dotnet test` on the affected fixture, capture emitted SQL) gives exact attribution — but **narrow to a commit range first, because the timestamps usually do it for free and often land on a single commit:**

1. **Which run wrote this file.** `git log --format="%h %ad %s" --date=short <branch> -- "<Provider>/…/<Test>(<Provider>).sql"` lists every baselines commit that touched it. Files are only committed when their content changes, so a run that left the file alone produces no entry — the *absence* of a commit for an earlier run is itself the evidence that the SQL was still master's at that point.
2. **Where the run boundaries are.** The branch log is one commit per job, so a run appears as a dense timestamp cluster. `git log --format="%ad %s" --date=format:"%Y-%m-%d %H:%M" <branch>` filtered to a single recurring job name (`Select-String 'SQL Server 2022'`) prints one line per run and reads as the run history directly.
3. **Intersect with the PR's commits.** `git log --format="%h %ad %s" --date=format:"%Y-%m-%d %H:%M" origin/master..HEAD` in the source worktree. The change is in the commits between the last run that left the file alone and the run that rewrote it.

On #5750 that reduced a 68-provider baseline change to the seven commits of one round; reading which of those touched the predicate the SQL depended on picked out the single commit, and no bisect was run.

**A baseline the PR changed and then changed *back* is never reverted on the run branch.** A leg's commit is a delta against whatever its clone is based on, and since [#5819](https://github.com/linq2db/linq2db/pull/5819) that is baselines **master**, not the run branch (`test-workflow-linux.yml` / `test-workflow-windows.yml` → *Checkout test baselines*). So a file whose regenerated content has returned to master's is an *empty* delta: it enters no commit, and the branch keeps the earlier run's version. Re-running CI cannot clear it — every subsequent run produces the same empty delta — so the baselines PR goes on showing SQL the branch no longer emits, until the release-time reset or a hand-written revert on the branch. (A fix is proposed in [#5878](https://github.com/linq2db/linq2db/pull/5878); until it merges, assume this holds.)

Two consequences when reading a baselines PR. **A stale entry looks exactly like a live one**, so before treating an entry as the PR's current output, date it: `git log --format="%h %ad %s" --date=short <branch> -- "<path>"` against the source commit that should have changed it — a last touch predating that commit means the entry is a leftover. And the counterpart entry for a test the PR *adds* is always live, because a file master does not have can never be an empty delta — which is why the two can disagree about the same behaviour on the same branch. (Surfaced on #5725: `GroupByTests.Max11/Max12` for two ClickHouse providers still showed a `CASE`-folded `MAX` three full-suite legs after the fold was removed, while `AggregationTests.MinMaxOverBooleanExpression` — added by that PR, same construct — was corrected on the first run after the fix.)

**Diff the branch against both its merge-base and baselines `master`.** `git merge-base origin/master <branch>` then diff the branch against each. Baselines `master` advances as other PRs' baselines merge, so a change that landed there after the branch forked would otherwise be misread as this PR's. Identical output from both diffs proves no such drift is in play; divergent output tells you which files to exclude before attributing anything.

**Baselines `master` can also be *behind* master's own test code — the drift runs both ways.** The rule above guards against master having moved *forward* past the branch. The inverse happens too, and it reads identically in the diff while pointing at the opposite culprit: a baselines PR merged from a source branch that predates a **test** change rewrites master's baselines back to the older SQL. Master's code and master's baselines then disagree, and the next PR whose branch *does* contain the test change produces the correct current output — which diffs against the regressed master as a large "modified" set that looks like its own churn.

The tell is a modified cluster in test groups the PR has no connection to, where the *PR side* looks more correct than the master side. Confirm by dating the master-side baseline rather than the branch: `git -C ../linq2db.baselines log -1 --format="%h %cI %s" origin/master -- "<path>"` names the baselines PR that last wrote it, and `git merge-base --is-ancestor <test-change-sha> <that PR's source branch>` settles whether that PR could have contained the test change. Report it as master-side drift, and note that merging this PR's baselines PR *corrects* it — do not write it up as a finding on the PR under review. (Surfaced on #5831: 53 of 65 changed files were `TestDataTypes` losing `ORDER BY ID` plus the DB2 `BulkCopy*` cleanup shape, because the baselines PRs for #5764 and #5766 were merged from branches predating #5784. #5831 contains #5784, so its run was right and master's baselines were wrong.)

**`git show` on a baselines commit needs `--format=""`.** The linq2dbot merge commits carry one `* [<job name>] baselines` bullet per provider leg — 40+ lines — so `git show <sha> -- '<path>'` fills the output with the commit message and the diff scrolls off, including under `| head -n`. `git show <sha> --format="" -U2 -- '<path>'` prints the hunks alone. Same for `--stat`.

Second implication: **the branch's tip has no relationship to the PR's tip.** Because commits land only when a CI run completes, the branch reflects whatever source the last *finished* run built — so a push after that run leaves the branch describing SQL the current code no longer emits, with no marker on the branch saying so. Before reading a baselines diff as the PR's output, date it:

```
git -C ../linq2db.baselines log -1 --format="%cI" origin/baselines/pr_<n>     # branch tip
```

and compare against the PR's HEAD commit date. If HEAD is newer and any intervening commit touches SQL generation, the diff is **superseded** — findings drawn from it can be ones those commits already fixed. Defer the pass until the in-flight run finishes rather than reviewing it. Combined with the append-only property above (files are never pruned across runs, so an early run's captures persist forever), this is why a baselines diff needs two independent staleness checks: *is the branch older than HEAD* (this one) and *were these particular files written by a superseded run* (the per-file `log -1` dating in `/review-pr` step 8 rule 4).

### Expected cross-provider variation (ignore these when flagging "unusual distinctions")

Minor differences that are routine and should not be called out:

- Parameter prefixes: `@p1` (SqlServer, Sybase, Access, SqlCe) vs `:p1` (Oracle, PostgreSQL, Firebird, DB2) vs `?` (ODBC/OleDb Access) vs others.
- Identifier quoting: `"x"` (ANSI) vs `` `x` `` (MySQL/MariaDB) vs `[x]` (SqlServer, Sybase, Access) vs unquoted.
- Paging: `TOP` (SqlServer, Sybase), `LIMIT/OFFSET` (PostgreSQL, MySQL, SQLite), `ROWNUM`/`FETCH FIRST N ROWS` (Oracle), etc.
- String literals: `N'...'` (SqlServer nchar) vs `'...'`.
- Boolean rendering: `1`/`0` vs `true`/`false`.
