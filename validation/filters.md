# Filter implementation and validation

The app implements ten SVG filter primitives in `svg.bend`: `feFlood`,
`feOffset`, `feGaussianBlur`, `feDropShadow`, `feColorMatrix`,
`feComponentTransfer`, `feComposite`, `feBlend`, `feMerge`, and `feMorphology`.
Parsing, graph resolution, intermediate buffers and pixel operations all run in
Bend. Neither frontend invokes a reference renderer.

Scene preparation walks children, masks, markers and pattern content before
rasterizing each filtered element. Buffers use compressed quadtrees of floating
point premultiplied RGBA values, with bilinear sampling and explicit color-space
conversion. SourceGraphic retains descendant effects; the filtered element's own
clip, mask and opacity apply afterward. Picking uses its original geometry.

The implementation follows the filter graph, default input, coordinate-system,
color-space and compositing rules in [Filter Effects Level 1](https://www.w3.org/TR/filter-effects-1/).
Named results resolve only preceding primitives; repeated names use the latest
result. SourceAlpha shares SourceGraphic's alpha. The default processing space
is linear RGB, with sRGB overrides; matrix and transfer operations use straight
color components, while blur and composition use premultiplied colors.

Filter buffers are limited to 1024 pixels on either axis. Larger regions reduce
buffer resolution. Gaussian blur uses two normalized, separable kernels truncated
at three standard deviations, following transformed primitive axes. Each kernel
has at most 1025 taps; larger radii increase tap spacing. This is an approximation,
and reference engines use different blur kernels and offscreen resolutions.
Filter clipping includes boundary pixels detected by the requested sampling grid;
very narrow fractional regions need further testing, especially while dragging
at AA1. Hard clipping, transformed edges and repeated sampling remain limitations.

Unsupported features include CSS filter functions and filter lists, external
filter references, FillPaint/StrokePaint and backdrop inputs, feImage, feConvolveMatrix, feDisplacementMap, lighting,
feTile and feTurbulence. Invalid attribute handling and extreme/singular
transforms need broader coverage. Unsupported primitives currently pass through
the selected input. This is partial filter support, not full conformance.

## Pixel comparisons

All seven filter fixtures are rendered at 64×64 with AA8. Chromium is the primary
reference consistently across this group; all resvg 2.6.2 comparisons are retained.
The existing limits remain MAE ≤ 1/255, RMSE ≤ 5/255 and at most 1% of pixels with
channel error greater than 32. Five fixtures pass and two fail.

| Fixture | MAE /255 | RMSE /255 | Max channel error | Pixels >32 | Verdict |
| --- | ---: | ---: | ---: | ---: | --- |
| filters-basic.svg | 0.109 | 0.330 | 1 | 0 | PASS |
| filters-blend.svg | 0.439 | 2.077 | 31 | 0 | PASS |
| filters-blur.svg | 0.953 | 3.273 | 31 | 0 | PASS |
| filters-composite.svg | 0.680 | 3.763 | 58 | 28 | PASS |
| filters-nested.svg | 1.811 | 6.488 | 67 | 73 | FAIL |
| filters-regions.svg | 0.473 | 4.122 | 79 | 38 | PASS |
| filters-transforms.svg | 1.221 | 3.673 | 48 | 21 | FAIL |

The transformed fixture fails the MAE limit. The nested fixture fails all three
limits; the largest Chromium discrepancy is filtered content inside a pattern.
Its quadrant MAE is 3.289/255 against Chromium and 0.704/255 against resvg.
The filtered marker comparison against resvg is dominated by that binding's
missing context-stroke paint. These alternate results help locate disagreements;
they do not replace the failing primary comparison.

For an offset applied after a restricted flood, resvg expands/translates the
output subregion while Chromium retains the inherited subregion. The regions
fixture preserves this disagreement. Its primary Chromium comparison passes;
the alternate resvg comparison fails. Both images remain in the artifacts.

The [gallery](gallery.html) shows the actual matrix, selected reference and
amplified difference. Raw reports are `report.json` and `chromium-report.json`;
`coverage.json` declares references and `summary.json` records all verdicts.
`filter-quadrants.mjs` reproduces the quadrant diagnostic from saved images.

## Regression and frontend checks

23 Bend regression files pass, including interpolation/premultiplication,
filter graph ordering, SourceAlpha, linearRGB/sRGB transfer, subregions,
zero-radius blur, zero-radius drop shadows, filter replacement and opacity.
`filter-parity-report.json` proves that the 69 earlier non-filter fixture matrices
remain byte-identical after adding filters, with source hashes recorded.

The native app, C server and headless renderer build successfully. The browser
flow loads a filtered SVG, replaces/removes its filter reference, drags the shape,
and verifies exact source and pixel restoration after undo. No browser errors
occurred on either backend. The flow took 18.88 seconds on JavaScript and 4.69
seconds on the compiled C server; both reports record source hashes.
`native-all-report.json` confirms byte-identical C/JavaScript matrices for all
76 fixtures.

The native window was also opened with a 256×256 version of the transformed
filter fixture. `native-filters.png` records the visually inspected blur and
shadow output. `web-filters-editor.png` records the compiled browser flow.

All sixteen feBlend modes are now implemented. See [blend validation](blends.md)
for the four added fixtures and all raw reference comparisons.

A later [buffer-density diagnostic](filter-density-investigation.md) tests
twice the intermediate resolution against these same seven fixtures. It was
not integrated: both existing failures remain and the blur fixture regresses.

The integrated [morphology validation](morphology-investigation.md) adds four
primary passing fixtures, full-matrix geometric regressions and web editing
checks on both backends. The older measurements above retain their original
checkpoint scope; current build and source hashes are in morphology-build-report.json.
