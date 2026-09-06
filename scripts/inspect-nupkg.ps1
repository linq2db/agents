#!/usr/bin/env pwsh
<#
Inspect what a NuGet package ACTUALLY ships - its dependency ranges, its lib
assemblies per TFM, and optionally the strings inside those assemblies.

Why this script exists
----------------------
`.claude/AGENTS.md` and `agent-rules.md` both say a cited external precedent is
a claim: check the SHIPPED artifact, not the source repo, because shared props /
imported targets / generated metadata supply what a visible csproj omits. They
say it without giving you a way to do it, so the sequence gets hand-rolled -
`Invoke-WebRequest` the nupkg, `[System.IO.Compression.ZipFile]` it open, find
the nuspec, read the dependency groups, notice the assembly name. That is four
to six calls, and two of them have traps: `ExtractToFile` rejects its 3-argument
form when the entry arrives from a piped `Where-Object`, and the flat-container
URL wants the id and version lowercased.

Two questions this answers that nothing else does:

  1. "Does this version's dependency range fit the pins we already have?" -
     the `dependencies` output, compared against `Directory.Packages.props`. See
     `.claude/docs/release/nuget-package-notes.md` -> "Prefer the version whose
     dependencies the repo's pins already satisfy".
  2. "Is this fork actually a drop-in?" - `libFiles` shows a renamed assembly,
     and `-ScanPattern` shows renamed internal namespaces. A fork that renames
     its assembly changes what `DatabaseFacade.ProviderName` and friends report,
     which is a code change, not just a package swap.

Contract
--------

Input (named parameters):
  -Id            <string>  required; package id (case-insensitive)
  -Version       <string>  optional; defaults to the latest STABLE version
                           (prerelease versions - those containing '-' - are
                           skipped unless -IncludePrerelease)
  -ListVersions            optional; report the version list and exit without
                           downloading anything
  -IncludePrerelease       optional; allow a prerelease as the default -Version
  -ScanPattern   <regex>   optional; scan each lib assembly's raw bytes for this
                           regex and report the distinct matches with counts.
                           Use it to detect renamed namespaces in a fork, e.g.
                           -ScanPattern 'Microting\.[A-Za-z0-9_.]*'
  -Top           <int>     optional; cap on distinct -ScanPattern matches (20)
  -OutDir        <path>    optional; where to extract. Default
                           <cwd>/.build/.agents/nupkg-<id>-<version>

Output (stdout, single JSON object):
  {
    "id": "Microting.EntityFrameworkCore.MySql",
    "version": "10.0.10",
    "latestStable": "10.0.11",
    "versionCount": 16,
    "license": "MIT",
    "projectUrl": "https://github.com/...",
    "repositoryUrl": "https://github.com/...",
    "dependencies": [ { "targetFramework": "net10.0",
                        "packages": [ { "id": "...", "version": "[10.0.10, 10.0.999]" } ] } ],
    "libFiles":     [ { "tfm": "net10.0", "file": "Microting.EntityFrameworkCore.MySql.dll",
                        "assemblyName": "Microting.EntityFrameworkCore.MySql" } ],
    "scanMatches":  [ { "value": "Microting.EntityFrameworkCore.MySql.Storage.Internal", "count": 3 } ],
    "outDir": "C:/.../.build/.agents/nupkg-microting...-10.0.10"
  }

`scanMatches` is absent when -ScanPattern was not supplied.

Exit codes:
  0 = inspected successfully (or listed versions)
  1 = bad input, package/version not found, or the download failed
#>

param(
    [Parameter(Mandatory)][string]$Id,
    [string]$Version,
    [switch]$ListVersions,
    [switch]$IncludePrerelease,
    [string]$ScanPattern,
    [int]$Top = 20,
    [string]$OutDir
)

. "$PSScriptRoot/_shared.ps1"

$global:ScriptBaseName = 'inspect-nupkg'
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression.FileSystem

$idLower = $Id.ToLowerInvariant()
$base    = "https://api.nuget.org/v3-flatcontainer/$idLower"

try {
    $index = Invoke-RestMethod -Uri "$base/index.json" -MaximumRedirection 5
}
catch {
    Exit-WithError -Message "package not found on nuget.org: $Id ($($_.Exception.Message))" `
                   -NextAction 'check the package id spelling; ids are case-insensitive but must otherwise match exactly'
}

$all    = @($index.versions)
$stable = @($all | Where-Object { $_ -notmatch '-' })
$latestStable = if ($stable.Count) { $stable[-1] } else { $null }

if ($ListVersions) {
    Write-JsonOutput ([ordered]@{
        id           = $Id
        versionCount = $all.Count
        latestStable = $latestStable
        versions     = $all
    })
    exit 0
}

if (-not $Version) {
    $Version = if ($IncludePrerelease -or -not $latestStable) { $all[-1] } else { $latestStable }
}

if ($all -notcontains $Version) {
    Exit-WithError -Message "version '$Version' is not published for $Id (latest stable: $latestStable)" `
                   -NextAction 'run again with -ListVersions to see the published set'
}

$verLower = $Version.ToLowerInvariant()

if (-not $OutDir) {
    $OutDir = Join-Path (Get-Location).Path ".build/.agents/nupkg-$idLower-$verLower"
}
if (Test-Path -LiteralPath $OutDir) { Remove-Item -LiteralPath $OutDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$nupkg = Join-Path $OutDir "$idLower.$verLower.nupkg"

try {
    Invoke-WebRequest -Uri "$base/$verLower/$idLower.$verLower.nupkg" -OutFile $nupkg
}
catch {
    Exit-WithError -Message "download failed for $Id $Version ($($_.Exception.Message))" `
                   -NextAction 'retry; nuget.org flat-container fetches are occasionally transient'
}

# ExtractToDirectory, not ExtractToFile: the latter's 3-arg overload is not
# reachable when the entry comes from a piped Where-Object, which fails with a
# confusing "cannot find an overload ... argument count 3".
$extract = Join-Path $OutDir 'x'
[System.IO.Compression.ZipFile]::ExtractToDirectory($nupkg, $extract)

$nuspecFile = Get-ChildItem -LiteralPath $extract -Filter '*.nuspec' -File | Select-Object -First 1
if (-not $nuspecFile) {
    Exit-WithError -Message "no .nuspec inside $Id $Version" -NextAction 'inspect the extracted package manually at the outDir path'
}

[xml]$nuspec = Get-Content -LiteralPath $nuspecFile.FullName -Raw
$meta = $nuspec.package.metadata

$dependencies = @()
$groups = @($meta.dependencies.group)
if ($groups.Count -and $groups[0]) {
    foreach ($g in $groups) {
        $dependencies += [ordered]@{
            targetFramework = $g.targetFramework
            packages        = @(@($g.dependency) | Where-Object { $_ } | ForEach-Object {
                [ordered]@{ id = $_.id; version = $_.version }
            })
        }
    }
}
else {
    # Flat (ungrouped) <dependencies> - older packages.
    $flat = @($meta.dependencies.dependency) | Where-Object { $_ }
    if ($flat.Count) {
        $dependencies += [ordered]@{
            targetFramework = '(any)'
            packages        = @($flat | ForEach-Object { [ordered]@{ id = $_.id; version = $_.version } })
        }
    }
}

$libRoot  = Join-Path $extract 'lib'
$libFiles = @()
if (Test-Path -LiteralPath $libRoot) {
    foreach ($dll in Get-ChildItem -LiteralPath $libRoot -Recurse -Filter '*.dll' -File) {
        $asmName = $null
        try { $asmName = [System.Reflection.AssemblyName]::GetAssemblyName($dll.FullName).Name } catch { }
        $libFiles += [ordered]@{
            tfm          = $dll.Directory.Name
            file         = $dll.Name
            assemblyName = $asmName
        }
    }
}

$result = [ordered]@{
    id            = $meta.id
    version       = $meta.version
    latestStable  = $latestStable
    versionCount  = $all.Count
    license       = if ($meta.license) { $meta.license.InnerText } else { $null }
    projectUrl    = $meta.projectUrl
    repositoryUrl = if ($meta.repository) { $meta.repository.url } else { $null }
    dependencies  = $dependencies
    libFiles      = $libFiles
    outDir        = $OutDir
}

if ($ScanPattern) {
    $counts = @{}
    foreach ($dll in Get-ChildItem -LiteralPath $libRoot -Recurse -Filter '*.dll' -File) {
        $bytes = [System.IO.File]::ReadAllBytes($dll.FullName)
        $text  = [System.Text.Encoding]::ASCII.GetString($bytes)
        foreach ($m in [regex]::Matches($text, $ScanPattern)) {
            if ($counts.ContainsKey($m.Value)) { $counts[$m.Value]++ } else { $counts[$m.Value] = 1 }
        }
    }
    $result['scanMatches'] = @($counts.GetEnumerator() |
        Sort-Object -Property Value -Descending |
        Select-Object -First $Top |
        ForEach-Object { [ordered]@{ value = $_.Key; count = $_.Value } })
}

Write-JsonOutput $result
