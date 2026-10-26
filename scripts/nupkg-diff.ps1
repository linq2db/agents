#!/usr/bin/env pwsh
<#
Compare the contents of locally built .nupkg files, before vs after, entry by entry and by
SHA-256 - the check a packaging change needs and that no CI gate performs.

Why this script exists
----------------------
CI's package gates cannot see a silently missing file. `third-party-notices.ps1 -Action
verify` maps the files a package *has* to components, and a component whose `files` match
nothing is not a violation; the size check cannot see nine small natives. So a packaging PR
proves "ships the same bytes" by packing before and after and diffing the archives. On #6163
that was hand-rolled as two scratch scripts and run 15+ times (master, cold, warm, mutated and
CI-built packs), which is the shape this replaces. For a package published on nuget.org, use
`inspect-nupkg.ps1` instead.

Contract
--------

Input (named parameters):
  -Before <path>         required; a .nupkg file or a directory searched recursively for *.nupkg
  -After  <path>         required; same
  -Package <string[]>    optional; package ids to compare (case-insensitive). Default: every id
                         present on either side
  -IgnorePattern <regex> optional; entries whose hash difference is expected and reported apart
                         (`ignoredDiff`) rather than as `hashDiff`. Default: first-party
                         linq2db*.dll and the .nuspec, which embed the version and the
                         SourceLink commit and so differ between any two builds

Packages are matched by the <id> in their .nuspec, not by file name, so a before/after pair
with different versions (6.6.0-local.1 vs 6.6.0-dev.971) still lines up. Packaging metadata
(_rels/, package/, [Content_Types].xml, *.psmdcp) and nuget.org's .signature.p7s are skipped.

Output (stdout, single JSON object):
  {
    "identical": false,               // no onlyBefore / onlyAfter / hashDiff in any package,
                                      // and no package present on one side only
    "packages": [
      { "id": "linq2db.SqlCe", "beforeVersion": "6.6.0-local.1", "afterVersion": "6.6.0-dev.971",
        "beforeEntries": 58, "afterEntries": 58,
        "onlyBefore": [], "onlyAfter": [], "hashDiff": ["tools/THIRD-PARTY-NOTICES.txt"],
        "ignoredDiff": ["linq2db.SqlCe.nuspec", "tools/linq2db.dll"] }
    ],
    "onlyInBefore": [],               // package ids found on one side only
    "onlyInAfter":  []
  }

Exit codes:
  0 = compared; identical
  3 = compared; differences found (read the JSON)
  1 = bad input (path missing, no .nupkg found, unreadable archive)
#>

param(
    [Parameter(Mandatory)][string]$Before,
    [Parameter(Mandatory)][string]$After,
    [string[]]$Package,
    [string]$IgnorePattern = '(^|/)linq2db[^/]*\.dll$|\.nuspec$'
)

. "$PSScriptRoot/_shared.ps1"

$global:ScriptBaseName = 'nupkg-diff'
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-Nupkgs([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Exit-WithError -Message "path not found: $Path" -NextAction 'pass a .nupkg file or a directory that holds one'
    }
    $item = Get-Item -LiteralPath $Path
    $files = if ($item.PSIsContainer) { @(Get-ChildItem -LiteralPath $Path -Recurse -File -Filter '*.nupkg') } else { @($item) }
    if ($files.Count -eq 0) {
        Exit-WithError -Message "no .nupkg under $Path" -NextAction 'point at the pack output directory (e.g. .build/package/release)'
    }
    return , $files
}

# id -> @{ version; entries = @{ path -> sha256 } }
function Read-Side([string]$Path) {
    $side = @{}
    $sha = [System.Security.Cryptography.SHA256]::Create()
    foreach ($f in Get-Nupkgs $Path) {
        try { $zip = [System.IO.Compression.ZipFile]::OpenRead($f.FullName) }
        catch { Exit-WithError -Message "cannot open $($f.FullName): $($_.Exception.Message)" }
        try {
            $entries = @{}
            $id = $null; $version = $null
            foreach ($e in $zip.Entries) {
                $name = $e.FullName
                if ($name -match '^(_rels/|package/|\[Content_Types\]\.xml$|\.signature\.p7s$)' -or $name -match '\.psmdcp$') { continue }
                if ($name.EndsWith('/')) { continue }
                $s = $e.Open()
                try {
                    if ($name -match '^[^/]+\.nuspec$') {
                        $ms = [System.IO.MemoryStream]::new()
                        $s.CopyTo($ms)
                        $bytes = $ms.ToArray()
                        # Load from a stream: GetString keeps the BOM, which an [xml] cast rejects.
                        $x = [xml]::new()
                        $x.Load([System.IO.MemoryStream]::new($bytes))
                        $id = $x.package.metadata.id
                        $version = $x.package.metadata.version
                        $hash = $sha.ComputeHash($bytes)
                    }
                    else { $hash = $sha.ComputeHash($s) }
                }
                finally { $s.Dispose() }
                $entries[$name] = [System.BitConverter]::ToString($hash).Replace('-', '')
            }
        }
        finally { $zip.Dispose() }
        if (-not $id) { Exit-WithError -Message "no .nuspec id in $($f.FullName)" }
        $side[$id.ToLowerInvariant()] = @{ id = $id; version = $version; entries = $entries }
    }
    return $side
}

function Sort-Ordinal([string[]]$Values) {
    if (-not $Values -or $Values.Count -eq 0) { return , @() }
    $copy = [string[]]$Values.Clone()
    [Array]::Sort($copy, [System.StringComparer]::Ordinal)
    return , $copy
}

$b = Read-Side $Before
$a = Read-Side $After

$ids = Sort-Ordinal ([string[]](@($b.Keys) + @($a.Keys) | Select-Object -Unique))
if ($Package) {
    $want = @($Package | ForEach-Object { $_.ToLowerInvariant() })
    $ids = Sort-Ordinal ([string[]]($ids | Where-Object { $want -contains $_ }))
}

$packages = [System.Collections.Generic.List[object]]::new()
$onlyInBefore = [System.Collections.Generic.List[string]]::new()
$onlyInAfter  = [System.Collections.Generic.List[string]]::new()
$identical = $true

foreach ($k in $ids) {
    if (-not $a.ContainsKey($k)) { $onlyInBefore.Add($b[$k].id); $identical = $false; continue }
    if (-not $b.ContainsKey($k)) { $onlyInAfter.Add($a[$k].id);  $identical = $false; continue }
    $be = $b[$k].entries; $ae = $a[$k].entries
    $onlyB = Sort-Ordinal ([string[]]($be.Keys | Where-Object { -not $ae.ContainsKey($_) }))
    $onlyA = Sort-Ordinal ([string[]]($ae.Keys | Where-Object { -not $be.ContainsKey($_) }))
    $changed = @($be.Keys | Where-Object { $ae.ContainsKey($_) -and $be[$_] -ne $ae[$_] })
    $ignored = Sort-Ordinal ([string[]]($changed | Where-Object { $_ -match $IgnorePattern }))
    $diff    = Sort-Ordinal ([string[]]($changed | Where-Object { $_ -notmatch $IgnorePattern }))
    if ($onlyB.Count -or $onlyA.Count -or $diff.Count) { $identical = $false }
    $packages.Add([ordered]@{
        id            = $b[$k].id
        beforeVersion = $b[$k].version
        afterVersion  = $a[$k].version
        beforeEntries = $be.Count
        afterEntries  = $ae.Count
        onlyBefore    = $onlyB
        onlyAfter     = $onlyA
        hashDiff      = $diff
        ignoredDiff   = $ignored
    })
}

Write-JsonOutput ([ordered]@{
    identical    = $identical
    packages     = $packages
    onlyInBefore = $onlyInBefore
    onlyInAfter  = $onlyInAfter
})
exit $(if ($identical) { 0 } else { 3 })
