// Splits one-line method chains onto one call per line (testing.md -> Test layout, rule 1), on the lines a
// test-diff-sweep.ps1 report names. Usage, from the repository root:
//   .claude/scripts/test-diff-sweep.ps1 -Repo <worktree> -IncludeWorkingTree > <worktree>/.build/.agents/sweep.json
//   dotnet run --project .claude/tools/chain-split -c Release -- <worktree> <worktree>/.build/.agents/sweep.json
// Edits the files in place; review the diff. Chains nested in an argument stay on the call's line, and chains that
// are an operand of a binary operator are listed on stdout and left alone (pull both into a local by hand); text
// inside string literals (generator-test input) is never touched.
// A chain: a member-access sequence whose head is a call-like expression (invocation, object creation,
// parenthesized, element access) followed by >= 1 member, or a dotted name followed by >= 2 members of which
// the first is invoked. Only chains that sit on one line are split; chains inside interpolated strings are not.
using System.Text.Json;

using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using Microsoft.CodeAnalysis.Text;

var repo  = args[0];
var sweep = JsonDocument.Parse(File.ReadAllText(args[1])).RootElement;

var targets = new Dictionary<string, HashSet<int>>(StringComparer.OrdinalIgnoreCase);
foreach (var listName in new[] { "chains", "nestedChains" })
{
	foreach (var hit in sweep.GetProperty(listName).EnumerateArray())
	{
		var file = hit.GetProperty("file").GetString()!;
		if (!targets.TryGetValue(file, out var set))
			targets[file] = set = [];
		set.Add(hit.GetProperty("line").GetInt32());
	}
}

var total = 0;
foreach (var (relative, lines) in targets)
{
	var path = Path.Combine(repo, relative);
	var text = File.ReadAllText(path);
	var eol  = text.Contains("\r\n", StringComparison.Ordinal) ? "\r\n" : "\n";
	var tree = CSharpSyntaxTree.ParseText(text, new CSharpParseOptions(LanguageVersion.Preview));
	var root = tree.GetRoot();
	var src  = tree.GetText();

	var changes = new List<TextChange>();

	foreach (var node in root.DescendantNodes().OfType<ExpressionSyntax>())
	{
		if (!IsChainTop(node))
			continue;

		var span      = node.GetLocation().GetLineSpan();
		var startLine = span.StartLinePosition.Line + 1;
		if (span.StartLinePosition.Line != span.EndLinePosition.Line || !lines.Contains(startLine))
			continue;
		if (node.Ancestors().Any(a => a is InterpolationSyntax))
			continue;
		// an outer chain on the same line is split instead; a chain inside its argument stays on the call's line
		if (node.Ancestors().OfType<ExpressionSyntax>().Any(a => IsChainTop(a) && a.GetLocation().GetLineSpan().StartLinePosition.Line == span.StartLinePosition.Line))
			continue;
		// an operand of `&&`, `==`, `+` …: breaking it strands the operator mid-chain (#6037:
		// `value != null && value` / `.GetType()` / `.IsGenericType && value`) - pull it into a local by hand
		if (node.Ancestors().TakeWhile(static a => a is ExpressionSyntax).Any(static a => a is BinaryExpressionSyntax))
		{
			Console.WriteLine($"{relative}:{startLine}: chain is an operand of a binary expression - split by hand");
			continue;
		}

		var dots = SplitDots(node);
		if (dots.Count == 0)
			continue;

		var lineText = src.Lines[span.StartLinePosition.Line].ToString();
		var indent   = lineText[..(lineText.Length - lineText.TrimStart().Length)] + "\t";

		foreach (var dot in dots)
		{
			// replace the whitespace before the dot with a break: column-aligned code pads the receiver
			// (`model  .FindType`), and inserting at the dot left that padding trailing (#6037 NIT001)
			var start = dot.SpanStart;
			while (start > 0 && src[start - 1] is ' ' or '\t')
				start--;
			changes.Add(new TextChange(TextSpan.FromBounds(start, dot.SpanStart), eol + indent));
		}
		total++;
	}

	if (changes.Count == 0)
		continue;

	var updated = src.WithChanges(changes.OrderBy(c => c.Span.Start)).ToString();
	File.WriteAllText(path, updated, new System.Text.UTF8Encoding(text.Length > 0 && text[0] == '﻿'));
	Console.WriteLine($"{relative}: {changes.Count} breaks");
}
Console.WriteLine($"chains split: {total}");

// the outermost member-access/invocation node of a chain
static bool IsChainTop(ExpressionSyntax node)
{
	if (node is not (InvocationExpressionSyntax or MemberAccessExpressionSyntax or ConditionalAccessExpressionSyntax))
		return false;
	var parent = node.Parent;
	return parent switch
	{
		MemberAccessExpressionSyntax ma when ma.Expression == node        => false,
		InvocationExpressionSyntax inv when inv.Expression == node        => false,
		ElementAccessExpressionSyntax ea when ea.Expression == node       => false,
		ConditionalAccessExpressionSyntax ca when ca.Expression == node   => false,
		PostfixUnaryExpressionSyntax { RawKind: (int)SyntaxKind.SuppressNullableWarningExpression } => false,
		_                                                                  => true,
	};
}

// dots to break before: walk the receiver spine from the top down, collect member-access dots, then decide
// where the head ends
static List<SyntaxToken> SplitDots(ExpressionSyntax top)
{
	var segments = new List<(SyntaxToken Dot, bool Invoked)>();
	ExpressionSyntax? current = top;
	var invokedNext = false;

	while (current is not null)
	{
		switch (current)
		{
			// a call with no receiver (F(x)) is a call-like head
			case InvocationExpressionSyntax inv when inv.Expression is not MemberAccessExpressionSyntax && segments.Count > 0:
				segments.Reverse();
				return Decide(segments, callLikeHead: true);
			case InvocationExpressionSyntax inv:
				invokedNext = true;
				current = inv.Expression;
				continue;
			case ElementAccessExpressionSyntax ea:
				invokedNext = true;
				current = ea.Expression;
				continue;
			case PostfixUnaryExpressionSyntax { RawKind: (int)SyntaxKind.SuppressNullableWarningExpression } bang:
				current = bang.Operand;
				continue;
			case MemberAccessExpressionSyntax ma:
				segments.Add((ma.OperatorToken, invokedNext));
				invokedNext = false;
				current = ma.Expression;
				continue;
			default:
				// head reached
				segments.Reverse();
				var callLikeHead = current is InvocationExpressionSyntax or ObjectCreationExpressionSyntax or ImplicitObjectCreationExpressionSyntax
					or ParenthesizedExpressionSyntax or ElementAccessExpressionSyntax or AwaitExpressionSyntax or TypeOfExpressionSyntax
					or BaseObjectCreationExpressionSyntax or ThisExpressionSyntax or LiteralExpressionSyntax or InterpolatedStringExpressionSyntax;
				return Decide(segments, callLikeHead || IsCallLike(current));
		}
	}
	return [];
}

static bool IsCallLike(ExpressionSyntax head) => head is InvocationExpressionSyntax;

static List<SyntaxToken> Decide(List<(SyntaxToken Dot, bool Invoked)> segments, bool callLikeHead)
{
	if (callLikeHead)
		return segments.Count >= 1 ? segments.Select(s => s.Dot).ToList() : [];

	// a dotted-name head (namespace / type / local / field path): the head runs up to the member that is first
	// invoked or indexed; everything from that member on is the chain
	var first = segments.FindIndex(s => s.Invoked);
	if (first < 0)
		return [];
	// x.M() and System.IO.File.M() are single calls, not chains; x.M().N() is a chain. The dotted prefix
	// (System.IO.File) stays on the first line.
	if (segments.Count - first < 2)
		return [];
	return segments.Skip(first).Select(s => s.Dot).ToList();
}
