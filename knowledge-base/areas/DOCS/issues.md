---
area: DOCS
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# DOCS -- GitHub themes

## Open themes

- **Site publishing mechanism (track)** -- the docfx site moved into the repository by #6265 (follow-up #6264), but publishing still pushes the built output to linq2db/linq2db.github.io with an SSH deploy key. #6267 (open) evaluates GitHub Pages' Actions publishing as the replacement. One open item, so this is a track rather than a cluster. Sample: #6265, #6267.
- **Readers cannot find the answer in the docs** -- six open requests ask for a topic the published articles or README do not make findable: query logging setup (#4645), a comparison with Entity Framework (#4288, discussion), guidance for writing a new data provider (#4555, discussion), disabling back references in JSON scaffolding (#4432, discussion), a separate folder for the generated context (#5374, discussion) and the README change-tracking reference (#5722, discussion). Sample: #4645, #4555, #5722.
- **XML doc text that disagrees with runtime behaviour** -- the BulkCopy timeout XML doc promises an infinite timeout, but with default settings the driver default applies (#6001, open, tagged area: bulk-copy). The API reference is generated from these comments, so the wrong promise reaches the site. Sample: #6001.

## Resolved themes

- **Broken links and stale README pointers** -- a 404 link in the README (#2616, 2020), the general docs link pointing at the Linq2DbTools repository (#4141, closed 2025-12-15), and "Document Link Broken" (#5494, closed 2026-10-26). Sample: #2616, #4141, #5494.
- **Doc text that contradicted the code** -- wrong T4 README information (#1500), the CLI include-tables example (#4388), copy-pasted IsNotNull and IsNullable summaries (#4941) and the DontEscapeLowercaseIdentifiers doc comments (#2830). Sample: #4388, #4941.
- **Documentation requests closed with new text** -- fluent mapping (#4484), EF Core provider-specific options (#5830, closed 2026-08-29) and the BeginTransaction behaviour for DataContext (PR #5061, fixes #5059). Sample: #4484, #5830, #5061.
- **Usage questions routed to the documentation label (2013-2019)** -- 59 closed issues carry the area: documentation label, most of them usage questions answered in the thread (for example #384, #650 and #1379, how to do group by). Sample: #1379, #650, #1674.
- **Docfx build warnings** -- docfx warnings fixed by PR #3998 (2023) and PR #4787 (2025), then the Source-side warnings behind the in-repo docs build fixed by PR #6264 (2026). Sample: #3998, #4787, #6264.
- **README upkeep** -- badge reorganisation (PR #2184), code formatting (PR #3294), the NuGet readme (PR #3457, fixes #3335), TIP block separation (PR #5046), the JetBrains section (PR #5448) and the F# sample (PR #4804). Sample: #5046, #5448, #3457.
- **CONTRIBUTING.md rules and links** -- typo and link fixes (PRs #1031, #2748, #3077) and the test-layout rules (PR #6274, merged 2026-11-08). Sample: #3077, #6274.
- **Site moved into the repository (2026)** -- the docs moved out of linq2db/docs by PR #6265 (merged 2026-11-10). The decision is recorded in [decisions.md](decisions.md). Sample: #6265, #6264.

## Active discussions

- [[Docs] Comparison with Entity Framework](https://github.com/linq2db/linq2db/discussions/4288) -- [General] asks for a comparison with Entity Framework in the docs.
- [linq2db CLI, Json scaffolding ignore table back references on indexes?](https://github.com/linq2db/linq2db/discussions/4432) -- [Q&A] no documentation found for disabling back references on indexes in JSON scaffolding.
- [Documentation for creating new data provider or extending existing](https://github.com/linq2db/linq2db/discussions/4555) -- [Q&A] asks for guidance on writing a new provider or extending an existing one.
- [Is there an option to generate Context in a separate folder from generated entities?](https://github.com/linq2db/linq2db/discussions/5374) -- [Q&A] asks for a scaffold option that the scaffold docs do not show.
- [About Change-Tracking](https://github.com/linq2db/linq2db/discussions/5722) -- [General] asks where the change-tracking plug-in mentioned in the README is.

## Stats

- Open issues: 3 (#4645, #6001, #6267; #6001 carries the bulk-copy label and is counted by content)
- Closed issues: 13 cited above; 59 closed issues carry the area: documentation label index-wide
- Open PRs: 0
- Total PRs: 14 cited (docs content, merged or closed)
- Discussions: 5 open (#4288, #4432, #4555, #5374, #5722)
- Last fetched: 2026-11-11

<details><summary>Coverage</summary>

- Index entries scanned: 6240 (3245 issues + 2699 PRs + 296 discussions). 194 matched the content keywords (docs, docfx, documentation, article, readme, contributing, xref, linq2db.github.io, the documentation label, docs/ paths).
- Themes extracted: 3 open, 8 resolved.
- Items classified by content, not by the area tag: DOCS-tagged #5494, #6264, #6265, #6267 and #6274, plus GLOBAL-, EFCORE- and DATA-tagged documentation items.
- Not themed: #5376 (open PR with the documentation label, AGENTS-INFRA, ships an agent skill in the NuGet package); #5736 and #5693 (agent-corpus docs, not site content); #5786 (LINQPad driver docs); #4707 and #4703 (PostgreSQL ltree mapping, not docs); #4491 and #4774 (closed discussions that cite the docs only as context); #5516 (BUILD gating PR).
</details>
