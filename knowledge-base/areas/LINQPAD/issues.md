---
area: LINQPAD
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: low
last_verified: 2026-10-21
last_verified_sha: 89b5ce16278728b9936ba374827fea002c76e962
---

# LINQPAD -- GitHub themes

## Open themes
- **Access schema and connection failures under LINQPad** -- A schema refresh on an ACE OLE DB (Access .mdb) connection in LINQPad fails with "Schema Build Error: Invalid argument" and freezes the LINQPad UI for about 60 seconds (#5235). Same family as the earlier Access-under-LINQPad crashes on connect (#2534) and on update (#846), both closed. Open, no fix recorded.
- **Context configuration for LINQPad** -- Feature request to extend the LINQPad context configuration, with a PostGIS-over-LINQPad use case reported on the LINQPad forum (#5253). Single open request, so evidence of a recurring pattern is weak.

## Resolved themes
- **Driver packaging on macOS and Linux** -- The 6.2.0 and 6.2.1 driver packed only a net8.0-windows7.0 assembly, so LINQPad's NuGet manager reported "No compatible assemblies found" on macOS and Linux (#5497). Fixed by packing the driver under net8.0 in PR #5571 (merged 2026-06-04).
- **Driver unusable on LINQPad 9 for macOS** -- The WPF-only driver assembly could not load under LINQPad 9 for macOS, so connections failed after the package installed (#5768). Fixed by PR #5786 (merged 2026-08-21), "Fix LINQPad driver on macOS and provision database clients per connection".
- **Packaging and version regressions** -- The "Fix linqpad packaging" regression was fixed in PR #5421 (merged 2026-03-13). An earlier FileNotFoundException on the 6.0.0 driver when creating a connection was closed as #5242.
- **Connection dialog layout** -- Fixed-width dropdowns were clipped in the connection dialog. Fixed in PR #5579 (merged 2026-06-03).
- **Driver repository migration** -- The driver moved into the main repository (PR #5104, merged 2025-08-20; post-release issue #5102 closed 2025-12-06).
- **Build race in the LINQPad Pack project** -- The LinqToDB.LINQPad Pack project built the driver chain twice, so the Build and pack job failed intermittently with locked or missing obj files (MC2000, CS2001, CS2012). Fixed by PR #6030 (merged 2026-10-11).

## Active discussions
No active discussions in this area.

## Stats
- Open issues: 2 (#5235, #5253)
- Closed issues: 8 (#846, #1383, #2216, #2534, #5102, #5242, #5497, #5768)
- Open PRs: 0
- Total PRs: 8 (#3803, #5104, #5247, #5421, #5571, #5579, #5786, #6030)
- Discussions: 0
- Last fetched: 2026-10-21 (incremental refresh at 89b5ce162)

<details><summary>Coverage</summary>

- Index entries scanned: 18 (10 issues + 8 PRs + 0 discussions), matched on area LINQPAD, the "area: linqpad" label, or a LINQPad title
- Themes extracted: 8 (2 open, 6 resolved)
- Merge notes: PR #6030 added from the refresh fetch; PR #3803 (closed, area SCAFFOLD, LINQPad title) was in the index but missing from the prior stats
</details>
