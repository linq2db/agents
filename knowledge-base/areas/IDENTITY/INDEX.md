---
area: IDENTITY
kind: area-index
sources: [code]
confidence: high
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
coverage_tier_1: 8/8
coverage_tier_2: 10/10
---

# IDENTITY

`linq2db.Identity` -- ASP.NET Core Identity persistence provider over a linq2db `IDataContext`. Implements the `Microsoft.Extensions.Identity.Stores` contracts (`IUserStore`, `IRoleStore` and the optional families) using the stock `IdentityUser<TKey>` / `IdentityRole<TKey>` entity types and the EF Core `AspNet*` table layout, so it is a drop-in storage backend for an existing Identity database. Single project `Source/LinqToDB.Identity/LinqToDB.Identity.csproj` (assembly `linq2db.Identity`, TFMs `net462`, `netstandard2.0`, `net8.0` to `net10.0`), tests in `Tests/Linq/Identity/`. It supersedes the standalone `linq2db.Identity` 6.0.0 package with a deliberately breaking API: `PackageValidationBaselineVersion` is empty and `EnablePackageValidation` is false (`Source/LinqToDB.Identity/LinqToDB.Identity.csproj:23`). Not trimming/AOT safe (DI wiring uses `MakeGenericType`).

## Subsystems

### Stores (`Stores/`)

Three generic families, each with a chain of convenience subclasses that fix `TKey = string` and the stock satellite types:

- `UserOnlyStore<TUser, TContext, TKey, TUserClaim, TUserLogin, TUserToken[, TUserPasskey]>` (`Source/LinqToDB.Identity/Stores/UserOnlyStore.cs`) derives `UserStoreBase<...>` and implements login, claim, password, security-stamp, email, lockout, phone, two-factor, authentication-token, authenticator-key, recovery-code and queryable-user interfaces. `IUserPasskeyStore<TUser>` is added under `#if NET10_0_OR_GREATER`.
- `UserStore<TUser, TRole, TContext, TKey, ...>` (`Source/LinqToDB.Identity/Stores/UserStore.cs`) derives `UserOnlyStore` and adds `IUserRoleStore<TUser>` (`GetUsersInRoleAsync`, `AddToRoleAsync`, `RemoveFromRoleAsync`, `GetRolesAsync`, `IsInRoleAsync`). On net10.0 it derives the passkey-aware 7-argument `UserOnlyStore`, so `UserStore<...,TRoleClaim>` is NOT a `UserOnlyStore<...,TUserToken>` there (readme, Customization limits).
- `RoleStore<TRole, TContext, TKey, TUserRole, TRoleClaim>` (`Source/LinqToDB.Identity/Stores/RoleStore.cs`) derives `RoleStoreBase` and adds role claims.

Every store holds an `IDataContext` (`Context`), exposes tables via `Context.GetTable<T>()` as `protected virtual IQueryable<>` properties (`UserClaims`, `UserLogins`, `UserTokens`, `UserRoles`, `Roles`, `RoleClaims`, `UserPasskeys`) and overrides the `*Async` members with linq2db queries. Constructors take `(context, IdentityErrorDescriber?, IOptions<IdentityOptions>?)`. Only `IdentityOptions.Stores.SchemaVersion` is read (`Source/LinqToDB.Identity/Stores/UserOnlyStore.cs:148`), defaulting to `IdentitySchemaVersions.Version1`. `ProtectPersonalData` is unsupported (no `IProtectedUserStore`): `UserManager` refuses to resolve when it is enabled (test `DependencyInjection_ProtectPersonalDataIsRejected`, message mentions `IProtectedUserStore<>`).

Extension points the tests exercise: `CreateUserPasskey(user, passkey)` is a `protected virtual` hook. A subclass of the 6-argument `UserOnlyStore` overrides it with the stock `IdentityUserPasskey<string>` signature (`StockStorePasskeyOverride` in `Tests/Linq/Identity/IdentityStoreTests.cs`), and a custom-passkey `UserStore<..., TUserPasskey>` fills its extra member (`AppPasskeyStore` in `IdentityCustomizationTests.cs`, `Device = passkey.Name`).

Behaviors that differ from EF Core and matter when debugging:

- **No change tracker, every call writes immediately.** `UserManager` methods composed of several store calls are not atomic (readme). Token set is find-then-insert-or-update (`UserOnlyStore.SetTokenAsync`), `AddToRoleAsync` is find-then-insert and idempotent (`Source/LinqToDB.Identity/Stores/UserStore.cs:244`, test `UserRoles` re-adds a role without a PK violation), claim replace is `Set(...).UpdateAsync`.
- **Argument and state guards run before any DB access.** Null `user` / `claim` / `login` arguments throw `ArgumentNullException`, blank role names throw `ArgumentException`, an unknown role throws `InvalidOperationException`, and a disposed store throws `ObjectDisposedException` (`IdentityStoreNegativeTests.cs`: `NullArguments`, `RoleNameValidation`, `DisposedStore`, no schema needed). Finders return `null` for missing rows, and removing a missing login, token or claim is a no-op (`NotFoundReturnsNull`, `IdempotentRemovals`).
- **Optimistic concurrency.** `UpdateAsync` calls `Context.UpdateOptimisticWithRefreshAsync` (refreshes the regenerated `ConcurrencyStamp` onto the entity, so the same instance stays usable for a further update, tests `UserProfileFields`, `RoleCrudAndClaims`) and returns `ConcurrencyFailure` unless exactly 1 row changed (`Source/LinqToDB.Identity/Stores/UserOnlyStore.cs:198`, `Source/LinqToDB.Identity/Stores/RoleStore.cs:126`). `DeleteAsync` uses `DeleteOptimisticAsync` and, when the provider has no affected-rows count (`SqlProviderFlags.IsAffectedRowsCountSupported` false), decides via an `AnyAsync` existence probe (`UserOnlyStore.cs:213`). A delete that loses the optimistic check must not remove dependents either (`UserDeleteConflictKeepsDependents`). ClickHouse cannot decide the update check, so user and role updates throw there. SQL Server `OUTPUT` fails on tables with `UPDATE` triggers.
- **Manual cascade delete.** `CreateTable` emits no FKs, so `DeleteAsync` deletes claims, logins, tokens, passkeys (Version3+, net10.0), user-roles (`UserStore.DeleteAsync`) and role dependents itself, unless `DatabaseCascadesDeletes()` is true (see Options). Tests give a surviving user/role the same dependents so a delete that drops its owner filter fails (`UserDeleteRemovesDependents`, `RoleDeleteRemovesDependents`).
- **Identity keys.** `InsertAndSetIdentity` (`Source/LinqToDB.Identity/Extensions.cs:16`) uses `InsertWithIdentityAsync` when the entity descriptor has a single identity column and writes the key back via `ChangeType`, else a plain `InsertAsync`. `AddClaimsAsync` uses the internal `BulkCopyAsync` extension, which falls back to per-row `InsertAndSetIdentity` if the claim table has an identity column (`Extensions.cs:35`). Guid keys and DB-generated int keys are covered (`GuidKeys`, `IntKeys_IdentityGenerated`), and `UserManager.FindByIdAsync(string)` converts to the int key.
- **`RemoveClaimsAsync`** builds an OR-of-(type AND value) expression tree by hand and issues one `DELETE` (`UserOnlyStore.cs:294`). Claim values past 255 chars (a 120-part serialized permissions claim) still match by `=` in `GetUsersForClaimAsync` / `RemoveClaimsAsync`.
- **Passkeys (net10.0 only).** `AddOrUpdatePasskeyAsync` is find-then-insert-or-update keyed on the predicate `CredentialId`, not the mapped PK, because Access, Informix and Firebird 2.5 cannot key the 1024-byte id (`UserOnlyStore.cs:525`). Test `DuplicatePasskeyRowStillResolves` inserts a duplicate row on those three and checks find, update and remove still resolve. Below `IdentitySchemaVersions.Version3` all passkey members throw `Resources.PasskeysRequireVersion3` (message contains `Version3`) and `DeleteAsync` does not touch `AspNetUserPasskeys` (`UserDeleteRemovesPasskeys` with `[Values] bool schemaV3`). `NET11_0_OR_GREATER` adds `Aaguid` copying.

### Contexts (`Context/`)

`IdentityDataConnection<...>` (over `DataConnection`) and `IdentityDataContext<...>` (over `DataContext`) are structurally identical twins with several generic tiers each: non-generic (`IdentityUser`/`IdentityRole`/`string`), `<TUser>`, `<TUser, TRole, TKey>`, user-only `<TUser, TKey, TUserClaim, TUserLogin, TUserToken[, TUserPasskey]>`, and full `<TUser, TRole, TKey, TUserClaim, TUserRole, TUserLogin, TRoleClaim, TUserToken[, TUserPasskey]>`. The full form derives the user-only form and overrides `ConfigureMappings` to add role entities. The constructor calls `AddMappingSchema(GetMappingSchema())`, where the schema is built once per most-derived `GetType()` in a static `ConcurrentDictionary<Type, MappingSchema>` (`Source/LinqToDB.Identity/Context/IdentityDataConnection.cs:144`), so mappings cannot vary per instance. Customization means overriding `ConfigureMappings`, calling base first, then a second `FluentMappingBuilder` pass. When user, role or claim types are custom, `ConfigureMappings` also maps the stock satellite types because `IdentityNavigations` return stock types (`IdentityDataConnection.cs:190`, `:322`). Exposes `ITable<>` properties `Users`, `UserClaims`, `UserLogins`, `UserTokens`, `UserRoles`, `Roles`, `RoleClaims`, `UserPasskeys`. On net10.0 the non-passkey generic forms derive the `TUserPasskey` forms (`IdentityUserPasskey<TKey>`), so arity-9 (full) and arity-6 (user-only) are the passkey-aware bases. `Context/IdentityDataContext.cs` mirrors `IdentityDataConnection.cs` line for line (duplication, any fix must be applied twice).

Customization precedence, as pinned by `Tests/Linq/Identity/IdentityCustomizationTests.cs`:

- **Second pass in `ConfigureMappings` clones the defaults.** A rename of `IdentityUser.Email` keeps `Length` 256 (`ConfigureMappingsOverridesDefaults`), and the renamed schema round-trips against an independent `[Table]` mapping that pins the physical names (`RenamedSchemaRoundTrips`).
- **`DataOptions.UseMappingSchema` cannot override defaults.** The context adds its own schema in the constructor after the options, and the later addition wins (`DataOptionsMappingSchemaDoesNotOverrideDefaults`), though it still maps types the defaults leave alone.
- **`AddMappingSchema(consumer)` after construction does win,** but a schema built standalone starts from a blank attribute, so the rename holds and the default length is lost (`AddedMappingSchemaReplacesDefaultColumn`).
- **A provider-scoped default outranks an unscoped override.** Renaming `IdentityUserToken<string>.UserId` is swallowed on Firebird 2.5 (`ProviderScopedColumnResistsUnscopedRename`), while a later scoped attribute with the same `Configuration` replaces the whole column mapping and must restate the dropped key (`ProviderScopedColumnOverridesScopedDefault`). A later scoped `DataTypeAttribute` also moves the lookup parameter type on Oracle (`ProviderScopedDataTypeOverridesScopedDefault`).
- **Custom model types keep the defaults.** Defaults are registered against the consumer's types (`AppUser : IdentityUser<string>` etc.), so inherited members keep widths (`Email` 256, string `Id` / `UserId` / `RoleId` 36) and the consumer's own members are mapped (`CustomModelTypesKeepDefaultMappings`, `GenericContextsKeepDefaultMappings` across every context tier). Custom navigation properties declared on the consumer's own subclasses (`[Association]` with `QueryExpressionMethod`) work and are not mapped as columns (`OwnNavigationProperties`).
- **Custom passkey type** (`AppUserPasskey : IdentityUserPasskey<string>`) keeps `AspNetUserPasskeys`, `CredentialId` length 1024 (2048 on Informix, hex text), and the stock passkey type is not mapped beside it because no passkey navigation exists (`CustomPasskeyTypeKeepsDefaultMappings`).

### DI wiring (`IdentityLinqToDBBuilderExtensions.cs`)

`AddLinqToDBStores<TContext>(this IdentityBuilder)` (namespace `Microsoft.Extensions.DependencyInjection`) resolves store types by reflection. It finds the `IdentityUser<>` / `IdentityRole<>` base to get `TKey`, then walks the context base chain (`FindGenericBaseType`) for `IdentityDataContext<,,,,,,,,>` or `IdentityDataConnection<,,,,,,,,>` (arity 9 on net10.0, 8 otherwise) and pulls `TUserClaim`, `TUserRole`, `TUserLogin`, `TUserToken`, `TRoleClaim` from `GenericTypeArguments[3..7]` (`Source/LinqToDB.Identity/IdentityLinqToDBBuilderExtensions.cs:58`). A stock passkey type keeps the 9-argument `UserStore`, a custom one selects the 10-argument form (`:68`). With no identity context in the chain it falls back to `UserStore<,,,>` / `RoleStore<,,>` / `UserOnlyStore<,,>` and applies no mappings (tables named after CLR types). No role type configured selects `UserOnlyStore`. Registrations use `TryAddScoped`. Index-based `GenericTypeArguments[n]` is brittle to any reorder of the context type parameters.

Resolution matrix pinned by `Tests/Linq/Identity/IdentityStoreVariantTests.cs` (asserted with `ShouldBeOfType` on the exact closed store type):

- `IdentityDataConnection` or `IdentityDataContext` plus `AddRoles` gives `UserStore<..., TContext, string, stock satellites>` and `RoleStore<...>`. A custom full context (`AppIdentityConnection`) gives the stores typed by its own satellites (`DependencyInjection_RoleStoresFollowTheContext`, a missed context base would fall back to stock types).
- A user-only 5-argument context (`AppUserOnlyConnection`) gives the 6-argument `UserOnlyStore` with the context's satellite types read in the right order (`DependencyInjection_UserOnly_IdentityContext`). A full context registered without `AddRoles` also takes the user-only path (`DependencyInjection_FullContextWithoutRoles`), as does a `DataContext`-based one (`DependencyInjection_UserOnly_DataContext`).
- A plain `DataConnection` falls back to `UserStore<,,,>` / `RoleStore<,,>` (with roles) or `UserOnlyStore<,,>`, and `IRoleStore` is then absent (`DependencyInjection_PlainContext`).
- Custom passkey contexts resolve the 10-argument `UserStore` or 7-argument `UserOnlyStore`, and the store casts to `IUserPasskeyStore<TUser>` (`DependencyInjection_CustomPasskey`, net10.0).
- Non-`IdentityUser<TKey>` / `IdentityRole<TKey>` types throw `InvalidOperationException` naming the expected base (`DependencyInjection_RejectsNonIdentityTypes`).
- Full `UserManager` / `RoleManager` round trips run for string and int keys (`DependencyInjection_ResolvesStores_AndUserManagerRoundTrips`, `DependencyInjection_IntKeys_UserManagerRoundTrips`).

### Mappings (`Mapping/DefaultMappings.cs`)

`internal static class DefaultMappings` with `SetupIdentityUser|Role|UserClaim|RoleClaim|UserRole|UserLogin|UserToken|UserPasskey<TKey, T>(FluentMappingBuilder)` plus string-key shortcut overloads. Defines `AspNet*` table names, widths (36 for string keys and stamps, 256 for name/email/profile columns, 128 for login/token key parts, 1024 for the passkey credential id), `OptimisticLockPropertyAttribute(VersionBehavior.Guid)` on both `ConcurrencyStamp` columns, and identity only for int/long keys (`IsAutoIncrementKey`). The bulk of the file is provider-scoped workarounds applied as `DataTypeAttribute` / `ColumnAttribute` / `ValueConverterAttribute` with `Configuration = ProviderName.X`:

- `LockoutEnd` (`DateTimeOffset?`) pinned to the widest datetime type with a UTC-whole-seconds converter on MySQL, Access, SqlCe, SqlServer2005, Sybase, SapHana, Informix, DB2LUW, Firebird and Ydb (`_lockoutEndDataTypes`, `LockoutEndAsUtc`, `Source/LinqToDB.Identity/Mapping/DefaultMappings.cs:41`). Firebird cannot write `TIMESTAMP WITH TIME ZONE` (#5915). Test `UserLockout` also stores `DateTimeOffset.MaxValue` as a permanent lockout (a day short on SQLite.MS, #6031).
- Text columns: Access 255, Informix `LVarChar(1024)`, Oracle `NVarChar`. `ClaimValue` and token `Value` get per-provider types (`_claimValueTypes`, `_tokenValueTypes`). Name and email columns are 256 characters, not bytes (`FullWidthNonAsciiNames` writes 256 non-ASCII characters, 255 on Access). Oracle (UTF-8 test DB) and Informix count bytes for `ClaimType` and `ProviderDisplayName`, covered by `NonAsciiClaimTypeAndLoginName`. A 1800-char JWT fits in token `Value` (`LoginsAndTokens`).
- Key drops: `AspNetUserTokens` PK dropped on Firebird25 via a scoped `ColumnAttribute` with `IsPrimaryKey = false` (must be stated explicitly, `DefaultMappings.cs:383`). Passkey `CredentialId` PK dropped on Access, Firebird25 and Informix (Informix stores hex text through `ValueConverter<byte[], string>`).
- Passkey `Data` (`IdentityPasskeyData`) is stored as one JSON string column via `HasConversionFunc` (`System.Text.Json`, IL2026/IL3050 suppressed), with NText overrides on MySQL, Oracle, Firebird, Access, Informix and SqlCe. A realistic registration is about 900 JSON characters (`Passkeys`). `LargePasskeyData` (SAP HANA only) stores about 6200 characters, past SqlCe NVarChar 4000, while HANA's widest NVarChar is 5000 and its NText binds as Xml, so the readme documents a cap there.

The readme holds the authoritative per-provider table. Tests pin it in both directions:

- `ScopedDefaultsMatchDocumentedInventory` (`Tests/Linq/Identity/IdentityCustomizationTests.cs`) enumerates every `MappingAttribute` with a non-empty `Configuration` on the Identity entities for the current provider's `MappingSchema.ConfigurationList` and compares it, as `Entity.Member Kind @Configuration` strings, with the hand-kept `ScopedDefaults` table (Access/Informix/Oracle text limits, `LockoutEnd` data type plus converter, claim/login/token long-text rows, Firebird25 token key, passkey rows under `#if NET10_0_OR_GREATER`). A scoped default added, dropped or moved fails on that provider's leg until the table and readme follow.
- `ScopedOverrideWinsOverEveryScopedDefault` registers one later scoped attribute per documented row (via `EveryScopedDefaultOverriddenConnection`) and checks the override wins for every row of the active provider (`DbType`, `DataType`, `ValueConverter` identity or `ColumnName`), which is the readme's override recipe.

### Options (`LinqToDBIdentityOptions.cs`, `IdentityDataOptionsExtensions.cs`)

`LinqToDBIdentityOptions` is a sealed positional record `: IOptionSet` with a single member `DatabaseCascadeDelete` (default false) and a hand-written `ConfigurationID` built with `IdentifierBuilder` (`Source/LinqToDB.Identity/LinqToDBIdentityOptions.cs:33`). A comment there requires updating `ConfigurationID` when a parameter is added. Set through `DataOptions.UseIdentityDatabaseCascadeDelete(bool enabled = true)` (`WithOptions`). The internal extension `DatabaseCascadesDeletes(this IDataContext)` reads it (`Source/LinqToDB.Identity/Extensions.cs:13`). On a remote context set it on the client options. With the option on, the stores delete only the user / role row and leave dependents in place on a schema without FKs (`DatabaseCascadeDeleteSkipsDependentDeletes`). On SQL Server, PostgreSQL, MySQL, Oracle, SqlCe and Access with `ON DELETE CASCADE` FKs added by `ALTER TABLE` DDL built through `ConvertInline`, the database removes them (`DatabaseCascadeDeleteRemovesDependentsThroughForeignKeys`).

### Navigations (`IdentityNavigations.cs`)

Extension-method association markers on the Microsoft entity types: `Roles()`, `Claims()`, `Logins()` on `IdentityUser<TKey>` and `Users()`, `Claims()` on `IdentityRole<TKey>`. One-to-many ones use `[Association(ThisKey, OtherKey)]`, many-to-many (`Roles`, `Users`) use `[ExpressionMethod]` over private `UserRoles()` / `Role()` / `User()` associations. They are methods, not properties, because extension-property access is illegal in expression trees (CS9296). Bodies throw `InvalidOperationException` outside a query. They return stock types only, which is why custom-model contexts also map the stock satellites to the same tables (`CustomModelNavigations` queries `AppUser.Roles()`, `Claims()`, `Logins()` and `AppRole.Users()`, `Claims()`, and `NavigationAssociations` does the same on the stock types). Consumers who want their own typed result declare `[Association]` properties on their subclasses instead (`OwnNavigationProperties`).

## Key types

- `UserOnlyStore<...>`, `UserStore<...>`, `RoleStore<...>` -- stores (see Stores).
- `IdentityDataConnection<...>`, `IdentityDataContext<...>` -- mapping-carrying contexts.
- `IdentityLinqToDBBuilderExtensions.AddLinqToDBStores<TContext>` -- DI entry point.
- `LinqToDBIdentityOptions`, `IdentityDataOptionsExtensions.UseIdentityDatabaseCascadeDelete` -- `DataOptions` extension.
- `IdentityNavigations` -- query-only association helpers.
- Internal: `DefaultMappings`, `Extensions` (`DatabaseCascadesDeletes`, `InsertAndSetIdentity`, `BulkCopyAsync`), `Resources` (error strings).

## Files (Tier 1 / Tier 2)

Tier 1 (all read in full):

| File | Role |
|---|---|
| `Source/LinqToDB.Identity/Stores/UserStore.cs` | role-aware user store chain, `IUserRoleStore` |
| `Source/LinqToDB.Identity/Stores/UserOnlyStore.cs` | bulk of store logic incl. passkeys |
| `Source/LinqToDB.Identity/Stores/RoleStore.cs` | role store, role claims, cascade |
| `Source/LinqToDB.Identity/Context/IdentityDataConnection.cs` | `DataConnection`-based context |
| `Source/LinqToDB.Identity/Context/IdentityDataContext.cs` | `DataContext`-based context |
| `Source/LinqToDB.Identity/IdentityLinqToDBBuilderExtensions.cs` | DI registration |
| `Source/LinqToDB.Identity/Mapping/DefaultMappings.cs` | `AspNet*` fluent mappings, provider workarounds |
| `Source/LinqToDB.Identity/LinqToDB.Identity.csproj` | package, PublicAPI per-TFM overlay |

Tier 2, all read in full: `Extensions.cs`, `IdentityDataOptionsExtensions.cs`, `IdentityNavigations.cs`, `LinqToDBIdentityOptions.cs`, `Resources.cs` (all under `Source/LinqToDB.Identity/`) and, under `Tests/Linq/Identity/`, `IdentityTestData.cs`, `IdentityStoreTests.cs` (CRUD, widths, cascade, lockout, authenticator, claims, roles, navigations, logins/tokens, passkeys), `IdentityStoreVariantTests.cs` (UserOnlyStore, DataContext, Guid/int keys, DI resolution matrix), `IdentityStoreNegativeTests.cs` (null args, role-name validation, concurrency failures, disposed store) and `IdentityCustomizationTests.cs` (custom model types, `ConfigureMappings` overrides, scoped-attribute precedence, documented-inventory pin). Also read: `readme.md` (584 lines, the user-facing spec incl. provider table), `PublicAPI.Shipped.txt` and `PublicAPI/net10.0/PublicAPI.Shipped.txt` (both empty, `#nullable enable` only), `PublicAPI.Unshipped.txt` (all-TFM surface) and `PublicAPI/net10.0/PublicAPI.Unshipped.txt` (passkey overlay). The whole surface is unshipped.

## Tests

`Tests/Linq/Identity/` namespace `Tests.Identity`, base `IdentityTestData` (`[NoBaselines]` because ids and stamps are random). `Schema` creates the default `AspNet*` tables with `CreateLocalTable` on a direct `IdentityDataConnection`, `KeyedSchema<...>` does the same for custom key types and satellite sets, `GetSetup(context)` returns the direct connection whose `MappingSchema` is fed to `GetDataContext(context, ms)` so the same cases run direct and through LinqService (`[DataSources]` vs `[DataSources(false)]` for direct-only: mapping-metadata assertions, DI, `IdentityDataContext`). ClickHouse gates (`RefreshGate`, `IdentityGate`) use `[ActiveIssue(Configuration = TestProvName.AllClickHouse, ErrorType, ErrorMessage)]` pinning the exact failure. 61 test methods across 4 fixtures (some parameterized by `[Values] bool`, and net10.0-only ones under `#if NET10_0_OR_GREATER`):

- `IdentityStoreTests` (23): CRUD, width and non-ASCII, dependent deletes, cascade option, lockout, profile, claims ownership, roles, navigations, logins/tokens, passkeys (5, net10.0).
- `IdentityStoreVariantTests` (14): `UserOnlyStore`, `IdentityDataContext`, Guid and int keys, 9 DI cases.
- `IdentityStoreNegativeTests` (7): null args, role-name validation, concurrency failures on update/delete, disposed store, not-found nulls, idempotent removals.
- `IdentityCustomizationTests` (17): custom model types, navigations, renamed schema, precedence limits, scoped-default inventory and override pins.
- Technique worth copying: concurrency tests corrupt `ConcurrencyStamp` through the store ctx, not the setup connection, because Access does not show one connection the rows another inserted, so the 0-row match would silently void the premise. Delete and cascade tests seed a bystander with identical dependents so a lost owner filter fails.

## Inbound / outbound dependencies

- Outbound: `LinqToDB` core (project reference): `DataConnection`, `DataContext`, `FluentMappingBuilder`, `LinqToDB.Concurrency` optimistic-update APIs, `LinqToDB.Internal.Options` and `IdentifierBuilder` for the options record, `LinqToDB.Internal.Extensions.GetMethodEx`. NuGet `Microsoft.Extensions.Identity.Stores`. See [MAPPING](../MAPPING/INDEX.md) for fluent mapping and [DATA](../DATA/INDEX.md) for connection and context types.
- Inbound: none in-repo besides `Tests/Linq/Identity`. Packaged as `linq2db.Identity`.
- Cross-area: provider workarounds in `DefaultMappings` depend on `ProviderName.*` constants and per-provider DDL behavior (Access, Firebird, Informix, Oracle, MySQL, SAP HANA, Sybase, SqlCe, YDB, DB2). The cascade-FK test also uses `LinqToDB.Internal.SqlProvider.ConvertType` and the SQL builder `ConvertInline` from the SQL provider layer.

## Known issues / debt

- ClickHouse: `UpdateAsync` cannot decide optimistic concurrency, updates throw. No identity columns, int/long keys must be caller-assigned. Tests gate these with `[ActiveIssue]` on `RefreshGate` / `IdentityGate` (`UserCrud`, `UserLockout`, `UserProfileFields`, `RoleCrudAndClaims`, `UserDeleteConflictKeepsDependents`, `ConcurrencyFailureOnUpdate`, `IntKeys_IdentityGenerated`, DI round trips).
- SQL Server: an `UPDATE` trigger on `AspNetUsers` / `AspNetRoles` breaks the `OUTPUT`-based stamp refresh.
- No FKs and no indexes from `CreateTable`: name uniqueness rests on validators, add `UserNameIndex` / `RoleNameIndex` by hand. The Firebird 2.5 token table and the Access/Informix/Firebird 2.5 passkey table have no PK, so duplicates are possible (finders take the first row, pinned by `DuplicatePasskeyRowStillResolves`).
- `IdentityDataConnection.cs` and `IdentityDataContext.cs` are near-identical copies, several generic tiers each.
- `AddLinqToDBStores` relies on positional `GenericTypeArguments` indexes and on arity constants that differ by TFM.
- Mappings are cached per context type for the process lifetime, no per-tenant table names.
- `ProtectPersonalData` and every `IdentityOptions.Stores` member except `SchemaVersion` are ignored.
- API baseline: package validation disabled until the next major resets `BaselineVersion`. All PublicAPI entries are still `Unshipped`.
- The `ScopedDefaults` table in `IdentityCustomizationTests.cs` is a hand-maintained mirror of `DefaultMappings` and the readme: any provider-scoped default change needs three edits (mapping, test table, readme).
- Provider limits recorded mainly in tests: SAP HANA passkey JSON cap (NVarChar 5000), SQLite.MS `DateTimeOffset.MaxValue` shift (#6031).

## See also

- `Source/LinqToDB.Identity/readme.md` -- user documentation, provider-specific mapping table, migration from the standalone package.
- [EFCORE](../EFCORE/INDEX.md) -- the other EF-interop package, same `AspNet*` schema compatibility goal.

## Pointers

- Cascade: `Extensions.DatabaseCascadesDeletes`, `LinqToDBIdentityOptions.DatabaseCascadeDelete`, tests `DatabaseCascadeDeleteSkipsDependentDeletes`, `DatabaseCascadeDeleteRemovesDependentsThroughForeignKeys`.
- Concurrency: `UpdateOptimisticWithRefreshAsync`, `DeleteOptimisticAsync`, tests `ConcurrencyFailureOnUpdate` / `ConcurrencyFailureOnDelete`.
- Provider quirks: `DefaultMappings` arrays `_lockoutEndDataTypes`, `_claimValueTypes`, `_tokenValueTypes`, `_passkeyIdWithoutPrimaryKey`, `_passkeyDataAsText`.
- Mapping precedence and override recipes: `IdentityCustomizationTests` regions "Scenario B", "What customization cannot do", "Provider-scoped overrides".
- DI resolution cases: `IdentityStoreVariantTests` `DependencyInjection_*`.

<details><summary>Coverage</summary>

Tier 1: 8/8 read in full (UserStore.cs, UserOnlyStore.cs, RoleStore.cs, IdentityDataConnection.cs, IdentityDataContext.cs, IdentityLinqToDBBuilderExtensions.cs, DefaultMappings.cs, LinqToDB.Identity.csproj).

Tier 2: 10/10 `.cs` files read in full (Extensions.cs, IdentityDataOptionsExtensions.cs, IdentityNavigations.cs, LinqToDBIdentityOptions.cs, Resources.cs, IdentityTestData.cs, plus the four test fixtures read in the coverage-fill run below). Non-`.cs` files also read: readme.md, 4 PublicAPI files (the two Shipped files are empty, the Unshipped files were read to line 40 and line 30 respectively).

Tier 3: none (no bin/obj files counted).

Read (this run): all files listed above. Skipped: remaining bodies of the four partially-read test fixtures, listed in DEFERRED-COVERAGE.

Read (this run -- coverage-fill):
- Tests/Linq/Identity/IdentityCustomizationTests.cs -- full (995 lines): custom model/navigation/passkey types, `ConfigureMappings` precedence, `ScopedDefaultsMatchDocumentedInventory`, `ScopedOverrideWinsOverEveryScopedDefault`.
- Tests/Linq/Identity/IdentityStoreNegativeTests.cs -- full (205 lines): argument guards, role-name validation, concurrency failure on update/delete, disposed store, null results, idempotent removals.
- Tests/Linq/Identity/IdentityStoreTests.cs -- full (1171 lines): CRUD, widths, dependent deletes, cascade option and FK variant, lockout, claims, roles, navigations, tokens, passkeys incl. duplicate row and SAP HANA large data.
- Tests/Linq/Identity/IdentityStoreVariantTests.cs -- full (516 lines): UserOnlyStore, DataContext, Guid/int keys, DI resolution matrix, ProtectPersonalData rejection.
No contradictions with the prior body. The earlier "about 70 test methods" estimate is corrected to 61 counted methods.

</details>
