# Gap ledger — issue/5955-clickhouse-datetime64-coercion (PR #5959)

## Round 1 — reviewed HEAD ee69074134d995debea0041f0d0de9acb56306c0

No work plan exists on this branch; attributed against the absent artifact.

| Finding | Gap | Would-have-carried block | Gate | Preventable |
|---|---|---|---|---|
| BLK001 stale `[ActiveIssue(5955)]` on `IntervalTranslationTests.Difference.cs:230` (arrived via master #5987) | GAP-03 | `P7` row from a grep of `ActiveIssue(5955` across `Tests/`; `P4` "no gate on the fixed issue remains" | G-01 | yes |
| MIN001 SQL Server `datetime` parameter typed `datetime2` beside MAX/COALESCE | GAP-02 | `P5`/`P7` consumer rows for `SuggestColumnDescriptor`; `TO-n` SQL Server probe | — | partly |
| MIN002 set-op literal narrowed across from MAX(dateCol) | GAP-02 | `P7` caller sweep of the `QueryHelper.GetDbDataType` Element arm (`SetOperationBuilder`) | — | partly |
| MIN201 unanchored `ActiveIssue` `ErrorMessage` | GAP-06 | convention rule (`{1}but was`) | — | yes |
| SUG201 `MinMax…` test hand-feeds `SqlArgumentDomain.Element` | GAP-05 | `TO-n` must go through `ForAggregate` | — | yes |
| SUG202 coarse comparison test covers literal path only | GAP-05 | `TO-n` covering literal and parameter paths | — | yes |
| NIT201 "everywhere" remark vs YDB exclusion | GAP-10 | — | — | no |
| OOS Informix `DateTime2` CAST → FRACTION(3) | GAP-03 | `P7` row for sibling provider CAST rendering | — | partly |

### Aggregate

7 of 8 trace to blocks a Tier M plan would have required. Dominant class GAP-03 + GAP-02 (5): shared descriptor / type-inference seams changed without a consumer sweep. Single most useful change: mandatory `P7` consumer sweep for every altered shared helper, plus a grep for the fixed issue id across `Tests/` (would have prevented BLK001).

### Recommended durable fixes (route to `/session-reflect` plan-rule bucket)

- GAP-03/GAP-02 → `work-plan/SKILL.md` scout brief: grep `ActiveIssue(<id>` for the issue being fixed and list each as an un-gate edit-point; for every changed shared helper, list callers and the provider rendering paths it reaches.
- GAP-05 → `plan-critic.md` attack vector: can the `TO-n` go red if the mapping under test is broken, or does it hand-feed the intermediate value / cover one path only?
- GAP-06 → `code-reviewer.md` rubric: `ActiveIssue` `ErrorMessage` uses the anchored `{1}but was` form.
