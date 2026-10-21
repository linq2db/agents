---
area: MAPPING
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: high
last_verified: 2026-10-21
last_verified_sha: 89b5ce16278728b9936ba374827fea002c76e962
---

# MAPPING -- GitHub themes

## Open themes

- **Type conversion and custom mapping** -- 9 open issues. Users struggle with custom value converters and generic types: open generic converters (#1994), provider-specific conversions for stored procedure outputs (#2103), ValueToSqlConverter for generic types (#3117), and MapValue read/write asymmetry for undefined values (#363). F# option element converters are not applied to `.Value` comparisons (#5886). Mapping schema defaults are keyed by CLR type only, while some defaults need the database type too: the "value read for NULL" default (#5999, e.g. SQL Server datetime cannot hold 0001-01-01), attribute-built SQL typed with the schema default for the member's CLR type instead of the value's type (#6044, ClickHouse DateTime64 coercion skipped), and IN-list values written at the schema's default decimal scale (#6064). A provider reader is missing for a type the provider returns: SQLite.MS reads DateTimeOffset through GetDateTime and loses the offset (#6031). Sample: #363, #1994, #2103, #3117, #5886, #5999, #6031, #6044, #6064.

- **Fluent mapping API and attribute refactoring** -- 6 open issues. Requests for a consistent fluent mapping API and for decoupling attributes from metadata. Open items: refactoring fluent builders away from column/table attribute logic (#3914), decoupling model attributes from metadata (#2502), QueryFilter declarative syntax (#4543), type references in AssociationAttribute.QueryExpressionMethod (#4273), System TableAttribute forcing Column attributes (#3691), and metadata readers unable to see the active MappingSchema (#5675, filed 2026-07-04). Recent closure: #5540 (ExpressionMethod substitution at materialization, v6 regression) closed 2026-07-09. Sample: #3914, #2502, #4543, #4273, #3691, #5675.

- **Association and relationship mapping** -- 3 open issues. Problems with association key resolution and EF compatibility (owned entities, FK-PK matching in complex scenarios), and an association reached through a cast to an interface that fails during SQL generation (#4773, updated 2026-10-21). Sample: #4627, #4650, #4773.

- **Advanced mapping scenarios** -- 6 open issues. Emerging pattern: need for more flexible property-column mapping, for both inheritance and derived types. Open items: dynamic tables (#4730), complex type property built from multiple columns with fluent mapping (#4758), explicit interface implementation (#4715), chunked BLOB reads (#1075), derived-entity writes through a base-mapped table in entity-builder, Upsert and Merge (#5837), and a [Column] on a new-shadowing member of a TPH subtype silently ignored (#5852, filed 2026-09-02). Sample: #4730, #4758, #4715, #1075, #5837, #5852.

- **Infrastructure, caching and provider data types** -- 5 open issues. Long-standing refactoring requests to unify provider-specific type systems and add naming convention support (snake_case, CamelCase), plus mapping cache growth. Items: unify provider data types (#1181), NamingConventions (#4700), EntityDescriptorsCache pinning discarded schemas (#5718, filed 2026-07-13), ulong.MaxValue literal failing on several providers with a direct vs remote difference on PostgreSQL (#5973, filed 2026-09-26), and a decimal mapped with Precision but no Scale written through a Decimal(P, 0) parameter on YDB (#6063, filed 2026-10-17). Related draft PRs: #5694 bounds MappingAttributesCache growth (fixes #5692) and #4836 replaces the SqlDataType AST type in the mapping schema with DbDataType. Sample: #1181, #4700, #5718, #5973, #6063.

- **netstandard2.0 build loses provider type conversions** -- 3 open issues. Provider type conversions gated by TFM symbols (SUPPORTS_DATEONLY, #if) are not compiled into the netstandard2.0 asset, so an app on a modern runtime that loads that asset cannot read Npgsql 10 date/time values into classic DateTime / TimeSpan / NpgsqlRange<DateTime> properties (#6077), DuckDB TIMETZ into TimeSpan (#6084), or MySQL VECTOR into float[] with MySqlConnector (#6085). Draft PR #6092 addresses #6077 only. Sample: #6077, #6084, #6085.

## Resolved themes

- **Fluent mapping API enhancements** -- 17 closed issues. Historical requests for fluent variants of existing attribute-based patterns. Sample: #26, #162, #179, #202, #961, #1089, #1128, #1160.

- **Association and relationship mapping** -- 8 closed issues. Fixes to parent-child navigation, N+1 optimization, and explicit join mapping. Sample: #498, #1443, #1498, #3230, #3561, #2592, #529, #4723.

- **Column and table mapping fundamentals** -- 10 closed issues. Core attribute mapping (Column, Table, PrimaryKey, Identity), inheritance strategies. Sample: #26, #197, #1074, #2499, #3894, #3830, #1833, #4605.

- **Insert/Update statement mapping** -- 7 closed issues. Mapping of DML statements (INSERT/UPDATE/MERGE) to entity changes and bulk operations. Sample: #2504, #2692, #3342, #4055, #3131, #3891, #5289.

- **Recent resolutions (2026-07 to 2026-10)** -- 4 closed issues and 2 merged PRs since the 2026-07-06 cut. Issues: #5540 (ExpressionMethod substitutions at materialization regardless of IsColumn, v6 regression, closed 2026-07-09), #4194 (UpdateOptimistic did not change the concurrency token on the entity, closed 2026-08-30), #4662 (EF HasConversion<string> ignored for enum properties, closed 2026-09-06), #5779 (analyzer rule L2DB1002 for a duration comparison that can never match, closed 2026-09-08). PRs: #5695 (EF Core mapping schema cached by model-cache key to fix query-cache misses, merged 2026-07-11) and #5780 (wrong MappingSchema when one DbContext type is used with several providers, fixes #5778, regression from #5695, merged 2026-08-15). Resolved-theme counts above were not reclassified and remain as of 2026-07-06.

- **Recent resolutions (2026-10-09 to 2026-10-21)** -- 3 closed issues and 3 merged PRs. Issues: #5976 (closed 2026-10-09, EF Core DateTime value converters in Concat/Union raised an op_Inequality operand mismatch; no linked PR is recorded in the index), #6052 (closed 2026-10-16, Union over columns that share a value converter class threw ArgumentException from SequenceHelper.Canonicalize; fixed in 6.5.1 by #5978, regression test in #6060), #4199 (closed 2026-10-21, "Property X is not defined for interface type Y"; fixed in 6.0.0-preview.1 by #3401, and #6097 rewrote its tests to the issue's repro and removed the gate). PRs: #6025 (merged 2026-10-12, F# records that declare a static let mapped constructor arguments to the wrong fields, because static let bindings take CompilationMapping sequence numbers), #6060 (merged 2026-10-16, regression test for #6052), #6097 (merged 2026-10-21, #4199 test rewrite).

## Active discussions
- [Incrementally add mappings without "invalidating" EntityDescriptorsCache](https://github.com/linq2db/linq2db/discussions/4269) -- [Q&A] Large ERP model (about 150 POCO classes) asks how to add mappings incrementally without invalidating the entity descriptors cache (performance).
- [Relation between different types of mapping](https://github.com/linq2db/linq2db/discussions/5554) -- [Q&A] How the mapping approaches relate (SetConverter, MappingSchema configuration, wrappers over primitive values).

## Stats

- Open issues: 32
- Closed issues: 137
- Open PRs: 3
- Total PRs: 43
- Discussions: 16 (2 open)
- Last fetched: 2026-10-21

<details><summary>Coverage</summary>

- Index entries scanned: 213 (158 issues + 39 PRs + 16 discussions) at the 2026-10-10 cut; the 2026-10-21 merge read 128 updated items (63 issues + 65 PRs) and added 15 by content (11 issues + 4 PRs)
- Themes extracted: 12 (6 open + 6 resolved)
</details>
