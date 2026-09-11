#!/usr/bin/env pwsh
<#
Extract one or more files from a git ref into a scratch directory, so they can be
`Read` when the current checkout does not contain them.

Why this script exists
----------------------
The primary clone is routinely many commits behind `origin/master` (86 on the session
that prompted this, 47 on an earlier measured one), so a file a recent commit added is
simply absent and a working-tree search returns a clean "no matches" rather than
anything that looks like staleness - see `agent-rules.md` -> "A working-tree search is
evidence about *your checkout*, not about the repo".

The obvious recovery, `git show <ref>:<path>`, fails with `ambiguous argument` whenever
<ref> contains a `/` (so for every `origin/...` ref), and the prescribed workaround is
`git ls-tree` + `git cat-file -p` (`agent-rules.md` -> Windows Git Bash gotchas). Done
inline that needs a blob-sha parse off ls-tree's `<mode> <type> <object>\t<file>` output,
which is the part that silently goes wrong.

Two traps this script closes
----------------------------
1. `git ls-tree -- '<glob>'` does NOT glob. It matches literal paths and directory
   prefixes, so a pattern exits 0 with no output even when matching files exist - a
   result indistinguishable from absence. On #5764 that misread cost two review
   subagents an abandoned probe. This script rejects a glob-looking path up front and
   points at the enumeration commands that do work.
2. A `pwsh -File` parameter is always a string, so a `[string[]]` param does not collect
   `-Path a,b,c`. `-Path` is declared `[string]` and split explicitly.

Text files only - the content round-trips through a string, so this is not safe for
binaries.

Usage
-----
    .claude/scripts/ref-file.ps1 -Ref origin/master -Path Tests/Linq/Linq/ParameterTests.cs
    .claude/scripts/ref-file.ps1 -Ref origin/master -Path 'a/Foo.cs,b/Bar.cs' -OutDir .build/.agents

Output: one JSON object on stdout with a `files[]` entry per requested path (each with
`outPath` to `Read`), plus `missing[]` for paths absent from the ref. Exit 1 when every
requested path is missing.
#>

param(
    [Parameter(Mandatory)][string]$Ref,
    [Parameter(Mandatory)][string]$Path,
    [string]$OutDir   = '.build/.agents',
    [string]$RepoRoot = '.'
)

$global:ScriptBaseName = 'ref-file'
. "$PSScriptRoot/_shared.ps1"

$ErrorActionPreference = 'Stop'

$paths = $Path.Split(',', [StringSplitOptions]::RemoveEmptyEntries) | ForEach-Object { $_.Trim() } | Where-Object { $_ }

if (-not $paths) {
    Exit-WithError -Message 'no paths given' -NextAction 'pass -Path <repo-relative-path>[,<path>...]'
}

$globbed = @($paths | Where-Object { $_ -match '[*?]' })
if ($globbed) {
    Exit-WithError -Message "git ls-tree does not glob; these patterns would silently match nothing: $($globbed -join ', ')" `
        -NextAction 'enumerate first with `git diff --name-only <base>...<ref>` or `git ls-files <ref>`, then pass literal paths'
}

if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

$utf8NoBom = New-Object System.Text.UTF8Encoding $false
$files     = @()
$missing   = @()

foreach ($p in $paths) {
    $ls = Invoke-Git -ArgumentList @('ls-tree', $Ref, '--', $p) -WorkingDirectory $RepoRoot

    if (-not $ls.ok) {
        Exit-WithError -Message "git ls-tree failed for '$p': $($ls.error)" `
            -NextAction "verify the ref exists: git rev-parse $Ref"
    }

    $line = ($ls.stdout -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 1)

    if (-not $line) {
        $missing += $p
        continue
    }

    # `<mode> SP <type> SP <object> TAB <file>` - split the tab off first, then the
    # metadata on spaces, so a path containing spaces cannot shift the sha's index.
    $sha = ($line -split "`t", 2)[0].Trim() -split '\s+' | Select-Object -Last 1

    $cat = Invoke-Git -ArgumentList @('cat-file', '-p', $sha) -WorkingDirectory $RepoRoot

    if (-not $cat.ok) {
        Exit-WithError -Message "git cat-file failed for '$p' ($sha): $($cat.error)"
    }

    $outPath = Join-Path $OutDir (Split-Path $p -Leaf)
    [System.IO.File]::WriteAllText($outPath, $cat.stdout, $utf8NoBom)

    $files += [pscustomobject]@{
        path    = $p
        outPath = (Resolve-Path $outPath).Path
        bytes   = [System.Text.Encoding]::UTF8.GetByteCount($cat.stdout)
    }
}

if ($files.Count -eq 0) {
    Exit-WithError -Message "none of the requested paths exist in '$Ref'" `
        -NextAction "check the path spelling against ``git ls-files $Ref``"
}

Write-JsonOutput ([pscustomobject]@{
    ok      = ($missing.Count -eq 0)
    ref     = $Ref
    outDir  = $OutDir
    files   = $files
    missing = $missing
})
