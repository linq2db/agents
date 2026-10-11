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
