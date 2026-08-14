# Debugging managed-memory retention

How to prove — and then localise — "a process-wide cache is keeping something alive that should have died". Written after PR #5780, where a linq2db EF cache pinned an ASP.NET request scope for the lifetime of the process.

Reach for this when the symptom is *lifetime*, not correctness: a DI scope, a `DbConnection`, an `IModel`, or a whole service graph surviving the object that created it. For **ADO connection-pool** leaks (undisposed contexts held alive) the repro shape is different — see auto-memory `project_connection_leak_repro_design`.

## The test shape

```csharp
[Test]
public void CacheDoesNotRetainX()
{
    var weak = BuildAndDiscard();

    GC.Collect();
    GC.WaitForPendingFinalizers();
    GC.Collect();

    weak.IsAlive.ShouldBeFalse();

    [MethodImpl(MethodImplOptions.NoInlining)]
    static WeakReference BuildAndDiscard()
    {
        var target = /* the thing that must die */;
        using (var ctx = /* the owner */) { /* populate the cache */ }
        return new WeakReference(target);
    }
}
```

Three details are load-bearing:

- **The allocation must live in a `[MethodImpl(MethodImplOptions.NoInlining)]` static local function.** A local in the test method's own frame can stay reachable through the frame, so the test fails for a reason that has nothing to do with the cache.
- **`Collect` → `WaitForPendingFinalizers` → `Collect`.** One pass misses anything sitting on the finalizer queue.
- **The target must be something no other root can reach.** A bare `new ServiceCollection().BuildServiceProvider()` works well: nothing else in the process can reach it, so a surviving reference is unambiguously the cache's.

Such a test is only meaningful if it was **red before the fix**. A retention test written after the fix proves nothing — it would pass against an empty cache too.

## The bisect ladder

Reasoning about which field retains what is unreliable — on #5780 two confidently-reasoned hypotheses were both wrong. Bisect empirically instead, cheapest probe first. Each rung is one build.

1. **Is it ours at all?** Call the product's own `ClearCaches()` (or equivalent) immediately before the `GC.Collect` sequence. Collected ⇒ one of our caches holds it. Still alive ⇒ stop — the retainer is the framework, the harness, or the test, and no change to our code will fix it.
2. **Which cache?** Re-run the scenario populating only *one* cache (call the narrow accessor rather than the wide one). Repeat per cache.
3. **Which field?** Hold only a candidate object — the key, the value, one captured service — and nothing else, then assert the target dies. This is how #5780 cleared `IModel`: holding the model alone, with no linq2db call at all, left the provider collectable.
4. **Exactly which reference chain?** Walk the object graph and print the path (below).

## Printing the actual reference chain

A BFS over instance fields from the cache root to the target, recording a parent map, prints the chain that reasoning keeps getting wrong. On #5780 it produced the answer in one run:

```
ConcurrentDictionary`2._tables -> Tables._buckets -> [] -> VolatileNode._node
  -> Node._value [EFCoreMetadataReader]
  -> EFCoreMetadataReader._logger [DiagnosticsLogger`1]
  -> DiagnosticsLogger`1.<Interceptors>k__BackingField [Interceptors]
  -> Interceptors.<CoreOptionsExtension>k__BackingField [CoreOptionsExtension]
  -> CoreOptionsExtension._applicationServiceProvider
```

Implementation notes, each of which cost a wrong answer or a wasted run:

- **Do not skip value-type arrays.** .NET's `ConcurrentDictionary` stores its buckets as `VolatileNode[]` — an array of **structs** wrapping the node reference. A walker that only enumerates arrays of reference types never enters the dictionary and reports *"no path"*, which reads exactly like "the cache is innocent". This produced a false negative on the first #5780 run. Enumerate every array whose element type is not primitive, and let boxing carry each struct element into the field walk.
- **Walk the inheritance chain**, `DeclaredOnly` per level, or you miss base-class fields and double-visit others.
- **Compare with `ReferenceEqualityComparer.Instance`** for both the visited set and the parent map. Value equality collapses distinct objects and truncates the path.
- **Check the target *after* adding to the visited set, not before** — otherwise the first visit is swallowed by the dedup.
- **Cap the depth** (~25 is plenty) and wrap `FieldInfo.GetValue` in `try`/`catch`; some runtime types throw on reflection access.
- Auto-property backing fields appear as `<Name>k__BackingField`, which is usually enough to identify the property without extra work.

Keep the walker as a throwaway test in the worktree; it is a diagnostic, not something to commit.

## Reading the result

The chain names the field to change, but the fix is rarely "remove the field" — it is usually **reconstruct the retaining object without the dependency you don't want**. See [`bug-investigation.md`](bug-investigation.md) → *A cached object that retains too much*.

Two framework-level checks worth making once you have the chain:

- **Does the framework itself guard against this?** If it caches the same object long-term, look at what it strips first. EF's `ServiceProviderCache.GetOrAdd` replaces the options' core extension with `WithApplicationServiceProvider(null)` before storing — direct evidence that retaining it is a known hazard, and a ready-made idiom to copy.
- **Distinguish the *unbounded* half from the *one-instance* half.** A cache keyed on a per-instance object grows without bound; a cache whose single entry holds one graph forever is a fixed cost. They need different fixes (`ConditionalWeakTable` for the former, dropping the reference for the latter) and warrant different severities.
