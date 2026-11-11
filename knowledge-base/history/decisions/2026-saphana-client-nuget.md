---
area: GLOBAL
kind: decision
sources: [git]
confidence: high
last_verified: 2026-11-11
last_verified_sha: f90c5bcfb86d88db436a6494f0640c4c43dd691f
---

# Source the SAP HANA client from SAP's NuGet packages

## Context
Tests used a checked-in 2.23.27 copy of the HANA .NET client under `Redist/SapHana`, and `Sap.Data.Hana.v4.5.dll` was packed into linq2db.SapHana and linq2db.t4models (#5862).

## Decision
Tests take the client from `Sap.Data.Hana.Net.v8.0` (net8.0/net9.0) and `Sap.Data.Hana.Net.v10.0` (net10.0), version 2.30.27, natives included. `Redist/SapHana/v8.0` and native PDBs were deleted. The 2.23.27 natives remain for net462 only (the client requires the native's major.minor.build to equal its own and no package carries the .NET Framework client). The net10.0 linq2db build probes `Sap.Data.Hana.Net.v10.0` first, the detector maps that name to the native provider, the net8 list is unchanged. `Sap.Data.Hana.v4.5.dll` is no longer packed and the `sap-hana-client` licence component was removed.

## Why
Per the body: no redistribution terms are on record for the v4.5 DLL, and the copy cannot connect without an installed HANA client, which already provides it. The net8 list stays unchanged so LINQPad's .NET 8 host is never offered a net10.0 assembly.

## Consequences
- LINQPad 8+ driver provisions `Sap.Data.Hana.Net.v8.0` for the native provider and sets `HDBDOTNETCORE` via an AssemblyLoad handler. SAP HANA is not offered in Windows ARM64 LINQPad.
- x86 stubs (`HANASTUBS`) removed. `SapHana.Native` joined the Linux h_SAPHANA2 CI leg with its own `TESTDBNATIVE` schema.
- Native provider users need an installed client (noted in the T4 starter template).
- Related: `41849ec` (#6163) likewise sourced SQL Server Compact from the `Microsoft.SqlServer.Compact` 4.0.8876.1 package and deleted `Redist/SqlCe`, with byte-identical files and a `CheckSqlCeNatives` build guard.

## Sources
- Commit `1562369` -- Source the SAP HANA client from SAP's NuGet packages, probe v10.0, stop packing v4.5 (#6162) (MaceWindu, 2026-10-28)
- Commit `41849ec` -- Source SQL Server Compact from its NuGet package, retire Redist/SqlCe (#6163)
