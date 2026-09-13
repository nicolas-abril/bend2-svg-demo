# Paint order and overlapping text

The paint-order and glyph-run changes are integrated. All 46 Bend checks pass,
all 108 C/JavaScript fixture matrices are identical, and both web backends pass
the full editor flow. The 105 preceding fixture matrices are unchanged. The
primary suite passes 85/108, retaining the same 23 earlier failures. Build and
source hashes are recorded in paint-order-build-report.json; browser reports
are browser-paint-order-report.json and browser-paint-order-js-report.json.

The library implements all six permutations of fill, stroke and markers.
Omitted operations follow in their default order. The inherited CSS property
handles normal, whitespace/case normalization, and invalid/duplicate-token
fallback. Shape paints, marker paints, owner opacity, masks and filters retain
their existing compositing boundaries. The web property menu exposes paint-order.

Adjacent glyphs with a shared style now form one internal geometry for painting.
Overlapping glyphs receive one fill operation and one stroke operation, in the
requested order, rather than accumulating fill opacity separately. SVG text
ignores fill-rule. Glyph runs are only in the rendering copy: source text,
character layout, resource references and editor ownership are preserved.
Different span-style runs remain separate; full cross-span painting equivalence
still requires broader conformance tests.

The new synthetic regression checks all six translucent fill/stroke/marker
orders against independently calculated colors. A full-matrix regression compares
overlapping text with the equivalent compound path, for both default and
stroke-first order, including text's ignored evenodd fill rule.

All three added independent fixtures pass their predeclared primary thresholds:

| Fixture | Primary reference | MAE | RMSE | Max channel error |
| --- | --- | ---: | ---: | ---: |
| paint-order-shapes | Chromium |0.041|0.203|1|
| paint-order-markers | Chromium |0.464|1.046|14|
| text-paint-order | resvg |0.314|1.022|13|

Alternate comparisons are retained. Markers exceed the resvg limits, and text
exceeds the Chromium limits. These are not claimed identical across all engines.
The implementation follows [SVG2 paint order](https://www.w3.org/TR/SVG2/painting.html#PaintOrder)
and the [text painting rules](https://www.w3.org/TR/SVG2/text.html#TextRenderingOrder).

The first JavaScript attempt exceeded its startup timeout under concurrent
compiler/fixture load. A subsequent test click missed the drawing because its
viewBox scales by four in the 256-pixel viewport. The corrected complete flow
passes, including all three full matrices, translucent marker colors, text
paint order, ignored text fill-rule, owning-text deletion, exact undo and save.
Earlier failed attempts are not counted as passing frontend checks.

The native window screenshot matches the headless matrix except for 174 pixels
in the operating system’s rounded bottom corners. The input guard stopped
before sending events because the window did not acquire focus. Native input
remains unverified; see [the native report](native-paint-order-report.json).
