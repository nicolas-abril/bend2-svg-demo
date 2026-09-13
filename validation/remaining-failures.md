# Remaining failure audit

Primary conformance is 108/117 with the thresholds unchanged (MAE ≤ 1/255,
RMSE ≤ 5/255, at most 1% of pixels with a channel error above 32).
`failure-audit.mjs` regenerates the cross-engine table for every failing fixture
into `failure-audit.json`; `side.mjs NAME` writes Bend | reference | difference
composites (`SIDE_REF=chromium` or `firefox` selects the engine image).

## What changed

The earlier suite compared Bend's exact 8×8 coverage with each engine's own
64×64 rasterization, so most of its 24 failures measured the reference
rasterizer rather than Bend: Skia widens diagonal strokes by 5% (the
stroke-vector path has an exact area of 225.8 px²; Bend paints 226.2, both
browsers 238) and snaps feOffset to its buffer grid (Chromium's blurred box in
filters-transforms sits at an offset of 1.5/0.5 instead of 1.8/0.65); pattern
tiles and embedded SVG images are resampled or aliased; resvg quantizes text
coverage to quarter pixels. Every reference is now rendered at eight times the
output size and box-averaged down (`reference-scale.mjs`), which removes those
artifacts while leaving geometry, layout and paint differences intact. The
earlier 1× reports and images are retained as `*-x1.json` and `*-x1.png`.
Fixtures whose result depends on the output resolution keep a 1× reference
(`referenceScale` in coverage.json): raster images are resampled at the output
resolution, feConvolveMatrix kernels default to device pixels, and morphology
radii are quantized to the filter buffer.

Three renderer rules changed, each with a regression case. Letter-spacing is no
longer applied after the last glyph of a chunk when anchoring, per CSS Text 3
("not applied at the beginning or end of a line"); this is what resvg does, and
it moved text-position from MAE 2.9 to 0.26. An embedded SVG image's intrinsic
size comes from its root width/height attributes rather than its own
stylesheet, as both browsers compute it; svg-image-auto now matches Chromium
exactly. The final filter region clips each buffer pixel by its covered
fraction (exact overlap for axis-aligned regions, sampled otherwise) instead of
including every touched pixel; intermediate primitive subregions keep the
inclusive rule so an edge is faded once. The zero-length dash fixture selects
Firefox, which paints the zero-length closed dash with its square cap as Bend
does; Chromium and resvg omit it.

## Remaining failures

| Fixture | Reference | MAE / RMSE / pixels > 32 | Cause |
| --- | --- | --- | --- |
| text-length-spans | resvg | 14.97 / 41.55 / 627 | Nested textLength. Chromium, Firefox and resvg differ from each other by MAE 15–18; Chromium adds the fitted span's spacing delta after its last glyph and re-expands fitted descendants, resvg stretches the nested spacingAndGlyphs span into the parent fit and ignores the percentage length. Bend keeps the SVG2 resolve-text-length rule (descendants with their own textLength are fixed units). |
| text-length | resvg | 1.20 / 5.38 / 70 | resvg shifts the middle-anchored fitted row by half a spacing step (`text-length-anchor-probe.json`); Chromium reproduces Bend's glyph origins to 0.045 units but differs in font rasterization. |
| text-path-basic, text-path-styles | resvg | 2.65 / 9.87 / 166, 1.69 / 8.39 / 124 | Text on paths. The engines disagree with each other (MAE 4–9 on the positions fixture); Bend's placement agrees with an analytic arc-length integral (`text-path-precision-investigation.md`). |
| text-path-positions, text-path-references | chromium | 1.11 / 4.41 / 2, 1.51 / 5.15 / 15 | Same text-on-path placement differences against Chromium's own distance approximation. |
| markers-zero | chromium | 0.75 / 6.77 / 54 | A lone `M10 10` subpath: both browsers draw a single marker rotated 45°, the direction from the origin to the point; SVG2 path directionality gives the positive x axis for a zero-length path and both start and end markers apply to its only vertex. Chromium also keeps a vertex for the equal-endpoint arc that SVG2 9.5.1 omits. |
| mask-errors | chromium | 42.5 / 104.1 / 1024 | CSS Masking: a missing, wrong, empty or zero-sized mask reference is a transparent-black layer. Every engine paints some of those targets unmasked, and no two engines agree (Chromium and Firefox differ by MAE 10.6). |
| convolve-alpha | chromium | 4.14 / 12.37 / 356 | Alpha-scaled bias per the W3C resolution retained in SVG 1.1 Second Edition; both browsers add the unscaled bias and agree with each other. |

The text and marker rows can only pass by reproducing one engine's private
behaviour, and the mask and convolution rows by leaving the specification; none
is applied. Thresholds, fixtures and the retained raw comparisons are unchanged.
