#!/usr/bin/env pwsh
<#
Compare a **locally captured** baselines tree against `linq2db.baselines` master and a PR's
baselines branch, and say — per file — which side the local capture agrees with.

Why this script exists
----------------------
The question "does my local run reproduce what CI captured?" comes up on every baselines
investigation, and hand-rolling it gets three things wrong on a regular basis:

  1. **Comparing by pattern instead of by bytes.** A regex written to detect the suspect shape
     matches the *clean* shape too, and reports every provider as affected. Byte equality is the
     only reliable comparison; a diff is for reading afterwards, not for deciding.
  2. **`Get-Content` without `-LiteralPath`.** Baseline file names contain `[` and `]`
     (`Issue3986Test1(SQLite.MS,[123, Ko, null]).sql`), which PowerShell treats as wildcards, so
     the read fails with "does not exist, or has been filtered by the -Include parameter".
  3. **Iterating the whole capture.** A `git show` per captured file is minutes of process spawns
     (5316 files timed out at ten). Only files in the branch's own delta can disagree
     meaningfully, so intersect first — that set is normally a handful.

Contract
--------

Input (named parameters):
  -Pr            <int>     required; PR number, resolves `origin/baselines/pr_<n>`
  -CapturePath   <path>    required; local BaselinesPath root (contains `<Provider>/Tests/...`)
  -BaselinesRepo <path>    optional; default `../linq2db.baselines`
  -Fetch                   optional; fetch master + the branch before comparing

Output (stdout, single JSON object):
  {
    "pr": 5737,
    "branch": "origin/baselines/pr_5737",
    "captured":        5316,        // files present locally
    "changedOnBranch": 167,         // files in origin/master...branch
    "compared":        5,           // intersection actually compared
    "notCaptured":     162,         // in the delta but never exercised locally
    "verdicts": { "matchesMaster": 1, "matchesBranch": 4, "matchesNeither": 0 },
    "files": [ { "path": "...", "verdict": "matches-master" }, ... ]
  }

`matches-branch` means the local run reproduced CI. `matches-master` means it did not — the local
run produced the pre-change SQL, which is the interesting case: it says the branch's content needs
a different explanation than "this code emits it".

Exit codes:
  0 = comparison completed
  1 = bad input (missing capture path / branch not found)
#>

param(
	[Parameter(Mandatory = $true)][int]$Pr,
	[Parameter(Mandatory = $true)][string]$CapturePath,
	[string]$BaselinesRepo = "../linq2db.baselines",
	[switch]$Fetch
)

$ErrorActionPreference = 'Stop'

function Fail([string]$message) {
	[Console]::Out.WriteLine((@{ error = $message } | ConvertTo-Json -Compress))
	exit 1
}

if (-not (Test-Path -LiteralPath $CapturePath)) { Fail "capture path not found: $CapturePath" }
if (-not (Test-Path -LiteralPath $BaselinesRepo)) { Fail "baselines repo not found: $BaselinesRepo" }

$repo   = (Resolve-Path -LiteralPath $BaselinesRepo).Path
$root   = (Resolve-Path -LiteralPath $CapturePath).Path
$branch = "origin/baselines/pr_$Pr"

if ($Fetch) {
	& git -C $repo fetch origin master --quiet
	& git -C $repo fetch origin "+refs/heads/baselines/pr_${Pr}:refs/remotes/baselines/pr_$Pr" --quiet
	# tracking-ref form per baselines-repo-layout.md; never diff FETCH_HEAD
	$branch = "refs/remotes/baselines/pr_$Pr"
}

& git -C $repo rev-parse --verify --quiet "$branch^{commit}" | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "branch not found: $branch (fetch it, or the PR produced no baselines)" }

# Local capture: relative POSIX paths, matching git's index form.
$captured = @{}
$rootLen  = $root.Length
foreach ($f in Get-ChildItem -LiteralPath $root -Recurse -File) {
	$rel = $f.FullName.Substring($rootLen).TrimStart('\', '/').Replace('\', '/')
	$captured[$rel] = $f.FullName
}

$changed = @(& git -C $repo diff --name-only "origin/master...$branch")

function Read-Blob([string]$ref, [string]$path) {
	$text = (& git -C $repo show "${ref}:${path}" 2>$null) -join "`n"
	if ($LASTEXITCODE -ne 0) { return $null }
	return $text.TrimEnd("`n")
}

$files   = @()
$counts  = @{ matchesMaster = 0; matchesBranch = 0; matchesNeither = 0 }
$missing = 0

foreach ($rel in $changed) {
	if (-not $captured.ContainsKey($rel)) { $missing++; continue }

	$local = ((Get-Content -Raw -LiteralPath $captured[$rel]) -replace "`r`n", "`n").TrimEnd("`n")
	$onMaster = Read-Blob 'origin/master' $rel
	$onBranch = Read-Blob $branch $rel

	$verdict =
		if ($local -eq $onBranch) { 'matches-branch' }
		elseif ($local -eq $onMaster) { 'matches-master' }
		else { 'matches-neither' }

	switch ($verdict) {
		'matches-branch'  { $counts.matchesBranch++ }
		'matches-master'  { $counts.matchesMaster++ }
		'matches-neither' { $counts.matchesNeither++ }
	}

	$files += [ordered]@{ path = $rel; verdict = $verdict }
}

[Console]::Out.WriteLine((
	[ordered]@{
		pr              = $Pr
		branch          = $branch
		captured        = $captured.Count
		changedOnBranch = $changed.Count
		compared        = $files.Count
		notCaptured     = $missing
		verdicts        = $counts
		files           = $files
	} | ConvertTo-Json -Depth 4
))
