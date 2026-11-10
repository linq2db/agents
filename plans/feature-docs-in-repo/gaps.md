# Gap ledger: feature-docs-in-repo

## Round 1 — reviewed HEAD 1dd66b19255d724e926688106737281cdc5964c0

## Attribution

- **MAJ001** — GAP-02 — `P4` has no unknown for how a skipped ancestor propagates through `needs` (U-16 asked only how a skip reports to branch protection), and E-8 prescribes the defect verbatim as deploy `if: github.event_name == 'release' || inputs.deploy` with no status function, on top of D-12's `changes` job whose `build` condition also had none; commit `9edc95364` added `!cancelled() && !failure()` to `build` only, so propagation was handled for the direct child and not the grandchild, and A-4 again re-derived `build` alone; G-09 ran and recorded `if:`/needs semantics as OK, so this is not GAP-08; secondary GAP-05, as TO-9 (`deploy=false`, asserts deploy skipped) is green with this bug and TO-10, the only arm that can go red, is post-merge although a same-shape run on the fork (Actions enabled per U-8/E-9) settled it — G-09 — preventable: yes
- **MIN001** — GAP-07 — `docs/github-actions.md:137-148` (*`upload-artifact` silently drops dotfiles*, in the corpus since `4f9ecea`, 2026-09-06, two months before the plan) states this failure and this fix, but `skills/work-plan/SKILL.md` step 4 (`:65-74`) has no trigger for an edit-point under `.github/workflows/` and neither that skill, `work-plan.md`, `plan-critic.md` nor the plan links the doc, so E-8 specified the upload with only `if-no-files-found: error` while E-1 lists `.nojekyll` and D-4 specifies `rsync --delete`; the P7 row for existing workflows searched `include` over `tests*.yml`, which matches `tests.yml:345`, and recorded only the path-filter conclusion; secondary GAP-05, as TO-2 covers only `api/<id>/` and `articles/**` on the local `_site`, and TO-6 recorded the artifact's size but not its file list — G-09 — preventable: yes

## Aggregate

The two findings split evenly, one `GAP-02` and one `GAP-07`, but share one cause: a `.github/workflows/` edit-point gets no design-time treatment. Step 4 does not embed `github-actions.md`, and `plan-critic.md` has no vector mentioning workflows. Both also had evidence that stopped short of the real publish path: TO-2 read the local tree rather than the artifact, and TO-9 exercised only the no-deploy arm. The single change that prevents both is embedding `github-actions.md` at step 4 for workflow edit-points, but it covers MAJ001 only once that doc states the skip-propagation rule. At plan time no such rule existed, and the `e1dec64` section (2026-11-08) covers a failed detection job, not a skipped ancestor's descendants.

## Recommended durable fixes

- GAP-07 × 1, plus GAP-02 × 1 once the next fix lands → the embed list in `.claude/skills/work-plan/SKILL.md` step 4 — when `P6` has an edit-point under `.github/workflows/`, embed `docs/github-actions.md` for the author and the critic.
- GAP-02 × 1 → `.claude/docs/github-actions.md`, *A job gated on a detection job must fail open* — add that a job skipped by event skips every transitive descendant lacking a status function, so each job downstream of a conditional job spells out `!cancelled() && needs.<parent>.result == 'success'`.
- GAP-02 × 1 and secondary GAP-05 × 2 → a new attack vector in `.claude/agents/plan-critic.md` — for a new or changed workflow, require a table of every `on:` event against each job's expected status, and for a publish job a `TO-n` that runs the deploying arm before merge (same-shape workflow on a fork) and checks the artifact the publish step actually consumes.
