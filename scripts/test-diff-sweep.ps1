#!/usr/bin/env pwsh
<#
Mechanical sweep of a branch's added test code for the two *Test layout* misses a hand sweep keeps
letting through:

  1. one-line call chains on an added line (`data.Select(r => r.D).ToArray()` inside an assertion) —
     testing.md -> *Test layout*, rule 1;
  2. narrowed provider sets on an added line (`[IncludeDataSources(...)]`, `[DataSources(<exclusions>)]`)
     with the nearest non-attribute line above (from three lines of diff context, so an unchanged comment
     further up shows as blank — open the file), so a missing or stale reason line is visible —
     testing.md -> *A narrowed provider set is a claim* -> *State the reason at the attribute*.

Why this script exists
----------------------
`/work-plan` amend step 4 asks for the branch's test diff to be swept against those rules and the result
recorded on the amendment's `conventions:` line. Done by hand it was done as a list of tests the author
remembered touching, and three review rounds on #5943 (2, 5, 6) each found a chain or a reason line in a
test the list omitted. This reads every added line instead.

It reports candidates, not verdicts: a chain inside a lambda body or a provider-specific translator test
with its reason in the test comment can be fine. Read each hit.

Invoke directly via the PowerShell tool:

    .claude\scripts\test-diff-sweep.ps1 -Repo C:\Worktrees\linq2db\<worktree>
    .claude\scripts\test-diff-sweep.ps1 -Repo <path> -Base origin/master -Path Tests/Linq

Contract
--------
  -Repo  <path>    required; the checkout whose branch is swept (a worktree)
  -Base  <ref>     default 'origin/master'; diffed as `<Base>...` (merge base), committed changes only
  -Path  <path>    default 'Tests/'
  -IncludeWorkingTree  also sweep uncommitted changes (`git diff <Base>` instead of `<Base>...`)

Output: one JSON document — { base, path, chains: [{file, line, text}], narrowedSets: [{file, line,
attribute, lineAbove}] }.
#>

param(
	[Parameter(Mandatory)][string]$Repo,
	[string]$Base = 'origin/master',
	[string]$Path = 'Tests/',
	[switch]$IncludeWorkingTree
)

$global:ScriptBaseName = 'test-diff-sweep'
. "$PSScriptRoot/_shared.ps1"

if (-not (Test-Path -LiteralPath $Repo)) {
	Exit-WithError "repo not found: $Repo" -NextAction 'pass the absolute path of the worktree to sweep'
}

$range = if ($IncludeWorkingTree) { $Base } else { "$Base..." }
$diff  = git -C $Repo diff -U3 $range -- $Path

if ($LASTEXITCODE -ne 0) {
	Exit-WithError "git diff $range failed in $Repo" -NextAction "fetch $Base, or pass -Base <ref> that exists in the repo"
}

$file   = ''
$line   = 0
$recent = [System.Collections.Generic.List[string]]::new()
$chains = @()
$sets   = @()

# the nearest preceding line that is not blank and not an attribute (`[Test]`, `[ActiveIssue(...)]`)
function Get-LineAbove {
	for ($i = $recent.Count - 1; $i -ge 0; $i--) {
		$t = ($recent[$i] -replace '^[+ ]', '').Trim()
		if ($t -and $t -notmatch '^\[') { return $t }
	}
	return ''
}

foreach ($l in $diff) {
	if ($l -match '^\+\+\+ b/(.*)')   { $file = $Matches[1]; continue }
	if ($l -match '^\+\+\+ ')          { continue }
	if ($l -match '^@@ .*\+(\d+)')    { $line = [int]$Matches[1] - 1; $recent.Clear(); continue }
	if ($l.StartsWith('-'))            { continue }

	$line++

	if ($l.StartsWith('+')) {
		$text = $l.Substring(1)

		# a call followed by `.Member(` on the same line, not a continuation line and not a comment
		if ($text -match '\)\s*\.\s*[A-Z]\w*\s*\(' -and $text -notmatch '^\s*\.' -and $text -notmatch '^\s*//') {
			$chains += [pscustomobject]@{ file = $file; line = $line; text = $text.Trim() }
		}

		if ($text -match '\[(IncludeDataSources|DataSources)\s*\((?<args>[^\]]*)\)') {
			$isNarrowed = $Matches[1] -eq 'IncludeDataSources' -or ($Matches['args'] -match '\S' -and $Matches['args'] -notmatch '^\s*(true|false)\s*$')

			if ($isNarrowed) {
				$sets += [pscustomobject]@{
					file      = $file
					line      = $line
					attribute = $Matches[0]
					lineAbove = Get-LineAbove
				}
			}
		}
	}

	$recent.Add($l)
	if ($recent.Count -gt 6) { $recent.RemoveAt(0) }
}

[ordered]@{
	base         = $range
	path         = $Path
	chains       = @($chains)
	narrowedSets = @($sets)
} | ConvertTo-Json -Depth 4
