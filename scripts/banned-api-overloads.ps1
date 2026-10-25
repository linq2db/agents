#!/usr/bin/env pwsh
<#
Find overloads that a `BannedSymbols.txt` ban list does not cover: every public
method of a banned member's declaring type with the same name whose
documentation ID is not banned.

Why this script exists
----------------------
RS0030 bans by documentation ID, i.e. per overload. A new .NET major adds
overloads (`params ReadOnlySpan<object?>`, `ReadOnlySpan<char>` / UTF-8 twins,
new optional-argument shapes), and C# overload resolution often prefers the new
one, so code that was banned keeps compiling against the new TFM with no
warning. The rule is in `.claude/docs/code-design.md` -> "Adding a .NET major
TFM: re-check the ban lists"; this script makes its "list the gaps" step
mechanical. It reads reference assemblies with System.Reflection.Metadata, so it
needs no build and no SDK for the target TFM - only its targeting pack.

Contract
--------
Input (named parameters):
  -RefDir         <path[]>  required; reference-assembly directories of the TFM to
                            check, e.g. ...\packs\Microsoft.NETCore.App.Ref\11.0.0\ref\net11.0
  -BaselineRefDir <path[]>  optional; the previous TFM's directories. When given,
                            every gap is marked `newInTarget` = true when the
                            overload does not exist in the baseline.
  -BanFile        <path[]>  optional; default: every tracked `BannedSymbols.txt`
                            under -RepoRoot
  -RepoRoot       <path>    optional; default: current directory

Output (stdout, single JSON object):
  {
    "gaps": [ { "banFile": "Source/BannedSymbols.txt", "member": "System.String.Format",
                "docId": "M:System.String.Format(System.String,System.ReadOnlySpan{System.Object})",
                "newInTarget": false } ],
    "unresolved": [ { "banFile": "...", "docId": "M:..." } ]   # ban entries matching no overload in -RefDir
  }

A gap is a candidate, not a verdict: an overload that takes an IFormatProvider,
a StringComparison or a char is often the sanctioned alternative the ban's
message points to. Unresolved entries are expected for non-BCL members
(e.g. linq2db's own types) and for members of packages outside -RefDir.

Exit codes: 0 = success (gaps included); 1 = bad input.
#>

param(
    [Parameter(Mandatory)][string[]]$RefDir,
    [string[]]$BaselineRefDir = @(),
    [string[]]$BanFile        = @(),
    [string]$RepoRoot         = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

foreach ($d in $RefDir + $BaselineRefDir) {
    if (-not (Test-Path -LiteralPath $d -PathType Container)) {
        [Console]::Error.WriteLine("Reference directory not found: $d")
        exit 1
    }
}

if ($BanFile.Count -eq 0) {
    $BanFile = @(git -C $RepoRoot ls-files -- '*BannedSymbols.txt' | ForEach-Object { Join-Path $RepoRoot $_ })
    if ($BanFile.Count -eq 0) {
        [Console]::Error.WriteLine("No tracked BannedSymbols.txt under $RepoRoot")
        exit 1
    }
}

if (-not ('BannedOverloads.Scanner' -as [type])) {
    Add-Type -ReferencedAssemblies System.Reflection.Metadata, System.Collections.Immutable, System.Runtime, System.Collections, System.Linq -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Collections.Immutable;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Reflection.Metadata;
using System.Reflection.PortableExecutable;

namespace BannedOverloads
{
	sealed class DocIdProvider : ISignatureTypeProvider<string, object>
	{
		public static readonly DocIdProvider Instance = new();

		public string GetPrimitiveType(PrimitiveTypeCode t) => t switch
		{
			PrimitiveTypeCode.Boolean        => "System.Boolean",
			PrimitiveTypeCode.Byte           => "System.Byte",
			PrimitiveTypeCode.SByte          => "System.SByte",
			PrimitiveTypeCode.Char           => "System.Char",
			PrimitiveTypeCode.Int16          => "System.Int16",
			PrimitiveTypeCode.UInt16         => "System.UInt16",
			PrimitiveTypeCode.Int32          => "System.Int32",
			PrimitiveTypeCode.UInt32         => "System.UInt32",
			PrimitiveTypeCode.Int64          => "System.Int64",
			PrimitiveTypeCode.UInt64         => "System.UInt64",
			PrimitiveTypeCode.Single         => "System.Single",
			PrimitiveTypeCode.Double         => "System.Double",
			PrimitiveTypeCode.IntPtr         => "System.IntPtr",
			PrimitiveTypeCode.UIntPtr        => "System.UIntPtr",
			PrimitiveTypeCode.Object         => "System.Object",
			PrimitiveTypeCode.String         => "System.String",
			PrimitiveTypeCode.TypedReference => "System.TypedReference",
			PrimitiveTypeCode.Void           => "System.Void",
			_                                => t.ToString(),
		};

		public string GetTypeFromDefinition(MetadataReader r, TypeDefinitionHandle h, byte kind) => Scanner.TypeName(r, h);
		public string GetTypeFromReference (MetadataReader r, TypeReferenceHandle  h, byte kind) => Scanner.TypeName(r, h);
		public string GetTypeFromSpecification(MetadataReader r, object ctx, TypeSpecificationHandle h, byte kind)
			=> r.GetTypeSpecification(h).DecodeSignature(this, ctx);

		public string GetSZArrayType(string e)                 => e + "[]";
		public string GetArrayType(string e, ArrayShape s)     => e + "[" + string.Join(",", Enumerable.Repeat("0:", s.Rank)) + "]";
		public string GetByReferenceType(string e)             => e + "@";
		public string GetPointerType(string e)                 => e + "*";
		public string GetPinnedType(string e)                  => e;
		public string GetModifiedType(string m, string u, bool req) => u;
		public string GetGenericTypeParameter(object ctx, int i)   => "`" + i;
		public string GetGenericMethodParameter(object ctx, int i) => "``" + i;
		public string GetFunctionPointerType(MethodSignature<string> s) => "=FUNC:" + s.ReturnType;

		public string GetGenericInstantiation(string g, ImmutableArray<string> args)
		{
			var tick = g.LastIndexOf('`');
			return (tick > 0 ? g.Substring(0, tick) : g) + "{" + string.Join(",", args) + "}";
		}
	}

	public sealed class Overload
	{
		public string DocId    = "";
		public string Member   = "";
	}

	public static class Scanner
	{
		public static string TypeName(MetadataReader r, TypeDefinitionHandle h)
		{
			var t    = r.GetTypeDefinition(h);
			var name = r.GetString(t.Name);
			var decl = t.GetDeclaringType();
			if (!decl.IsNil)
				return TypeName(r, decl) + "." + name;
			var ns = r.GetString(t.Namespace);
			return ns.Length == 0 ? name : ns + "." + name;
		}

		public static string TypeName(MetadataReader r, TypeReferenceHandle h)
		{
			var t    = r.GetTypeReference(h);
			var name = r.GetString(t.Name);
			if (t.ResolutionScope.Kind == HandleKind.TypeReference)
				return TypeName(r, (TypeReferenceHandle)t.ResolutionScope) + "." + name;
			var ns = r.GetString(t.Namespace);
			return ns.Length == 0 ? name : ns + "." + name;
		}

		static bool IsVisible(MetadataReader r, TypeDefinition t)
		{
			var vis = t.Attributes & TypeAttributes.VisibilityMask;
			if (vis == TypeAttributes.Public)
				return true;
			if (vis != TypeAttributes.NestedPublic && vis != TypeAttributes.NestedFamily && vis != TypeAttributes.NestedFamORAssem)
				return false;
			return IsVisible(r, r.GetTypeDefinition(t.GetDeclaringType()));
		}

		// every public/protected method of the requested declaring types, keyed "Type.Name"
		public static List<Overload> Scan(string[] dirs, HashSet<string> members)
		{
			var result = new List<Overload>();
			var seen   = new HashSet<string>(StringComparer.Ordinal);

			foreach (var dir in dirs)
			foreach (var file in Directory.EnumerateFiles(dir, "*.dll"))
			{
				using var stream = File.OpenRead(file);
				using var pe     = new PEReader(stream);
				if (!pe.HasMetadata)
					continue;
				var r = pe.GetMetadataReader();

				foreach (var th in r.TypeDefinitions)
				{
					var t = r.GetTypeDefinition(th);
					if (!IsVisible(r, t))
						continue;
					var typeName = TypeName(r, th);

					foreach (var mh in t.GetMethods())
					{
						var m      = r.GetMethodDefinition(mh);
						var access = m.Attributes & MethodAttributes.MemberAccessMask;
						if (access != MethodAttributes.Public && access != MethodAttributes.Family && access != MethodAttributes.FamORAssem)
							continue;

						var name   = r.GetString(m.Name);
						var key    = typeName + "." + name.Replace('.', '#');
						if (!members.Contains(key))
							continue;

						var sig    = m.DecodeSignature(DocIdProvider.Instance, null);
						var arity  = m.GetGenericParameters().Count;
						var docId  = "M:" + key + (arity > 0 ? "``" + arity : "")
							+ (sig.ParameterTypes.Length > 0 ? "(" + string.Join(",", sig.ParameterTypes) + ")" : "");
						if (name == "op_Implicit" || name == "op_Explicit")
							docId += "~" + sig.ReturnType;

						if (seen.Add(docId))
							result.Add(new Overload { DocId = docId, Member = key });
					}
				}
			}

			return result;
		}
	}
}
'@
}

# ban entries: "M:<id>; message" / "M:<id> message" / comments (# or //)
$bans = foreach ($file in $BanFile) {
    $rel = [IO.Path]::GetRelativePath($RepoRoot, $file).Replace('\', '/')
    foreach ($line in Get-Content -LiteralPath $file) {
        $l = $line.Trim()
        if ($l -notmatch '^M:') { continue }
        $id     = ($l -split ';', 2)[0].Trim()
        $member = ($id -replace '\(.*$', '') -replace '``\d+$', ''
        [pscustomobject]@{ banFile = $rel; docId = $id; member = $member.Substring(2) }
    }
}

$members = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($b in $bans) { [void]$members.Add($b.member) }

$target   = [BannedOverloads.Scanner]::Scan([string[]]$RefDir, $members)
$baseline = if ($BaselineRefDir.Count) {
    $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($o in [BannedOverloads.Scanner]::Scan([string[]]$BaselineRefDir, $members)) { [void]$ids.Add($o.DocId) }
    $ids
}

$targetIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($o in $target) { [void]$targetIds.Add($o.DocId) }

$gaps = foreach ($group in $bans | Group-Object banFile) {
    $banned  = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $inFile  = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($b in $group.Group) { [void]$banned.Add($b.docId); [void]$inFile.Add($b.member) }

    foreach ($o in $target | Where-Object { $inFile.Contains($_.Member) -and -not $banned.Contains($_.DocId) } | Sort-Object DocId) {
        [pscustomobject]@{
            banFile     = $group.Name
            member      = $o.Member
            docId       = $o.DocId
            newInTarget = if ($null -ne $baseline) { -not $baseline.Contains($o.DocId) } else { $null }
        }
    }
}

$unresolved = foreach ($b in $bans) {
    if (-not $targetIds.Contains($b.docId)) { [pscustomobject]@{ banFile = $b.banFile; docId = $b.docId } }
}

[pscustomobject]@{
    gaps       = @($gaps)
    unresolved = @($unresolved)
} | ConvertTo-Json -Depth 4
