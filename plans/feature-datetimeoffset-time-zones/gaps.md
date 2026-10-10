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
