<#
release-nuget-verify.ps1 — confirm every expected linq2db NuGet
package was published to nuget.org at the release version.

Discovery: scans Source/ and NuGet/ csproj files for packable
projects (skipping IsPackable=false). Each project's PackageId is
either its <PackageId> element or its filename without .csproj.
EF-variant projects (linq2db.EntityFrameworkCore.EF3.csproj etc.)
typically share a PackageId and dedupe by it.

Verification: for each unique PackageId, queries the nuget.org
flatcontainer index and checks whether <version> appears in the
listed versions. Listed-only — unlisted (yanked) versions are not
counted as published.

Push-log mode (authoritative — prefer it): -PushLog <path> takes the
expected list from the release build's 'Publish to Nuget.org' step log
(fetch it with azp-step-log.ps1) instead of csproj discovery. Every
`Pushing <id>.<ver>.nupkg` line becomes one expected package checked at
ITS OWN version, so the per-RID linq2db.cli.<rid> packages, linq2db.FSharp
and the EF-major-versioned linq2db.EntityFrameworkCore rows are all covered
(csproj discovery misses or mis-versions them). -Version is then optional.

Action:

  verify      Inputs:  -Version <ver>                 # the release version (discovery mode)
                       [-PushLog <path>]              # push-log mode, see above
                       [-Repo <owner/repo>]           (default: linq2db/linq2db)
                       [-SourceRoot <path>]
                       [-ExtraIds id1,id2,...]        # extra package IDs to verify
                                                       # (use when discovery misses one
                                                       # — e.g. dotnet-tool nuspec sourcing)
                       [-WaitMinutes <n>]             # poll until all are listed or n min pass
                       [-PollSeconds <n>]             (default: 120)
              Output:  {
                ok, version, source: 'push-log'|'discovery', complete,
                packages[]: { id, version, published, latestListed, hasTargetVersion, csproj? },
                counts: { total, published, missing }
              }
              `ok` reports fetch health, not publication — read `complete` / `counts.missing`.

nuget.org indexing lags the push: on 6.5.1, 0 of 40 packages were listed
6 min after the push and all 40 after ~25 min. Without -WaitMinutes the
script checks once; re-invoke, or pass -WaitMinutes to poll.

Conventions: `.claude/docs/script-authoring.md`.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('verify')]
    [string]$Action,

    [string]$Version,
    [string]$PushLog,
    [string]$Repo = 'linq2db/linq2db',
    [string]$SourceRoot,
    [string]$ExtraIds,
    [int]$WaitMinutes = 0,
    [int]$PollSeconds = 120,
    [int]$MaxParallel = 8
)

$global:ScriptBaseName = 'release-nuget-verify'
. (Join-Path $PSScriptRoot '_shared.ps1')

# -- exclusion (shared with release-deps-discover) ---------------------------

function Test-IsExcludedPath {
    param([string]$Path)
    if (-not $Path) { return $false }
    $norm = ($Path -replace '\\','/') + '/'
    return ($norm -match '/(\.build|\.git|bin|obj|node_modules|packages)/')
}

# -- packable-project discovery ----------------------------------------------

# Parse a csproj for IsPackable + PackageId. Returns @{ packable; id; csproj }.
# PackageId resolution order matches MSBuild's default:
#   1. <PackageId> if explicit
#   2. <AssemblyName> if set (defaults PackageId per Microsoft.NET.Sdk)
#   3. filename minus .csproj (final fallback)
# linq2db uses the AssemblyName form widely: filename `LinqToDB.csproj` carries
# AssemblyName `linq2db` → published PackageId `linq2db`. Without checking
# AssemblyName, the filename fallback would query `LinqToDB` and get a 404.
function Read-CsprojPackageInfo {
    param([string]$CsprojPath)
    $text = [System.IO.File]::ReadAllText($CsprojPath, [System.Text.UTF8Encoding]::new($false))
    $packable = $true
    if ($text -match '<IsPackable\s*>\s*false\s*</IsPackable\s*>') {
        $packable = $false
    }
    $id = $null
    # 1. Sibling .nuspec wins for projects with a custom packaging spec
    # (e.g. dotnet-tools where AssemblyName = `dotnet-linq2db` but the
    # nuspec id is `linq2db.cli`). NuspecFile in csproj also overrides
    # csproj-derived PackageId at pack time.
    if ($text -match '<NuspecFile\s*>\s*([^<]+?)\s*</NuspecFile\s*>') {
        $nuspecRel = $Matches[1].Trim()
        $nuspecAbs = if ([System.IO.Path]::IsPathRooted($nuspecRel)) { $nuspecRel }
                     else { Join-Path ([System.IO.Path]::GetDirectoryName($CsprojPath)) $nuspecRel }
        if (Test-Path -LiteralPath $nuspecAbs) {
            $nuspecText = [System.IO.File]::ReadAllText($nuspecAbs)
            if ($nuspecText -match '<id\s*>\s*([^<]+?)\s*</id\s*>') {
                $id = $Matches[1].Trim()
            }
        }
    }
    # Defensive: scan for sibling .nuspec even without explicit <NuspecFile>.
    if (-not $id) {
        $siblings = Get-ChildItem -LiteralPath ([System.IO.Path]::GetDirectoryName($CsprojPath)) -Filter '*.nuspec' -ErrorAction SilentlyContinue
        foreach ($n in $siblings) {
            $nuspecText = [System.IO.File]::ReadAllText($n.FullName)
            if ($nuspecText -match '<id\s*>\s*([^<]+?)\s*</id\s*>') {
                $id = $Matches[1].Trim()
                break
            }
        }
    }
    # 2. <PackageId> in csproj
    if (-not $id -and $text -match '<PackageId\s*>\s*([^<]+?)\s*</PackageId\s*>') {
        $id = $Matches[1].Trim()
    }
    # 3. <AssemblyName> defaults PackageId per Microsoft.NET.Sdk
    if (-not $id -and $text -match '<AssemblyName\s*>\s*([^<]+?)\s*</AssemblyName\s*>') {
        $id = $Matches[1].Trim()
    }
    # 4. filename fallback
    if (-not $id) {
        $id = [System.IO.Path]::GetFileNameWithoutExtension($CsprojPath)
    }
    return @{ packable = $packable; id = $id; csproj = $CsprojPath }
}

function Find-PackableProjects {
    param([string]$Root)
    $sourceDir = Join-Path $Root 'Source'
    $nugetDir  = Join-Path $Root 'NuGet'
    $files = @()
    if (Test-Path -LiteralPath $sourceDir) {
        $files += @(Get-ChildItem -Path $sourceDir -Recurse -Filter '*.csproj' -ErrorAction SilentlyContinue |
            Where-Object { -not (Test-IsExcludedPath $_.FullName) })
    }
    if (Test-Path -LiteralPath $nugetDir) {
        $files += @(Get-ChildItem -Path $nugetDir -Recurse -Filter '*.csproj' -ErrorAction SilentlyContinue |
            Where-Object { -not (Test-IsExcludedPath $_.FullName) })
    }
    $byId = @{}
    foreach ($f in $files) {
        $info = Read-CsprojPackageInfo -CsprojPath $f.FullName
        if (-not $info.packable) { continue }
        # Dedupe by PackageId — multiple csproj can share an id (EF variants).
        # Keep the first encountered csproj path for reporting.
        if (-not $byId.ContainsKey($info.id)) {
            $byId[$info.id] = $info.csproj
        }
    }
    $rows = New-Object 'System.Collections.Generic.List[object]'
    foreach ($id in ($byId.Keys | Sort-Object)) {
        $rows.Add(@{ id = $id; csproj = $byId[$id] }) | Out-Null
    }
    return $rows.ToArray()
}

# -- verify (main) -----------------------------------------------------------

function Get-ExpectedFromPushLog {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { Exit-WithError "push log not found: $Path" }
    $rows = New-Object 'System.Collections.Generic.List[object]'
    $seen = @{}
    foreach ($m in (Select-String -LiteralPath $Path -Pattern 'Pushing (?<id>\S+?)\.(?<ver>\d+\.\d+\.\d+(?:-[0-9A-Za-z.\-]+)?)\.nupkg')) {
        $id  = $m.Matches[0].Groups['id'].Value
        $ver = $m.Matches[0].Groups['ver'].Value
        $key = "$id|$ver"
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $rows.Add(@{ id = $id; version = $ver; csproj = $null }) | Out-Null
    }
    if ($rows.Count -eq 0) { Exit-WithError "no 'Pushing <id>.<ver>.nupkg' lines in $Path" }
    return $rows.ToArray()
}

function Get-ExpectedFromDiscovery {
    if (-not $Version) { Exit-WithError '-Version is required unless -PushLog is given' }
    $root = if ($SourceRoot) { $SourceRoot } else { Get-Location | Select-Object -ExpandProperty Path }

    $discovered = Find-PackableProjects -Root $root
    $extras = @()
    if ($ExtraIds) {
        $extras = $ExtraIds -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }
    # Merge extras with discovery, marking extras as "supplied" (no csproj).
    $idMap = @{}
    foreach ($d in $discovered) { $idMap[$d.id] = $d.csproj }
    foreach ($e in $extras) {
        if (-not $idMap.ContainsKey($e)) { $idMap[$e] = $null }
    }
    if ($idMap.Count -eq 0) {
        Exit-WithError "no packable projects discovered under $root and no -ExtraIds given"
    }
    return @($idMap.Keys | Sort-Object | ForEach-Object { @{ id = $_; version = $Version; csproj = $idMap[$_] } })
}

function Do-Verify {
    $source   = if ($PushLog) { 'push-log' } else { 'discovery' }
    $expected = if ($PushLog) { Get-ExpectedFromPushLog -Path $PushLog } else { Get-ExpectedFromDiscovery }
    $deadline = (Get-Date).AddMinutes($WaitMinutes)

    while ($true) {
        $packages = Test-Expected -Expected $expected
        $missing  = @($packages | Where-Object { -not $_.published }).Count
        if ($missing -eq 0 -or (Get-Date) -ge $deadline) { break }
        Write-Verbose "$missing of $($packages.Count) not listed yet; retrying in $PollSeconds s"
        Start-Sleep -Seconds $PollSeconds
    }

    Write-JsonOutput @{
        ok       = $true
        action   = 'verify'
        version  = $Version
        source   = $source
        repo     = $Repo
        complete = ($missing -eq 0)
        packages = $packages
        counts   = @{
            total     = $packages.Count
            published = $packages.Count - $missing
            missing   = $missing
        }
    }
}

function Test-Expected {
    param([object[]]$Expected)
    $ids = @($Expected | ForEach-Object { $_.id } | Sort-Object -Unique)

    # Parallel fetch listed versions for each ID. flatcontainer index.json
    # returns listed versions only (unlisted/deleted are absent).
    $results = $ids | ForEach-Object -ThrottleLimit $MaxParallel -Parallel {
        $id = $_
        $lcid = $id.ToLowerInvariant()
        $url = "https://api.nuget.org/v3-flatcontainer/$lcid/index.json"
        try {
            $resp = Invoke-RestMethod -Uri $url -TimeoutSec 30 -UseBasicParsing
            [pscustomobject]@{ id = $id; versions = @($resp.versions); status = 'ok'; error = $null }
        } catch {
            $code = $null
            if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
            $status = if ($code -eq 404) { 'not-found' } else { 'error' }
            [pscustomobject]@{ id = $id; versions = @(); status = $status; error = $_.Exception.Message }
        }
    }

    $byId = @{}
    foreach ($r in $results) { $byId[$r.id] = $r }

    $packages = New-Object 'System.Collections.Generic.List[object]'
    foreach ($e in $Expected) {
        $r = $byId[$e.id]
        $hasTarget = ($r.versions -contains $e.version)
        $latest = $null
        if ($r.versions.Count -gt 0) {
            # Best-effort latest: take the lexically-greatest version. Not a
            # semver-aware comparison, but good enough for "what's the most
            # recent version published?" diagnostic display.
            $latest = $r.versions | Sort-Object -Descending | Select-Object -First 1
        }
        $packages.Add([ordered]@{
            id               = $e.id
            version          = $e.version
            csproj           = $e.csproj
            published        = $hasTarget
            hasTargetVersion = $hasTarget
            latestListed     = $latest
            fetchStatus      = $r.status
            fetchError       = $r.error
        }) | Out-Null
    }
    return $packages.ToArray()
}

# -- dispatch ----------------------------------------------------------------

switch ($Action) {
    'verify' { Do-Verify }
    default  { Exit-WithError "unknown action: $Action" }
}
