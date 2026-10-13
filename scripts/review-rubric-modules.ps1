#!/usr/bin/env pwsh
#requires -Version 7
<#
.SYNOPSIS
	Select the code-reviewer rubric modules a diff needs, from its changed paths.

.DESCRIPTION
	Path-triggered rules of the code-reviewer rubric live in docs/review-rubric/rubric-*.md
	instead of agents/code-reviewer.md. This script maps changed paths to the modules whose
	rules can fire on them; dispatchers brief the result as `rubricModules`.

	Per path, the union of every matching row:
	  tests      Source/** code (.cs .fs .vb .tt .ttinclude), Tests/**, DataProviders.json,
	             UserDataProviders.json*
	  ci-infra   .github/ Build/ .githooks/ .vscode/ .cursor/ .gemini/ .claude (incl. the gitlink),
	             project / props / targets / yml / yaml, global.json, *.sln*, .editorconfig,
	             nuget.config, .cmd/.ps1/.sh outside Source/ and Tests/, binary extensions
	  packaging  Source/**/*.csproj|fsproj, Directory.*.props, NuGet/, Build/licenses/, Redist/,
	             Source/** non-code except the API-baseline and analyzer-config files
	  tooling    Source/LinqToDB.{CLI,Scaffold,Templates,LINQPad}/**, NuGet/**/*.tt*
	A path no row matches selects nothing when it is documentation or an API-baseline /
	analyzer-config file, and every module otherwise (reported in `unmatched`).

	`byFocus` maps each review focus to the selected modules holding a rule of that focus,
	read from the `[module]` marks in the core rubric's Focus scoping index.

.PARAMETER Paths
	Changed paths, repo-relative with forward slashes.

.PARAMETER PathsFile
	File with one changed path per line (alternative to -Paths).

.PARAMETER Base
	Compute the paths instead: `git diff --name-only <Base>...HEAD` plus every path
	`git status --porcelain` reports (uncommitted and untracked), in -RepoRoot.

.PARAMETER RepoRoot
	Repository for -Base. Defaults to the superproject the corpus is mounted in.

.OUTPUTS
	{ paths: <count>, modules: [path], byFocus: { <focus>: [path] }, unmatched: [path] }
	A single `focus: "all"` pass takes `modules`; byFocus has no `all` key.
	Module entries are superproject-relative paths, e.g. `.claude/docs/review-rubric/rubric-tests.md`.
#>
[CmdletBinding()]
param(
	[string[]]$Paths,
	[string]$PathsFile,
	[string]$Base,
	[string]$RepoRoot
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/_shared.ps1"
$global:ScriptBaseName = 'review-rubric-modules'

$corpus = (Resolve-Path "$PSScriptRoot/..").Path

if ($Base) {
	if (-not $RepoRoot) { $RepoRoot = (Resolve-Path "$corpus/..").Path }
	$committed = @(& git -C $RepoRoot diff --name-only "$Base...HEAD")
	if ($LASTEXITCODE -ne 0) { Exit-WithError "git diff --name-only $Base...HEAD failed in $RepoRoot" -NextAction 'fetch the base ref, or pass -RepoRoot <repo>' }
	$status = @(& git -C $RepoRoot status --porcelain --untracked-files=all)
	if ($LASTEXITCODE -ne 0) { Exit-WithError "git status failed in $RepoRoot" -NextAction 'pass -RepoRoot <repo>' }
	# porcelain v1: `XY path` or `XY old -> new`; quoted when the path has special characters
	$working = foreach ($l in $status) {
		$p = $l.Substring(3)
		if ($p -match ' -> (.+)$') { $p = $Matches[1] }
		$p.Trim('"')
	}
	$Paths = @($committed) + @($working)
}
elseif ($PathsFile) {
	if (-not (Test-Path -LiteralPath $PathsFile)) { Exit-WithError "paths file not found: $PathsFile" -NextAction 'write one changed path per line to the file' }
	$Paths = @(Get-Content -LiteralPath $PathsFile)
}

$Paths = @($Paths | ForEach-Object { "$_".Trim() -replace '\\', '/' } | Where-Object { $_ } | Sort-Object -Unique)
if ($Paths.Count -eq 0 -and -not $Base) { Exit-WithError 'no paths given' -NextAction 'pass -Paths, -PathsFile or -Base' }

$binary  = '\.(dll|exe|pdb|so|dylib|zip|nupkg|snupkg|7z|png|jpe?g|gif|webp|ico|bmp|svg|pdf|sqlite|mdb|accdb|sdf|db|bin)$'
$noneSet = '(^|/)PublicAPI[^/]*\.txt$|(^|/)CompatibilitySuppressions\.xml$|^Source/BannedSymbols\.txt$|^Source/CodeMetricsConfig\.txt$|\.DotSettings$'
$code    = '\.(cs|fs|vb|tt|ttinclude)$'

$rows = [ordered]@{
	'tests' = @(
		"^Source/.*$code"
		'^Tests/'
		'^DataProviders\.json$'
		'^UserDataProviders\.json'
	)
	'ci-infra' = @(
		'^\.github/', '^Build/', '^\.githooks/', '^\.vscode/', '^\.cursor/', '^\.gemini/', '^\.claude(/|$)'
		'\.(csproj|fsproj|vbproj|props|targets|ya?ml)$'
		'(^|/)global\.json$', '\.sln[a-z]*$', '(^|/)\.editorconfig$', '(^|/)nuget\.config$'
		'^(?!Source/|Tests/).*\.(cmd|ps1|sh)$'
		$binary
	)
	'packaging' = @(
		'^Source/.*\.(csproj|fsproj)$'
		'(^|/)Directory\.[^/]+\.props$'
		'^NuGet/', '^Build/licenses/', '^Redist/'
		{ param($p) $p -match '^Source/' -and $p -notmatch $code -and $p -notmatch $noneSet }
	)
	'tooling' = @(
		'^Source/LinqToDB\.(CLI|Scaffold|Templates|LINQPad)/'
		'^NuGet/.*\.tt[^/]*$'
	)
}
$none = "^(?!Source/|Tests/).*\.(md|txt)$|$noneSet"

function Get-ModulePath([string]$name) { ".claude/docs/review-rubric/rubric-$name.md" }

$selected  = [Collections.Generic.HashSet[string]]::new()
$unmatched = [Collections.Generic.List[string]]::new()
foreach ($p in $Paths) {
	$hit = $false
	foreach ($name in $rows.Keys) {
		foreach ($rx in $rows[$name]) {
			$match = if ($rx -is [scriptblock]) { & $rx $p } else { $p -match $rx }
			if ($match) { [void]$selected.Add($name); $hit = $true; break }
		}
	}
	if ($hit) { continue }
	if ($p -match $none) { continue }
	$unmatched.Add($p)
	foreach ($name in $rows.Keys) { [void]$selected.Add($name) }
}

# byFocus from the core index: `N (title) [module]` entries inside each `- **`<focus>`**` line.
$core = [IO.File]::ReadAllLines((Join-Path $corpus 'agents/code-reviewer.md'))
$byFocus = [ordered]@{}
foreach ($l in $core) {
	if ($l -notmatch '^- \*\*`([a-z-]+)`\*\* — ') { continue }
	$focus = $Matches[1]
	$mods  = @([regex]::Matches($l, '\d+ \([^)]*\) \[([a-z-]+)\]') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
	foreach ($m in $mods) {
		if (-not $rows.Contains($m)) { Exit-WithError "core index marks unknown module [$m]" -NextAction "add a '$m' row to this script or fix the mark in agents/code-reviewer.md" }
	}
	$byFocus[$focus] = @($mods | Where-Object { $selected.Contains($_) } | ForEach-Object { Get-ModulePath $_ })
}
if ($byFocus.Count -ne 3) { Exit-WithError "expected 3 focus lines in the core index, found $($byFocus.Count)" -NextAction 'check the Focus scoping list format in agents/code-reviewer.md' }

Write-JsonOutput ([pscustomobject]@{
	paths     = $Paths.Count
	modules   = @($rows.Keys | Where-Object { $selected.Contains($_) } | ForEach-Object { Get-ModulePath $_ })
	byFocus   = [pscustomobject]$byFocus
	unmatched = @($unmatched)
})
