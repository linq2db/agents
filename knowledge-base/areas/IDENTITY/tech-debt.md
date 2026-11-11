---
area: IDENTITY
kind: tech-debt
sources: [code]
confidence: medium
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# IDENTITY -- Tech debt

No detected-issues entries exist for IDENTITY (`detected-issues/index.json` has none, and a sweep of `Source/LinqToDB.Identity/` finds no TODO/FIXME/HACK/XXX comments). The debt below is structural, taken from [INDEX.md](INDEX.md). `issues.md` and `decisions.md` do not exist yet for this area (new area).

## Severity distribution

| Severity | Count |
|---|---|
| detected (DI-*) | 0 |
| structural (curated below) | 9 |

## Structural debt (curated, not detector output)

- **Duplicated contexts.** `Source/LinqToDB.Identity/Context/IdentityDataConnection.cs` and `Context/IdentityDataContext.cs` are line-for-line twins with several generic tiers each. Any fix must be applied twice.
- **Positional DI reflection.** `AddLinqToDBStores` reads `GenericTypeArguments[3..7]` of the context base and uses arity constants that differ by TFM (9 on net10.0, 8 otherwise), `Source/LinqToDB.Identity/IdentityLinqToDBBuilderExtensions.cs:58`. Reordering context type parameters silently breaks resolution. Not trimming/AOT safe (`MakeGenericType`).
- **Process-lifetime mapping cache.** The mapping schema is built once per most-derived context type in a static `ConcurrentDictionary<Type, MappingSchema>` (`IdentityDataConnection.cs:144`). No per-tenant or per-instance table names.
- **No FKs or indexes from `CreateTable`.** Name uniqueness rests on validators. Deletes are manual cascades in the stores unless `UseIdentityDatabaseCascadeDelete` is set. Firebird 2.5 token table and Access/Informix/Firebird 2.5 passkey table have no PK, so duplicates are possible (finders take the first row, test `DuplicatePasskeyRowStillResolves`).
- **Non-atomic multi-call operations.** No change tracker, every store call writes immediately, so `UserManager` operations composed of several store calls are not atomic.
- **Provider limits.** ClickHouse cannot decide the optimistic update check (updates throw, tests gated with `[ActiveIssue]` on `RefreshGate` / `IdentityGate`) and has no identity columns. SQL Server `OUTPUT`-based stamp refresh fails on tables with `UPDATE` triggers. SAP HANA passkey JSON is capped by NVarChar 5000. SQLite.MS shifts `DateTimeOffset.MaxValue` (#6031).
- **Triple-edit mirror.** `ScopedDefaults` in `Tests/Linq/Identity/IdentityCustomizationTests.cs` is a hand-kept mirror of the provider-scoped attributes in `Mapping/DefaultMappings.cs` and the readme table. A scoped default change needs three edits (mapping, test table, readme).
- **Ignored `IdentityOptions`.** `ProtectPersonalData` (no `IProtectedUserStore`) and every `IdentityOptions.Stores` member except `SchemaVersion` are ignored.
- **API baseline off.** `PackageValidationBaselineVersion` is empty and `EnablePackageValidation` false (`Source/LinqToDB.Identity/LinqToDB.Identity.csproj:23`). All PublicAPI entries are still `Unshipped`. Hand-written `ConfigurationID` in `LinqToDBIdentityOptions` must be updated when a parameter is added.

## See also

- [INDEX.md](INDEX.md) -- area overview
- [patterns.md](patterns.md) -- area patterns
- [EFCORE tech-debt](../EFCORE/tech-debt.md) -- sibling EF-interop package

<details><summary>Coverage</summary>

Aggregated from `areas/IDENTITY/INDEX.md` (read in full), `detected-issues/index.json` (no IDENTITY entries) and a TODO/FIXME grep over `Source/LinqToDB.Identity/*.cs` (no matches). Source files were not re-read beyond INDEX.md, whose Tier-1/Tier-2 coverage is 8/8 and 10/10. `issues.md` / `decisions.md` absent.

</details>
