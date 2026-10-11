# Gap ledger — `feature/identity-migration` (PR #5640)

## Round 1 — reviewed HEAD db605986c

Plan on branch: yes, but scoped to the three CI failures (plan.md:5-6); the migration itself (stores, readme,
original fixtures) predates it, so findings in that code are attributed against the block a Tier L plan would
have required (the branch adds public API outside `LinqToDB.Internal.*`).

### Attribution

- **MAJ002** (`DeleteAsync` leaves dependents) — GAP-03 — no `P7` mirrored-site row for EF Core's reference store / `IdentityDbContext` model enumerating what EF `DeleteAsync` delegates to the database (`OnDelete(Cascade)` FKs that linq2db `CreateTable` never emits). — preventable: yes
- **MAJ003** (passkey `Data` width) — GAP-02 — the in-code deferral at `DefaultMappings.cs:361-363` assumes only Oracle-style bounded NVARCHAR is affected, unprobed; `U-5` (plan.md:66) read this column and asked only the `DateTimeOffset` question; `A-6` measured per-provider limits on the same entity but did not sweep its other unbounded column. Second class GAP-05 (245-char fixture payload stays under the 255 cap). — preventable: partly
- **MIN004** (Guid keys not generated) — GAP-03 — same missing EF-parity `P7` row; EF generates the client-side Guid for a default PK. Second class GAP-05 (Guid test sets `Id` explicitly). — G-01 — preventable: yes
- **MIN005** (MySQL `LockoutEnd` TIMESTAMP range) — GAP-02 — `SC-2` / the `P7` "Providers not in D-2" row assert MySQL "already renders" `DateTimeOffset`: a DDL-validity check, not a range check; `A-5` noted a DDL-text criterion cannot see a value defect but re-derived only the pinned set. Missing probe: a `DateTimeOffset.MaxValue` round-trip `P4` row. — G-01 — preventable: yes
- **MIN006** (`ConfigureMappings` undocumented) — GAP-08 — the migration's public surface was never walked against `G-03`; CS1591 NoWarn means the build cannot stand in for the gate. — G-03 — preventable: yes
- **MIN007** (generic contexts untested) — GAP-05 — `P6`/`P7` list all five `ConfigureMappings` overrides reaching `SetupIdentityUser`, but `P8` has no per-entry-point symmetry obligation; `d975d4051` later fixed a defect of exactly this shape without adding one. — G-01 — preventable: yes
- **MIN008** (readme "new major version") — GAP-01 — no `D-n` on package version / breaking-change disclosure (6.0.0 → 6.6.0 breaking). — preventable: partly
- **MIN009** (readme remote-context claim) — GAP-02 — no `P4` row probing a remote context for AspNet* mappings. Second class GAP-09 (`db605986c` readme pass removed a parallel claim but left these lines; no `E-n` / `P11`). — preventable: yes
- **MIN010** (navigations vs custom satellites) — GAP-02 — custom satellites probed only through the stores, not through the navigation extension methods. — preventable: yes
- **MIN011** (`RenamedSchemaRoundTrips` cannot fail) — GAP-09 — `IdentityCustomizationTests.cs` is new in `db605986c` with no `E-n` / `P11`; `G-09` still pending. Second class GAP-05. — G-09 — preventable: yes
- **MIN012** (`?.` vacuity on `FindByLoginAsync`) — GAP-09 — as MIN011. — G-09 — preventable: yes
- **MIN013** (YDB delete-conflict vacuity) — GAP-05 — no obligation naming what proves the assertions per provider; `891d11049` fixed the same class for Access without sweeping other providers. Second class GAP-09. — G-01 — preventable: yes
- **MIN014** (DI paths untested) — GAP-05 — no `TO-n` per DI registration path / documented error path. — G-03 — preventable: yes
- **MIN015** (NUnit `Assert` vs Shouldly) — GAP-07 — rule exists in `AGENTS.md`/`testing.md` but wasn't in front of the author while porting; post-plan edits kept writing `Assert.That`. — preventable: yes
- **NIT001–NIT006** (doc-comment copy-paste, leftover comments) — GAP-10 — prose; no design block prevents it; a pre-push review (`G-09`) catches the class. — G-09 — preventable: no

### Aggregate

20 findings: GAP-10 ×6 (prose nits), GAP-02 ×4, GAP-05 ×3, GAP-03 ×2, GAP-09 ×2, GAP-01/GAP-07/GAP-08 ×1. 14 of
20 trace to blocks a Tier L plan would have required. Both majors and two minors (MAJ002, MAJ003, MIN004,
MIN005) share one cause: the port never enumerated what EF Core gets from its framework rather than from the
ported store code — cascade FKs, Guid value generation, per-provider column types incl. length and range. Second
cluster: five findings (MIN007, MIN011–MIN014) are tests that cannot go red or paths with no test; three were
written or edited after the plan existed and outside its `P6`.

### Recommended durable fixes (route to `/session-reflect` → `plan-rule`)

- GAP-02/GAP-03 ×4 → `work-plan/SKILL.md` scout brief: when a branch ports or mirrors an external implementation, one `P7` row per behaviour the original gets from its framework (FK cascades, value generation, provider type mapping), each probed per provider with `CreateTable` DDL plus a max-value / production-sized round-trip.
- GAP-05/GAP-09 ×5 → `definition-of-done.md` `G-09`: on an already-open PR "before the PR opens" never fires; owe the adversarial read on each push that adds or changes a test fixture.
- GAP-09 ×2 (+2 second class) → `work-plan.md` `P6` semantics: a scope-noted plan on a pre-existing branch still authorizes only its `P6`; run `-Reconcile` with `-Base` at the plan's creation commit before each push.

## Round 2 — reviewed HEAD 96bebf54e

Plan on branch: yes (Tier M, CI-failure scoped plus `A-8`/`A-9`). Nine round-1 fix commits landed between `A-8` and `A-9`
with no `P11` entry (`8681b22c1`, `21a4047d5`, `cba3fa2fd`, `b2da6d1ce`, `11e19e88a`, `fed909272`, `f6168723c`,
`b5f042a2a`, `903e83cdc`); only MIN005 → `A-8` was logged.

### Attribution

- **CI1** (Access ODBC `LongText` bound as `SQL_WVARCHAR`) — GAP-02 — "NText also makes the parameter bind as a CLOB" (`DefaultMappings.cs:393-394`, `21a4047d5`) asserted unprobed on the Access ODBC path, reused by `cba3fa2fd`. Second class GAP-09. Defect in `Source/LinqToDB/**`, out of scope under `P3`. — G-01 — preventable: partly
- **CI2** (YDB `Timestamp` overflow) — GAP-03 — `A-8` found the range class and fixed only MySQL; no `P7` row re-checked `SC-2`'s other non-pinned providers (YDB `Timestamp` ends 2105). Second class GAP-02. — G-01 — preventable: yes
- **CI3** (YDB `UserDeleteRemovesPasskeys` ungated) — GAP-09 — test arrived with `8681b22c1`, outside `P6` until `A-9`; `A-7`'s gating never applied. Superseded by OOS1. — G-01 — preventable: yes
- **CI4** (YDB gate over-fired, vacuous conflict assertion) — GAP-05 — no positive control required on the gated engine (`b5f042a2a`). Second class GAP-09. First-triage miss (gate verdicts filtered) is a process miss, not a plan gap. — G-01 — preventable: yes
- **MIN016** (non-atomic dependent delete) — not-a-gap: rejected by the maintainer; record "callers use explicit transactions" in `P10` so round 3 does not re-raise it.
- **MIN017** (duplicate `ConfigureMappings` overrides) — GAP-04 — `D-4` re-shaped the hierarchy without deciding which arity owns the mappings. — preventable: partly
- **MIN018** (`MaxValue` rounds past pinned column max) — GAP-07 — `A-8` narrowed `UserLockout`'s input for every provider, against `bug-investigation.md:451`; the narrowed value hid the overflow, incl. on locally-runnable SqlCe. Second class GAP-02. — G-01 — preventable: yes
- **MIN019** (Firebird `DbType` strings drop `UNICODE_FSS`) — GAP-02 — raw `DbType` strings never compared with `FirebirdSqlBuilder` output; `TO-2`'s DDL instrument existed. Second class GAP-09. — preventable: yes
- **MIN020** (passkeys never worked on Informix) — GAP-02 — `A-6` / `DefaultMappings.cs:383-384` asserted `BYTE` "holds the value fine" without probing comparability; `A-7`'s gate kept the false premise alive while the readme advertised the feature. Second class GAP-07 (gate declared no expected failure, `testing.md:87`). — G-01 — preventable: yes
- **MIN021** (scoped `DataTypeAttribute` outranks user `HasDataType`/`HasLength`) — GAP-02 — `P7` "consumers own their column types" (plan.md:190) contradicted by the plan's own `U-1`. — preventable: yes
- **MIN022** (readme retry semantics) — GAP-02 — unprobed `UserManager` claim (`903e83cdc`). Second class GAP-09. — preventable: yes
- **MIN023** (readme `AddMappingSchema` inheritance) — GAP-02 — same unprobed-readme class as round-1 MIN009, same commit `db605986c`; round-1 fix did not sweep the file. Second class GAP-09. — preventable: yes
- **MIN024** (self-referencing `inheritdoc cref`) — GAP-10 — doc prose; round-1 doc pass missed it. — G-09 — preventable: no
- **SUG003** (no role-update positive control on YDB) — GAP-05 — no `TO-n` requiring a positive control on the gated engine's surviving arm. — G-01 — preventable: yes
- **SUG004** (gates pin no expected failure) — GAP-07 — `testing.md:87` existed since 2026-09-22; gates still added without declarations on 2026-10-11. — G-01 — preventable: yes
- **NIT007**, **NIT008** — GAP-10 — stale prose. — G-09 — preventable: no
- **OOS1** (YDB/ClickHouse stores unusable for writes) — GAP-02 — `P3` anti-goal named the failures "`InsertOrUpdate`/identity-support gaps" and `A-7` gated them without probing mechanisms (affected-rows delete, upsert, joined `DELETE`, identity). Second classes GAP-01, GAP-09. — G-01 — preventable: partly
- **OOS3** (Informix 255-byte name/email) — GAP-03 — width fixes had no `P7` row listing every string column over a provider's `NVARCHAR` cap. — G-01 — preventable: yes
- **OOS4** (passkey `Data` capped on SqlCe/HANA) — GAP-02 — affected set stated without comparing SqlCe 4000 / HANA 5000 to payload size. Second class GAP-09. — G-01 — preventable: yes
- **OOS5** (net10 type hierarchy differs) — GAP-02 — `U-9` reasoned-unprobed and scoped to the non-net10 surface; consumer-visible cast consequence never carried into `E-12`. — G-03 — preventable: yes
- **OOS6** (navigations returned link rows) — GAP-05 — `f6168723c` asserted navigations resolve, not what they return. Second class GAP-09. — G-01 — preventable: partly

### Aggregate

22 findings: GAP-02 ×9, GAP-05 ×3, GAP-10 ×3, GAP-03 ×2, GAP-07 ×2, GAP-04 ×1, GAP-09 ×1, not-a-gap ×1. Dominant class:
a per-provider or behavioural claim written down as fact and never probed — in code comments, the readme, and the
plan's own verdicts. 9 of 22 originate in commits with no `P11` entry, which `-Reconcile` could not have seen because
`A-9`'s file-level `E-n` retroactively authorize every path they touched.

### Continuity with round 1

15 of 22 come from a round-1 finding's own fix or its unswept siblings:

| Round-1 finding | Round-2 findings | Through |
|---|---|---|
| MAJ002 | CI3, OOS1 | fix `8681b22c1` |
| MAJ003 | CI1, MIN019, OOS3, OOS4 | fixes `21a4047d5`, `cba3fa2fd` |
| MIN005 | CI2, MIN018 | `A-8` fixed one provider and narrowed the test input |
| MIN007 | MIN017 | the same `ConfigureMappings` overrides |
| MIN009 | MIN022, MIN023 | same unprobed-readme class; MIN023 from the same commit |
| MIN010 | OOS6 | fix `f6168723c` |
| MIN013 | CI4, SUG003 | fix `b5f042a2a` |
| NIT001–006 | MIN024 | doc pass `b2da6d1ce` |

Round-1 recommendations: Rec 1 (framework-provided behaviours as probed `P7` rows) landed as `fec9550` after the
round-1 fixes it describes and was never applied back to them — CI1, CI2, MIN018, OOS3, OOS4 are that shape. Rec 2
(`G-09` on each push to an open PR) and Rec 3 (`-Reconcile -Base` before each push) did not land; Rec 3 is also too
weak, as file-level reconcile is satisfied retroactively by a later amendment.

### Recommended durable fixes (route to `/session-reflect` → `plan-rule`)

- GAP-02 ×9 → `plan-critic.md` attack vector: enumerate every per-provider / behavioural claim the plan or diff writes as prose (code comment, readme sentence, `P3` reason, `P7` verdict) and require a probe citation or a `U-n` marked reasoned for each.
- GAP-09 (×9 second class) → `work-plan.md` `P11` semantics: a review-round fix commit must cite the `A-n` authorizing it, written before the commit; `-Reconcile` maps commits to amendments, not files to `E-n`.
- GAP-05/GAP-07 ×5 → `work-plan/SKILL.md` convention embed and `P8` semantics: every `[ActiveIssue]` gate is a `TO-n` with a declared `ErrorTypeName`/`ErrorMessage` and a positive control on the gated engine; embed `bug-investigation.md:451` whenever `P8` changes a `[DataSources]` test's input.
