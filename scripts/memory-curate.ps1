<#
.SYNOPSIS
  Auto-memory curation helper: survey, drop, and verify a memory store's integrity.

.DESCRIPTION
  Supports the periodic MEMORY.md compaction pass (the size hook fires around 20 KB against a
  24.4 KB read cap). Three actions, all emitting one JSON object on stdout:

    -Action survey   Inventory every memory file with its size, plus each project_* entry's
                     referenced issue/PR numbers resolved to state via parallel `gh` calls.
                     This is what makes "is this record settled?" checkable instead of guessed:
                     drop an entry when its own tracking item is closed AND it records completed
                     work. Keep dead-ends and anything naming still-open follow-on work.

    -Action drop     Delete the named memory files and strip their MEMORY.md entries, then verify.
                     A rollup line ("**Topic** - [a](a.md) . [b](b.md)") keeps its surviving links;
                     a line left with no links is removed entirely.

    -Action verify   Report orphans (file with no index entry) and broken links (index entry with
                     no file). Run after any hand edit to MEMORY.md.

  The memory directory is per-user, so it is a REQUIRED parameter - never hardcode a path here.

.PARAMETER MemoryDir
  Absolute path to the memory store (the directory holding MEMORY.md).

.PARAMETER List
  For -Action drop: comma-separated memory names WITHOUT the .md suffix. Note `pwsh -File` binds
  every argument as a string, so this is deliberately [string] and split in-script - a [string[]]
  would collect "a,b,c" into one element (see docs/script-authoring.md).

.PARAMETER Repo
  owner/repo used to resolve issue/PR state during -Action survey. Default linq2db/linq2db.

.EXAMPLE
  pwsh -NoProfile -File .claude/scripts/memory-curate.ps1 -Action survey -MemoryDir <dir>
  pwsh -NoProfile -File .claude/scripts/memory-curate.ps1 -Action drop -MemoryDir <dir> -List a,b,c
  pwsh -NoProfile -File .claude/scripts/memory-curate.ps1 -Action verify -MemoryDir <dir>
#>
#requires -Version 7
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('survey', 'drop', 'verify')][string]$Action,
    [Parameter(Mandatory)][string]$MemoryDir,
    [string]$List,
    [string]$Repo = 'linq2db/linq2db',
    [int]$Concurrency = 8
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $MemoryDir)) { Write-Error "memory dir not found: $MemoryDir" }
$index = Join-Path $MemoryDir 'MEMORY.md'
if (-not (Test-Path -LiteralPath $index)) { Write-Error "MEMORY.md not found in $MemoryDir" }

function Get-MemoryFiles {
    Get-ChildItem -LiteralPath $MemoryDir -Filter '*.md' |
        Where-Object { $_.Name -ne 'MEMORY.md' } |
        Select-Object -ExpandProperty Name
}

# A link label may itself contain brackets - "[YDB keyless: plain [PrimaryKey]](f.md)" - so match the
# target first and take the shortest label back to the preceding '['. A naive \[[^\]]*\] misses those.
function Get-IndexedTargets([string]$body) {
    [regex]::Matches($body, '\(([A-Za-z0-9_.-]+\.md)\)') |
        ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
}

function Test-Integrity {
    $body    = [System.IO.File]::ReadAllText($index)
    $files   = @(Get-MemoryFiles)
    $targets = @(Get-IndexedTargets $body)
    [ordered]@{
        fileCount   = $files.Count
        linkCount   = $targets.Count
        indexBytes  = (Get-Item -LiteralPath $index).Length
        orphans     = @($files   | Where-Object { $body -notmatch [regex]::Escape($_) })
        brokenLinks = @($targets | Where-Object { -not (Test-Path -LiteralPath (Join-Path $MemoryDir $_)) })
    }
}

switch ($Action) {

    'survey' {
        $rows = foreach ($f in (Get-MemoryFiles | Sort-Object)) {
            $body = [System.IO.File]::ReadAllText((Join-Path $MemoryDir $f))
            $nums = @()
            if ($f -like 'project_*') {
                $nums = @(
                    ([regex]::Matches($f,    'project_(\d{3,5})_') | ForEach-Object { $_.Groups[1].Value }) +
                    ([regex]::Matches($body, '#(\d{4,5})\b')       | ForEach-Object { $_.Groups[1].Value })
                ) | Select-Object -Unique
            }
            [pscustomobject]@{ file = $f; sizeBytes = $body.Length; refs = $nums }
        }

        $state = @{}
        $all = @($rows.refs | Select-Object -Unique | Where-Object { $_ })
        if ($all.Count) {
            $all | ForEach-Object -ThrottleLimit $Concurrency -Parallel {
                $j = gh api "repos/$using:Repo/issues/$_" `
                        --jq '{n:.number,s:.state,kind:(if .pull_request then "PR" else "ISSUE" end)}' 2>$null
                if ($j) { $j } else { "{`"n`":$_,`"s`":`"unknown`",`"kind`":`"unknown`"}" }
            } | ForEach-Object {
                try { $o = $_ | ConvertFrom-Json; $state[[string]$o.n] = "$($o.kind):$($o.s)" } catch { }
            }
        }

        [ordered]@{
            action    = 'survey'
            integrity = Test-Integrity
            entries   = @($rows | ForEach-Object {
                [ordered]@{
                    file      = $_.file
                    sizeBytes = $_.sizeBytes
                    refs      = @($_.refs | ForEach-Object { [ordered]@{ number = $_; state = $state[[string]$_] } })
                }
            })
        } | ConvertTo-Json -Depth 6
    }

    'drop' {
        if (-not $List) { Write-Error "-Action drop requires -List <name>[,<name>...]" }
        $names = $List.Split(',', [StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim() }

        $deleted = @(); $missing = @(); $freed = 0
        foreach ($n in $names) {
            $p = Join-Path $MemoryDir "$n.md"
            if (Test-Path -LiteralPath $p) {
                $freed += (Get-Item -LiteralPath $p).Length
                Remove-Item -LiteralPath $p -Force
                $deleted += $n
            }
            else { $missing += $n }
        }

        $before = (Get-Item -LiteralPath $index).Length
        $kept = foreach ($line in [System.IO.File]::ReadAllLines($index)) {
            $hits = @($names | Where-Object { $line -match [regex]::Escape("$_.md") })
            if (-not $hits) { $line; continue }
            $new = $line
            foreach ($h in $hits) {
                # drop "[label](name.md) trailing-hook" plus its separator; label may contain brackets
                $new = [regex]::Replace($new, '\s*·?\s*\[[^\r\n]*?\]\(' + [regex]::Escape("$h.md") + '\)[^·\r\n]*', '')
            }
            if ($new -match '\([A-Za-z0-9_.-]+\.md\)') {
                ($new -replace '—\s*·\s*', '— ' -replace '\s+·\s*$', '').TrimEnd()
            }
        }
        [System.IO.File]::WriteAllLines($index, [string[]]$kept, (New-Object System.Text.UTF8Encoding $false))

        [ordered]@{
            action      = 'drop'
            deleted     = $deleted
            missing     = $missing
            freedBytes  = $freed
            indexBefore = $before
            integrity   = Test-Integrity
        } | ConvertTo-Json -Depth 6
    }

    'verify' {
        [ordered]@{ action = 'verify'; integrity = Test-Integrity } | ConvertTo-Json -Depth 6
    }
}
