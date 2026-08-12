// Aggregate self / inclusive time per frame from a speedscope JSON produced by
//     dotnet-trace collect --format speedscope -- <app> <args>
//
// The exporter is TraceEvent's, which emits "evented" profiles (open/close event streams), not the
// "sampled" profiles speedscope's own docs describe - code written against samples/weights silently
// reports zero. Self time is not useful (leaves collapse into TraceEvent's CPU_TIME /
// UNMANAGED_CODE_TIME pseudo-frames); inclusive time is what localises cost. Totals are summed over
// all threads, so normalise per thread when interpreting percentages.
//
// The JSON is routinely ~100MB, which rules out PowerShell's ConvertFrom-Json - hence a C# script.
//
// Usage:
//     dotnet script .claude/scripts/speedscope-top.csx -- <trace>.speedscope.json [top] [nameFilter]
//
// See .claude/docs/measuring-query-build.md for the wider recipe.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;

if (Args.Count < 1)
{
    Console.Error.WriteLine("usage: speedscope-top.csx -- <trace>.speedscope.json [top] [nameFilter]");
    return 1;
}

var path   = Args[0];
var top    = Args.Count > 1 ? int.Parse(Args[1]) : 30;
var filter = Args.Count > 2 ? Args[2] : null;

var fs  = File.OpenRead(path);
var doc = JsonDocument.Parse(fs);

var root   = doc.RootElement;
var frames = root.GetProperty("shared").GetProperty("frames");
var names  = new string[frames.GetArrayLength()];

var fi = 0;
foreach (var f in frames.EnumerateArray())
    names[fi++] = f.TryGetProperty("name", out var n) ? (n.GetString() ?? "?") : "?";

var self  = new Dictionary<string, double>();
var incl  = new Dictionary<string, double>();
var total = 0.0;

foreach (var p in root.GetProperty("profiles").EnumerateArray())
{
    if (p.GetProperty("type").GetString() != "evented")
        continue;

    var stack     = new List<(int Frame, double At)>();
    var openCount = new Dictionary<int, int>();
    var lastAt    = 0.0;
    var first     = true;

    foreach (var ev in p.GetProperty("events").EnumerateArray())
    {
        var kind = ev.GetProperty("type").GetString();
        var frm  = ev.GetProperty("frame").GetInt32();
        var at   = ev.GetProperty("at").GetDouble();

        if (first) { lastAt = at; first = false; }

        // time since the previous event belongs to whatever was on top of the stack
        if (stack.Count > 0 && at > lastAt)
        {
            var leaf = names[stack[stack.Count - 1].Frame];
            self.TryGetValue(leaf, out var sv);
            self[leaf] = sv + (at - lastAt);
            total     += at - lastAt;
        }

        lastAt = at;

        if (kind == "O")
        {
            stack.Add((frm, at));
            openCount.TryGetValue(frm, out var c);
            openCount[frm] = c + 1;
        }
        else
        {
            for (var i = stack.Count - 1; i >= 0; i--)
            {
                if (stack[i].Frame != frm)
                    continue;

                openCount.TryGetValue(frm, out var c);
                openCount[frm] = c - 1;

                // count only the outermost activation so recursion is not double counted
                if (c - 1 == 0)
                {
                    var nm = names[frm];
                    incl.TryGetValue(nm, out var iv);
                    incl[nm] = iv + (at - stack[i].At);
                }

                stack.RemoveRange(i, stack.Count - i);
                break;
            }
        }
    }
}

bool Keep(string n) => filter == null || n.IndexOf(filter, StringComparison.OrdinalIgnoreCase) >= 0;

Console.WriteLine($"total attributed time: {total:F1} ms (summed over all threads)   frames: {names.Length}");
Console.WriteLine();
Console.WriteLine("=== TOP SELF (expect TraceEvent pseudo-frames to dominate - prefer inclusive) ===");
foreach (var kv in self.Where(x => Keep(x.Key)).OrderByDescending(x => x.Value).Take(top))
    Console.WriteLine($"{100 * kv.Value / total,6:F2}%  {kv.Value,10:F1}ms  {kv.Key}");

Console.WriteLine();
Console.WriteLine("=== TOP INCLUSIVE ===");
foreach (var kv in incl.Where(x => Keep(x.Key)).OrderByDescending(x => x.Value).Take(top))
    Console.WriteLine($"{100 * kv.Value / total,6:F2}%  {kv.Value,10:F1}ms  {kv.Key}");

return 0;
