# Extended filter blend modes

The Bend feBlend implementation now supports all16 modes: normal, multiply,
screen, darken, lighten, overlay, color-dodge, color-burn, hard-light, soft-light,
difference, exclusion, hue, saturation, color and luminosity. Color mixing uses
straight components; the result is combined with the original premultiplied
inputs using source-over alpha composition. Achromatic inputs and black/white
limits have explicit handling. The filter graph retains sRGB/linearRGB selection.

The formulas follow [W3C Compositing and Blending](https://www.w3.org/TR/compositing-1/#blending).
This adds filter blend modes; CSS mix-blend-mode and group isolation remain
separate, unfinished features.

All four new fixtures pass the existing Chromium limits. Both complete resvg
and Chromium reports remain available; resvg differs more on nonseparable modes
and some boundary colors. The original89 fixture matrices are unchanged.

| Fixture | MAE/255 | RMSE/255 | Max channel error |
| --- | ---: | ---: | ---: |
| filters-blend-compositing.svg | 0.542 | 2.317 | 31 |
| filters-blend-opaque.svg | 0.012 | 0.108 | 1 |
| filters-blend-linear.svg | 0.290 | 0.811 | 5 |
| filters-blend-alpha.svg | 0.076 | 0.275 | 1 |

The opaque, alpha and linear fixtures each contain16 modes ×16 color pairs.
The compositing fixture adds curved edges, clips, a luminance mask and group
opacity. The full selected suite is78/93, with all15 previous failures retained.
No thresholds or existing reference choices changed.

All33 Bend regression files pass. The128 new cases use independent Chromium
pixels with one channel level of rounding tolerance; they also pass compiled C.
Another1024 sampled C/JavaScript colors match exactly, and all7 pre-existing
filter fixtures retain identical matrices. Historical candidate evidence is in
`blend-candidate-check-report.json`, `blend-existing-fixtures-report.json` and
`blend-experiment-report.json`; their source hash matches the integrated library.

The JavaScript web blend editor flow passes in45.43s, including
filter switching, drag, exact source/pixel undo and saved SVG primitives.
All three native/web/render binaries build and all33 saved checks pass.
All93 C/JavaScript matrices match exactly. The native compositing window was
captured, inspected and closed. The rebuilt C web interaction flow passes in6.82s; its launch
binary hash matches the build report. Both web flows verify saved blend
primitives and exact source/pixel restoration. Previous
build reports identify older sources and do not prove this checkpoint's builds.
