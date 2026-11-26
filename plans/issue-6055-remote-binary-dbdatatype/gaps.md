# Gap ledger — issue-6055-remote-binary-dbdatatype

## Round 1 — reviewed HEAD 50537142a

- **BLK001** (stale `[ActiveIssue(6055)]` gates from master's #5943 on MathFunctionTests Round29/30/31/34/35) — GAP-03 — P7's `git grep "ActiveIssue(6055"` searched only the branch base, though P1, the P7 YDB-comment row and #6055 all named #5943 as an open PR exercising this bug; secondary GAP-10: four of the five gates were written after approval and reached master on 10-22, after the PR's only CI run, and no CI leg runs YDB — — — preventable: partly
- **MIN001** (new per-issue fixture `Tests/Linq/UserTests/Issue6055Tests.cs`) — GAP-10 — the #6058 ban landed in the corpus (`ed602b5`, 2026-10-17 00:53 +0200) ~13 h after the fixture's last commit; at plan time `test-writer.md` made `UserTests/Issue<N>Tests.cs` the allowed fallback — — — preventable: no
- **NIT001** (one-line chains at `Issue6055Tests.cs:31`, `:97`) — GAP-07 — *Test layout* rule 1 existed (2026-10-12) and `work-plan` step 4 was to embed it for E-3; the approved plan shows no embed; `:97`'s single-call-plus-assertion shape was named only on 10-17 (secondary GAP-10) — — — preventable: partly

Aggregate: no dominant class. Shared cause: the branch sat idle 2026-10-16 → 2026-11-25 (111 commits behind); the #5943 gates and three corpus conventions (per-issue fixture ban, single-call chain clause, `test-diff-sweep.ps1`) landed in that window, and nothing re-checked the branch until review.

### Corpus trace

- BLK001 — `skills/work-plan/SKILL.md:158` greps gates "at the branch base" only; `:342`'s post-merge re-sweep would catch them, but no merge happened before review. Correction: extend `:158` to cross-referenced open PRs and make the gate grep a standing re-check at every master merge. Recurs: `plans/issue-5955-clickhouse-datetime64-coercion/gaps.md` BLK001 (gate via master #5987).
- MIN001 — `scripts/test-diff-sweep.ps1` check 11 (`:293-298`) exempts any file named `Issue*`, so a new per-issue fixture is never flagged. Correction: add a "branch-added `Tests/**/Issue<N>Tests.cs`" hit. Recurs: `plans/issue-5930/gaps.md` MIN007, `plans/issue-5777-support-sqlserver2014-elapsed-time/gaps.md` MIN006.
- NIT001 — the sweep and DoD pre-push sweep arrived after the branch's last push. Correction: `skills/work-plan/SKILL.md:342` — on a master merge also run `test-diff-sweep.ps1 -Ref HEAD` on the branch's own tests and log counts in the merge's `A-n`. Recurs: `plans/feature-4992-select-dynamic/gaps.md` NIT003, `plans/feature-access-libred-dialect/gaps.md` NIT002.
