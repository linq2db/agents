---
area: IDENTITY
kind: patterns
sources: [code]
confidence: medium
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# IDENTITY -- Patterns

## Recurring code patterns

- **Store override shape.** Stores expose tables as `protected virtual IQueryable<>` from `Context.GetTable<T>()` and override each `*Async` member with a linq2db query. Subclasses hook in via `protected virtual` factories such as `CreateUserPasskey` (`Source/LinqToDB.Identity/Stores/UserOnlyStore.cs`).
- **Find-then-insert-or-update, idempotent.** Tokens, role membership and passkeys do not rely on a mapped PK (`AddToRoleAsync`, `SetTokenAsync`, `AddOrUpdatePasskeyAsync` keyed on `CredentialId`). Removing a missing row is a no-op, finders return `null`.
- **Guards before DB access.** Null / blank / unknown-role / disposed checks throw before any query.
- **Optimistic concurrency via core API.** `UpdateOptimisticWithRefreshAsync` and `DeleteOptimisticAsync` with a `ConcurrencyFailure` result unless exactly 1 row changed. Fallback `AnyAsync` probe when `SqlProviderFlags.IsAffectedRowsCountSupported` is false.
- **Manual cascade unless the DB cascades.** Stores delete dependents themselves unless `DatabaseCascadesDeletes()` (option `UseIdentityDatabaseCascadeDelete`) is true.
- **Provider-scoped mapping attributes.** `DefaultMappings` applies `DataTypeAttribute` / `ColumnAttribute` / `ValueConverterAttribute` with `Configuration = ProviderName.X` for provider workarounds. Override recipe: a later scoped attribute with the same `Configuration` replaces the whole column mapping and must restate dropped members (for example `IsPrimaryKey`).
- **Customization via `ConfigureMappings`.** Override, call base, then a second `FluentMappingBuilder` pass. `DataOptions.UseMappingSchema` cannot override defaults.
- **Per-TFM generic tiers.** Passkey-aware generic forms are the bases on net10.0 (`#if NET10_0_OR_GREATER`), with a separate `PublicAPI/net10.0/` overlay.
- **Navigations as extension methods** with `[Association]` / `[ExpressionMethod]` (CS9296 forbids extension properties in expression trees).

## Test patterns

- `IdentityTestData` base, `[NoBaselines]` (random ids and stamps). Same cases run direct and via LinqService with `[DataSources]`, direct-only with `[DataSources(false)]`.
- Corrupt `ConcurrencyStamp` through the store context, not the setup connection (Access visibility).
- Seed a bystander user/role with identical dependents so a lost owner filter fails.
- Pin the documented provider inventory in both directions (`ScopedDefaultsMatchDocumentedInventory`, `ScopedOverrideWinsOverEveryScopedDefault`).
- ClickHouse gaps gated with `[ActiveIssue(Configuration, ErrorType, ErrorMessage)]` pinning the exact failure.

## Applicable conventions

- No conventions cite files in this area. See [conventions/](../../conventions/) for the catalog.

## Recorded decisions affecting this area

- No area-scoped recorded decisions yet (`decisions.md` not built). Documented stance: deliberately breaking API versus the standalone `linq2db.Identity` 6.0.0 package, EF Core `AspNet*` table layout kept for drop-in storage.

## Test coverage

- `Tests/Linq/Identity/` (61 test methods, 4 fixtures). No dedicated TESTS-* area page.

## See also

- [INDEX.md](INDEX.md) -- area architecture
- [tech-debt.md](tech-debt.md) -- structural debt
- [EFCORE patterns](../EFCORE/patterns.md) -- sibling EF-interop package

<details><summary>Coverage</summary>

Aggregated from `areas/IDENTITY/INDEX.md` (read in full). No detected-issues entries, no `issues.md` / `decisions.md` for this new area. Claims cite INDEX.md, not fresh source reads.

</details>
