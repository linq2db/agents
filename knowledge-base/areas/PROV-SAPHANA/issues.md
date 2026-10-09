---
area: PROV-SAPHANA
kind: issues
sources: [gh-issues, gh-prs, gh-discussions]
confidence: medium
last_verified: 2026-10-10
last_verified_sha: 05150894edc2511f0dd0bc7829b2a309cec36ec9
---

# PROV-SAPHANA -- GitHub themes

## Open themes

- **Client assembly loading and NuGet packaging of the HANA provider** -- the provider still ships hand-copied SAP binaries under `Redist/SapHana`. #5862 proposes restoring the .NET-side binaries from SAP's `Sap.Data.Hana.Net.v6.0/v8.0/v10.0` packages (the .NET Framework v4.5 assembly stays separate). Same family as the closed load/GAC and client-version work (#239, #629, #1157, #4887) and the NU5019 HintPath packaging failure (#5535, closed). Open: #5862.
- **KeyedQuery detail-side Take/Skip on HANA** -- eager-load detail queries with Take/Skip emit a `LATERAL` correlated to a literal key set, which HANA rejects ("non-field expression with LATERAL"). Open: #5940. Related open cross-provider item: #3015 (CTE support across providers, PROV-ORACLE in the index, labelled `provider: sap-hana`). Earlier APPLY/LATERAL enablement is under Resolved themes.
- **Array column types** -- HANA array columns are not mapped (`Cannot convert value 'System.Byte[]' to type 'System.String[]'`). Open: #3302 (index tags it GLOBAL; labels `provider: sap-hana`, `status: has-pr`) and PR #3303 "[SAP HANA] Arrays Support" (open, PROV-SAPHANA). Original question: discussion #3301 (closed, GLOBAL). Two items only, below the three-item cluster threshold; kept because both are open.
- **Stored procedure name escaping** -- #1740 "Linq To DB should escape procedure name (new API needed)" (open; index tags it GLOBAL; labels `provider: sap-hana`, `area: extensions`). Singleton; kept because it is open and provider-labelled.

## Resolved themes

- **SQL feature enablement for HANA 2 (APPLY, TOP, CTE, UPDATE FROM, LATERAL)** -- CROSS/OUTER APPLY (#3154, SQL-AST in index), TOP in subqueries (#1779), CTE (#3099), UPDATE FROM (#3196), LATERAL support for SAP HANA/MySQL (PR #3165). Closing PR ids for #1779, #3099, #3196 are not recorded in the index.
- **Parameter binding and ordering** -- "Parameter/Column not bound" and positional-parameter ordering: #1528 fixed by PR #1530 ("requires all parameters ordered"); #1685 (Sql.Expression with positional parameters) closed.
- **Nullable mapping and identity values** -- PR #1684 (mapper expression with nullable columns on SAP HANA) and PR #2742 (wrong identity returned on SapHana).
- **Client assembly loading and client versions** -- #239 (cannot load Sap.Data.Hana.dll) fixed by PR #629 and PR #1157 (GAC load); PR #1384 (ODP.NET GAC discovery); #4886 (newer HANA assembly versions, GLOBAL in index); PR #4887 (support for v6/v8 clients); #5535 (NU5019 HintPath, closed).
- **CI and test enablement** -- PR #2720 (enable SAP HANA on CI), PR #4566 (update deps, fix saphana scripts), PR #4361 (HANA docker fixes, GLOBAL in index), PR #1872 (Azure DevOps HANA support, INFRA in index).
- **Closed issues sharing the hana keyword (sample)** -- #13, #154, #239, #1462, #1528, #2443, #3719, #1779.

## Active discussions

- No active discussions. (#4270 "Linq2DB still support SAP HANA ?" is closed, category General.)

## Stats

- Open issues: 2 (#5862, #5940)
- Closed issues: 13
- Open PRs: 1 (#3303)
- Total PRs: 16
- Discussions: 1 (#4270, closed)
- Last fetched: 2026-10-09 (index data through 2026-10-09)

<details><summary>Coverage</summary>

- Index entries scanned: 43 (21 issues + 20 PRs + 2 discussions), of which PROV-SAPHANA-tagged: 15 issues + 16 PRs + 1 discussion; the rest are HANA-titled or `provider: sap-hana`-labelled items tagged to other areas.
- Themes extracted: 9 (4 open + 5 resolved)
</details>
