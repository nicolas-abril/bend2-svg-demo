# Convolution filter validation

Status: integrated. All 51 Bend checks (532 assertions), all 117 exact C/JavaScript fixture matrices, both browser backends and two native window/save comparisons pass.

`feConvolveMatrix` previously passed through its input. The implementation covers
rectangular, asymmetric kernels; order/target defaults; divisor normalization;
bias; both preserveAlpha modes; none/duplicate/wrap edges; SourceAlpha and named
filter inputs; sRGB/linearRGB; explicit, fractional and transformed
kernelUnitLength. The shared SVG library performs all of these operations.

Kernel weights are rotated 180 degrees. Edge extension applies to integer input
pixels before bilinear interpolation. Primitive input bounds use exact transformed
corners: the geometric bounds helper's small coverage tolerance incorrectly added
a transparent pixel around the input domain in an early version. Independent
edge matrices exposed this and now pass. Explicit spacing uses transformed kernel
taps over the existing intermediate grid; it does not resample the entire filter
grid. Very large kernels are bounded to 4096 cells; invalid or oversized kernels
pass through. These limits are implementation limits, not claims of full SVG
filter conformance.

## Bias and alpha

The [SVG working-group resolution](https://lists.w3.org/Archives/Public/public-svg-wg/2010OctDec/0228.html)
chose alpha-scaled bias for premultiplied colors. The
[SVG 1.1 Second Edition](https://www.w3.org/TR/SVG11/filters.html#feConvolveMatrixElement)
and [Filter Effects specification](https://www.w3.org/TR/filter-effects-1/#feConvolveMatrixElement)
retain that equation. For preserveAlpha=false, Bend computes the filtered alpha
plus bias, adds bias times that result to the filtered premultiplied color, then
clamps the output. The raw alpha participates in the color equation before final
clamping. For preserveAlpha=true, Bend convolves straight colors, adds bias,
restores the input alpha and premultiplies. This follows the specification's
separate straight-color procedure for preserved alpha.

Chromium 153 and Firefox 155 add unscaled bias to premultiplied RGB in the tested
preserveAlpha=false case. Transparent input with bias 0.2 therefore becomes white
when composited on white; Bend produces gray. This is retained as a failing
comparison. The resvg binding agrees closely with that part of Bend's output,
but differs on the preserved-alpha inversion quadrant. None of those differences
is hidden by choosing a reference separately for individual pixels.

`convolve-reference-report-initial.json`, `convolve-firefox-report-initial.json`
and `convolve-alpha-quadrants.json` preserve the first measurements. The final
alpha-clamping correction changes some overlap pixels; final full reports are
`convolve-reference-report.json` and `convolve-firefox-report.json`.

## Reference capability checks

Removing every kernelUnitLength attribute changes zero pixels in Chromium and
the installed resvg binding, but changes 704 pixels in Firefox (maximum channel
change 183). Firefox is consequently selected for `convolve-units.svg`.
Chromium remains selected for the other four convolution fixtures, consistent
with the existing filter policy. Every complete Chromium, resvg and Firefox
comparison is retained. Reference choices for all older fixtures stay unchanged.

- `convolve-unit-reference-probe.json`: Chromium/resvg attribute-removal probe.
- `convolve-firefox-report.json`: Firefox comparisons and removal probe.
- `convolve-reference-report.json`: complete Chromium/resvg comparisons.
- `check-convolve.bend`: 26 independent whole-matrix expectations, including
  asymmetric direction, rectangular kernels, invalid arguments, all edge modes,
  alpha preservation, excess-alpha clamping, fractional spacing, scaling and
  rotated filter axes.
- `convolve-editor-cases.json`: original, source-edited and explicit-spacing
  drawings with complete 256×256 AA4 expected matrices.

The five 64×64 AA8 fixtures cover kernels, alpha, edges, result graphs and units.
The graph fixture consumes its convolved SourceAlpha result, including named
input use after an intervening flood primitive. The alpha fixture remains failed;
the other four pass their declared reference's unchanged limits. This adds four
passing cases and one failure to the prior 89/112 result, yielding 93/117. It does not resolve any of the 23 older failures.

A separate native pointer diagnostic bundled the already-validated camera
executable as a temporary `.app`. Launch and activation returned success, but
macOS reported the app inactive and not frontmost. Process-addressed Save worked;
process-addressed selection still did not. `native-bundle-pointer-probe.json`
retains the result. No global input was sent, and the temporary process was
closed. This does not establish whether pointer handling works for a human
clicking the native window.

An eight-case zero-length stroke probe is retained in
`zero-dash-firefox-probe.json`. Bend paints the exact 6×6 square required by
SVG2 for the tested closed zero-length dashed subpaths; Firefox matches exactly.
Chromium and the resvg binding omit those dashed closed squares. Solid/open and
moveto-only controls are included. This supports a future reference-policy
review; this checkpoint still retains the older fixture's primary failure.

## Installed validation

`convolve-build-report.json` records the frozen source and all three binary
hashes. `convolve-native-all-report.json` compares all 117 C and JavaScript
matrices byte for byte. The unchanged older matrices are independently recorded
in `convolve-prior-report.json`.

`browser-convolve-report.json` and `browser-convolve-js-report.json` cover file
loading, kernel source edits, undo, new-file history reset and saving. Each
compares five complete 256×256 canvas matrices to headless Bend expectations.
`browser-convolve-camera-report.json` and its `-js-` counterpart rerun the
existing navigation and pointer-editing flow on the current sources.

`native-convolve-report.json` compares the actual native kernel and explicit-unit
windows against the same complete matrices and verifies process-addressed Save
keys. The existing independently measured OS border calibration is applied, with
all raw differences retained. Native pointer editing remains unverified.

`firefox-all-report.json` retains an additional full Firefox comparison. Three
older failed fixtures pass Firefox's limits (closed zero-length dashes, nested
filters and basic-shape text paths). That is diagnostic evidence, not a change
to their existing declared reference or their failed primary status.
