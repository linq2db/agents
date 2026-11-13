---
area: PROV-SAPHANA
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-11-11
last_verified_sha: 1732302e2365c87b9465ab754b768a149308a537
---

# PROV-SAPHANA -- GitHub themes

## Open themes

- **Client probing on the netstandard2.0 and net8+ builds** -- the netstandard2.0 build of linq2db probes only `Sap.Data.Hana.Core.v2.1` for the native SAP HANA client, while the net8+ build probes `Sap.Data.Hana.Net.v8.0` and `v6.0` first. #6076 reports that the netstandard2.0 build misses the .NET 8 client (`Sap.Data.Hana.Net.v8.0`). Fix PR #6083 (draft, open) adopts the net8+ probe list on every non-.NET Framework build. The NuGet sourcing of the client (#5862, PR #6162) is under Resolved themes. Open: #6076, PR #6083.
- **KeyedQuery detail-side Take/Skip on HANA** -- eager-load detail queries with Take/Skip emit a `LATERAL` correlated to a literal key set, which HANA rejects ("non-field expression with LATERAL"). Open: #5940. Related open cross-provider item: #3015 (CTE support across providers, PROV-ORACLE in the index, labelled `provider: sap-hana`). Earlier APPLY/LATERAL enablement is under Resolved themes.
- **Array column types** -- HANA array columns are not mapped (`Cannot convert value 'System.Byte[]' to type 'System.String[]'`). Open: #3302 (index tags it GLOBAL; labels `provider: sap-hana`, `status: has-pr`) and PR #3303 "[SAP HANA] Arrays Support" (open, PROV-SAPHANA). Original question: discussion #3301 (closed, GLOBAL). Two items only, below the three-item cluster threshold; kept because both are open.
- **Stored procedure name escaping** -- #1740 "Linq To DB should escape procedure name (new API needed)" (open; index tags it GLOBAL; labels `provider: sap-hana`, `area: extensions`). Singleton; kept because it is open and provider-labelled.

## Resolved themes

- **SQL feature enablement for HANA 2 (APPLY, TOP, CTE, UPDATE FROM, LATERAL)** -- CROSS/OUTER APPLY (#3154, SQL-AST in index), TOP in subqueries (#1779), CTE (#3099), UPDATE FROM (#3196), LATERAL support for SAP HANA/MySQL (PR #3165). Closing PR ids for #1779, #3099, #3196 are not recorded in the index.
- **Parameter binding and ordering** -- "Parameter/Column not bound" and positional-parameter ordering: #1528 fixed by PR #1530 ("requires all parameters ordered"); #1685 (Sql.Expression with positional parameters) closed. PR #2423 (SAP HANA native provider parameters fix, severity critical) is a later parameter fix.
- **Nullable mapping and identity values** -- PR #1684 (mapper expression with nullable columns on SAP HANA) and PR #2742 (wrong identity returned on SapHana).
- **Client assembly loading and client versions** -- #239 (cannot load Sap.Data.Hana.dll) fixed by PR #629 and PR #1157 (GAC load); PR #1384 (ODP.NET GAC discovery); #1385 (DbProviderFactories support for more providers, closed) and PR #1961 (refactoring of ADO.NET provider integration code); #4886 (newer HANA assembly versions, GLOBAL in index); PR #4887 (support for v6/v8 clients); #5535 (NU5019 HintPath, closed; fixed by PR #5565, which resolves scaffold-package Redist references without SolutionDir). Client sourcing changed in #5862 (closed 2026-10-28) and PR #6162 (merged 2026-10-28): the .NET-side client now comes from SAP's `Sap.Data.Hana.Net.v6.0` / `v8.0` / `v10.0` NuGet packages, the probe includes v10.0, and the v4.5 assembly is no longer packed. Redist/SapHana no longer ships the .NET-side binaries.
- **CI and test enablement** -- PR #2720 (enable SAP HANA on CI), PR #4566 (update deps, fix saphana scripts), PR #4361 (HANA docker fixes, GLOBAL in index), PR #1872 (Azure DevOps HANA support, INFRA in index), PR #2323 (update SAP HANA tests to use the latest provider).
- **Closed issues sharing the hana keyword (sample)** -- #13, #154, #239, #1462, #1528, #2443, #3719, #1779.

## Active discussions

- No active discussions. (#4270 "Linq2DB still support SAP HANA ?" is closed, category General.)

## Stats

- Open issues: 5 cited (#1740, #3015, #3302 with other area tags; #5940, #6076 PROV-SAPHANA-tagged)
- Closed issues: 14 PROV-SAPHANA-tagged (#5862 and #5535 closed)
- Open PRs: 2 (#3303, #6083; #6083 is a draft)
- Total PRs: 18 (PROV-SAPHANA-tagged)
- Discussions: 1 (#4270, closed)
- Last fetched: 2026-11-11 (incremental refresh; index data through 2026-11-10)

<details><summary>Coverage</summary>

- PROV-SAPHANA-tagged index entries: 16 issues + 18 PRs + 1 discussion. Cited items with other area tags: #1740, #3015, #3302, #3301, #3154, #4886, #5565.
- Themes extracted: 10 (4 open + 6 resolved)
- Changes this run: 4 refs added (#1385, PR #1961 in client loading; PR #2423 in parameter binding; PR #2323 in CI and test enablement). No refs dropped. All open-theme citations kept (#6076, PR #6083, #5940, #3015, #3302, PR #3303, #1740 are all still open; discussion #3301 kept as the origin of #3302).
- Considered and not added: #3398 (SAP Anywhere Database, a different product); #5569, #5725, #5817, #6201, #5994, #698 (HANA mentioned only in body text, no HANA theme); #4682 (generic title "SAP HANA improvements", no theme text to anchor it); #1759 (release 2.7.3); #887 (HANA 2.0 SP2, closed 2017, GLOBAL, single item).
</details>
