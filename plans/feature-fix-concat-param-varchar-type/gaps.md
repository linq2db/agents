# Gap ledger — feature/fix-concat-param-varchar-type (#6186)

## Round 1 — reviewed HEAD 812895b835

No plan on the branch (flag: no-plan). Each finding is attributed to the block a Tier M plan would have had to carry. A Tier M plan applies because the change edits a cross-cutting core lookup, `QueryHelper.GetColumnDescriptor`.

### Attribution

- **MAJ001** — GAP-03 — needed a `P7` caller census of `QueryHelper.GetColumnDescriptor` covering **both** modes, with each caller classified by what it does with the result. The read-path (`forTyping: false`) callers that use the descriptor to *type a value* needed their own rows, with a probe each. Scout question `work-plan/SKILL.md:82` ("Who calls `<symbol>`") run against the PR head returns about 25 callers. About 6 of them feed `UsingColumnDescriptor`/`UsingColumnDescriptorBeside`, including `ContainsBuilder.cs:191`. The PR body names the PR's own split: "The read path (value converters) is unchanged". That is the plan's unverified premise, and it would have been the `P4` row: does every non-`forTyping` caller read only converters? Second class: GAP-02. The body's reach list also shows the routing miss. "`titles.Contains(p.Sku + suffix)`" is the local-collection IN list at `ExpressionBuildVisitor.cs:5577`. The sequence `Select(...).Contains(v)` goes through a different builder, and the text "Contains" made the two look like one site (same shape as `SKILL.md:95`, enumerate by routing). G-02 could not catch it: 0 baselines modified means no existing test reaches this shape, so a gate driven off the missing row had nothing to fail on. — — — preventable: yes
- **SUG001** — GAP-07 — the reuse rule exists as `code-reviewer.md:268` (*Reuse over reinvention*, "`internal` as much as `public`"). Its author-facing twin `code-design.md:341` covers only the nullable-type helpers. No plan meant no step-4 convention baseline to put either in front of the author. The existing spelling was a private `static` local at `SqlExpressionOptimizerVisitor.cs:1470`, so the honest fix was extraction, not reuse. That instance falls outside the rule as written, which is why this is only `partly`. A `P7` same-token sweep for the new predicate's existing spellings (one `git grep "NChar or DataType.NVarChar"`) would have found it. — — — preventable: partly
- **NIT001** — GAP-07 — the rule exists: `testing.md:588`, *Test layout* rule 1. The mechanical detector exists too: `test-diff-sweep.ps1` lists exactly these one-line chains. `definition-of-done.md:11` scopes the author-side sweep to "a planned branch", so with no plan it did not run before push. The only run is the reviewer's, `review-pr/SKILL.md:400`, which is where the finding came from. The overlay's pointer ("read *Test layout* first") did not bind, same as on `grpc-shared-channel` NIT001. — G-01 — preventable: yes

### Aggregate

3 of 3 findings trace to blocks a Tier M plan would have required. The classes are GAP-03 ×1 and GAP-07 ×2. None is GAP-10: all the information existed on master when the change was designed. MAJ001 is the one that matters. The change narrowed one mode of a two-mode lookup and asserted that the other mode's callers were converter-only, without listing them. The single most valuable step would have been a `P7` caller census of `GetColumnDescriptor` classified by use, which a stock scout question already produces. The two GAP-07s share a cause: on a no-plan branch the conventions reach the author only through pointers, and the one mechanical check (`test-diff-sweep.ps1`) is gated on a plan existing.

### Recommended durable fixes

- GAP-03 × 1 → the scout brief in `work-plan/SKILL.md` step 5. Extend the read/write-pair bullet at `:86`: when the change narrows or alters one mode of a shared lookup (a `forTyping`-style flag, a strict/lenient overload pair), census the callers of **every** mode and classify them by what they do with the result. A caller that uses the unchanged mode for the changed purpose gets a `P7` row and a `P4` probe. Name call-site routing, not just call text: sequence `Contains` vs IN-list `Contains`.
- GAP-07 × 1 (NIT001) → `definition-of-done.md:11`. Drop "On a planned branch" from the `test-diff-sweep.ps1` clause in `G-01`, so any branch that edits `Tests/` runs the sweep before push. The DoD walk is plan-independent and the rule exists; only the scoping kept it from running here.
- GAP-07 × 1 (SUG001) → `code-design.md`, beside `:341`. Generalize the author-facing reuse rule past the nullable helpers: before spelling an enum-membership predicate inline (`DataType is A or B or C`), grep for an existing spelling. A private local copy elsewhere is an extraction candidate, which moves to `QueryHelper` beside `IsDecimal`.

## Round 2 — reviewed HEAD cf4421037

No plan on the branch (flag: no-plan). Findings measured on SQL Server 2022, master `965f63450` vs PR head; MIN001 was rejected in the walk (DbType facets are not inferred, `code-design.md:78`) and is kept here only for the attribution.

### Attribution

- **MAJ003** — GAP-03 — needed a `P7` row for `ExpressionBuildVisitor.ConvertInPredicate`: a read-path `QueryHelper.GetColumnDescriptor(expr)` caller that types the IN items, exactly the "caller uses the unchanged mode for the changed purpose" shape at `work-plan/SKILL.md:86`, with one sub-row per item route (captured array → parameter; inline literal / row reference → literal). The rule landed (`38ef4b2`, 2026-10-30 01:41) about 19 hours before the fix round and round 1 already named `:5577`, but the fix round ran without a plan, so the census never ran against it (second class GAP-07). Second class GAP-05: `ConcatInListKeepsUnicode` covers one of the two item routes. — — — preventable: yes
- **MAJ004** — GAP-02 — the `ContainsBuilder` fallback ("read path only when the typing lookup is null") rested on the unchecked premise that a non-null typing result names the column the read path converts through. The PR's own concat arm breaks it: for a mixed concat the typing lookup returns the Unicode operand, the read path the first column. Needed a `P4` row asking whether the two modes can name different columns for one expression, and a `TO-n` at the separating input (converted VarChar + NVarChar). `d8f014c8f` tested single-column shapes only (second class GAP-05). — — — preventable: yes
- **MIN001** (rejected) — GAP-07 — reviewer rule `code-reviewer.md:73` (a guard on `DbDataType.DataType` alone misreads a DbType-only column) conflicts with author-facing `code-design.md:78` (don't parse `DbType`); the maintainer upheld `:78`. — — — preventable: partly

### Aggregate

3 findings, 2 accepted, both residuals of round-1 MAJ001 introduced by the review-fix round rather than the original design. None is GAP-10. The every-mode census rule from round 1 was applied to `/work-plan` but lives only in its scout brief, and a review-fix commit on a no-plan branch never reaches it.

### Recommended durable fixes

- GAP-03 + GAP-02 (MAJ003, MAJ004) → `acting-on-findings.md`, extending the rule at `:13`: a fix that edits a two-mode shared lookup reruns the every-mode caller census (enumerated by route) and adds one test at an input where the modes return different descriptors — whether or not the branch has a plan.
- GAP-07 (MIN001) → reconcile `code-reviewer.md:73` with `code-design.md:78`: a type predicate over `DbDataType` is not a finding for a DbType-only column, since DbType facets are a deferred known gap.

### Continuity

- Round-1 MAJ001 recurs twice (MAJ003, MAJ004). Its recommendation was applied (`work-plan/SKILL.md:86`) and was still the right fix — it did not bind because the round-1 fixes were made outside `/work-plan`. The recommendation was aimed at the plan step; the miss was in the fix step.
