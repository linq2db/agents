---
area: METADATA
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: low
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# METADATA -- GitHub themes

## Open themes
- **No theme meets the 3-item threshold yet** -- METADATA now has 6 classified items (2 issues, 4 PRs). Items are listed below as emerging clusters for watching.
- **Raw-SQL entity materialization (emerging, 2 items)** -- Query<T>(string sql) and [Column]/[ValueConverter] honoring for raw-SQL constructor mapping, both tied to #4437. See #5659 (merged) and #5660 (closed, not merged). Watch for a third item before promoting to a theme.
- **Metadata reader attribute resolution (emerging, 1 item)** -- Schema-aware attribute resolution against the active MappingSchema instead of MappingSchema.Default. See #5677 (open). Related core seam work is tracked in the v7 design notes.
- **Schema filter ordering and baseline capture (emerging, 1 item)** -- Unsorted IncludedSchemas reaching emitted SQL, plus two baseline-capture races. See #5918 (open).

## Resolved themes
- **TPH (single-table inheritance) hierarchy fixes (single item)** -- Abstract intermediates, sibling columns mapping one member to different physical columns, and derived-type association discriminators. Merged as #5661 on 2026-07-03.
- **Scaffolding relation cardinality (single item, closed without fix note)** -- Scaffolder generates a multiple relation where a 1-1 is expected. Closed as #4874 on 2026-06-14; index has no linked closing PR.

## Active discussions
- None classified to METADATA.

## Stats
- Open issues: 1
- Closed issues: 1
- Open PRs: 1
- Total PRs: 4
- Discussions: 0
- Last fetched: 2026-10-09 (index cutoff)

<details><summary>Coverage</summary>

- Index entries scanned: 6 (2 issues + 4 PRs + 0 discussions)
- Themes extracted: 0 (3-item threshold not met; 4 emerging clusters listed above)
</details>
