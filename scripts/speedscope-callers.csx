// Attribute the inclusive time of frames whose name contains <frameSubstring> to their nearest
// linq2db! callers, from a speedscope JSON produced by
//     dotnet-trace collect --format speedscope -- <app> <args>
//
// speedscope-top.csx ranks frames but cannot say who called them; this answers "which build-path code
// reaches X" - e.g. whether DynamicMethod / CompileExpression time is per-build or one-time setup.
// Only the outermost activation of a matching frame is charged, so recursion is not double counted.
// Frames between the match and its linq2db! callers (BCL, System.Linq.Expressions) are skipped.
//
// Usage:
//     dotnet script .claude/scripts/speedscope-callers.csx -- <trace>.speedscope.json <frameSubstring> [depth] [top]
//
// depth = linq2db! caller frames per chain (default 4); top = chains printed (default 20).
// Written in C# 7 style: dotnet script's compiler rejects `using var` and nullable annotations.
// See .claude/docs/measuring-query-build.md for the wider recipe.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;

if (Args.Count < 2)
{
    Console.Error.WriteLine("usage: speedscope-callers.csx -- <trace>.speedscope.json <frameSubstring> [depth] [top]");
    return 1;
}

var path   = Args[0];
var filter = Args[1];
var depth  = Args.Count > 2 ? int.Parse(Args[2]) : 4;
var top    = Args.Count > 3 ? int.Parse(Args[3]) : 20;

var fs  = File.OpenRead(path);
var doc = JsonDocument.Parse(fs);

var root   = doc.RootElement;
var frames = root.GetProperty("shared").GetProperty("frames");
var names  = new string[frames.GetArrayLength()];

var fi = 0;
foreach (var f in frames.EnumerateArray())
    names[fi++] = f.TryGetProperty("name", out var n) ? (n.GetString() ?? "?") : "?";

string Short(string s)
{
    var p = s.IndexOf('(');
    if (p > 0) s = s.Substring(0, p);
    var b = s.IndexOf('!');
    return b >= 0 ? s.Substring(b + 1) : s;
}

var match = names.Select(x => x.IndexOf(filter, StringComparison.OrdinalIgnoreCase) >= 0).ToArray();
var agg   = new Dictionary<string, (double Ms, int Count)>();

foreach (var p in root.GetProperty("profiles").EnumerateArray())
{
    if (p.GetProperty("type").GetString() != "evented")
        continue;

    var stack  = new List<(int Frame, double At, string Key)>();
    var active = 0;

    foreach (var ev in p.GetProperty("events").EnumerateArray())
    {
        var kind = ev.GetProperty("type").GetString();
        var frm  = ev.GetProperty("frame").GetInt32();
        var at   = ev.GetProperty("at").GetDouble();

        if (kind == "O")
        {
            string key = null;

            if (match[frm] && active == 0)
            {
                var chain = new List<string>();
                for (var i = stack.Count - 1; i >= 0 && chain.Count < depth; i--)
                {
                    var nm = names[stack[i].Frame];
                    if (nm.StartsWith("linq2db!", StringComparison.Ordinal) && !match[stack[i].Frame])
                        chain.Add(Short(nm));
                }

                key = Short(names[frm]) + "  <=  " + string.Join("  <=  ", chain);
            }

            if (match[frm]) active++;
            stack.Add((frm, at, key));
        }
        else
        {
            for (var i = stack.Count - 1; i >= 0; i--)
            {
                if (stack[i].Frame != frm)
                    continue;

                // a close may pop several frames at once; release every matched one it pops
                for (var j = i; j < stack.Count; j++)
                {
                    if (match[stack[j].Frame]) active--;

                    var k = stack[j].Key;
                    if (k != null)
                    {
                        agg.TryGetValue(k, out var v);
                        agg[k] = (v.Ms + (at - stack[j].At), v.Count + 1);
                    }
                }

                stack.RemoveRange(i, stack.Count - i);
                break;
            }
        }
    }
}

foreach (var kv in agg.OrderByDescending(x => x.Value.Ms).Take(top))
    Console.WriteLine($"{kv.Value.Ms,9:F1}ms  x{kv.Value.Count,-6} {kv.Key}");

return 0;
