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

## Round 4 — reviewed HEAD f90bec55c

Plan on branch: yes (Tier M, critic weak on the A-9 delta). Round 3 was igor-tkachev's external review, never
ledgered; its fixes are `A-11`, followed by `A-12`. Dispositions (`A-13`): 13 fixed, MIN027 **withdrawn on
measurement** (the unsized default is 255 in `CREATE TABLE`, not the builder's width; the reviewer read the builder's
`Length is null` arm, which `CreateTable` never reaches), MIN030 rejected, OOS1 left to `/release-notes`. The MIN027 row
below is therefore a false finding, kept for the record: a "default width" claim needs the emitted DDL, not the builder.

### Attribution

- **MIN025** (passkey writes ignore `SchemaVersion`; `DeleteAsync` gates cleanup on it) — GAP-01 — `D-4` / `TO-7` prove
  passkey cleanup at `Version3` only; no `D-n` / `TO-n` names a passkey write below `Version3`, where EF Core ignores
  the entity. `P7`'s `UserOnlyStore.cs:459-609` row listed passkey users without asking which are `SchemaVersion`-gated.
  Second class GAP-05. — G-01 — preventable: yes
- **MIN026** (package validation disabled "until next release", no re-enable step) — GAP-01 — no `D-n` or `deferred:`
  row; `E-0` lists the csproj as unapproved pre-plan surface. — preventable: partly
- **MIN027** (`ClaimValue` 2000 narrower than defaults on SqlCe / HANA / Sybase / DB2; comment rationale false) —
  GAP-02 — unprobed comment claims; `A-10` fixed Informix and passkey `Data` widths without sweeping every string
  column. — G-01 — preventable: yes
- **MIN028** (readme migration example CS0311) — GAP-02 — `A-11` rewrote the migration section; the sample was never
  compiled against the guide's own `ApplicationUser`. — preventable: yes
- **MIN029** (not in master's FPU JIT sweep) — GAP-10 — the `Tests.FpuJit` registry arrived on master after the branch
  base (#6051/#6058); unknowable to the plan, caught only by a master sync. — preventable: partly
- **MIN030** (four store arities untested) — GAP-05 — `TO-7`/`TO-9` cover the new arities only; round-1 MIN007's
  per-entry-point symmetry gap still open. — G-01 — preventable: yes
- **SUG005** (readme omits Access 255 / `ClaimValue` 2000 caps; Firebird reason wrong) — GAP-02 — `A-12`'s *Provider
  support* text written from the pinned set, unprobed. — preventable: yes
- **SUG006** (`DataType.Text` ODBC arm untested) — GAP-05 — `E-13` changed two arms, `LongTextParameter` proves one. —
  G-01 — preventable: yes
- **NIT009**, **NIT010**, **NIT014**, **NIT015**, **NIT016** (stale / incomplete comments, doc typos) — GAP-10 — prose.
  — G-09 — preventable: no
- **NIT011**–**NIT013** (one-line `SelectMany` / call chains in new tests) — GAP-07 — *Test layout* exists; `A-11`'s
  hand sweep covered `cbfc89b15..e3f85ade0` only. — G-09 — preventable: yes

### Aggregate

16 findings: GAP-10 ×6, GAP-02 ×3, GAP-05 ×3, GAP-07 ×3, GAP-01 ×2. No dominant class. Three clusters: an arity /
version / provider arm no `TO-n` must hit (MIN025, MIN030, SUG006); unprobed prose in comments and the readme (MIN027,
MIN028, SUG005); and the test-layout sweep run over one range only (NIT011–013).

### Continuity with rounds 1–2

| Prior finding | Round-4 finding | Through |
|---|---|---|
| round-1 MIN007 (generic contexts untested) | MIN030 | per-entry-point obligation never added; `D-4` multiplied arities |
| round-1 MIN009, round-2 MIN022/MIN023 (unprobed readme) | MIN028, SUG005 | readme passes inside `A-11` / `A-12` |
| round-2 OOS3/OOS4 (string widths) | MIN027 | no `P7` row enumerating every string column × provider cap |
| round-2 CI1 (Access ODBC) | SUG006 | the `A-10` fix tested one of two arms |
| round-1 MIN015 (convention not in front of the author) | NIT011–013 | hand sweep over one range |

Round-2's recommended `plan-critic.md` prose-claim vector did not land; MIN028 and SUG005 are its shape again.

### Recommended durable fixes (route to `/session-reflect` → `plan-rule`)

- GAP-05 ×3 (+ GAP-07) → `work-plan.md` `P8` semantics: code that dispatches on arity, `SchemaVersion` or provider owes
  one obligation per arm, each able to go red when the arm is not hit.
- GAP-02 ×3 → the round-2 `plan-critic.md` vector (probe citation per prose claim), plus: readme code samples compile
  against the guide's own types.
- GAP-01 ×2 + MIN029 → `definition-of-done.md`: before CI on a long-lived branch, merge master and check new shipped
  assemblies against master's registries; a csproj switch disabled "until next release" needs a named release step.

## Round 5 — reviewed HEAD 01d3ff195

Plan on branch: yes (Tier M). The round's delta was merge-only (`01d3ff195`; no PR-owned commit since `afb9ba0e9`).
Dispositions (`A-14`): 9 fixed (`cc4a5dc41`, `48fe1e503`, `0a12ea523`, `4462c00f1`); the Sybase 5461-character
passkey cap **withdrawn on measurement** (ASE caps `nvarchar(n)` by bytes; ASCII JSON of 6228 characters round-tripped)
— the second width claim in two rounds made from the builder rather than a round-trip; the Access memo-prefix probe
found no defect; one dropped (settled by `A-6`); Copilot's net10 PublicAPI threads declined (release task).

### Attribution

- **R5-1** (hand-set `BASELINE_DISABLED` instead of #6061's `[NoBaselines]`) — GAP-10 — #6061 and its sweep of master's sites arrived with merge `01d3ff195`; `P7`'s `linq2db.baselines` row names the retired idiom, and `definition-of-done.md` re-walks the checklist after a merge, not branch code against idioms the merge retired. — — — preventable: partly
- **R5-2** (Oracle `VARCHAR2(n)` byte length; `ORA-12899` on a 256-character non-ASCII name) — GAP-03 — no `P7` row lists, per 256-wide string column × provider, the emitted type and whether its length counts bytes or characters; `A-10` fixed the class for Informix only; the scout width rule asks for a max-length round-trip, not a multi-byte one, and `A-11`'s `UserProfileFields` probe was ASCII. Second class GAP-05. — G-01 — preventable: yes
- **R5-3** (readme omits SQL Server `OUTPUT` vs `UPDATE` trigger) — GAP-02 — unprobed claim from `A-10`; the mechanism is in `ConcurrencyExtensions`' own XML doc; `P12` records no critic run after `A-9`, so the prose-claim vector never reached `A-10`…`A-13`. — — — preventable: yes
- **R5-4** (no unique name indexes; readme named the missing FKs only; + Copilot's four find-then-insert race threads) — GAP-03 — round-1 MAJ002's missing `P7` row again: what EF Core's model declares (`HasIndex(...).IsUnique()`), not its store code; the scout rule landed as an example list without indexes. — — — preventable: yes
- **R5-5** (narrower-column list incomplete: `ClaimType`, `ProviderDisplayName`, Informix / HANA token `Value`) — GAP-03 — the same missing width × provider inventory as R5-2; `A-13` wrote the list from the pinned set. Second class GAP-02. — — — preventable: yes
- **R5-6** (readme: "`UseMappingSchema` does not work at all") — GAP-02 — absolute claim from `A-10` without a probe; the test added in `0a12ea523` is that probe. — — — preventable: yes
- **R5-7** (DI round-trip asserted a type-name prefix; role-path `#else` and `IdentityDataContext` arms untested) — GAP-05 — `TO-9` claims every DI test asserts the resolved types and that CI's net8/net9 legs cover the `#else` arm, true for the user-only path only; `A-9`'s `G-01` ran net10.0 only; the per-arm rule lists arity, schema version and provider, not a TFM `#if` arm. Second class GAP-02. — G-01 — preventable: yes
- **R5-8** (role-membership tests had one user / one role; mutation-confirmed) — GAP-05 — pre-plan port, no `TO-n` for the store filters, so the `separates:` rule had nothing to bind. — G-01 — preventable: partly
- **R5-9** (multi-claim `OrElse` arm unexercised; no claim / delete-cleanup test with a second owner; mutation-confirmed) — GAP-05 — R5-8's shape. — G-01 — preventable: partly
- **R5-12** (`RemoveUserTokenAsync` keyless delete) — not-a-gap: settled in `P11 A-6`; lifted into `P10` with this round.
- **R5-13** (Copilot: net10 `PublicAPI.Unshipped.txt`) — not-a-gap: out-of-plan-scope, `P7` defers it to `/release-publicapi` (`D-4`).

### Aggregate

9 findings: GAP-03 ×3, GAP-05 ×3, GAP-02 ×2, GAP-10 ×1. Two clusters: no EF Core parity inventory (every `HasKey` /
`HasIndex(...).IsUnique()` / `HasMaxLength` / length unit against what `CreateTable` emits per provider), so both the
mapping and the readme's limit lists were written from memory (R5-2, R5-4, R5-5); and tests on pre-plan or `#if`-split
code that no `TO-n` could make fail (R5-7, R5-8, R5-9).

### Continuity with rounds 1–4

| Prior finding | Round-5 finding | Through |
|---|---|---|
| round-1 MAJ002 (cascade FKs) | R5-4 | the scout rule landed as an example list; indexes not in it |
| round-2 OOS3, round-4 MIN027 (string widths) | R5-2, R5-5 | width × provider inventory never built; fourth round on this class |
| round-1 MIN009, round-2 MIN022/MIN023, round-4 MIN028/SUG005 (unprobed readme) | R5-3, R5-5, R5-6 | the prose-claim vector exists but is never run on amendments |
| round-1 MIN014 (DI paths untested) | R5-7 | `TO-9` credited the `#else` arm to CI legs without naming the assertion |
| round-1 MIN013, round-4 MIN030/SUG006 (arms without a test) | R5-8, R5-9 | per-arm / `separates:` rules bind `TO-n` rows only, never pre-plan tests |
| round-4 MIN029 (master sync missed a registry) | R5-1 | DoD re-walk covers checklist items, not idioms a merge retired |
| round-4 MIN027 (width claim withdrawn) | withdrawn Sybase cap | reviewer side: width claims read off the builder, not emitted DDL / a round-trip |

Round-2's recommendation that a review-round fix commit cite an `A-n` written before it did not land; this round's fix
commits were again amended after the fact.

### Review-process note (not a plan gap)

- **R5-PROC** — the round's first pass was briefed on the merge and found nothing; with no PR-owned commits in the round
  delta, the round must be a full review of `merge-base(origin/master, head)..head` plus a check of merge resolutions
  in PR paths, never a review of the merge itself. Fix site: `review-pr/SKILL.md`, round-delta rule.

### Recommended durable fixes (route to `/session-reflect` → `plan-rule`)

- GAP-03 ×3 → `work-plan/SKILL.md` scout brief: an exhaustive pass over the original's model configuration (every
  `HasKey` / `HasIndex(...).IsUnique()` / `HasMaxLength` / FK / concurrency token), one `P7` row each; the width probe
  reads each provider's emitted DDL with its length unit and round-trips a max-length **multi-byte** value; user-facing
  limit lists are derived from that table.
- GAP-05 ×3 → `work-plan.md` per-arm and `separates:` rules: add a TFM `#if` arm as a dispatch axis; a coverage claim
  credited to another CI leg names the assertion that runs there; a review round editing pre-plan code owes a
  `separates:` row (a second owner) per filter it touches.
- GAP-02 ×2 → `work-plan.md` `P11` / `P12`: an amendment changing user-facing prose gets the prose-claim vector over its
  delta before push, recorded in `P12`.

## Round 6 — reviewed HEAD 4462c00f1

Plan on branch: yes (Tier M). The round delta is `01d3ff195..4462c00f1`, which holds round 5's fix commits `cc4a5dc41`,
`48fe1e503`, `0a12ea523` and `4462c00f1`. `A-15` was written before this round's fix commits, the first round in which
round 2's recommendation 2 held. `P9` has no `G-01` / `G-05` row for `A-14` or `A-15`. `A-14`'s local results sit only
in its `P11` prose, and `test-all` 25135 is still recorded as pending. No finding below turns on a skipped gate.

### Attribution

- **MIN031** (readme race paragraph: false EF Core parity, and a duplicate passkey row made `FindUserPasskey*Async` throw) — GAP-03 — `A-6` dropped the passkey table's key on Access / Informix / Firebird 2.5 (`d4713b14e`, `7516dab09`) and traced only the write paths on a keyless entity (`UpdateAsync` via `GetKeys(true)`, and `DeleteAsync`); no `P7` row listed the readers that rely on the dropped key's uniqueness — `SingleOrDefaultAsync` at `UserOnlyStore.cs:597,603`, inside `P7`'s own `(D-4) users of IdentityUserPasskey` row (`UserOnlyStore.cs:459-609`), which asked one question per decision, round-4 MIN025's shape. Second class GAP-02: "as EF Core's stores do" (`0a12ea523`; `A-14` "EF Core parity") was never checked against EF Core's `UserStore.AddToRoleAsync`, which has no existence check; `P12`'s last round is `A-9`, and the amendment-delta critic rule (`work-plan/SKILL.md:293-294`) binds Tier L only and landed after this commit. — — — preventable: yes
- **SUG007** (`ClaimType` left as byte-counted `VARCHAR2` on Oracle) — GAP-03 — `P7` still has no row per string column × provider giving the emitted type and its length unit; `48fe1e503` pinned the columns R5-2 named (`A-14`: name, email, phone, password-hash, security-stamp, `ProviderDisplayName`), yet R5-5 named `ClaimType` in the same round and `0a12ea523` documents its width; the round-5 scout rule (`work-plan/SKILL.md:165`, inventory from the original's model configuration with a multi-byte max-length probe) landed in corpus `805744c` 17 minutes after `48fe1e503` and was never applied back to it — round 2 recorded the same for round 1's Rec 1. — — — preventable: yes
- **NIT017** (one-line `GetRequiredService<…>().ShouldBeOfType<…>()` / `(await …).Succeeded.ShouldBe…()` chains in `IdentityStoreVariantTests.cs`) — GAP-06 — `A-13` embedded `testing.md` → *Test layout* rule 1 with `test-diff-sweep.ps1` as the instrument and reported "every rule-1 chain the sweep found rewritten"; the sweep's pattern `\)\s*\.\s*[A-Z]\w*\s*\(` (`test-diff-sweep.ps1:105,137`) needs `(` straight after the member name, so it never matches a generic method (`.ShouldBeOfType<U>(`) or a property hop (`).Succeeded.ShouldBe(`), and the earlier sites survived `A-13`. Second class GAP-07: `A-14` has no `conventions:` line for `4462c00f1`'s test edits, which added new sites. — G-09 — preventable: yes

### Aggregate

3 findings: GAP-03 ×2, GAP-06 ×1. Both GAP-03s are a fix that covered the instances its finding named and not the class
behind them: `A-6` checked the keyless writes but not the readers that need a unique key; `48fe1e503` pinned R5-2's
columns but not the inventory's. The width rule that would have caught SUG007 already existed, but landed minutes after
the commit and was not re-applied. The change that would have prevented the most findings: a fix amendment takes its
site list from a class enumeration (the `P7` inventory, or every consumer of the invariant it changes), never from the
finding's list of instances.

### Continuity with rounds 1–5

| Prior finding | Round-6 finding | Through |
|---|---|---|
| round-1 MAJ002, round-5 R5-4 (EF model parity: FKs, unique indexes) | MIN031 | R5-4's own fix `0a12ea523`; the readme paragraph repeats an unprobed parity claim |
| round-4 MIN025 (`P7` passkey-users row asked one question) | MIN031 | the same `UserOnlyStore.cs:459-609` row, never re-asked after `A-6` dropped the key |
| round-1 MIN009 … round-5 R5-3/R5-6 (unprobed readme) | MIN031 (second class) | no critic round on `A-10`…`A-14`; the delta-critic rule is Tier L only |
| round-1 MAJ003, round-2 OOS3/OOS4, round-4 MIN027, round-5 R5-2/R5-5 (string widths) | SUG007 | fix `48fe1e503`; a width finding in five of six rounds |
| round-1 MIN015, round-4 NIT011–013 (test layout) | NIT017 | the sweep now exists, but cannot see generic-method or property-hop chains |

Round-5 recommendations: Rec 1 (scout inventory with a multi-byte probe) landed as `work-plan/SKILL.md:165` (`805744c`),
after the fix commits it would have governed. Rec 3 (prose-claim vector on amendment deltas) landed as
`work-plan/SKILL.md:293-294` (`0279bbc`), but only at Tier L, so it does not bind this Tier M plan. Round-2 Rec 2 (`A-n`
written before the fix) held for the first time with `A-15`.

### Recommended durable fixes (route to `/session-reflect` → `plan-rule`)

- GAP-03 (MIN031) → `work-plan/SKILL.md` step 5 scout brief: an edit-point that drops or relaxes a key or unique
  constraint (per provider or overall) gets one `P7` row per consumer of that uniqueness — `Single*` lookups,
  find-then-insert, `Update` / `Delete(entity)` — each with a disposition.
- GAP-03 (SUG007) → `work-plan.md` `P11` semantics: a review-round amendment fixing a per-column or per-provider finding
  names the class and takes its site list from the `P7` inventory; a plan rule landing from a round's ledger is
  re-applied to that round's unpushed fix commits before push.
- GAP-06 (NIT017) → `.claude/scripts/test-diff-sweep.ps1` + `testing.md` *Test layout* rule 1: allow generic arguments
  and property hops between `)` and the next call (e.g. `\)(\s*\.\s*\w+)*\s*\.\s*[A-Z]\w*\s*(<[^()]*>)?\s*\(`), and add
  a do/don't example for `sp.GetRequiredService<T>().ShouldBeOfType<U>()`.
