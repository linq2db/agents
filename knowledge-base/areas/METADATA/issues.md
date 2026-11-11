---
area: METADATA
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# METADATA -- GitHub themes

## Open themes
- **Attribute resolution and attribute caching against MappingSchema (4 items)** -- Attribute lookups read the live schema instead of a table handle's snapshot, and the per-MappingSchema attribute cache grows without bound. Cites #6269 (Sql.Extension, QueryExtension and TableFunction lookups ignore a handle's fluent HasAttribute), #5677 (open PR: schema-aware attribute resolution against the active MappingSchema), #5692 (unbounded MappingAttributesCache growth, the NETFX multi-config OOM driver) and #5694 (draft PR reworking that cache, fixes #5692).
- **TPH inheritance on base-mapped tables (emerging, 2 open items)** -- Writes and returned rows through a table mapped to an `[InheritanceMapping]` base are wrong: derived-entity writes fail in the entity-builder, Upsert and Merge paths (#5837), and InsertWithOutput/UpdateWithOutput read the primary key as the discriminator (#5838). Follows the TPH fixes merged as #5661. Watch for a third item before promoting to a theme.
- **Schema filter ordering and baseline capture (emerging, 1 item)** -- Unsorted IncludedSchemas reach emitted SQL, plus two baseline-capture races. See #5918 (open).

## Resolved themes
- **Raw-SQL entity materialization (2 items, closed)** -- Query<T>(string sql) constructor mapping. #5659 (merged 2026-06-28) honors [Column] and [ValueConverter] in raw-SQL constructor materialization. #5660 (closed without merge 2026-06-27) was the broader unify-with-LINQ-path attempt for #4437.
- **TPH (single-table inheritance) hierarchy fixes (single item)** -- Abstract intermediates, sibling columns mapping one member to different physical columns, and derived-type association discriminators. Merged as #5661 on 2026-07-03.
- **Scaffolding relation cardinality (single item, closed without fix note)** -- Scaffolder generates a multiple relation where a 1-1 is expected. Closed as #4874 on 2026-06-14; index has no linked closing PR.

## Active discussions
- None classified to METADATA.

## Stats
- Open issues: 5
- Closed issues: 1
- Open PRs: 2
- Total PRs: 5
- Discussions: 0
- Last fetched: 2026-11-11 (index cutoff)

<details><summary>Coverage</summary>

- Index entries scanned: 11 (6 issues + 5 PRs + 0 discussions), classified by area tag and by content
- Themes extracted: 1 (3-item threshold met by the attribute cluster; 2 emerging clusters listed above)
</details>
