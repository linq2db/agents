#!/usr/bin/env pwsh
<#
Run one scratch probe test in two arms - the tree as it stands, and the tree with `Source/`
swapped to another ref - and prove each arm ran the code it claims, in one call.

Why this script exists
----------------------
"Does this behaviour predate the change?" is answered by running the same probe against two
versions of `Source/`. By hand that is about ten calls per comparison, and several of them have
a documented way to go quietly wrong (`.claude/docs/evidence-discipline.md`):

  1. The swap must be no-overlay: `git restore --source=<ref> --staged --worktree -- Source/`.
     `git checkout <ref> -- Source/` keeps files only the previous arm had, so the next arm
     builds them.
  2. The tree has to be proven after the swap, and restored afterwards even when a run fails.
  3. Identical output from both arms is exactly what a stale build produces. A tree check says
     what should have been built, not what ran - so with -Marker each arm's built `linq2db.dll`
     is searched for an identifier only one arm's source contains.
  4. The probe is linked into `Tests.Playground` for a fast build, and the link is playground
     scratch that must not survive the run.

Contract
--------

Input (named parameters; plain strings and switches, so `pwsh -File` binds them as declared):
  -RepoRoot       <path>    required; the worktree root (absolute)
  -ControlRef     <ref>     required; the ref whose `Source/` the control arm builds - usually the
                            merge base of the change under test
  -ProbeFile      <path>    required; the scratch test file, relative to RepoRoot. Linked into
                            `Tests/Tests.Playground/Tests.Playground.csproj` for the run only; the
                            file itself is the caller's and is left in place.
  -Filter         <string>  required; the probe's test filter, e.g. `FullyQualifiedName~MyProbe`.
                            `FullyQualifiedName~CreateData.CreateDatabase|` is prepended.
  -Provider       <string>  required; comma-separated provider ids, passed to --provider
  -Marker         <string>  optional; an identifier present in exactly one arm's source - a private
                            method the change adds is ideal, a generic name matches both arms
  -Configuration  <string>  optional; default Debug
  -ScratchBaselines         optional; write a RepoRoot-local `UserDataProviders.json` copied from
                            the nearest one above RepoRoot with `BaselinesPath` pointed into
                            `.build/.agents/`, so a nested worktree's runs cannot write into the
                            primary clone's baselines folder. Removed at the end. Refused when
                            RepoRoot already has its own `UserDataProviders.json`.
  -StopLanguageServer       optional; stop any `csharp-ls` process before each arm's build - it
                            intermittently locks `CodeGenerators.dll` and fails the build with
                            MSB3027.

The probe tells the arms apart through `$env:PROBE_ARM` (`head` / `control`): have it write its
findings to a file whose name includes that value.

RepoRoot must have no tracked changes - the swap and the link are undone by restoring HEAD. The
untracked probe file is the only expected difference.

Output (stdout, single JSON object):
  {
    "ok": true,
    "controlRef": "7c5d5b5ae8...",
    "marker": "AsDateTime64",
    "markerDiscriminates": true,     // null without -Marker
    "swapOk": true,                  // Source/ matched ControlRef exactly before the control arm
    "treeRestored": true,            // no tracked changes left afterwards
    "scratchBaselines": "...",       // what -ScratchBaselines did, null without it
    "arms": [
      { "name": "head",    "sourceRef": "HEAD",         "exitCode": 0, "buildFailed": false,
        "summary": { "total": 3, "failed": 0, ... }, "failedTests": [], "markerPresent": true,
        "logPath": "..." },
      { "name": "control", "sourceRef": "7c5d5b5ae8...", ... "markerPresent": false, ... }
    ]
  }

A failing test inside an arm is data, not a script failure - read it from that arm's summary.

Exit codes:
  0 = both arms built and ran, the tree is back at HEAD, and (with -Marker) the marker was
      present in exactly one arm
  1 = bad input, tracked changes in RepoRoot, a failed swap or build, a marker that did not
      discriminate, or a tree left dirty - inspect the JSON
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepoRoot,
    [Parameter(Mandatory)][string]$ControlRef,
    [Parameter(Mandatory)][string]$ProbeFile,
    [Parameter(Mandatory)][string]$Filter,
    [Parameter(Mandatory)][string]$Provider,
    [string]$Marker,
    [string]$Configuration = 'Debug',
    [switch]$ScratchBaselines,
    [switch]$StopLanguageServer
)

. "$PSScriptRoot/_shared.ps1"

$global:ScriptBaseName = 'ab-probe'
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) {
    Exit-WithError -Message "RepoRoot not found: $RepoRoot" -NextAction 'pass -RepoRoot <absolute worktree path>'
}

$repoFull   = (Resolve-Path -LiteralPath $RepoRoot).Path
$probeFull  = Join-Path $repoFull $ProbeFile
$playground = Join-Path $repoFull 'Tests/Tests.Playground/Tests.Playground.csproj'
$agentsDir  = Join-Path $repoFull '.build/.agents'
$userConfig = Join-Path $repoFull 'UserDataProviders.json'

if (-not (Test-Path -LiteralPath $probeFull -PathType Leaf)) {
    Exit-WithError -Message "ProbeFile not found under RepoRoot: $probeFull" -NextAction 'pass -ProbeFile <path relative to RepoRoot>'
}

if (-not (Test-Path -LiteralPath $playground -PathType Leaf)) {
    Exit-WithError -Message "Tests.Playground project not found: $playground"
}

$providerList = @($Provider.Split(',', [StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim() })
if ($providerList.Count -eq 0) {
    Exit-WithError -Message 'Provider is empty' -NextAction 'pass -Provider <id>[,<id>]'
}

$rev = Invoke-Git -ArgumentList @('rev-parse', '--verify', "$ControlRef^{commit}") -WorkingDirectory $repoFull
if (-not $rev.ok) {
    Exit-WithError -Message "ControlRef does not resolve to a commit: $ControlRef" -NextAction 'fetch the ref first, or pass a commit SHA'
}
$controlSha = $rev.stdout.Trim()

$status = Invoke-Git -ArgumentList @('status', '--porcelain=v1', '--untracked-files=no') -WorkingDirectory $repoFull
if (-not $status.ok) {
    Exit-WithError -Message "git status failed: $($status.error)"
}
if ($status.stdout.Trim()) {
    Exit-WithError -Message "RepoRoot has tracked changes:`n$($status.stdout.Trim())" -NextAction 'commit or set aside the tracked changes; only the untracked probe file may differ'
}

# Everything below is computed before the first write, so a refusal leaves the tree untouched.

$configText    = $null
$baselinesNote = $null

if ($ScratchBaselines) {
    if (Test-Path -LiteralPath $userConfig) {
        Exit-WithError -Message 'RepoRoot already has its own UserDataProviders.json' -NextAction 'drop -ScratchBaselines, or move that file aside'
    }

    $source = $null
    $parent = Split-Path -Parent $repoFull
    while ($parent) {
        $candidate = Join-Path $parent 'UserDataProviders.json'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $source = $candidate
            break
        }
        $parent = Split-Path -Parent $parent
    }

    if ($source) {
        $text       = [System.IO.File]::ReadAllText($source)
        $scratchDir = Join-Path $agentsDir ('ab-probe-baselines-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        $escaped    = $scratchDir.Replace('\', '\\')
        $pattern    = '("BaselinesPath"\s*:\s*")([^"]*)(")'

        if ([regex]::IsMatch($text, $pattern)) {
            $configText    = [regex]::Replace($text, $pattern, { param($m) $m.Groups[1].Value + $escaped + $m.Groups[3].Value })
            $baselinesNote = "BaselinesPath of $source redirected to $scratchDir"
        }
        else {
            $baselinesNote = "$source sets no BaselinesPath; nothing to redirect"
        }
    }
    else {
        $baselinesNote = 'no UserDataProviders.json above RepoRoot; nothing to redirect'
    }
}

$csprojBytes = [System.IO.File]::ReadAllBytes($playground)
$csprojText  = [System.IO.File]::ReadAllText($playground)
$nl          = if ($csprojText.Contains("`r`n")) { "`r`n" } else { "`n" }
$csprojLines = [System.Collections.Generic.List[string]]::new([System.IO.File]::ReadAllLines($playground))

$lastCompile = -1
for ($i = 0; $i -lt $csprojLines.Count; $i++) {
    if ($csprojLines[$i] -match '<Compile Include=') { $lastCompile = $i }
}
if ($lastCompile -lt 0) {
    Exit-WithError -Message "no <Compile Include> line in $playground to anchor the probe link on"
}

$indent  = [regex]::Match($csprojLines[$lastCompile], '^\s*').Value
$include = [System.IO.Path]::GetRelativePath((Split-Path -Parent $playground), $probeFull)
$link    = [System.IO.Path]::GetFileName($probeFull)
$csprojLines.Insert($lastCompile + 1, "$indent<Compile Include=""$include"" Link=""$link"" />")

$linkedText = ($csprojLines -join $nl)
if ($csprojText.EndsWith("`n")) { $linkedText += $nl }

if (-not (Test-Path -LiteralPath $agentsDir)) {
    New-Item -ItemType Directory -Force -Path $agentsDir | Out-Null
}

function Invoke-Arm {
    param([string]$Name, [string]$SourceRef)

    if ($StopLanguageServer) {
        Get-Process -Name 'csharp-ls' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }

    $env:PROBE_ARM = $Name
    $log = Join-Path $agentsDir "ab-probe-$Name.log"

    $json = & "$PSScriptRoot/worktree-test.ps1" `
        -RepoRoot      $repoFull `
        -Project       'Tests/Tests.Playground/Tests.Playground.csproj' `
        -Tfm           'net10.0' `
        -Configuration $Configuration `
        -Filter        "FullyQualifiedName~CreateData.CreateDatabase|$Filter" `
        -Provider      $providerList `
        -LogPath       $log | Out-String
    $exitCode = $LASTEXITCODE

    $run = $null
    try { $run = $json | ConvertFrom-Json } catch { }

    $failed = @()
    if ($run -and $run.failedTests) { $failed = @($run.failedTests) }

    $markerPresent = $null
    if ($Marker) {
        $dll = Join-Path $repoFull ".build/bin/Tests.Playground/$Configuration/net10.0/linq2db.dll"
        if (Test-Path -LiteralPath $dll) {
            $markerPresent = [bool](Select-String -LiteralPath $dll -Pattern $Marker -SimpleMatch -Quiet)
        }
    }

    [ordered]@{
        name          = $Name
        sourceRef     = $SourceRef
        exitCode      = $exitCode
        buildFailed   = if ($run) { [bool]$run.buildFailed } else { $true }
        summary       = if ($run) { $run.summary } else { $null }
        failedTests   = $failed
        markerPresent = $markerPresent
        logPath       = $log
    }
}

$arms         = [System.Collections.Generic.List[object]]::new()
$swapOk       = $false
$treeRestored = $false
$wroteConfig  = $false

try {
    if ($configText) {
        [System.IO.File]::WriteAllText($userConfig, $configText, [System.Text.UTF8Encoding]::new($false))
        $wroteConfig = $true
    }

    [System.IO.File]::WriteAllText($playground, $linkedText, [System.Text.UTF8Encoding]::new($false))

    $arms.Add((Invoke-Arm -Name 'head' -SourceRef 'HEAD'))

    $swap = Invoke-Git -ArgumentList @('restore', "--source=$controlSha", '--staged', '--worktree', '--', 'Source/') -WorkingDirectory $repoFull
    if ($swap.ok) {
        $same   = Invoke-Git -ArgumentList @('diff', '--quiet', $controlSha, '--', 'Source/') -WorkingDirectory $repoFull
        $swapOk = $same.ok
    }
    else {
        [Console]::Error.WriteLine("ab-probe: swap to $controlSha failed: $($swap.error)")
    }

    if ($swapOk) {
        $arms.Add((Invoke-Arm -Name 'control' -SourceRef $controlSha))
    }
}
finally {
    Invoke-Git -ArgumentList @('restore', '--source=HEAD', '--staged', '--worktree', '--', 'Source/') -WorkingDirectory $repoFull | Out-Null
    [System.IO.File]::WriteAllBytes($playground, $csprojBytes)
    if ($wroteConfig) { Remove-Item -LiteralPath $userConfig -Force }
    Remove-Item Env:PROBE_ARM -ErrorAction SilentlyContinue

    $after        = Invoke-Git -ArgumentList @('status', '--porcelain=v1', '--untracked-files=no') -WorkingDirectory $repoFull
    $treeRestored = $after.ok -and -not $after.stdout.Trim()
}

$markerDiscriminates = $null
if ($Marker) {
    $markerDiscriminates = $false
    if ($arms.Count -eq 2 -and $null -ne $arms[0].markerPresent -and $null -ne $arms[1].markerPresent) {
        $markerDiscriminates = $arms[0].markerPresent -ne $arms[1].markerPresent
    }
}

$armsOk = $arms.Count -eq 2
foreach ($arm in $arms) {
    if ($arm.buildFailed -or $null -eq $arm.summary) { $armsOk = $false }
}

$ok = $armsOk -and $swapOk -and $treeRestored -and ($null -eq $markerDiscriminates -or $markerDiscriminates)

Write-JsonOutput -InputObject ([ordered]@{
    ok                  = $ok
    controlRef          = $controlSha
    marker              = if ($Marker) { $Marker } else { $null }
    markerDiscriminates = $markerDiscriminates
    swapOk              = $swapOk
    treeRestored        = $treeRestored
    scratchBaselines    = $baselinesNote
    arms                = @($arms)
})

if (-not $ok) { exit 1 }
