<#
dump-assembly-api.ps1 — list the public API of a managed assembly without loading it.

Reads type / member metadata straight out of a .dll or .exe via System.Reflection.Metadata, so it
works on reference assemblies (`ref/**`), assemblies for another TFM, and assemblies whose
dependencies aren't present — none of which can be `Assembly.Load`ed. Answers the questions that
otherwise cost a web search or a guess: does this API exist, is it static, is it virtual (i.e.
overridable), what are its parameter names, what version is the assembly.

Typical use: establishing the surface of a third-party SDK the repo compiles against, e.g.
`LINQPad.Reference`'s `ref/netcoreapp3.0/LINQPad.Runtime.dll` vs `ref/net46/LINQPad.exe` — the two
differ, and an API present in one may be missing in the other (see auto-memory
`reference_linqpad_driver_contexts`).

Params:
  -AssemblyPath <path>  (required) .dll / .exe to inspect
  -Type <pattern>       only types whose full name matches this regex (default: all)
  -Member <pattern>     only members whose name matches this regex - implies member listing
  -Members              list members of every matched type (implied by -Member)
  -Fields               include fields alongside methods
  -Public               only public / protected members (default: all)

Output (stdout, single JSON): { ok, assembly:{name,version,publicKey}, types:[{name,members:[…]}] }
Member entries carry name, static, virtual, visibility and parameter names.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $AssemblyPath,
    [string] $Type,
    [string] $Member,
    [switch] $Members,
    [switch] $Fields,
    [switch] $Public
)

. "$PSScriptRoot/_shared.ps1"
$ErrorActionPreference = 'Stop'

if (-not (Test-Path $AssemblyPath)) { Exit-WithError "assembly not found: $AssemblyPath" -NextAction 'pass -AssemblyPath <existing .dll/.exe>' }
if ($Member) { $Members = $true }

$stream = [System.IO.File]::OpenRead((Resolve-Path $AssemblyPath))
try {
    $pe = New-Object System.Reflection.PortableExecutable.PEReader($stream)
    if (-not $pe.HasMetadata) { Exit-WithError "no managed metadata in $AssemblyPath (native image?)" }
    $md = [System.Reflection.Metadata.PEReaderExtensions]::GetMetadataReader($pe)

    $asm = $md.GetAssemblyDefinition()

    $mask   = [System.Reflection.MethodAttributes]::MemberAccessMask
    $result = @()

    foreach ($handle in $md.TypeDefinitions) {
        $td = $md.GetTypeDefinition($handle)
        $ns = $md.GetString($td.Namespace)
        $nm = $md.GetString($td.Name)
        $full = if ($ns) { "$ns.$nm" } else { $nm }

        if ($Type -and $full -notmatch $Type) { continue }

        $entry = [ordered]@{ name = $full }

        if ($Members) {
            $list = @()

            foreach ($mh in $td.GetMethods()) {
                $m  = $md.GetMethodDefinition($mh)
                $mn = $md.GetString($m.Name)

                if ($Member -and $mn -notmatch $Member) { continue }

                $vis = ($m.Attributes -band $mask).ToString()
                if ($Public -and $vis -notin 'Public', 'Family', 'FamORAssem') { continue }

                $names = @()
                foreach ($ph in $m.GetParameters()) { $names += $md.GetString($md.GetParameter($ph).Name) }

                $list += [ordered]@{
                    kind       = 'method'
                    name       = $mn
                    static     = ($m.Attributes -band [System.Reflection.MethodAttributes]::Static)  -ne 0
                    virtual    = ($m.Attributes -band [System.Reflection.MethodAttributes]::Virtual) -ne 0
                    visibility = $vis
                    parameters = @($names | Where-Object { $_ })
                }
            }

            if ($Fields) {
                foreach ($fh in $td.GetFields()) {
                    $f  = $md.GetFieldDefinition($fh)
                    $fn = $md.GetString($f.Name)

                    if ($Member -and $fn -notmatch $Member) { continue }

                    $fvis = ($f.Attributes -band [System.Reflection.FieldAttributes]::FieldAccessMask).ToString()
                    if ($Public -and $fvis -notin 'Public', 'Family', 'FamORAssem') { continue }

                    $list += [ordered]@{ kind = 'field'; name = $fn; visibility = $fvis }
                }
            }

            # only report a type whose members were filtered away when no member filter was given
            if ($Member -and $list.Count -eq 0) { continue }

            $entry['members'] = @($list)
        }

        $result += [pscustomobject]$entry
    }

    Write-JsonOutput ([ordered]@{
        ok       = $true
        assembly = [ordered]@{
            name       = $md.GetString($asm.Name)
            version    = $asm.Version.ToString()
            publicKey  = -not $asm.PublicKey.IsNil
        }
        types    = $result
    })
}
finally {
    $stream.Dispose()
}
