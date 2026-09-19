# Adding a new provider (or a new transport for an existing one)

Traps that surface when linq2db grows a **new** data provider — a new database, or a new ADO.NET
transport under a database it already supports. Sibling of
[`adding-provider-version.md`](adding-provider-version.md), which covers adding a *version anchor* to
a provider that already exists; the failure modes are different, so check both when the work is
"Access gains a third driver" rather than "PostgreSQL gains v19".

Written from the LibRed managed-Access work (2026-09-19/20), where every item below was found the
expensive way.

## The driver has to satisfy linq2db, not just ADO.NET

A driver that passes a hand-written smoke test can still be unusable, because linq2db calls parts of
`DbDataReader` / `DbConnection` that a minimal provider legitimately leaves unimplemented.

**`IsDBNullAllowed` is the one that bites first.** `DataProviderBase.IsDBNullAllowed`
(`Source/LinqToDB/Internal/DataProvider/DataProviderBase.cs:307-311`) is an **unguarded**
`reader.GetSchemaTable()`, and `ConvertFromDataReaderExpression.cs:178` calls it for every column not
already forced to a null check. So on a driver without `GetSchemaTable`:

- DDL and DML stay green — they never materialize a row;
- **every `SELECT` throws before its first row.**

That ordering is what makes it costly: the create-data step passes, the provider looks wired up, and
the failure lands on the whole suite at once with a message that points into linq2db rather than at
the driver. Six providers already override it for this class of reason —
`FirebirdDataProvider.cs:144-147`, `SqlCeDataProvider.cs:161-164`, `YdbDataProvider.cs:124`,
`SapHanaDataProvider.cs:275`, `ClickHouseDataProvider.cs:169-173`, `SQLiteDataProvider.cs:242` — the
first three returning `true` outright and the others per flavour.

Check the same way for the rest of the optional surface before committing to a design:
`DbConnection.GetSchema(...)` (the base `SchemaProviderBase.GetDataTypes` calls it, so a driver
without it needs that override too), `DbDataReader.GetSchemaTable()`, `IDbColumnSchemaGenerator`,
and `DbConnection.Database` / `.DataSource` (read by `SchemaProviderBase` and by several
`*SchemaProviderBase` classes).

## Reader registrations are keyed on the **driver's** type-name string

`SetCharField`, `SetCharFieldToType<T>`, `SetField<TP,T>` and `SetToType<..>`
(`DataProviderBase.cs:186-203`) all key their `ReaderInfo` on a `DataTypeName` — the string the
driver's `GetDataTypeName(int)` returns. Mirroring another flavour's registrations only works if the
new driver reports the same vocabulary.

A driver that reports **CLR** names (`String`, `Int32`) rather than store types cannot be wired this
way at all: `CHAR`, `VARCHAR` and `MEMO` become indistinguishable, so a fixed-width trim cannot be
registered without also trimming every `VARCHAR`. The `ToType`-narrowed overload is still usable —
`SetCharFieldToType<char>("String", …)` matches only members mapped to `char`, which is unambiguous —
but the plain `SetCharField` trim has no safe key. Decide it explicitly and record the divergence;
don't copy the neighbouring provider's lines and assume they fire.

## TFM availability belongs in the provider lists, not in `#if`

When a provider's driver package only exists for some target frameworks, express that by **not listing
the provider in the other TFMs' provider lists** — the `NET110` section of
`UserDataProviders.json.template`, and a TFM-scoped section in the job's `Build/Azure/configs/*.json`.
Do **not** reach for `#if NET11_0_OR_GREATER` in `TestProvName` or in fixtures.

Two reasons. First, the provider list is the test environment's own statement of what exists, so
nothing in test code has to know why. Second, the `#if` route has to be applied in *two* places and is
easy to half-apply: the exclude-shaped `DataSourcesAttribute.GetProviders()`
(`Tests/Base/Attributes/DataSourcesAttribute.cs:24`) filters `UserProviders` through
`TestConfiguration.Providers`, but the include-shaped `IncludeDataSourcesAttribute.cs:24` intersects
with `UserProviders` **alone** — `TestConfiguration.cs:237-243` documents the asymmetry — so gating a
`TestProvName` constant silently misses every provider-only fixture.

The trap this closes: a release (`full_run`) leg runs the main suite for **every** TFM
(`Build/Azure/pipelines/templates/test-workflow-linux.yml:7-8,149`), while a CI job's provider list is
TFM-independent by design (`DataProviders.json:39-42`, one `Azure.TestJob` section staged for whichever
TFM the leg runs). A provider whose package is conditional therefore appears on a TFM that cannot load
it, and the leg goes red on every release run rather than occasionally. A job config that needs the
TFM-scoped section is deviating from what every other job does — comment it, or a later edit will
quietly normalize it away.

## A new provider owes a type-coverage fixture

`Tests/Linq/DataProvider/Types/` holds one `<Provider>TypeTests : TypeTestsBase` per provider, and
`TypeTestsBase.TestType<TType, TNullableType>` drives the whole per-type matrix: create-table, nullable
and non-nullable, parameter **and** literal, and every bulk-copy mode. A new provider adds one, with a
case per storage type of the database.

Where a database already has several providers and no fixture (Access, as of this writing), adding a
transport is the moment to write it for **all** of them rather than only the new one: a fixture that
covers one provider cannot show a divergence *between* providers, which is the diagnostic the work
actually needs. Expect it to fail on the pre-existing providers too — those are latent defects the new
coverage surfaces, and they get a named exclusion plus a filed issue, not a fix on the provider branch.

## Collect driver defects into a register; triage them in one pass

A new driver produces a stream of "that's arguably an upstream bug" findings — unimplemented ADO
surface, a literal form the reference engine accepts and this one silently mismatches, an exception
type that carries no error code. Filing them one at a time as they surface is both noisy and
premature, because the fix for several is often the same unreleased upstream change.

Keep a register in the branch's work plan instead: one row per measured behaviour, what makes it a
defect rather than a missing feature, and the workaround the branch applies. Triage the list in a
single pass at the end, checking each against the upstream tracker's existing issues *and* against any
open PR that moves the same surface. Rank by whether the behaviour produces a **wrong answer** (a
literal that parses and matches nothing outranks everything), then a crash where a capability error is
due, then plain dialect gaps.

The register is also what keeps the workarounds honest: every entry names the code that exists only
because the driver misbehaves, so when upstream fixes it there is a list of things to delete.
