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

## Round 3 — reviewed HEAD f8966ef88b6152e0f2dec3f16af0708ebb5a0aa5 (+ uncommitted round-3 fixes)

Round 2 (the external review's MAJ/MIN items, absorbed by `A-5`) was never attributed.

### Attribution

- **R3-01** — GAP-02 — `A-3` made `AsDateTime64` trust `QueryHelper.GetDbDataType(expr, MappingSchema)` with no `P4` row on whether that type is the operand's own; `U-1`(a) already recorded the schema fallback (`Undefined` → `DateTime64(7)`) a disagreeing `COALESCE` falls into. `A-3` superseded `D-1` without a `re-derives:` line. Fix site `ClickHouseExpressionExtensions.cs:25` — G-01 — preventable: yes
- **R3-02** — GAP-05 — `E-13`'s predicate ("a literal beside a computed coarse value") was written into `P6` after the code, with no discriminating input; TO-16 used only `MAX(coarse)`, never a coarse-typed value that reaches no column (a cast to `Date`). Secondary GAP-02 — G-01 — preventable: yes
- **R3-03** — GAP-03 — `E-8` widened `GetColumnDescriptor`'s `Element` arm to the first argument and `E-11` admitted LAG/LEAD; no `P7` row for that helper's consumers, so LAG's default argument was never listed. Round 1's caller-sweep rule (`work-plan/SKILL.md:118`) predated `A-5`, which named the gap in prose without a `P7` row — G-01 — preventable: yes
- **R3-04** — GAP-05 — `E-12` enumerates the stored path's members; `P8` covers CTE columns and set operations separately but not a set operation over one CTE inside another, the only input where a shared visited set reads as recursion. The scoping bug itself is implementation-level — G-01 — preventable: partly
- **R3-05** — GAP-10 — the *Test layout* rule was codified (406f742, 2026-10-12) after every test on the branch was committed (7a786fb87, 2026-10-11) — — — preventable: no
- **R3-06** — GAP-02 — `A-3`'s conditional rule assumes an operand reporting `DateTime64` is one on the server, reversing `P1`; `P7`'s operand-kinds producer sweep was not re-run, missing user-extension results (`Sql.ExtensionAttribute.cs:875`). The `A-5` critic delta named it as an unprobed lead; it reached review instead of a `P10` / `P7 deferred:` row (#6044). Secondary GAP-03 — G-01 — preventable: yes
- **R3-07** — GAP-03 — `E-12` changed the descriptor a comparison value receives, but `P7` never listed the in-list consumers (`ConvertInPredicate`, `ContainsBuilder.cs:163-170`); the `A-5` critic delta named both sites — G-01 — preventable: yes
- **R3-08** — GAP-03 — `E-11`/`E-21` put the value window functions in `Element`; no `P7` row for `E-12`'s parameter rule as a consumer, so `LAG(col) < @p`'s change against master was never listed. TO-14's parameter half was already gated (#5997) and could not go red (secondary GAP-05). Accepted in `P10`; listing it would have moved the decision earlier, not removed the behaviour — G-01 — preventable: partly
- **R3-09** — GAP-07 — `testing.md` → *A narrowed provider set is a claim* requires a measured failure per exclusion, but `work-plan` step 4 embeds only *Test layout*; f4e364c69's unprobed "MySQL DATETIME has no fractional seconds" hid #6049. Secondary GAP-02. Also an `A-5` critic lead — — — preventable: yes
- **R3-10** — GAP-02 — TO-16 gated Sybase as a server limit (`no-issue:`) without a probe, though `E-16` had already shown a Sybase date/datetime mismatch is fixable by a cast; a silent wrong answer, now #6050. No corpus rule limits `no-issue:` to refusals — — — preventable: yes

### Aggregate

Classes: GAP-03 ×3, GAP-02 ×3, GAP-05 ×2, GAP-07 ×1, GAP-10 ×1. One cause: 7 of 10 (R3-01/02/03/04/06/07/08) sit in mechanisms `A-3`/`A-5` introduced, and R3-09/10 in TO-16 gates `A-5` reconciled — none of those amendments re-derived `P4`/`P7`/`P8`, though `work-plan.md`'s amendment rules and `SKILL.md:118` were in force. `-Action validate` did not stop `A-5` (no "supersedes", no new public type; `A-3` predates the error cutoff). The `A-5` critic delta named R3-06/07/09 verbatim and they went to review as unprobed leads. Round 1's caller-sweep recommendation landed; the defect recurred because this plan was never re-walked against it.

### Recommended durable fixes (route to `/session-reflect` plan-rule bucket)

- GAP-03/GAP-02/GAP-05 ×7 → `work-plan.ps1 -Action validate` + `work-plan.md` → *P11 Amendments*: an `A-n` that adds `E-n` rows must carry a `re-derives:` line naming new `P4`/`P7`/`P8` rows — an error regardless of date or wording.
- GAP-03/GAP-02/GAP-07 ×3 → `work-plan.md` → *P12* + `plan-critic.md`: a critic lead marked "reasoned, unprobed" may not be carried to review; it becomes a `TO-n`, a `P7 deferred:` row with a reason, or a `P10` entry, and `validate -Done` fails on an open lead.
- GAP-07/GAP-02 ×2 → `work-plan/SKILL.md` step 4: embed `testing.md` → *A narrowed provider set is a claim* beside *Test layout*; extend `testing.md`'s `no-issue:` rule to refusals and probed server limits only — a gate whose observed failure is a wrong value gets a filed issue.
