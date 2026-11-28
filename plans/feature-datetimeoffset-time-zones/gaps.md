# Gap ledger — feature/datetimeoffset-time-zones (PR #5913)

## Round 1 — reviewed HEAD ba1c9299e

No plan in the corpus for this branch (commits 5defc29 / 6f90e1e cite an out-of-corpus plan). Each finding is attributed to the block it would have needed.

### Attribution

- **BLK-1** — GAP-07 — `P3` anti-goal "public contract outside `LinqToDB.Internal.*` preserved; 6.6.0 is minor" + `P7` row for `TranslationProviderFlags`' shipped 7-param ctor with `D-n` "keep the shipped overload" (#5750 precedent). Rule exists in `code-design.md` / `api-surface-classification.md` step 3; nothing put it in front of the author. — G-04 / G-03 — preventable: yes
- **MAJ-2** — GAP-02 — `P4` row "re-attaching a named zone after a shift reproduces `DateTimeOffset.AddX`'s kept offset", probed with a DST-crossing input; the remark at `DateFunctionsTranslatorBase.cs:1686` ("is exact") went unprobed and the fixture chose non-discriminating dates. Secondary GAP-05 (no `TO-n` naming the separating input). — G-01 — preventable: yes
- **MAJ-3** — GAP-03 — `P7` row enumerating every entry into Oracle `FROM_TZ` lowering keyed by operand storage type; 32a6d5e knew DATE→FROM_TZ raises ORA-00932 and fixed only the ADD_MONTHS path, f9507ac added the ctor entry without re-mapping. Also `P3` "shapes master evaluated client-side keep working". — G-01 — preventable: yes
- **MAJ-4** — GAP-03 — `P7` row treating frame/unframe as a mirrored pair; 3a62684 added the non-DTO skip to `DateTimeOffsetFrame` only. Secondary GAP-05 (`P8` symmetry guard). — G-01 — preventable: yes
- **MAJ-5** — GAP-02 — `P4` per consumer of `CanLowerTimeZoneConversion(AttachZone)`; enabled on PG/DuckDB for the internal UTC re-entry, never probed through user-facing `Sql.AtTimeZone(DateTime?, zone)` materialisation. Secondary GAP-05 (instant-only equality). — G-01 — preventable: yes
- **MIN-6** — GAP-02 — `P4` row "Oracle `CAST(x AS timestamp)` preserves fractional precision" (it is TIMESTAMP(6)); #5987's `timestamp(7)` precedent postdates the merge base, so only a probe would have found it. — G-01 — preventable: partly
- **MIN-7** — GAP-01 — refusal contract not restated with its measured limitation (cb3655d measured the comparison path drops the name; the doc still claims "by name"); ICU wording is prose drift. — — preventable: partly
- **MIN-8** — GAP-05 — `P8` capability-class × refusal-message matrix missed the no-zone-support class (SQLite/MySQL/ClickHouse/YDB). — G-01 — preventable: partly
- **MIN-9** — GAP-09 — `P3` anti-goal "plain-DateTime SQL / non-target providers unchanged" + `P11` amendment when 32a6d5e (Oracle plain DateTime month arithmetic) and f9507ac (SQL Server ctor) crossed it. — G-02 — preventable: yes
- **MIN-10** — GAP-05 — one `TO-n` per fix and per wire shape (DatePart(Week), ClickHouse UTC literal via `session_timezone`, LinqService for the new node's bound/demoted zone). — G-01 — preventable: partly
- **SUG-11** — GAP-07 — `UsingColumnDescriptor(null)` convention (21 sibling sites) not put in front of the author. — G-09 — preventable: partly
- **SUG-12** — GAP-03 — per-storage-type row for Oracle ADD_MONTHS (DATE arm recognised in 32a6d5e, never split). — G-02 — preventable: partly
- **NIT-13** — GAP-09 — comment at `DateFunctionsTranslatorBase.cs:1767` written against the deferred DuckDB UtcNow state; 444f4cd pulled the fix in without a `re-derives:` amendment. — — preventable: partly

### Aggregate

13/13 trace to blocks a Tier L plan would have required; no honest GAP-10. Spread: GAP-03 ×3, GAP-02 ×3, GAP-05 ×2, GAP-07 ×2, GAP-09 ×2, GAP-01 ×1. Cross-class shape: operand **mapped storage type ≠ CLR default** (Oracle DATE behind DateTime, DTO mapped to DateTime2, TIMESTAMP(9) behind a TIMESTAMP(6) cast) probed through one entry/direction only — MAJ-3, MAJ-4, MIN-6, SUG-12. Second cluster: "is exact" / "can lower" claims accepted without a discriminating probe or per-consumer probe — MAJ-2, MAJ-5.

### Recommended durable fixes

- GAP-03 ×3 + GAP-02 ×1 (MAJ-3, MAJ-4, SUG-12, MIN-6) → `work-plan/SKILL.md` step 5 scout brief: for a translator/lowering edit, enumerate each operand's mapped storage `DataType` variants per provider and route each through every entry into the lowering and both directions of any frame/unframe pair.
- GAP-02 ×2 (MAJ-2, MAJ-5) → `plan-critic.md` attack vector: any "is exact / identity / round-trips" claim needs a `P4` probe with an arm-separating input (DST crossing; offset asserted apart from instant); a capability flag read by internal plumbing and user-facing materialisation needs a probe per consumer.
- GAP-07 ×1 + GAP-09 ×1 (BLK-1, MIN-9) → `work-plan.md` `P3` semantics: on a non-major milestone list every non-`Internal.*` type in the edit set as "signature preserved; keep the shipped overload"; every PR-body "unchanged" claim becomes a `P3` row G-02 checks against moved baselines, with a `P11` entry when a commit crosses it.

## Round 2 — reviewed HEAD b56fdc828

Review passes were briefed without the plan (reviewer's local corpus 53 commits stale); no surviving finding contests a P10 entry. One probe was spent on a shape P10-12 already adjudicated (dropped).

- **MAJ006** (`OffsetInMinutes` / `InstantFromOperand` lack the storage guard) — GAP-03 — P7 rows cover only the frame/unframe pair; no row for the DateTimeOffset member handlers that translate the operand without framing it (DFTB:2052, :1823 → `.Offset`, `TotalOffsetMinutes`, `ToUniversalTime`, `ToOffset`, `.UtcDateTime`); D-10/E-9 edited the `.Offset` path without the guard; TO-6 shifts only — G-01 — preventable: yes
- **MIN009** (Oracle `DateTimeOffset.TimeOfDay` drops the fraction) — GAP-03 — A-8's P7 row keyed the class on "the TIME cast does not yield a time" and dispositioned Oracle as "own truncation override" unprobed; A-8's "master has the same delegation" is false (master DFTB:1978-1984 is a bare CAST, ORA-50031); TO-11/TO-38 use whole-second values — G-01 — preventable: yes
- **MIN010** (`InstantMembersAgreeWithTheRoundTrip` compares instants only) — GAP-05 — no TO-n asserts the offset ToOffset/ToUniversalTime produce on the SupportsDateTimeOffsetContext set; the only test reaching it there asserts DateTimeOffset equality — G-01 — preventable: partly
- **SUG003** (`TryGetZoneOffset` formats hours:minutes only) — GAP-01 — P3 states CLR agreement for values only; no block names the CLR's exception domain (non-whole-minute, beyond ±14 h); TO-20/P-h used whole-minute offsets — G-01 — preventable: partly
- **SUG004** (`MachineZoneMembersStayClientSide` ToLocalTime compares instants) — GAP-05 — same assertion idiom as MIN010; no TO-n asserts the local offset — G-01 — preventable: partly
- **SUG005** (no test reaches the AtTimeZone refusal on SQL Server 2005–2014) — GAP-05 — TO-17 lists the no-zone class by provider family; U-5 already showed only SQL Server 2016+ overrides CanLowerTimeZoneConversion — G-01 — preventable: yes
- **SUG006** (`Sql.AtTimeZone(DateTime?)` remarks omit the identity component read) — GAP-01 — U-25/A-7 measured the identity read without zone support, but A-7's `re-derives:` omits the XML-doc edit-point E-17 — — — preventable: partly
- **SUG007** (ClickHouse UTC formats derived by Insert) — GAP-10 — the human reviewer's preference for constant literals; no corpus rule states it and the code comment records the opposite choice — — — preventable: no
- **NIT002** (~58 one-line chains in TimeZoneFunctionsTests.cs) — GAP-08 — A-8's `conventions:` sweep reported 57 chains + 1 nested and set them aside as predating A-8, against definition-of-done.md:11; earlier G-01 sweeps used `-Base HEAD` — G-01 — preventable: yes

### Aggregate

9 findings: GAP-05 ×3, GAP-03 ×2, GAP-01 ×2, GAP-08 ×1, GAP-10 ×1. The common shape: a sibling sweep keyed on the wrong property — MAJ006 on the frame/unframe pair instead of "reads a DateTimeOffset whose storage may lack an offset", MIN009 on "the cast drops the time" instead of "loses what the CLR keeps", SUG005 on provider family instead of the flag's per-version answer. Second cluster: DateTimeOffset equality asserts the instant only (MIN010, SUG004), second round running.

### Recommended durable fixes

1. `skills/work-plan/SKILL.md` step 5 scout brief (widen :321 from amendments to any D-n/A-n): a storage-type guard added to one reader lists every handler for the operand's CLR type that bypasses the guarded helper; a base body switched to a virtual call lists each override it now reaches, probed at the CLR type's full resolution; a refusal TO-n takes its providers from the flag's per-version answer.
2. `docs/testing.md` assertion rules (+ `test-review-checklist.md` beside :76): `ShouldBe` on a DateTimeOffset compares the instant only — a claim about the offset asserts `.Offset` on its own line or uses `EqualsExact`.
3. `scripts/work-plan.ps1 -Action validate` (:624-634): fail when the latest G-01/`conventions:` sweep record has a nonzero count without a fixed / named-review-item disposition; SKILL.md:322 quotes definition-of-done.md:11's no-waiver clause.

### Continuity with round 1

- Recurs, next ring out: MAJ-4 → MAJ006 (same `DataType.DateTime2` storage shape; round 2 mirrored the pair and missed the bypassing readers; round-1 recommendation #1 never landed in SKILL.md); MIN-6 → MIN009 (Oracle sub-second precision, now via TO_CHAR); MIN-8 → SUG005 (no-zone class member missed again); MAJ-5 second class → MIN010, SUG004.
- Did not recur: BLK-1, MAJ-2 (round-1 recommendation #2 landed at plan-critic.md:87 and was followed), MAJ-3, MIN-7, MIN-9, MIN-10, SUG-11, SUG-12, NIT-13.
- New class: the CLR exception domain (SUG003). Waived sweep hits (NIT002) recur across plans (feature-query-batches NIT006, feature-1553-fsharp-codegen NIT205–NIT209).

## Round 3 — reviewed HEAD 9687f8493

A verify round, plus one pass over A-9's offset-less walk. Every round-2 finding is fixed except NIT002 (partly, NIT003). SUG007 was withdrawn after the author's drift argument. One candidate, the walk treating `MAX` / window value functions / scalar subqueries as leaves, was dropped: a probe on four providers found no wrong answer. Attributed by the reviewing session, not by a separate attributor run.

- **MIN011** (a mixed-offset CASE / set operation whose offset-less value comes first is read with no frame) — GAP-05 — critic round 8 objection 3 ("computed producers typed from one operand") was accepted, but TO-51's cells and U-33/U-34 measured only the `Dto`-first order; `CarriesOffset` returns at DFTB:1875 on the inferred type before the walk runs, so the swapped order (`QueryHelper.cs:963-982` types a CASE from its first result) was never reached. Secondary GAP-03: the entry gate is keyed on the inferred `DbDataType` instead of the CLR type, the round-2 "wrong property" shape. Red test 8135dd9ad (Oracle wrong in any zone; DuckDB / PostgreSQL off UTC); pre-existing on master for this spelling — G-01 — preventable: yes
- **NIT003** (one nested one-line chain left at TimeZoneFunctionsTests.cs:631) — GAP-08 — the round-2 fix's sweep ran over the delta only, and :631 predated it; the author's reply quoted the delta sweep as covering the whole fixture — G-01 — preventable: yes

### Aggregate

2 findings: GAP-05 ×1, GAP-08 ×1. MIN011 is the round-1/round-2 class again. An objection is accepted, and then its measurement covers one shape of the input class: one operand order, as before one storage type and one direction.

### Recommended durable fixes

1. `agents/plan-critic.md` / `docs/work-plan.md`: when an objection says a value is "typed from one operand" (or from one branch, one query), the reconciling `TO-n` must carry every operand order as a cell, not only the order that showed the defect.
2. `skills/work-plan/SKILL.md` G-01 sweep record: a fix for a sweep finding reruns the sweep over the whole file (`-Base` = merge base), not over the fix's own delta.

### Continuity with rounds 1–2

- Recurs: round-2's "sweep keyed on the wrong property" → MIN011 (entry gate on the inferred type); NIT002 → NIT003 (delta-only sweep, round-2 recommendation #3 not landed).
- Did not recur: MAJ006, MIN009, MIN010, SUG003–SUG006 (all fixed in 9687f8493, red tests ungated).
