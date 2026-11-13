# Gap ledger — feature/net11-support (#5942)

No work plan on this branch; rows are attributed to the block a Tier L plan would have required.

## Round 1 — reviewed HEAD 8bb42b92f

- **MIN006** (slnx stale script name) — GAP-10 — master renamed the script in #5996 (`91bb4c900`, 2026-10-04), 16 days after the branch's design commits; a master-merge conflict resolution restored the old name. No design-time P7 could list a rename that did not exist; the catch belongs at merge time — — — preventable: no
- **MIN007** (FSharp.EF11 excluded from Testing config) — GAP-03 — P7 needed a mirrored-set row for the EF band pair (each band project and its F# dependency's slnx configuration entries); the EF10 block was copied with no row checking the copy — — — preventable: partly
- **MIN008** (JoinBuilder.cs:33 count-only CanBuildMethod vs .NET 11 tuple-returning 5-arg joins) — GAP-03 — no P7 row for new framework Queryable overloads reaching name-keyed builders; the PR's FullJoin registration made it reachable. Second class GAP-05 (one TO-n per arity arm) — — — preventable: yes
- **MIN009** (MathFunctionTests query side moved to decimal, ROUND(<float>, n) coverage dropped) — GAP-07 — the don't-narrow-the-input rule (bug-investigation.md) existed but nothing put it in front of the author; a P3 anti-goal "absorbing a runtime change edits the expected side only" with characterization TO-n per edited test would have carried it — G-02 — preventable: yes
- **MIN010** (DeltaComparer vacuous on field-mapped LinqDataTypes) — GAP-05 — a new comparer is a check, so one TO-n must go red when it is absent; no obligation exercised it over each model shape (field- vs property-mapped) — G-01 — preventable: yes
- **MIN011** (type-only Sybase gate, DECIMAL row third) — GAP-05 — no TO-n pinned the measured message or recorded red-first per row arm; the specific testing.md rule landed 2026-11-03, after the gate commit, and nothing re-checks existing gates against a new rule — G-01 — preventable: partly
- **MIN012** (SapHanaProviderAdapter ns2.0 asset lost Hana.Net discovery) — GAP-03 — P7 needed the dropped-TFM ns2.0 break inventory, re-derived for the NET8_0_OR_GREATER arm a master merge brought in; second class GAP-06 (the rule is always loaded); the DoD item has no G-nn — — — preventable: yes
- **SUG002** (SumClampedValues ordered ShouldBe became a set comparison) — GAP-07 — same don't-weaken rule, not in front of the author of review-fix ad252ef47; an A-n would have owed a TO-n for the order the test names — G-01 — preventable: yes
- **SUG003** (EF11 EnablePackageValidation=false with no owner) — GAP-08 — definition-of-done.md requires a switch's real lifetime; the item was added after the line was written, and no DoD re-walk fires on corpus additions — G-04 — preventable: yes
- **NIT003** (template lost commented YDB entries) — GAP-10 — an editing slip on non-compiled example content; no design block names commented template lines — — — preventable: no
- **NIT004** (build-job.yml stale Roslyn 4.8 / net8 wording) — GAP-03 — P7 needed a token-sweep row for the dropped TFM and tooling floor across comments and YAML; the "5.6" half was already wrong on master — — — preventable: partly
- **NIT005** (impossible "or when net10.0 is dropped" lifting condition) — GAP-02 — a checkable framework claim written unverified — — — preventable: partly
- **NIT006** (ServerSideOnlyContract "CodeGenerators takes 5.6.0") — GAP-02 — a version written from memory in a review-fix commit; one Grep of Directory.Packages.props disproves it — — — preventable: partly
- **NIT007** (DurationComparisonAnalyzerTests net8.0 / Net80 wording) — GAP-03 — same missing dropped-TFM token-sweep row as NIT004 — — — preventable: partly
- **NOTE-bands** (band properties read empty for in-body TargetFramework / platform TFMs) — GAP-02 — the P5 decision to centralise per-band versions as TFM-conditioned properties had no failure-mode line; evaluating one body-TFM project checks it — — — preventable: yes
- **NOTE-efmysql** (EFTestProviders MySQL filter inert) — GAP-03 — feb0af018 gave EF11 a MySQL package, removing the filter's precondition; a re-derives / P7 row for readers of the EF_MYSQL-absent branch was checkable at that commit — — — preventable: partly

### Aggregate

14 of 16 trace to blocks a Tier L plan would have required; MIN006 and NIT003 are the GAP-10s. Dominant class GAP-03 (×6), all TFM-migration impact-map shapes. A second cluster (MIN009, MIN010, MIN011, SUG002) is one missing decision: absorbing .NET 11 numeric changes in tests. MIN006 and MIN012 entered through master-merge resolutions, SUG002 and NIT006 through earlier review-fix commits.

### Recommended durable fixes (for /session-reflect, not applied)

- work-plan.md P7: a TFM add/drop gets four rows — ref-pack diff of Queryable/Enumerable for every [BuildsMethodCall] name; a dropped-TFM / tooling-floor token sweep over comments and YAML; mirrored band projects' slnx entries; the ns2.0 break inventory re-derived after each master merge.
- testing.md + rubric-tests.md: absorbing a runtime/BCL change edits the expected side only; query-side types, ordering and row coverage stay; a new tolerance comparer ships with a mutation test per model shape.
- pr-and-push.md merge recipes: after resolving, read every hunk of `git diff origin/master -- <conflicted file>` that reverts master's side; on a TFM-dropping branch, inventory master's incoming `#if NET<N>` arms instead of stripping them.
