#!/usr/bin/env pwsh
# activeissue-census.ps1 - inventory every [ActiveIssue] / [ActiveIssueNew] gate in the test tree, and gate
# the migration on what it finds.
#
# Two questions, both answered statically - no build, no test run:
#
#   1. Which provider configurations does each gate name? TestProvName.All* are interpolated string constants
#      over ProviderName.*, so they resolve by parsing. This orders the migration sweep: a gate naming one
#      provider costs one filtered run to harvest, a gate naming none costs the whole matrix.
#   2. How is each gate attributed to an issue? Six sources, in descending exactness: the int constructor, an
#      external tracker URL, a linq2db URL passed as a string (which must become the int ctor), an issue URL
#      inside Details, the sibling [Test(Description = "...")], and the IssueNNNN convention in the test or
#      fixture name.
#
# It also flags where a gate shares a method with a Throws* attribute - both families rewrite the test result
# and neither knows about the other - and counts the waiver markers a migrated gate may carry in Details.
#
# -Gate turns the inventory into a check: it exits non-zero unless every gate is either explicitly attributed
# or carries a marker saying why it cannot be. Expect it to fail until the migration is finished; that is what
# it is for.
#
# Output: one JSON summary on stdout; the full per-site rows to <WriteDir>/activeissue-census.json.

[CmdletBinding()]
param(
	# Repository to inventory. Defaults to the checkout this script's corpus is mounted in; pass a worktree
	# path explicitly when the branch under migration lives in one.
	[string] $RepoRoot,
	[string] $WriteDir,
	# Committed audit ledger. When given, the run cross-checks that every migrated gate has a ledger entry -
	# a site with no entry is invisible to the audit's sampling, which is how an unvalidated gate would hide.
	[string] $LedgerFile,
	[switch] $Gate
)

$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path }

$RepoRoot = (Resolve-Path $RepoRoot).Path

if (-not $WriteDir) { $WriteDir = Join-Path $RepoRoot '.build/.agents/activeissue-census' }
if (-not (Test-Path $WriteDir)) { New-Item -ItemType Directory -Path $WriteDir -Force | Out-Null }

# ---------- 1. constant map ----------

$constFiles = @(
	(Join-Path $RepoRoot 'Tests/Base/TestProvName.cs')
) + @(Get-ChildItem -Path (Join-Path $RepoRoot 'Source') -Recurse -Filter 'ProviderName.cs' -File | Select-Object -ExpandProperty FullName)

$consts = @{}

foreach ($f in $constFiles) {
	if (-not (Test-Path $f)) { continue }

	$owner = [System.IO.Path]::GetFileNameWithoutExtension($f)
	$text  = Get-Content -Raw -LiteralPath $f

	foreach ($m in [regex]::Matches($text, 'public\s+const\s+string\s+(\w+)\s*=\s*([^;]+);')) {
		$consts["$owner.$($m.Groups[1].Value)"] = $m.Groups[2].Value.Trim()
	}
}

$resolving = @{}

function Resolve-Const {
	param([string] $Key)

	if (-not $consts.ContainsKey($Key)) { return $null }
	if ($resolving.ContainsKey($Key))   { return $null }   # cycle guard

	$resolving[$Key] = $true

	try {
		$expr = $consts[$Key]

		# $"{A},{B}" - interpolated concatenation of other constants
		if ($expr -match '^\$"(.*)"$') {
			$body  = $Matches[1]
			$parts = @()

			foreach ($piece in ($body -split ',')) {
				$piece = $piece.Trim()

				if ($piece -match '^\{(.+)\}$') {
					$inner = $Matches[1].Trim()
					$parts += (Resolve-Token $inner)
				}
				elseif ($piece) {
					$parts += $piece
				}
			}

			return ($parts | Where-Object { $_ }) -join ','
		}

		# plain literal
		if ($expr -match '^"(.*)"$') { return $Matches[1] }

		# alias to another constant
		if ($expr -match '^[\w.]+$') { return (Resolve-Token $expr) }

		return $null
	}
	finally {
		$resolving.Remove($Key) | Out-Null
	}
}

function Resolve-Token {
	param([string] $Token)

	$Token = $Token.Trim()

	if (-not $Token) { return $null }

	# string literal
	if ($Token -match '^"(.*)"$') { return $Matches[1] }

	# Qualified: TestProvName.X / ProviderName.X
	if ($consts.ContainsKey($Token)) { return (Resolve-Const $Token) }

	# Bare X inside TestProvName.cs's own initializers
	foreach ($owner in @('TestProvName', 'ProviderName')) {
		if ($consts.ContainsKey("$owner.$Token")) { return (Resolve-Const "$owner.$Token") }
	}

	# A constant declared in the test file itself - several fixtures build their own provider sets.
	if ($localConsts -and $localConsts.ContainsKey($Token)) {
		$expr  = $localConsts[$Token]
		$parts = @()

		foreach ($piece in ($expr -split '[+,]')) {
			$piece = $piece.Trim().Trim('$')

			if (-not $piece) { continue }

			if ($piece -match '^"(.*)"$') { $parts += $Matches[1]; continue }

			$r = Resolve-Token $piece
			if ($r) { $parts += $r }
		}

		if ($parts.Count -gt 0) { return ($parts -join ',') }
	}

	return $null
}

# Resolves `const string <Name> = "a" + "b";` declared in the same file, so a Details that points at a
# shared constant still exposes its markers. Returns '' when the name is not a same-file string const.
function Resolve-ConstString {
	param([string] $Text, [string] $Name)

	if ($Text -notmatch "const\s+string\s+$([regex]::Escape($Name))\s*=\s*((?:\s*@?""(?:[^""\\]|\\.)*""\s*\+?)+)\s*;") { return '' }

	$parts = [regex]::Matches($Matches[1], '@?"((?:[^"\\]|\\.)*)"')

	return (($parts | ForEach-Object { $_.Groups[1].Value }) -join '')
}

# ---------- 2. attribute sites ----------

# Splits an argument list on top-level commas: nested [], (), {} and string literals do not separate args.
function Split-TopLevel {
	param([string] $Text, [char] $Separator = ',')

	$parts = @()
	$sb    = [System.Text.StringBuilder]::new()
	$depth = 0
	$inStr = $false

	for ($i = 0; $i -lt $Text.Length; $i++) {
		$c = $Text[$i]

		if ($inStr) {
			[void]$sb.Append($c)
			if ($c -eq '"' -and ($i -eq 0 -or $Text[$i - 1] -ne '\')) { $inStr = $false }
			continue
		}

		# NB: a `switch` here would double every bracket - `continue` inside a switch exits the switch, not
		# the enclosing loop, so the character gets appended twice.
		if ($c -eq '"') { $inStr = $true; [void]$sb.Append($c); continue }
		if ($c -eq '(' -or $c -eq '[' -or $c -eq '{') { $depth++; [void]$sb.Append($c); continue }
		if ($c -eq ')' -or $c -eq ']' -or $c -eq '}') { $depth--; [void]$sb.Append($c); continue }

		if ($c -eq $Separator -and $depth -eq 0) {
			$parts += $sb.ToString()
			[void]$sb.Clear()
			continue
		}

		[void]$sb.Append($c)
	}

	if ($sb.Length -gt 0) { $parts += $sb.ToString() }

	return @($parts | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

$files = Get-ChildItem -Path (Join-Path $RepoRoot 'Tests') -Recurse -Include '*.cs', '*.fs' -File |
	Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' }

$rows = @()

foreach ($file in $files) {
	$text  = Get-Content -Raw -LiteralPath $file.FullName

	if (-not $text) { continue }

	$rel   = $file.FullName.Substring($RepoRoot.Length).TrimStart('\', '/') -replace '\\', '/'

	# File-local provider constants (IntervalTranslationTests and friends declare their own).
	$localConsts = @{}

	foreach ($lm in [regex]::Matches($text, '(?:const|static\s+readonly)\s+string\s+(\w+)\s*=\s*([^;]+);')) {
		$localConsts[$lm.Groups[1].Value] = $lm.Groups[2].Value.Trim()
	}

	# Both attribute names, because the census has to keep working across the cutover rename - and because the
	# EF pilot's already-migrated sites are otherwise invisible to the SC-14 attribution gate.
	foreach ($m in [regex]::Matches($text, '\[<?ActiveIssue(New)?(?=[(\]\s>])')) {
		$start    = $m.Index
		$attrName = if ($m.Groups[1].Success) { 'ActiveIssueNew' } else { 'ActiveIssue' }

		# Prose mentions the token too - "Gated [ActiveIssue] until ..." in a comment is not a gate.
		$lineStart = $text.LastIndexOf("`n", $start) + 1
		$before    = $text.Substring($lineStart, $start - $lineStart)

		if ($before -match '//' -or $before -match '\*' -or $before -match '///') { continue }

		# Inside a string literal - the new attribute's own messages name "[ActiveIssueNew]" mid-sentence, so
		# testing only the preceding character misses them. Count unescaped quotes before the match on this
		# line: an odd number means we are inside one.
		$quotes = 0

		for ($q = $lineStart; $q -lt $start; $q++) {
			if ($text[$q] -eq '"' -and ($q -eq 0 -or $text[$q - 1] -ne '\')) { $quotes++ }
		}

		if ($quotes % 2 -eq 1) { continue }

		# walk to the matching close bracket of the attribute
		$i     = $start
		$depth = 0
		$inStr = $false
		$end   = -1

		while ($i -lt $text.Length) {
			$c = $text[$i]

			if ($inStr) {
				if ($c -eq '"' -and $text[$i - 1] -ne '\') { $inStr = $false }
				$i++
				continue
			}

			if     ($c -eq '"') { $inStr = $true }
			elseif ($c -eq '[') { $depth++ }
			elseif ($c -eq ']') { $depth--; if ($depth -eq 0) { $end = $i; break } }

			$i++
		}

		if ($end -lt 0) { continue }

		$attr = $text.Substring($start, $end - $start + 1)
		$line = ($text.Substring(0, $start) -split "`n").Count

		# argument list, if any
		$args = ''
		$op   = $attr.IndexOf('(')

		if ($op -ge 0) {
			$cp = $attr.LastIndexOf(')')
			if ($cp -gt $op) { $args = $attr.Substring($op + 1, $cp - $op - 1) }
		}

		$parts    = Split-TopLevel -Text $args
		$issue    = $null
		$issueKind = 'none'
		$cfgExpr  = $null
		$details  = $false
		$detailsText = $null
		$declares = $false
		$skipLs   = $false
		$skipNls  = $false

		foreach ($p in $parts) {
			if ($p -match '^\s*(Configuration|Configurations)\s*=\s*(.+)$') {
				$cfgExpr = $Matches[2].Trim()
			}
			elseif ($p -match '^\s*Details\s*=\s*"(.*)"\s*$') { $details = $true; $detailsText = $Matches[1] }
			# `Details = SomeConst` is the idiom once several gates in a file share one explanation, and the
			# marker lives in the const's value. Without resolving it the markers are invisible and SC-14 fires
			# on a site that does carry a waiver - which is how this was found.
			elseif ($p -match '^\s*Details\s*=\s*([A-Za-z_][A-Za-z0-9_]*)\s*$') {
				$details = $true
				$detailsText = Resolve-ConstString -Text $text -Name $Matches[1]
			}
			elseif ($p -match '^\s*Details\s*=')               { $details = $true }
			# What the gate asserts about the failure. Without one of these the gate matches *any* failure,
			# which is the masking risk SC-9 exists to bound.
			elseif ($p -match '^\s*(ErrorType|ErrorTypeName|ErrorMessage)\s*=') { $declares = $true }
			elseif ($p -match '^\s*SkipForLinqService\s*=\s*true')    { $skipLs  = $true }
			elseif ($p -match '^\s*SkipForNonLinqService\s*=\s*true') { $skipNls = $true }
			# Positional if it is not a named argument - test for the `Name =` *prefix*, not for a stray '=',
			# which prose legitimately contains ("type !=/== type parsing", ConcatUnionTests.cs:1053).
			elseif ($p -notmatch '^\s*\w+\s*=' -and -not $issue) {
				$issue     = $p.Trim()
				$issueKind = if ($issue -match '^\d+$') { 'int' } else { 'string' }
			}
		}

		# provider tokens
		$tokens    = @()
		$providers = @()

		if ($cfgExpr) {
			$inner = $cfgExpr

			if ($inner -match '^\[(.*)\]$')            { $inner = $Matches[1] }
			elseif ($inner -match '^new\[\]\s*\{(.*)\}$') { $inner = $Matches[1] }
			elseif ($inner -match '^new\s+string\[\]\s*\{(.*)\}$') { $inner = $Matches[1] }

			foreach ($t in (Split-TopLevel -Text $inner)) {
				$tokens += $t
				$r = Resolve-Token $t

				if ($r) { $providers += ($r -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
				else    { $providers += "UNRESOLVED:$t" }
			}
		}

		$providers = @($providers | Select-Object -Unique | Sort-Object)

		# member the attribute decorates: first signature-ish line after the attribute block. The offset where
		# that line starts also bounds the attribute block, which the Throws* scan below needs - siblings sit on
		# both sides of this attribute.
		$after       = $text.Substring($end + 1)
		$member      = ''
		$memberDelta = 0
		$seen        = 0

		# A sibling attribute may wrap over several lines, and its continuation lines look nothing like an
		# attribute - so skipping only lines that start with '[' lands the member on `ErrorTypeName = "..."`.
		# Track bracket depth instead and skip until it closes.
		$depth           = 0
		$inBlockComment  = $false

		# The cap only bounds a scan still inside attributes/comments - the loop breaks the moment it resolves a
		# member. 24 was too low once a site carried a per-provider declaration each: DateTimeAddTimeSpan's 13
		# attributes put the signature ~30 lines below the first one, and the site was keyed with an empty member.
		foreach ($l in (($after -split "`n") | Select-Object -First 160)) {
			$t     = $l.Trim()
			$delta = ([regex]::Matches($t, '\[')).Count - ([regex]::Matches($t, '\]')).Count

			if ($depth -gt 0) {
				$depth += $delta
				$seen  += $l.Length + 1
				continue
			}

			if ($inBlockComment) {
				if ($t.Contains('*/')) { $inBlockComment = $false }
				$seen += $l.Length + 1
				continue
			}

			if ($t.StartsWith('/*')) {
				$inBlockComment = -not $t.Contains('*/')
				$seen          += $l.Length + 1
				continue
			}

			if (-not $t -or $t.StartsWith('//') -or $t.StartsWith('#') -or $t.StartsWith('*')) {
				$seen += $l.Length + 1
				continue
			}

			if ($t.StartsWith('[')) {
				$depth = [Math]::Max(0, $delta)
				$seen += $l.Length + 1
				continue
			}

			if ($t -match '(\w+)\s*\(') { $member = $Matches[1] }
			elseif ($t -match 'member\s+.*?\.?(\w+)') { $member = $Matches[1] }
			else { $member = $t }

			$memberDelta = $seen
			break
		}

		# Throws* attributes in the same attribute block: both families are IWrapSetUpTearDown result-rewriters,
		# and neither recognises the other, so an overlapping provider set is a genuine collision.
		$blockStart = @(
			$text.LastIndexOf('{', $start)
			$text.LastIndexOf('}', $start)
			$text.LastIndexOf(';', $start)
		) | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum

		if ($blockStart -lt 0) { $blockStart = 0 }

		$blockEnd      = [Math]::Min($text.Length - 1, $end + $memberDelta)
		$block         = $text.Substring($blockStart, $blockEnd - $blockStart + 1)
		$throwsAttrs   = @()
		$throwsProvs   = @()

		foreach ($tm in [regex]::Matches($block, '\[(Throws\w*)\(')) {
			$throwsAttrs += $tm.Groups[1].Value
		}

		if ($throwsAttrs.Count -gt 0) {
			foreach ($pm in [regex]::Matches($block, '(?:TestProvName|ProviderName)\.\w+')) {
				# tokens inside the ActiveIssue attribute itself are not the Throws targeting
				$abs = $pm.Index + $blockStart

				if ($abs -ge $start -and $abs -le $end) { continue }

				$r = Resolve-Token $pm.Value
				if ($r) { $throwsProvs += ($r -split ',' | ForEach-Object { $_.Trim() }) }
			}
		}

		$throwsProvs = @($throwsProvs | Select-Object -Unique | Sort-Object)

		# Overlap is NOT a plain intersection, and getting that wrong produces a false clean on exactly the
		# dangerous site. A gate naming no configuration governs *every* provider, so an empty $providers
		# overlaps whatever the Throws* attribute targets - an intersection reports zero. And a Throws*
		# subclass computes its target set internally (ThrowsRequiresCorrelatedSubquery -> AllYdb, plus
		# AllClickHouse when simple:false), so an empty $throwsProvs means "not resolved here", not "disjoint".
		if ($throwsAttrs.Count -eq 0) {
			$overlap = @()
		}
		elseif ($providers.Count -eq 0) {
			$overlap = @('ALL: gate names no configuration, so it governs every provider the Throws* targets')
		}
		elseif ($throwsProvs.Count -eq 0) {
			$overlap = @('UNRESOLVED: Throws* target set is computed inside the attribute - resolve by hand')
		}
		else {
			$overlap = @($providers | Where-Object { $throwsProvs -contains $_ })
		}

		# Issue attribution. The int ctor is the only form that names a linq2db issue machine-readably; a string
		# is either an external tracker URL (legitimate) or prose (no reference at all). Where the reference is
		# missing, the test's own name usually still carries it - IssueNNNNTests.cs / IssueNNNNTest().
		# A URL is not automatically *external*: two sites link linq2db's own tracker through the string ctor
		# (EagerLoadingTests.cs:757,823), which SC-14 requires converting to the int ctor. Without the host
		# check they classify as external-url and the attribution gate passes over them.
		$issueKindDetail = switch ($issueKind) {
			'int'    { 'int' }
			'string' {
				if     ($issue -match 'github\.com/linq2db/linq2db/(issues|pull)/(\d+)') { 'linq2db-url' }
				elseif ($issue -match 'https?://')                                       { 'url' }
				else                                                                     { 'prose' }
			}
			default  { 'none' }
		}

		$selfUrlIssue = if ($issueKindDetail -eq 'linq2db-url' -and $issue -match 'github\.com/linq2db/linq2db/(?:issues|pull)/(\d+)') { $Matches[1] } else { $null }

		$nameIssue = $null

		foreach ($candidate in @($member, [System.IO.Path]::GetFileNameWithoutExtension($rel))) {
			if ($candidate -match 'Issue(\d{3,5})') { $nameIssue = $Matches[1]; break }
		}

		# [Test(Description = "https://github.com/linq2db/linq2db/issues/NNNN")] on the same method is an exact
		# reference, not a naming convention - it outranks the name when the two disagree.
		$descIssue = $null

		if ($block -match 'Description\s*=\s*"[^"]*linq2db/(?:issues|pull)/(\d{3,5})') {
			$descIssue = $Matches[1]
		}

		# ... and some gates put the issue URL in their own Details instead (OracleTests.cs:4481,
		# FluentMappingExpressionMethodTests.cs:47). Same exactness, so same rank.
		$detailsIssue = $null

		if ($attr -match 'Details\s*=\s*"[^"]*linq2db/(?:issues|pull)/(\d{3,5})') {
			$detailsIssue = $Matches[1]
		}

		# Waiver markers, anchored at the start of Details and chainable - a site with no harvestable failure is
		# also a site V1 cannot decide, so `no-declaration: unvalidated: ...` is a legitimate value. Counted per
		# prefix rather than per site, because SC-15b's number and SC-9's are different questions.
		$markers = @()
		$rest    = $detailsText

		while ($rest -match '^\s*(no-declaration|unvalidated|no-issue):\s*(.*)$') {
			$markers += $Matches[1]
			$rest     = $Matches[2]
		}

		# no-declaration implies unvalidated on V1: with no harvested failure there is nothing for the
		# defect-match check to compare against. Derived rather than hand-written, so the SC-15b count stays
		# right without every author typing both prefixes.
		if ($markers -contains 'no-declaration' -and $markers -notcontains 'unvalidated') { $markers += 'unvalidated' }

		$attribution =
			if ($issueKindDetail -eq 'int')                { 'explicit' }
			elseif ($issueKindDetail -eq 'url')            { 'external-url' }
			elseif ($issueKindDetail -eq 'linq2db-url')    { 'linq2db-url-needs-int' }
			elseif ($detailsIssue)                         { 'recoverable-from-details' }
			elseif ($descIssue)                            { 'recoverable-from-description' }
			elseif ($nameIssue)                            { 'recoverable-from-name' }
			else                                           { 'unknown' }

		$rows += [pscustomobject]@{
			file          = $rel
			line          = $line
			attrName      = $attrName
			member        = $member
			issueKindDetail = $issueKindDetail
			nameIssue     = $nameIssue
			descIssue     = $descIssue
			selfUrlIssue  = $selfUrlIssue
			markers       = $markers
			declares      = $declares
			attribution   = $attribution
			throwsAttrs   = @($throwsAttrs | Select-Object -Unique)
			throwsProviders = $throwsProvs
			throwsOverlap = $overlap
			issue         = $issue
			issueKind     = $issueKind
			details       = $details
			skipForLinqService    = $skipLs
			skipForNonLinqService = $skipNls
			tokens        = $tokens
			providers     = $providers
			providerCount = $providers.Count
			unresolved    = @($providers | Where-Object { $_ -like 'UNRESOLVED:*' })
			area          = ($rel -split '/')[1]
			attrText      = ($attr -replace '\s+', ' ')
		}
	}
}

# ---------- 3. report ----------

$selfTests = $rows | Where-Object { $_.file -match 'Infrastructure/ActiveIssue(Configuration|Generic)Tests\.cs' }
$live      = $rows | Where-Object { $_.file -notmatch 'Infrastructure/ActiveIssue(Configuration|Generic)Tests\.cs' -and $_.file -notmatch 'Tests/Base/Attributes/' }

function Bucket {
	param([int] $n)

	if ($n -eq 0) { return '0 (all providers)' }
	if ($n -le 3) { return "$n" }
	if ($n -le 6) { return '4-6' }
	if ($n -le 12) { return '7-12' }

	return '13+'
}

$payload = [pscustomobject]@{
	repoRoot   = $RepoRoot
	totalSites = $rows.Count
	liveSites  = $live.Count
	selfTests  = $selfTests.Count
	unresolvedTokens = @($rows | Where-Object { $_.unresolved.Count -gt 0 } | ForEach-Object { $_.unresolved } | Select-Object -Unique)
	byBucket   = ($live | Group-Object { Bucket $_.providerCount } | ForEach-Object { [pscustomobject]@{ bucket = $_.Name; sites = $_.Count } })
	byAttribution = ($live | Group-Object attribution | ForEach-Object { [pscustomobject]@{ attribution = $_.Name; sites = $_.Count } })
	byMarker   = (@('no-declaration', 'unvalidated', 'no-issue') | ForEach-Object { $m = $_; [pscustomobject]@{ marker = $m; sites = @($rows | Where-Object { $_.markers -contains $m }).Count } })
	byArea     = ($live | Group-Object area | Sort-Object Count -Descending | ForEach-Object { [pscustomobject]@{ area = $_.Name; sites = $_.Count } })
	rows       = $rows
}

# ---------- 4. gate ----------
#
# The accepted set is closed on purpose. Every recoverable-from-* class is a finding, not a pass: the whole
# point of SC-14 is that a reference sitting in a test name or a Description is not yet *in the attribute*,
# where a reader and /enable-disabled-test can act on it.

$migrated = @($rows | Where-Object { $_.attrName -eq 'ActiveIssueNew' })
$oldAttr  = @($rows | Where-Object { $_.attrName -eq 'ActiveIssue' -and $_.file -notmatch 'Tests/Base/Attributes/' })

$violations = @()

foreach ($r in $oldAttr) {
	$violations += [pscustomobject]@{ rule = 'SC-8'; site = "$($r.file):$($r.line)"; detail = 'still on the old attribute' }
}

foreach ($r in $migrated) {
	if (-not $r.declares -and $r.markers -notcontains 'no-declaration') {
		$violations += [pscustomobject]@{ rule = 'SC-9'; site = "$($r.file):$($r.line)"; detail = 'no ErrorType/ErrorTypeName/ErrorMessage and no no-declaration: marker' }
	}

	if ($r.attribution -notin @('explicit', 'external-url') -and $r.markers.Count -eq 0) {
		$violations += [pscustomobject]@{ rule = 'SC-14'; site = "$($r.file):$($r.line)"; detail = "attribution '$($r.attribution)' is not an accepted class and no marker explains it" }
	}
}

$ledgerChecked = $false
$ledgerMissing = @()

if ($LedgerFile) {
	if (-not (Test-Path $LedgerFile)) {
		[Console]::Error.WriteLine("activeissue-census: ledger not found: $LedgerFile")
		[Console]::Error.WriteLine("next_action: pass -LedgerFile <path to the committed ledger>, or omit it to skip the cross-check")
		exit 2
	}

	$ledger        = Get-Content -Raw -LiteralPath $LedgerFile | ConvertFrom-Json
	$ledgerKeys    = @($ledger.PSObject.Properties.Name)
	$ledgerChecked = $true

	# Keyed by member, not by line: E-34's schema says so, and several methods carry more than one attribute,
	# which a line key would demand a separate audit row for.
	$seenKeys = [System.Collections.Generic.HashSet[string]]::new()

	foreach ($r in $migrated) {
		$key = "$($r.file)::$($r.member)"

		if (-not $seenKeys.Add($key)) { continue }

		if ($ledgerKeys -notcontains $key) {
			$ledgerMissing += $key
			$violations    += [pscustomobject]@{ rule = 'TO-15'; site = $key; detail = 'migrated gate has no ledger entry, so the audit sample cannot reach it' }
		}
	}
}

$full = Join-Path $WriteDir 'activeissue-census.json'
$payload | Add-Member -NotePropertyName violations -NotePropertyValue $violations -PassThru | ConvertTo-Json -Depth 8 | Out-File -FilePath $full -Encoding utf8

$summary = [pscustomobject]@{
	repoRoot         = $RepoRoot
	totalSites       = $rows.Count
	oldAttributeSites = $oldAttr.Count
	migratedSites    = $migrated.Count
	selfTestSites    = $selfTests.Count
	unresolvedTokens = @($payload.unresolvedTokens).Count
	byBucket         = $payload.byBucket
	byAttribution    = $payload.byAttribution
	byMarker         = $payload.byMarker
	throwsCoSited    = @($rows | Where-Object { $_.throwsAttrs.Count -gt 0 }).Count
	throwsOverlapping = @($rows | Where-Object { $_.throwsOverlap.Count -gt 0 }).Count
	ledgerChecked    = $ledgerChecked
	ledgerMissing    = $ledgerMissing.Count
	violations       = $violations.Count
	violationsByRule = (@($violations | Group-Object rule | ForEach-Object { [pscustomobject]@{ rule = $_.Name; count = $_.Count } }))
	resultsFile      = $full
}

[Console]::Out.WriteLine(($summary | ConvertTo-Json -Depth 6))

if ($Gate -and $violations.Count -gt 0) {
	[Console]::Error.WriteLine("activeissue-census: $($violations.Count) violation(s); see $full")
	exit 1
}
