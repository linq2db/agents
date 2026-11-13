#!/usr/bin/env pwsh
<#
Mechanical sweep of a branch's added test code for the two *Test layout* misses a hand sweep keeps
letting through:

  1. one-line call chains on an added line (`data.Select(r => r.D).ToArray()` inside an assertion) —
     testing.md -> *Test layout*, rule 1;
  2. narrowed provider sets on an added line (`[IncludeDataSources(...)]`, `[DataSources(<exclusions>)]`)
     with the nearest non-attribute line above (from three lines of diff context, so an unchanged comment
     further up shows as blank — open the file), so a missing or stale reason line is visible —
     testing.md -> *A narrowed provider set is a claim* -> *State the reason at the attribute*;
  3. Shouldly-assertion gates (`[ActiveIssue]` / `[ThrowsForProvider]` naming `Shouldly`) whose
     `ErrorMessage` is the asserted expression (`records[2].FirstName`) and not a `should ...` clause —
     Shouldly writes the expression only when it can read the test source, so CI never matches it —
     testing.md -> *Gating an assertion failure*. (#6229: written against that rule, caught by the critic.)
  4. Shouldly-assertion gates with no `ErrorMessage` at all, the attribute read to its closing `)]` across
     lines — enough only when the test makes one Shouldly assertion, so read the body —
     testing.md -> *Gating an assertion failure*. (#6185 TO-27: two `ShouldBe`s under a type-only gate.)
  5. continuation lines of a split chain (`\t.Select(...)`) indented more than one tab past the line above —
     the drift a scripted split leaves (#5640 NIT018: two tabs past `passkey.Columns`, its siblings one).
     No written rule fixes the depth and some tests use two tabs after `var x = ...`, so a hit means "check it
     against the sibling chains in the same test". `.cs` files with tab indentation only; a shallower
     continuation (after query syntax or a wrapped argument list) is not reported. Measured over
     `origin/master~300...origin/master`: 9 hits.
  6. gates whose `ErrorMessage` is a rendered value (`{ Id = 1, …`, `[{ …`) not anchored as
     `should be{0}<expected>{1}but` — on an assertion failure that pins the order or value the engine
     happened to return, which another provider in the gate's set need not reproduce, and a gate with no
     `ErrorTypeName` never names `Shouldly`, so checks 3 and 4 cannot see it — testing.md ->
     *Gating an assertion failure*. (#6197 TO-80: pinned DuckDB's actual order; caught by the critic.)
     AssertQuery's `<actual> <> <expected>` form carries the expected value and is not reported. Measured
     over `origin/master~300...origin/master`: 0 hits; the #6197 gate is hit.

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
    .claude\scripts\test-diff-sweep.ps1 -Repo . -Ref origin/pr/5640      # no worktree needed

Contract
--------
  -Repo  <path>    required; the checkout whose branch is swept (a worktree), or any clone with -Ref
  -Base  <ref>     default 'origin/master'; diffed as `<Base>...` (merge base), committed changes only
  -Ref   <ref>     sweep `<Base>...<Ref>` instead of the checkout's HEAD (a PR head, a pushed branch)
  -Path  <path>    default 'Tests/'
  -IncludeWorkingTree  also sweep uncommitted changes (`git diff <Base>` instead of `<Base>...`) and untracked
                       files under -Path, every line counted as added; not with -Ref

Fixer for `chains` hits: `split-test-chains.ps1 -File <path> -Lines '<n,n,...>'` (read each hit first).

`chains` holds statement-level chains. A chain nested inside parentheses or braces - a call argument,
`new X(new DataOptions().UseConfiguration(...))`, an object initializer - goes to `nestedChains`:
on #5640 those were 35 of 148 hits and none was a layout defect.

Output: one JSON document — { base, path, chains: [{file, line, text}], nestedChains: [...],
narrowedSets: [{file, line, attribute, lineAbove, hasReason}], narrowedWithoutReason: [the narrowedSets entries whose
lineAbove is not a comment; a single-provider translator test is exempt, so read them], shouldlySubjectGates: [{file, line, errorMessage}],
typeOnlyShouldlyGates: [{file, line, text}], continuationIndents: [{file, line, text, expectedTabs, actualTabs}],
unanchoredAssertionGates: [{file, line, errorMessage}] }.
#>

param(
	[Parameter(Mandatory)][string]$Repo,
	[string]$Base = 'origin/master',
	[string]$Ref,
	[string]$Path = 'Tests/',
	[switch]$IncludeWorkingTree
)

$global:ScriptBaseName = 'test-diff-sweep'
. "$PSScriptRoot/_shared.ps1"

if (-not (Test-Path -LiteralPath $Repo)) {
	Exit-WithError "repo not found: $Repo" -NextAction 'pass the absolute path of the worktree to sweep'
}

if ($Ref -and $IncludeWorkingTree) {
	Exit-WithError '-Ref and -IncludeWorkingTree are exclusive' -NextAction 'drop one: -Ref sweeps a committed ref, -IncludeWorkingTree the checkout'
}

$range = if ($Ref) { "$Base...$Ref" } elseif ($IncludeWorkingTree) { $Base } else { "$Base..." }
$diff  = git -C $Repo diff -U3 $range -- $Path

if ($LASTEXITCODE -ne 0) {
	Exit-WithError "git diff $range failed in $Repo" -NextAction "fetch $Base, or pass -Base <ref> that exists in the repo"
}

# `git diff` never shows untracked files, and a new test file is the commonest thing to sweep (#4314)
if ($IncludeWorkingTree) {
	$diff = @($diff)
	foreach ($u in @(git -C $Repo ls-files --others --exclude-standard -- $Path)) {
		if ($u -notmatch '\.(cs|vb|fs)$') { continue }
		$diff += "+++ b/$u"
		$diff += '@@ -0,0 +1 @@'
		foreach ($t in (Get-Content -LiteralPath (Join-Path $Repo $u))) { $diff += "+$t" }
	}
}

$file   = ''
$line   = 0
$recent = [System.Collections.Generic.List[string]]::new()
$chains = @()
$nested = @()
$sets   = @()
$gates  = @()
$typeOnly    = @()
$indents     = @()
$unanchored  = @()
$pendingGate = $null

function Get-Tabs([string] $text) { return ([regex]::Match($text, '^\t*')).Length }

# the nearest preceding non-blank line in $recent, without its diff prefix
function Get-PreviousLine {
	for ($i = $recent.Count - 1; $i -ge 0; $i--) {
		$t = $recent[$i] -replace '^[+ ]', ''
		if ($t.Trim()) { return $t }
	}
	return $null
}

# `typeof(X)` / `nameof(X)` / `default(X)` / `sizeof(X)` are operands, not calls: `typeof(X).GetMethod(...)` is one call
function Remove-Operands([string] $text) {
	return [regex]::Replace($text, '\b(typeof|nameof|default|sizeof)\s*\([^()]*\)', 'x')
}

# `).Member(` after a call, also across property hops (`(await x).Succeeded.ShouldBeTrue(`, `).Name.Name.ShouldBe(`)
# and generic arguments (`).ShouldBeOfType<U>(`, or `<U<` left open where the type list wraps). #5640: the
# `\)\s*\.\s*[A-Z]\w*\s*\(` form missed 94 such chains.
$chainPattern = '\)(\s*\.\s*\w+)*\s*\.\s*[A-Z]\w*\s*(?:<[^()]*>\s*\(|<[^()]*$|\()'

# bracket depth at each `).Member(` on the line, string literals blanked first; 0 = statement level
function Get-ChainDepths([string] $text) {
	$t = [regex]::Replace($text, '"(?:[^"\\]|\\.)*"', { param($m) '"' + (' ' * ($m.Length - 2)) + '"' })
	$t = Remove-Operands $t
	$depths = @()
	foreach ($m in [regex]::Matches($t, $chainPattern)) {
		$d = 0
		for ($i = 0; $i -le $m.Index; $i++) {
			switch ($t[$i]) { '(' { $d++ } '{' { $d++ } ')' { $d-- } '}' { $d-- } }
		}
		# the `)` of the match closed one level, so the chain itself sits at $d
		$depths += $d
	}
	return $depths
}

# the nearest preceding line that is not blank and not an attribute (`[Test]`, `[ActiveIssue(...)]`)
function Get-LineAbove {
	for ($i = $recent.Count - 1; $i -ge 0; $i--) {
		$t = ($recent[$i] -replace '^[+ ]', '').Trim()
		if ($t -and $t -notmatch '^\[') { return $t }
	}
	return ''
}

foreach ($l in $diff) {
	if ($l -match '^\+\+\+ b/(.*?)\t?$') { $file = $Matches[1]; $pendingGate = $null; continue }
	if ($l -match '^\+\+\+ ')          { continue }
	if ($l -match '^@@ .*\+(\d+)')    { $line = [int]$Matches[1] - 1; $recent.Clear(); $pendingGate = $null; continue }
	if ($l.StartsWith('-'))            { continue }

	$line++

	# a multi-line gate attribute: its `ErrorMessage` may sit on a later line, added or context
	if ($pendingGate) {
		$body = if ($l.Length -gt 0) { $l.Substring(1) } else { '' }
		if ($body -match 'ErrorMessage\s*=') { $pendingGate = $null }
		elseif ($body -match '\)\]')        { $typeOnly += $pendingGate; $pendingGate = $null }
	}

	if ($l.StartsWith('+')) {
		$text = $l.Substring(1)

		# a call followed by `.Member(` on the same line, not a continuation line and not a comment
		if ((Remove-Operands $text) -match $chainPattern -and $text -notmatch '^\s*\.' -and $text -notmatch '^\s*//') {
			$hit = [pscustomobject]@{ file = $file; line = $line; text = $text.Trim() }
			if (@(Get-ChainDepths $text | Where-Object { $_ -le 0 }).Count -gt 0) { $chains += $hit } else { $nested += $hit }
		}

		# a chain continuation: one tab past a receiver line, at most one past a continuation above it
		if ($file -match '\.cs$' -and $text -match '^\t+\.\s*[A-Za-z_]' -and $text -notmatch '^\t* ') {
			$prev = Get-PreviousLine
			if ($null -ne $prev -and $prev -notmatch '^\t* ' -and $prev -notmatch '[\(\{,]\s*$|=>\s*$') {
				$actual  = Get-Tabs $text
				$prevTab = Get-Tabs $prev
				$isCont  = $prev -match '^\t*\.'
				# over-indentation only: a shallower continuation follows query syntax or a wrapped argument list
				$bad     = $actual -gt $prevTab + 1
				if ($bad) {
					$indents += [pscustomobject]@{ file = $file; line = $line; text = $text.Trim(); expectedTabs = $prevTab + 1; actualTabs = $actual }
				}
			}
		}

		if ($text -match '\[(IncludeDataSources|DataSources)\s*\((?<args>[^\]]*)\)') {
			# every -match below overwrites $Matches
			$attribute  = $Matches[0]
			$attrArgs   = $Matches['args']
			$isNarrowed = $Matches[1] -eq 'IncludeDataSources' -or ($attrArgs -match '\S' -and $attrArgs -notmatch '^\s*(true|false)\s*$')

			if ($isNarrowed) {
				$above = Get-LineAbove
				$sets += [pscustomobject]@{
					file      = $file
					line      = $line
					attribute = $attribute
					lineAbove = $above
					hasReason = [bool]($above -and $above -match '^\s*//')
				}
			}
		}

		# a member-access chain starting lower-case (`records[2].FirstName`, `t.Single().Value`) is an expression,
		# not an expected value - values such as `CONVERT(varchar(4), 123)` do not fit the shape
		if ($text -match '\[(ActiveIssue|ThrowsForProvider)\b' -and $text -match 'Shouldly' -and $text -match 'ErrorMessage\s*=\s*"(?<msg>(?:[^"\\]|\\.)*)"') {
			$msg = $Matches['msg'] -replace '\\"', '"'

			if ($msg -notmatch '(?i)\bshould\b' -and $msg -match '^[a-z_]\w*(\.\w+|\[[^\]]*\]|\([^()]*\))*$') {
				$gates += [pscustomobject]@{ file = $file; line = $line; errorMessage = $msg }
			}
		}

		if ($text -match '\[(ActiveIssue|ThrowsForProvider)\b' -and $text -match 'ErrorMessage\s*=\s*"(?<msg>(?:[^"\\]|\\.)*)"') {
			$msg = $Matches['msg'] -replace '\\"', '"'

			# `<actual> <> <expected>` is AssertQuery's message, which carries the expected value too
			if ($msg -match '\{ \w+ = |\[\{' -and $msg -notmatch '(?s)should be\{0\}.*\{1\}but' -and $msg -notmatch ' <> ') {
				$unanchored += [pscustomobject]@{ file = $file; line = $line; errorMessage = $msg }
			}
		}

		if ($text -match '\[(ActiveIssue|ThrowsForProvider)\b' -and $text -match 'Shouldly' -and $text -notmatch 'ErrorMessage\s*=') {
			$rec = [pscustomobject]@{ file = $file; line = $line; text = $text.Trim() }
			if ($text -match '\)\]') { $typeOnly += $rec } else { $pendingGate = $rec }
		}
	}

	$recent.Add($l)
	if ($recent.Count -gt 6) { $recent.RemoveAt(0) }
}

[ordered]@{
	base                 = $range
	path                 = $Path
	chains               = @($chains)
	nestedChains         = @($nested)
	narrowedSets         = @($sets)
	narrowedWithoutReason = @($sets | Where-Object { -not $_.hasReason })
	shouldlySubjectGates = @($gates)
	typeOnlyShouldlyGates = @($typeOnly)
	continuationIndents  = @($indents)
	unanchoredAssertionGates = @($unanchored)
} | ConvertTo-Json -Depth 4
