# Review rubric module: documentation site

Rules of the [`code-reviewer`](../../agents/code-reviewer.md) rubric that fire only on changes under `docs/source/` — the docfx site's articles, toc files, landing page and `templates/custom/`. Read when the briefing's `rubricModules` lists this module, or omits the field. Rule numbers are the core rubric's; "rule N" resolves through the core's **Focus scoping** index. In a multi-pass review, apply only the rules of your pass's focus:

| Rule | Focus |
|---|---|
| 36 | `code-correctness` |

36. **Hand-written site HTML and CSS: accessibility and claims.** Markdown pages and `templates/custom/` may carry raw HTML and CSS that docfx passes through unchecked: the `-WarningsAsErrors` build validates links and xrefs, not markup. On every added or changed block, check:
    - **No interactive control hidden with `display: none` / `visibility: hidden`.** It leaves the tab order, so a CSS-only widget (radio/checkbox tabs, toggles) becomes mouse-only. Visually hidden controls use the clip pattern and keep a `:focus-visible` style on what the user sees. `MIN`; `MAJ` when the widget is the page's main content.
    - **Every link has text.** An empty `<a class="stretched-link"></a>` or an icon-only anchor is announced as an unnamed link; put the link on the title text or add an accessible name. `MIN`.
    - **Heading levels don't skip and don't mis-nest.** `<h1>` → `<h3>` skips; a row of `<h3>`s directly after a card row of `<h2>`s nests under the last card. Fix with real levels plus a size class (`class="h4"`), or a visually hidden section heading. `NIT`.
    - **Small text meets WCAG AA (4.5:1 under 18.66 px bold / 24 px regular).** Low-alpha whites on a dark hero and a light accent on a white body are the usual failures. Check each colour in **both** themes (`[data-bs-theme="dark"]`) and sweep every same-shape sibling rule in the file, not only the line the finding names. State whether a ratio is computed or browser-measured. `MIN`.
    - **Overflow you can't see.** A `overflow-x: auto` strip with a hidden scrollbar hides items at narrow widths, and keyboard focus scrolls the focused *control* into view, not its label. Prefer wrapping. `MIN`.
    - **Feature claims are true of linq2db.** Landing and overview copy ("no reflection at runtime", "fastest") is a product statement; a false one is a defect, not style. `MIN`.

    A browser pass (keyboard, screen-reader tree, a narrow and a desktop viewport) is the only full check. When the PR has none, say so and list what remains unverified. (Surfaced on #6482: the code review found five of these on a landing page ported from linq2db/docs#59, and the author found the sixth, `display: none` radios. No rubric rule covered site markup.)
