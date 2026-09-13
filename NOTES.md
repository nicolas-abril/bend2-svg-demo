# SVG Studio implementation status

The original goal remains active and incomplete. Save work in
/Users/macolas/Software/bend3-demos/svg. Development staging is
/private/tmp/bend-svg-work; sync.py copies source and validation evidence.
Do not edit bend2/bend.ts or overwrite the user's comp.ts changes.

Latest checkpoint: fitted viewing/navigation, 50 passing Bend regression files,
112 exact C/JS fixture matrices plus three exact fitted matrices. All three fresh
C binaries are installed. Both web backends pass navigation and transformed
editing; native keyboard navigation/save pass ten window comparisons. Native
mouse editing remains unverified. The primary reference suite remains 89/112,
with all 23 failures retained. README.md and validation/camera-investigation.md
record the current state. Sections below retain earlier checkpoints and counts.

## Architecture

svg.bend: XML, SVG geometry, styles/paint, resource expansion, rasterization,
source serialization and picking. state.bend: common editor state, actions,
loading/saving, edits and undo. native.bend: cached pixel window and native input.
web.bend: sequential local HTTP server. web.html: pixel display and input adapter.
render.bend: headless PPM export. No SVG library is imported by the app; resvg
and browser SVG rendering are confined to independent validation.

## Implemented

- XML tree, attributes, mixed text, entity decoding/escaping and round-trip source.
- SVG number exponents, adjacent signs/decimals and compact arc flags.
- Basic shapes; M/L/H/V/C/S/Q/T/A/Z paths; curves/arcs; transforms and fill rules.
- Inherited/inline presentation, common/hex/rgb colors, premultiplied compositing,
  opacity and supersampling. Explicit inherit/initial/unset on core paint/stroke.
- Butt/round/square caps; miter/round/bevel joins and miter limits; odd/even/zero
  dashes, percentages/offsets, closed seams, pathLength and non-scaling strokes.
  Miter-clip is implemented but not reference validated; arcs joins are unsupported.
- Linear/radial gradients, units/transforms/spread, href templates, stops/opacity,
  focal points/radii, sRGB/linearRGB and paint fallbacks.
- Clip unions/intersections, transforms, bounding-box units, group clipping,
  and use references to shapes inside clips. Picking respects clips.
- Root and nested viewports, sizes/percentages, viewBox, aspect alignment,
  meet/slice/none, overflow clipping/visibility and zero-size suppression.
- Local use/href/xlink references, symbol/SVG instances, default/override sizes,
  instance styles, nested references and cycle suppression. Shadow rendering does
  not flatten source. Picking/dragging/recoloring targets an individual use element.
- Luminance and alpha masks, mask-mode overrides, coordinate units/regions,
  group/nested/gradient masks, inherited definition styles, linear-RGB mask
  compositing and bounded cycle handling. Transparent source pixels skip masks.
- Balanced bounds hierarchies for stroke, fill and clip sampling. Native caches
  idle frames. Web coalesces pending pointer moves. Both render AA4 idle/AA1 drag.

## Current evidence

Twenty-seven Bend regression files cover stroke extents, marker geometry and picking, including viewport clipping/picking and
independent instance editing/serialization. All 19 earlier actual raster matrices
remain byte-identical after viewport/reference changes.

83 fixtures compared at 64x64, AA8. 66/83 pass MAE<=1/255, RMSE<=5/255, at most 1%
pixels with channel error>32. coverage.json explicitly selects references;
summary.json records the verdict; both raw reports and images are retained.

Unresolved primary comparisons include seven text fixtures, three marker fixtures,
invalid masks, transformed patterns, and these earlier strokes:
- stroke-vector.svg: Chromium MAE 1.074/255 exceeds 1 (RMSE 4.487, max 32).
- stroke-dash-zero.svg: M40 49 Z with square cap/dasharray 0 4 produces a 36-pixel
  square in Bend; Chromium/resvg omit it. SVG2 ideal dash/cap rules appear to
  support Bend, but this is a failed comparison, not a proven conformance result.

Reference limitations: this resvg binding ignores fr, linearRGB, pathLength,
vector-effect and symbol default dimensions. It differs on quoted/empty gradient
paint and renders zero-sized nested viewports. Cyclic references hit its node
limit; compare.mjs records this error and continues. Probes preserve evidence.
It agrees on explicit inherited fill in an isolated use probe. Do not claim that
inheritance is broken based on the combined symbol fixture.

Alternate-reference discrepancies also remain: Chromium transformed clip RMSE 6.54,
compact path RMSE 6.07, and resvg clipped-use RMSE 5.38. At AA4 curved dashes narrowly
miss the declared limits. Do not loosen thresholds or remove failing fixtures.

Prior browser full editing flow passed in 46.15s after fill acceleration, versus
110.37s before. A 60-move burst generated one move request. Native stroke window
was captured and inspected; native/JS stroke-dashes AA8 output was identical.
Those artifacts predate the reference/viewport additions.

The pre-mask saved builds and nine regression checks passed.
The instance-specific browser flow passes (open file, move/recolor one instance,
preserve definitions and hrefs in source, undo). Screenshot inspected. C and JS
renderers produce byte-identical AA8 matrices for use, nested viewports and cyclic
references. All test servers/windows are stopped. Source and evidence synced to
the requested destination. That checkpoint predates masks; see current continuation below.

## Next work

Main remaining renderer features: wide-gamut/relative colors; advanced CSS/custom properties; advanced text layout and shaping; external image loading and PNG/JPEG color management;
remaining filter primitives and CSS filter functions; remaining marker edge cases. Animation has not been implemented. External resources and
symbol refX/refY anchors are unsupported. Clip visibility, clip use targets beyond
basic shapes, nested SVG inside clip paths, singular matrices and general resource
cycles need further conformance work. Symbol display override is not yet enforced.

Native/web control parity is incomplete: native has keyboard editing and startup
file loading, but lacks web source/property controls. Add shared selection display,
zoom/pan, viewport controls, robust parser diagnostics and unsupported-feature
reporting. Interaction latency is now bounded by scene compilation and text
layout rather than sampling (see the analytic coverage section).
Broaden real-world fixtures and native input validation before completion.

Specifications: https://www.w3.org/TR/SVG2/ ; structure/use and coordinates chapters.
Reference package: @resvg/resvg-js 2.6.2, plus isolated Chromium reference rendering.

## Mask continuation

Current mask implementation and all ten regression files pass. Full comparison:
32/35 selected fixtures pass. Added failed mask-errors.svg: invalid/missing/wrong
and cyclic sources become transparent in Bend, following CSS Masking's invalid
source rule; Chromium shows four red targets unmasked and resvg shows three.
Keep this discrepancy explicit. Empty and zero-sized masks agree. Browser behavior
for SVG mask presentation attributes may retain legacy error handling.

Classic luminance masks, units/regions, group/nested masks, gradients and definition
inheritance agree with resvg. Probes show resvg ignores mask-mode:alpha and
color-interpolation=linearRGB; those fixtures use Chromium. Translucent overlap
initially exposed sRGB compositing before conversion; fixed by blending the mask
subscene in linear RGB. Its Chromium comparison now has max channel error 1.
Only mask-compositing.svg changed after that fix plus transparent-source culling;
all other 34 matrices were byte-identical. New web properties expose masks/clips.

Browser mask flow passed using the JS server: open masked SVG, masked-out picking,
remove mask from a visible shape, preserve definition, undo. Duration 132.87s.
The identical flow passed on the compiled C server in 38.17s, a 3.48x speedup.
make web now uses build/web --gpu off; make web-js retains the Bun backend.
The saved native/web/render builds and all ten checks pass. Native and JS output
is byte-identical for mask-gradients, mask-compositing, mask-nested and mask-errors.
All test processes have been stopped. Final source/evidence sync completes this
mask checkpoint. Pattern implementation is next.

Future mask work: mask lists/composite operators, external/raster mask sources,
CSS cascade/shorthand precedence, child color-interpolation overrides and broader
resource cycle/error diagnostics. Editor mask picking intentionally excludes fully
masked paint; this is editor behavior rather than SVG DOM pointer-event semantics.

## Pattern continuation

Added pattern fills and strokes with independent tile/content units, origins,
transforms, viewBox/aspect fitting, href/xlink templates and inherited definition
styles. Pattern children reuse the scene renderer, including gradients, masks,
local uses and nested patterns. Template and paint recursion is bounded. Zero and
negative tile dimensions produce transparent paint. Tile overflow is clipped;
visible overflow and singular transforms remain work.

Scenes and paints are parameterized by brush data, allowing Brush to contain finite
compiled pattern scene trees. No functions are stored in Data. Affine compile and
sample continuations are created separately for fill/stroke/mask. Pattern content
is compiled once per referencing shape, not once per pixel. The sample traversal
is @unsafe because callbacks obscure structural descent through finite scene data.

Seven new fixtures, six selected passes, total 38/42. The transformed-pattern test
still fails against Chromium around tile edges. Initial normalized-bbox matrix
order caused a placement/rotation error and was corrected to apply patternTransform
in user space after bbox geometry. Do not claim full transformed-pattern agreement.
Both raw engine comparisons are retained. Resvg differs more on the skewed pattern.
Removing the title child from pattern-reference changes 1056 Chromium pixels and
zero resvg pixels; SVG2 explicitly excludes descriptive children when determining
whether to use template children. The pattern inheritance probe agrees with both
engines on using the template children's original inherited colors.

compare.mjs optionally accepts SVG_COMPARE_FILTER to refresh matching entries in
an existing report at the same AA setting. The complete pre-fix run established
all earlier fixtures unchanged in behavior; the filtered final run updates all
seven pattern entries after the matrix-order correction.

A separate pattern-supersampled-report.json diagnostic renders resvg at 1x/2x/4x/8x
and area-averages to 64 pixels. MAE decreases from 8.621 to 4.054 to 1.783 to 0.948;
8x RMSE is 3.976, 40 pixels exceed channel error 32. This supports tile rasterization
as a major source of disagreement. It does not replace the failing primary 64px
comparison or change its thresholds.

The saved native app, web server and headless renderer build successfully and all
12 Bend regression files pass. native-pattern-report.json records byte-identical
C/JS matrices for all seven pattern fixtures, with the saved SVG source hash.

The pattern browser test exposed a pre-existing click mutation: a zero-distance
move wrote an identity transform. Shared state now commits one history entry on
release only if the final document differs from its baseline; zero displacement
restores the original baseline exactly. Property/nudge/undo actions first finish
an active gesture. check-gesture.bend covers click, selection without an undo
entry, drag out and back, and undo of a real drag. The web property menu now offers
fill for URL pattern/gradient paints alongside the color picker.

After the gesture change, all saved native/web/render binaries rebuilt successfully
and all twelve regression files passed. The new headless build again matched all
seven pattern matrices byte for byte. The earlier failed browser run timed out
because fill was absent from the property menu; the identity-transform mutation
was independently visible in that run and is covered by the new gesture check.

The final browser pattern flow passes on the saved native server: open pattern
SVG, pick a painted area, change fill to another pattern, preserve definitions,
undo to byte-identical original SVG, replace pattern with a solid color, and no
browser errors. web-pattern-editor.png was inspected. Source hashes are saved
with browser-pattern-report.json. The test wrapper stopped its server and browser.
All pattern/gesture source and validation evidence is ready for final sync.

## CSS continuation

Added a render-only stylesheet pass before use expansion. It gathers embedded
style elements, computes selector matches and declaration precedence, and keeps
original classes/style blocks in the editable source. Supports type/id/class and
attribute selectors (=, ~=, |=, ^=, $=, *= and case flag i); descendant/child/
adjacent/general sibling combinators; :root, first/last/only-child, :empty,
an+b nth-child/nth-last-child and simple :not(). Specificity, source order,
inline priority and !important are handled. Comments and balanced quoted/function
values are scanned without splitting embedded semicolons. XML CDATA now becomes
literal text, preserving ampersands correctly through serialization.

Screen/print media types, min/max/exact width/height, orientation, comma groups,
not/only, nested @media and style media/type attributes are supported. Unsupported
at-rule blocks and semicolon at-rules are skipped; external imports are not loaded.
Malformed CSS recovery, custom properties/var(), escaped identifiers, of-type
pseudo-classes, full selector-list :not(), :is/:where, @supports/cascade layers,
complete property validity and geometry-property coverage still need work.

Five CSS fixtures agree with Chromium: cascade/media are byte-exact, selectors
max error 1, structural MAE .117, resources MAE .126. Isolated css-reference-probe
confirms resvg ignores each tested important-priority, geometry, media, nth-child
and case-flag behavior (0 pixels change when each feature is removed, versus
1024/486/1024/256/1024 changed Chromium pixels). All raw comparisons are retained.
check-css and check-css-media bring the regression count to 14.

Saved native/web/render builds and all 14 regression files pass. Native and JS
output matches byte-for-byte for all five CSS fixtures (native-css-report.json).
Browser CSS flow passes on the saved C server: CSS colors, selected shape edit,
normal inline priority, exact source/color undo, stylesheet important versus
normal inline, inline important versus stylesheet important. Authored style blocks
and class attributes remain in source. web-css-editor.png was inspected; source
hashes and duration are saved in browser-css-report.json. Browser/server test processes closed.

Full final comparison after CSS: 43/47 pass. The only selected failures remain
stroke-dash-zero, mask-errors, stroke-vector and pattern-transform; all five CSS
fixtures pass. Both reference reports and summary.json are current. Every native
build and all fourteen checks passed, and the native/browser CSS evidence matches
the saved source. Continue with complete colors/custom properties, text/font
rasterization, embedded images and filters; the overall goal remains incomplete.


## Bundled text rendering checkpoint

Text glyph lookup, font-asset parsing, metrics, kerning, placement and rasterization
now run in svg.bend. The 5 MB ASCII fonts.dat bundles Noto Sans Regular/Bold/Italic/
BoldItalic outlines and GPOS pair/class kerning for 2,840 mapped characters per
face. FontTools is used only to regenerate this static asset from the licensed
TTFs; no font/SVG rendering library is in the application runtime. Embedding the
full data directly in Bend caused excessive compiler checking costs, so both
frontends load the book once into shared state. SVG_FONTS overrides its path.

Text supports nested tspan/a inheritance, per-character positions and rotations,
chunk anchors, relative sizing and baseline shifts, spacing, default whitespace
collapse and xml:space preservation. Hidden spans and descriptive children do
not consume positions. Glyph outlines become internal geometry; stroke width
stays in text user units. Generated glyph metadata is absent from saved source.
Text paint bounds use full glyph cells. Seven fixtures compare against resvg and
Chromium using the same TTF files. Initial result: basic and whitespace pass;
spans, Unicode, paints, position and style exceed existing limits. Total45/54.
Chromium character-position probes agree closely on anchors/rotation but
baseline keyword offsets and glyph rasterization differ. No thresholds relaxed.

Remaining text work: ligatures, mark positioning, RTL/complex shaping, textPath,
textLength, vertical text, decoration, user fonts/families, refined baseline
metrics, transformed-span/ancestor paint bounds, and performance. Keep all
text comparisons and add stronger real-world coverage as layout expands.

Text rasterization diagnostic: resvg-converted outlines rendered by Bend match
Bend's own text closely for basic/style/Unicode/whitespace (MAE below0.03/255),
which localizes those reference differences to pixel rasterization rather than
layout. This diagnostic does not replace the independent comparisons. Converted
text paint servers can lose original glyph-cell bounds, so the painted-text row
is not a reliable pure-layout measurement. Anchor/spacing and baseline differences
still show in position/spans. Saved in text-rasterization-probe.json.

Saved native/web/render builds pass; all 15 Bend regression files pass.
All 7 text C/JavaScript matrices are byte-identical. The compiled browser flow
passes text picking/recoloring, original text preservation, exact source/pixel
undo, font-weight change and nudge/undo with no browser errors in 89.63 seconds.
Native window display verified for all four faces; screenshot native-text.png.
Both validation processes stopped. Performance and broader text layout remain
open. New text controls are presentation only; their operations use the common
Bend reducer. Fixed the existing pointercancel handler's missing event argument.

## Text length fitting

Added inside-out horizontal length fitting, spacing / spacingAndGlyphs,
percent/physical/em lengths, fitted anchors, and fixed nested descendants.
Private glyph metadata carries typographic origins/advances independently from
outlines; fitting changes glyph matrices before paint bounds are derived.
Small synthetic-font regressions check exact positions/scales, descendant
width preservation, whitespace, invalid values, single glyphs and attribute
serialization. New textLength/lengthAdjust UI controls use the common reducer.
Also corrected pathLength property editing to save an XML attribute.

Two additional 64px reference fixtures fail: text-length MAE 1.875/RMSE 6.962;
text-length-spans MAE 15.023/RMSE 41.510 against resvg. Chromium also differs.
The nested panel and character-position probe show engine disagreements,
including re-expansion of explicitly fitted descendants. Keep the SVG2 fixed
descendant rule and keep all failures. Following-text advancement, explicit
x/y list ordering, anchored multi-chunk text, forced line breaks and nested
trailing whitespace require further work. Full selected result 45/56.

Root fitted-text position probe: maximum x-origin difference from Chromium
0.04477 user units for the four spacing/stretch/anchor rows. Saved independent
pixel failures remain unchanged. validation/text-metrics.bend uses the actual
Bend CSS/use/text passes; probe-text-length-positions.mjs reproduces this metric
comparison from the browser metrics.

Saved native/web/render builds and all 16 regression files pass. All 9 text fixtures
have byte-identical C/JavaScript output, including both fitted-text fixtures.
The seven earlier text matrices remain unchanged.

Further length-fitting audit items: measurement currently assumes positive
advances; negative letter-spacing needs min/max endpoint handling. Explicit
x/y positions are currently applied before fitting, whereas SVG2 resolves
them after fitting; multi-chunk anchor metadata is not recomputed per adjusted
chunk. These are real implementation limits, beyond reference rasterization.

Compiled browser fitting flow passes in 113.73 seconds: select,
recolor, weight, nudge, textLength spacing, lengthAdjust glyph stretching, valid
attribute serialization and exact two-step source/pixel undo. No browser errors.
Source hashes verified against saved files. Browser/server wrapper exited cleanly.
Artifacts: browser-text-length-report.json and web-text-length-editor.png.

## Expanded sRGB colors

Added the full 148 CSS named-color table (W3C data and hash provenance saved),
unit-aware legacy/modern RGB/HSL/HWB parsing, hue normalization and angle units,
alpha percentages, component clamping and missing-component none. Function
syntax retains whitespace/comma/slash delimiters and validates arity; invalid
hex digits and lengths no longer produce partially interpreted colors. Color
keywords and currentColor now handle ASCII case. CSS inherit/initial/unset
are case-insensitive, including paint-resource inheritance.

Fill/stroke/group opacity now accept percentages. Gradient stop percentages
were already supported. Five new fixtures pass against Chromium: named colors
are exact; each other color/resource fixture has max channel error 1. Isolated
probes establish resvg's rebeccapurple and modern-syntax limitations. Total 50/61
selected comparisons pass; all 11 earlier failures remain.

Remaining color work: wide-gamut/Lab/OKLab/color() conversions and gamut mapping,
relative colors, color-mix/calc/var, CSS escapes, system colors and invalid-value
cascade recovery. HSL/HWB currently clamp channels to conventional ranges;
latest CSS unbounded-gamut behavior is not implemented.

Saved native/web/render builds and all 17 regression files pass. The complete
61-fixture C/JavaScript matrix comparison passes byte-for-byte, including all 56
earlier fixtures: the color changes do not alter any earlier comparison image.
All source hashes are saved in native-all-report.json. The initial browser color
test matched a pre-existing fill-opacity value and read an old frame; fixed its
wait condition to target the edited shape. No renderer change was needed.

Missing color components currently resolve to zero; carrying missing components
from the other stop during color interpolation still needs implementation.

The compiled browser color flow passes in 40.56 seconds, covering HWB alpha,
percentage fill opacity, named colors and exact source/color undo. Source hashes
match the saved application. Artifacts: browser-colors-report.json and
web-colors-editor.png. Run `bun validation/run-browser-colors.mjs` after building
to repeat this flow. The test server has been stopped.

## Markers

Path tracing stores authored vertices and analytic curve tangents separately from
flattened fill/stroke edges. Ordinary paths do not retain a trace. Markers compile
as separate Scene.markerNodes, so geometry bounds for paint servers stay correct.
The marker subtree is painted after the host shape and before opacity/mask/clip.
Resource IDs and decreasing compilation fuel prevent recursive expansion.

Inherited start/mid/end and CSS marker shorthand preserve cascade priority and
source order. Marker definition styles are independent from the host. markerUnits,
width/height, numeric/angle orient, auto/auto-start-reverse, refX/refY, viewBox,
preserveAspectRatio and overflow are implemented. A finite context-paint pass
resolves nested marker paints using the host brush and coordinate transform;
unfaded solid paint is retained so host fill/stroke-opacity does not leak into
context-fill/context-stroke. Gradient/pattern coordinates and bbox are preserved.

Eight new reference fixtures, five passing Chromium. Viewport (RMSE7.010),
compositing (RMSE5.943) and degenerate-path cases remain failures. Do not loosen
thresholds. Resvg has substantial differences for context paint, auto-start-reverse
and CSS shorthand; all raw results are saved. Equal-endpoint arcs omit the segment
per SVG2 9.5.1; Chromium retains an extra marker. Moveto-only default orientation
and marker count also differ and remain unresolved. Initial attempts to omit
moveto-only markers were reverted: their authored vertex is preserved.

Outstanding marker work: rect/circle/ellipse equivalent paths, keyword refX/refY,
paint-order, non-scaling-stroke marker scaling, symbol references, mixed zero-length
subpath directionality, and context paint scope through use instances.

Saved marker build verification: native/window, web/server and headless renderer
compile successfully, and all 19 Bend regression files pass. All 69 saved C matrices
match their JavaScript baselines byte-for-byte (137.43 seconds total C rendering).
The marker browser editing flow passes on the JavaScript server in 446.09 seconds.
This fixture is substantially slower than the earlier color fixture; marker-heavy
interactive rendering needs acceleration. The compiled C server passes the same flow in 108.09 seconds
(4.13x faster). Both browser reports include source hashes.

## Conservative scene coverage bounds

Each Scene stores a second bounding box for rendered coverage. A bottom-up pass
includes the node's flattened geometry, its compiled stroke mesh, children, and
marker subtrees. It also runs through pattern and mask resources. The original
object bounds remain unchanged for gradients, patterns and clips. Stroke-mesh
bounds use the mesh coordinate transform, including non-scaling strokes; local
stroke tolerances are padded before transformation. Non-finite transformed bounds
fall back to a permissive box rather than incorrectly suppressing visible pixels.

Sampling can now return the existing background immediately when a point is
outside an entire scene subtree. Picking uses the same conservative exclusion.
check-coverage.bend covers round caps, miter extensions and non-scaling strokes
beyond the host path's geometry bounds. coverage-parity.mjs compares every saved
fixture matrix with the optimized JavaScript renderer. coverage-benchmark.mjs
compares alternating old/new C runs and rejects any changed output before timing.

Coverage verification completed: all 20 Bend regression files pass; all 69
JavaScript matrices are unchanged, and the saved C renderer matches all69.
Paired C median speedups: markers-context4.36x, markers-vertices7.66x, text-basic1.94x,
pattern-nested1.06x. Every old/new output pair is byte-identical. The native marker
editing flow improves from108.09s to23.55s; JavaScript from446.09s to239.50s.
Full C fixture rendering improves from137.43s to58.11s. End-to-end timings are
observations; the alternating paired benchmark is the controlled comparison.
Source and binary hashes are preserved in the reports. Reference conformance
remains55/69. Future acceleration can reuse unchanged web frames and generate
pixel matrices in parallel before serialization.

## Filter continuation

Nine primitives now run entirely in Bend: feFlood, feOffset, feColorMatrix,
feComponentTransfer, feComposite, feBlend (five original modes), feMerge,
feGaussianBlur and feDropShadow. Scene preparation caches floating-point,
premultiplied RGBA quadtrees before image/PPM rasterization. Per-scope device
density supports filters in patterns, masks and markers. Host clips, masks and
opacity apply after filtering. Geometry picking remains independent of filters.

Seven new fixtures use Chromium as the primary reference; five pass. Keep the
transformed and nested filter failures and all resvg alternates. No thresholds
were relaxed. See validation/filters.md for limits and exact measurements.
23 regression files pass, including buffer interpolation, graph resolution,
color-space conversion and frontend-independent filtered pixels.

Filter checkpoint build and parity verification completed: native/web/render
binaries build, 23 checks pass, all 69 pre-filter matrices are unchanged and all
76 C/JavaScript matrices match exactly. Browser filter editing/removal/drag/undo
passes with exact source and pixel restoration on C (4.69s) and JS (18.88s).
Reports include source hashes. The full primary reference verdict is 60/76,
with all 16 failures retained in the gallery and summary.

## Embedded PNG continuation

svg.bend now decodes PNG data URIs without foreign code: persistent byte buffers,
base64/percent decoding, all DEFLATE block types, PNG CRC32/zlib Adler32 checks,
all legal color types/depths, all scanline filters, tRNS and Adam7 passes. A Bitmap
brush retains the decoded RGBA raster; image elements get SVG placement/intrinsic
sizes, preserveAspectRatio, inherited image-rendering, transforms and normal
clip/mask/filter/opacity composition. Image fill/stroke properties are ignored.
Web properties expose width/height, aspect ratio, image-rendering and href.

27 regression files pass. New tests include 11 inflater cases and 33 PNG cases.
Seven image fixtures compare with both references; six pass Chromium's original
thresholds. images-aspect remains a failure (MAE .411, RMSE 5.820, 30 pixels >32),
localized at nearest-neighbor boundaries. All 30 legal type/depth/interlace
combinations match both references within one channel level. The compression
fixture matches resvg exactly and exercises all compression paths in the app.
PNG colors currently assume sRGB; JPEG/SVG image payloads, external loading,
color management and APNG animation remain to implement. Decoder dimension cap
is 2048. See validation/images.md and the source-hashed parity/frontend reports.

PNG checkpoint verification completed: native/web/render all build, 27 saved
checks pass, the original 76 matrices are unchanged, and all 83 C/JavaScript
matrices match exactly. Browser resize/opacity/drag/undo/save flows pass on C
(17.76s) and JS (81.68s), with exact source/pixel restoration and data-URI
preservation. Native PNG window captured and inspected. Current primary
reference verdict is 66/83 with all 17 failures retained; gallery loads 249
images. Source hashes verified against the saved app. The large inline inflater
fixture was reduced to avoid a Bun compiler stack limit; all compression cases
remain, including larger file-based native coverage.
The inflater regression also compiles and passes all eleven cases on C; see
validation/inflate-native-report.json. Test servers and native windows are closed.

## Embedded JPEG continuation

Added a JPEG decoder to the same svg.bend library. It handles Huffman baseline,
extended sequential and progressive scans, restart markers, DC/AC coefficient
reconstruction and refinement, a separable inverse DCT, centered chroma
upsampling, grayscale/RGB/YCbCr and Adobe CMYK/YCCK. The existing bitmap brush
and data-URI image pipeline now accept JPEG. Approximation history validates
scan ordering; frame and quantization checks reject malformed inputs.

30 Bend regression files pass, including 19 full-pixel JPEG comparisons and
13 malformed-input cases. All 19 decoder matrices match C/JavaScript exactly,
and differ from Pillow/libjpeg by at most two channel levels. Six new SVG
fixtures all pass Chromium's original thresholds. The full selected-reference
verdict is now 72/89, with the same 17 failures retained. See validation/jpeg.md.
Full app rebuild, all-fixture parity and frontend verification are completed below.

Nine extended JPEG cases now cover dimension boundaries, partial MCUs, flat
progressive data, restart wraparound, quality extremes and 128x96 progressive
content. All nine C/JavaScript matrices match exactly. Eight meet the three-level
Pillow bound; the 1x17 case fails (max23) because libjpeg switches narrow chroma
planes to box upsampling while Bend retains bilinear. Raw failure retained in
validation/jpeg-stress-report.json and documented in validation/jpeg.md.

JPEG checkpoint verification completed: native/web/render all build and all 30
saved Bend checks pass. All 83 pre-JPEG matrices are unchanged, and all 89
C/JavaScript fixture matrices match exactly. Browser JPEG resize/opacity/drag/
undo/save flows pass on C (16.74s) and JS (89.57s), including exact
full-matrix/source restoration and data-URI preservation. Native JPEG window
captured, inspected and closed. The gallery loads all 267 images for 89 fixtures
and retains 17 failure cards. The SVG comparison verdict is 72/89; one additional
narrow-JPEG standalone stress comparison remains a documented failure.
Build/frontend/parity reports include hashes matching the saved sources.

## Image sampling corrections

Stabilized nearest-texel ties after inverse F32 transforms. The aspect-ratio
fixture's 30 wrong pixels are fixed: max error99→2, RMSE5.820→.151. All seven
PNG fixtures pass the unchanged thresholds; the selected SVG verdict is73/89.
Added libjpeg's narrow-plane box fallback: the 1x17 JPEG now matches Pillow
exactly, and all12 extended cases pass with exact C/JS parity.31 Bend checks
pass, including a regression derived from the actual boundary failure.
Stroke/text reference probes were added without changing those implementations.
Full saved-app rebuild and frontend validation are in progress.

Sampling checkpoint verification completed: all three binaries build,31 saved
Bend checks pass, and all89 C/JavaScript matrices match. PNG editor flows pass
on C (18.23s) and JS (70.06s), preserving source/pixel undo and the saved data URI.
Native aspect-ratio window captured, inspected and closed. All267 gallery images
load, with16 failure cards. Source SHA256 is 3eca300e0528681080b0f1d7e2127800d4692fcee23f6354ec92465c3e5e24b1.
The alternative coverage-sample experiment had mixed results and was not adopted.
An isolated font-metric correction fixes sub/super offsets and brings text-spans
within its primary limits; it is ready for a separate source change.

## Font metric continuation

Merged per-face OpenType OS/2 metrics into the Bend font book and reproducible
font asset. All32 Bend checks and eight compiled C metric cases pass. Nine text
fixtures were re-rendered; only text-spans changes, now passing its original
resvg limits (MAE0.801/RMSE3.333). The selected verdict is74/89, with15 failures
retained. Full binaries and frontend validation are in progress.
All three font-metric binaries now build;32 target checks pass and all89 C/JS
matrices match exactly. Native text window inspected and closed. JS text editor
flow passes in76.13s. A C web flow launched before the final binary completed
was excluded from current evidence; the runner now rejects stale binaries and
records its launch binary hash. The rebuilt C check is running.

Separately, a candidate adds the remaining11 feBlend modes. Three full matrices
cover all16 modes,16 color pairs, opaque/transparent sRGB and linearRGB. Chromium
max errors are1/1/5, within existing limits; alternate resvg errors are retained.
128 reference-derived Bend checks also pass C,1024 sampled C/JS colors match,
and all7 existing filter matrices remain unchanged. The candidate patch and
reports are saved; it is not merged into the production font-metric source.
Font-metric checkpoint complete: the rebuilt C text flow passes in18.59s
and its launch binary hash matches the build report. All32 checks, all89 backend
matrices, both text frontends and the native screenshot are verified. Current
primary verdict remains74/89, with15 failures retained.

## Blend-mode integration

Integrated all16 feBlend modes, the128-case regression, and four new fixtures.
All33 Bend checks pass. All4 new primary comparisons pass, taking the selected
verdict to78/93 while retaining15 failures and all89 previous matrices. The
gallery loads279 images. Full native/web/render builds and frontend checks are
in progress; see validation/blends.md and the historical candidate evidence.
Blend checkpoint builds all three binaries and passes all33 saved checks. All93
C/JavaScript matrices match exactly. Native blend/clip/mask/opacity preview was
captured, inspected and closed. JS blend editor passes in45.43s; final rebuilt
C web flow is running.

An isolated SVG-image prototype expands data-URI SVGs into vector subdocuments
with local resources, styles and fonts.37 Bend files pass, including UTF-8,
resource/style isolation, image visibility, owner selection, resizing and exact
source/pixel undo. Three prototype matrices and a12-case sizing probe retain
both reference outputs. Sizing/auto contexts still need broader checks; the
prototype is not merged. Its native headless renderer is compiling, session89765;
see svg-image-investigation/build-state.json and validation/svg-image-prototype.md.
Blend checkpoint verification completed: rebuilt C web flow passes in6.82s
with matching binary/source hashes. All33 checks, all93 backend matrices and
both frontends pass; primary comparison verdict remains78/93.

## Embedded SVG image continuation

Current svg.bend SHA256: cd77a3f56536818426710c872f4e95e63252883a0e12d36a12dce25d1cdbf736.
99 primary comparisons: 82 pass, 17 fail with unchanged thresholds. All previous
93 actual matrices are retained. Six new SVG image fixtures cover sizing,
resource/style isolation, nesting, automatic and percentage dimensions, and
patterns/masks/markers/use. Four pass; svg-image-auto and svg-image-contexts fail.
See validation/svg-images.md for metrics and reference policy.

40 Bend check files pass the integrated parser/sizing work; the expanded editor
regression also verifies aspect fitting and href replacement. The browser flow
caught preserveAspectRatio and href being saved as CSS declarations; state.bend
now writes them as SVG attributes. Current C frontend rebuild and validation are
pending. Do not use older binary mtimes as current-source evidence.

Frozen initial prototype native validation is complete: 96/96 C/JS matrices
agree (93 prior plus three initial SVG fixtures). That b1c681b4 source predates
the current auto-sizing/MIME/XML changes. Its evidence is historical, not a
substitute for current-source full native validation.

## Active follow-ups after SVG image editing

The corrected property-reducer build is running as session55423, log
svg-images-state-build.log; started approximately10:42 UTC. Do not restart it.
Initial library build completed with99/99 C/JS matrices and40 checks, but predates
the property storage correction; archived reports record its exact source hashes.

A newly found headless font-loading gap is fixed in the isolated
svg-image-fonts-investigation candidate, source9078af2d. Its render binary is
compiling as session13864, started approximately10:53 UTC. Native/web emitted C
is byte-identical to the current property-fix build. Read
validation/svg-image-fonts.md before integration. Current target source remains
cd77a3f5 and the new font-image fixture is not part of its99 comparisons yet.

The isolated text-path candidate passes42 checks, has22 independent position
probes and5 pixel fixtures (all exceed at least one unchanged threshold).
All99 prior JS matrix comparisons are running as session86061. Keep source frozen
until that run completes. The new editor ownership check currently fails; picking
should select the owning text element, not its textPath child. See
validation/text-path-investigation.md. No textPath code is integrated yet.

## Verified image/font checkpoint

Current app library SHA2569078af2d90a95e8de565217a320bf19e8c659ec8343fe3ab8a1606fbe477dcbd.
State SHA256a604ac987ef8a7607df05f015e437c965ad0577f7bfbcfd34fd84c91c2adab27.
All41 Bend checks pass. All100 C/JavaScript matrices are exact. Primary comparisons
82/100 pass,18 fail; gallery100 cards/300 images is verified. Native/web/headless
builds are complete. Native/web C is byte-identical across the font detection
change; the corrected headless binary was installed from the completed frozen
candidate. make all is up to date. Compiled browser image editing plus every pixel
of the embedded-text fixture pass in9.16 seconds. Final JavaScript extended flow
is still running as session47826; inspect svg-images-browser-js-final.log.

Native window355/PID43404 was captured and closed; its65362 non-corner pixels
match headless AA4 exactly.174 OS-rounded-corner pixels differ and remain in the
report. Native input could not be verified: the window could not acquire focus;
normal events were not sent after the guard failed. Do not claim native input
coverage or ask for permission for this optional test.

Text-path candidate source51c413d46dbb09167d8f7ffa5c9037a820df7c3111a157b0a039025aafaa6c3a.
43 checks pass including corrected owning-text selection and exact undo. All99
prior matrices matched the previous source before the ownership-only correction.
Five experimental pixel fixtures remain above at least one unchanged threshold;
a straight-path matrix exactly matches ordinary Bend text, identifying existing
font rasterization error. Candidate patch and evidence are retained in validation.
No textPath source has been integrated. Next work is textPath refinement/integration
and its final compiled/browser validation, plus the remaining renderer differences.


## Integrated text paths and large-document editor fix

The current saved source is recorded in validation/combined-svg-build-report.json.
All three C binaries were compiled from the frozen combined sources. Forty-four
Bend checks pass; all105 C/JavaScript matrices are identical. Both server backends
pass the full text-path and embedded SVG image editing flows, with exact matrix,
source and undo checks. The reference suite passes82/105, retaining23 failures.
The five added text-path fixtures all exceed at least one unchanged threshold.

The earlier JavaScript image-font flow that remained pending did fail: SVG
serialization and Base.String.eq exhausted the JavaScript stack on long strings.
The SVG library now serializes with reverse accumulators, and the shared reducer
uses a consuming tail-recursive equality helper. A65,582-character serialization
regression checks escaping and long-string equality; the browser flow loads and
edits the real27KB embedded-font SVG, then verifies exact undo and save.

Text paths resolve scoped local references, direct path data and basic shapes;
existing font layout supplies glyphs, and flattened path distances/tangents place
them. Start offsets, calibration, anchors, position lists, baselines, fitting and
following ordinary text are included. Synthetic glyphs remain hidden from saved
source and picking selects the owning authored text. Closed-path wrapping,
side/stretch options, invalid direct-path fallback, shaping/RTL/vertical text and
some nested fitting cases remain unfinished. Placement and tangent refinement
remain the next conformance target; all raw errors and independent probes are kept.

The subsequent higher-precision text-path experiment remains unintegrated. It
reduces angle error substantially but barely changes pixel error. See
validation/text-path-precision-investigation.md; the saved105-fixture build
and its passing44 regression files are unchanged.

The paint-order and glyph-run candidate passes46 Bend checks and its three new
primary reference fixtures. It remains unintegrated while the complete matrix
comparison and compiled/browser checks run. See
validation/paint-order-investigation.md. Supplemental text-layout,32x sampling,
current resvg and actual idle4x sampling results are retained in
validation/text-rasterization-investigation.md.


## Integrated paint order and shared glyph painting

All46 Bend checks pass. The installed native, web and headless binaries were
compiled from the frozen paint-order source; all108 C/JavaScript matrices match.
All105 prior matrices are unchanged. The three new primary comparisons pass,
bringing the suite to85/108 with the same23 retained failures. Both web backends
pass exact matrix/source editing, undo and save checks for the new behavior.

Paint order is inherited and supports all six permutations, omitted operations,
normal and invalid-token fallback. Adjacent glyphs sharing a style are painted
as a compound geometry, avoiding doubled fill opacity and misplaced stroke
layers on overlapping characters. Text ignores fill-rule. Different span-style
runs remain separate and need broader cross-span conformance tests.

The first JS browser attempts exposed test-environment load and incorrect test
coordinates; neither is reported as a passing run. The corrected full flows and
build/source provenance are recorded in validation/paint-order-build-report.json
and the paint-order browser reports. Independent reference disagreements,
including the alternate failing paint-order comparisons, remain visible.


## Integrated morphology filters

The installed SVG library now supports feMorphology with erosion/dilation,
separable transformed radii, premultiplied channel extrema and filter graph
integration. All 47 Bend checks pass and all 112 C/JavaScript matrices match.
The 108 earlier matrices are unchanged. The four new primary comparisons pass,
bringing the suite to 89/112 with the same 23 retained failures. Both web
backends pass every-pixel matrix checks, property/graph editing, drag, undo and
save. See validation/morphology-investigation.md for discrete-radius behavior,
alternate reference failures and remaining limits.


## Integrated source-edit undo

Applying edited SVG source now preserves history and clears stale selection.
Opening a new file still resets history. Applying unchanged serialized source
is a no-op. Active gestures finish before a source edit is recorded.
All 48 Bend checks pass and both web backends verify exact source/matrix undo,
successive source edits, file opening and saving. SVG rasterization is unchanged;
independently emitted headless C is byte-identical to the morphology renderer,
whose 112 C/JavaScript matrices match. The selected references remain 89/112,
with all 23 prior failures retained. Native/web binaries were freshly compiled.
See validation/source-undo-build-report.json and source-undo-investigation.md.

## View navigation continuation

Shared camera state now fits each loaded document, with 100%, center zoom and
32-pixel pan actions. The SVG library compiles in the document's natural viewport
and applies the camera independently of the authored tree. Picking/dragging use
the resulting inverse transforms; one output-pixel nudge remains consistent at
any zoom. Camera actions do not enter undo history or saved SVG. Source edits
recompute viewport dimensions while preserving the current camera.

Fifty Bend check files pass, including 15 camera matrix/history assertions and
seven sizing boundaries. The existing 112 matrices are unchanged. Three additional
wide/tall/resource drawings pass the original resvg error limits, and both C/JS
backends agree exactly for all 115. Native keyboard navigation/save now have direct
process-targeted event evidence; pointer probes remain unsuccessful. No foreground
activation or global keyboard/mouse posting is used by these new tests.

## Convolution checkpoint

The current build adds feConvolveMatrix in the same SVG library. It passes 51
Bend check files / 532 assertions, 117 exact C/JavaScript matrices, both web
backend flows and native filtered-window/Save checks. Primary conformance is
93/117; all 24 failures and alternate renderer results are retained. Explicit
kernel spacing uses Firefox as reference following an attribute-removal probe.
Alpha-scaled bias follows the W3C resolution and remains a browser discrepancy.
See [the convolution investigation](validation/convolve-investigation.md) for
formulas, limits, all evidence and source/binary provenance.

## Supersampled references and the final conformance pass

Every one of the 24 remaining primary failures was re-measured against the saved
resvg, Chromium and Firefox renders and against exact geometry. Most were not
Bend errors but the references' own coverage quantization: Skia widens diagonal
strokes by 5% and snaps feOffset to its buffer grid, pattern tiles and embedded
SVG images are resampled or aliased, text coverage is quantized to quarter
pixels. The comparison now renders every reference at eight times the output
size and box-averages it down (`validation/reference-scale.mjs`), so it measures
geometry, layout and paint rather than each engine's rasterizer. Thresholds and
fixtures are unchanged; the earlier 1x reports and images stay as `*-x1.json`
and `*-x1.png`. Fixtures whose meaning depends on the output resolution keep a
1x reference (`referenceScale` in coverage.json): raster images, feConvolveMatrix
(kernels default to device pixels) and morphology radii.

Three renderer rules changed, each with a regression case: letter-spacing is no
longer applied after the last glyph of a chunk when anchoring (CSS Text 3,
matching resvg); an embedded SVG image's intrinsic size comes from its root
width/height attributes rather than its stylesheet (both browsers); and the
final filter region clips each buffer pixel by its covered fraction instead of
including every touched pixel (intermediate primitive subregions are unchanged).
The zero-length dash fixture selects Firefox, which paints the zero-length
closed dash with its square cap as Bend does.

Primary conformance is 108/117. The remaining failures are documented
engine disagreements: nested and anchored textLength (the three engines differ
from each other by MAE 15-18 on nested spans), text on paths (both browsers
disagree with resvg and with each other), a lone moveto marker that both
browsers orient from the origin, invalid mask references (CSS Masking says
transparent black; every engine paints them unmasked) and alpha-scaled
convolution bias. See [validation/remaining-failures.md](validation/remaining-failures.md);
`validation/failure-audit.mjs` regenerates the cross-engine table. All 52 Bend
check files pass and the compiled renderer reproduces every fixture matrix.

## Libraries and the TrueType reader

`svg.bend` is split along its existing seams into single-file libraries that
import each other by relative path and never import `svg.bend`: `util` (text
scanning, numbers, small helpers), `xml` (tokens, tree, entities, serializer),
`css` (cascade over an XML tree), `bin` (bytes, bit streams, Huffman, DEFLATE,
checksums, base64, percent decoding), `img` (premultiplied colors, pixel
quadtrees, decoded pictures), `png`, `jpeg` and `font`. The decoders now return
an `Img.Picture` that `svg.bend` wraps into its `Raster`. Bend resolves names in
file order and lambdas consume linear variables, so the split kept every
definition before its first use and copies reused fields with `+` bindings.
All 117 fixture matrices are byte-identical before and after the split.

`font.bend` gained a TrueType reader: table directory, `head`/`maxp`/`hhea`/
`hmtx`, `loca`/`glyf` with simple and composite glyphs (an explicit frame stack
assembles nested composites, with point matching and scaled offsets), `cmap`
formats 4 and 12, OS/2 metrics and GPOS pair positioning (format 1 pairs and the
first format 2 class table, matching how `generate-fonts.py` built `fonts.dat`).
Outlines are emitted as M/L/Q/Z path data with implied on-curve midpoints, the
same decomposition fontTools uses. `check-ttf.bend`, generated by
`validation/generate-ttf-check.py`, compares a Noto Sans subset (with composites
and kerning) against fontTools' outlines, advances, classes, kerning and metrics;
`validation/ttf-parity.mjs` loads the four bundled TTFs through `SVG_TTF_FONTS`
and reproduces all 15 text fixture matrices exactly. Not read: CFF outlines,
font collections, WOFF/WOFF2 wrappers and the legacy `kern` table; `@font-face`
data URIs are the natural next consumer.

## Raw file reads and analytic coverage

`Bin.bytes.read(path)` is a foreign effect (`effs/bytes_read.c`, `effs/bytes_read.js`)
that returns a file's bytes as a string with one character per byte, since
`File.read` decodes UTF-8. `SVG_TTF_FONTS` now names `.ttf` files directly and
`check-bytes-read.bend` reads a bundled TrueType file's header through it.

Rasterization no longer tests a grid of sub-samples per pixel. Before a raster
is painted, `cover.scenes` walks the compiled scene once and attaches to every
fill, stroke outline and clip shape a coverage mask on that raster's grid
(`cover.bend`): the shape's edges (stroke pieces become oriented polygons) go
through a winding scan converter that samples `sub` horizontal scanlines per
pixel row (the AA setting, never below four), sorts each scanline's crossings
and walks them with a winding count, so overlapping contours follow the fill
rule exactly and every inside span adds its exact horizontal extent to the
cells it covers. Masks are sparse quadtrees, so uniform areas collapse. The
first version accumulated signed area (the font-rs scheme, exact in both axes
for non-overlapping contours) but over-counted stroke joints, where consecutive
pieces overlap; the scanline walk replaced it. Sampling then reads one coverage
value and one paint sample at the pixel center. `check-cover.bend` covers
partial cells, a triangle's area, even-odd and same-direction overlaps,
reversed orientation and clipping to the grid.

Three details followed from reading coverage at pixel centers. Scene boxes are
expanded by half a device pixel in the cover pass, since a shape that only
reaches into part of a pixel has its center outside the box (the first run
lost the edge row of every axis-aligned shape). Clip coverage travels down the
sampler as a limit that each shape takes the minimum of with its own coverage,
instead of multiplying the composite: a marker's viewport clip coincides with
its rectangle, and squaring that edge left it at a quarter coverage. An image's
rectangle joins its scene clip and the bitmap read clamps to the edge pixels,
so image edges get coverage like any shape; a minified image is first
box-filtered to its device footprint (`raster.resample`, area weights over the
source pixels each output pixel covers).

Pattern brushes are rendered once per referencing shape into a tile raster
(`cover.brush`), with their own content covered on that tile grid first;
nested patterns recurse. An axis-aligned tile of at least four device pixels
is rendered at device density and read bilinearly with wrap-around at the
seams (nearest-neighbour images inside it stay crisp). A rotated, skewed or
tiny tile is rendered at `sub` times the density and read with a `sub` by
`sub` grid of nearest lookups spread over the device pixel's footprint, which
reproduces the old sub-sample averaging for those tiles only. Point-sampled
pattern content had lost its anti-aliasing when the sub-sample grid went away
(pattern MAE 0.04 to 3.4 against resvg); the tiles restore it and make pattern
paint a lookup. Fractional filter-region edges still use `SVG_AA` sub-samples.
The frontends keep their idle/drag quality switch, which now only changes the
scanline count (floored at four) and filter-edge sampling.

Timings on this machine, compiled renderer, the previous sampler versus now:

| Fixture | 64x64 AA8 before | after | 256x256 AA4 before | after |
| --- | --- | --- | --- | --- |
| basic | 0.52 s | 0.03 s | 1.49 s | 0.15 s |
| markers-compositing | 0.30 s | 0.06 s | 4.13 s | 0.41 s |
| stroke-vector | 0.15 s | 0.03 s | 1.87 s | 0.20 s |
| text-path-styles | 1.60 s | 1.50 s | 3.04 s | 1.63 s |

Text fixtures were dominated by reading `fonts.dat` (about 1.3 s), not by
rasterization (see the on-demand fonts section); the interpreter renders
`basic` at 64x64 in 1.4 s instead of 6.5 s. `validation/compare.mjs` accepts `SVG_RENDER_BIN=build/render` to use
the compiled renderer while iterating; the recorded matrices still come from
the interpreter run and `native-all.mjs` proves C parity.

Reference verdict after the change: 108 of 117, the same nine documented
failures as before, with unchanged thresholds and fixtures. Against resvg the
sum of mean errors over all fixtures is slightly lower than with the
sub-sample grid; the transformed-pattern fixture moved from 0.95 to 1.52 there
(its Chromium verdict still passes) and the clipping fixtures from 0.05 to
0.2, both from tile resampling and the coincident-edge minimum.

## On-demand fonts and byte trees

Loading fonts was the whole text render time: `fonts.dat` (5 MB of text, every
glyph of four faces as a path string) was read as a String, five million cons
cells, and scanned into a map before layout began, 1.47 s of a 1.5 s render;
the TrueType path decoded a file's byte string into a tree and walked every
glyph into the book, 0.6 s per face. resvg maps the same four files and parses
only their table directories, half a millisecond, because glyphs are decoded
on demand.

Two changes close that gap. `effs/bytes_read` now builds the `Bin.Bytes` tree
itself, in C and in JavaScript, with packed byte leaves over the next power of
two and a single zero leaf for the unused tail, so no Bend-side pass touches
every byte. And `font.bend` keeps a TrueType face as its bytes plus table
offsets (`TTFace`): `font.glyph` finds the glyph index by a binary search over
the cmap format 4 segments or format 12 groups and decodes advance, outline and
kerning classes for that glyph only; `font.kern` walks the GPOS format 1 pair
sets and the class grid for the pair asked. The text-format book from
`font.parse` remains for the check programs. `fonts.dat` and its generator are
gone; `fonts/` holds the four Noto Sans files and `SVG_FONTS` names a directory
or a file list. `check-ttf.bend` reads its kerning through `font.kern`, and
`validation/ttf-parity.mjs` still reproduces all 15 text fixture matrices.

Timings, compiled renderer, whole process including startup and output:

| Fixture | fonts.dat, eager | TrueType, on demand |
| --- | --- | --- |
| text-path-styles 64x64 | 1.50 s | 0.07 s |
| text-style 64x64 | 1.49 s | 0.08 s |
| text-path-styles 256x256 | 1.63 s | 0.19 s |

Loading the four faces now costs about 50 ms, almost all of it the byte tree
(570 KB per file at two heap words per node); the glyph decodes for a fixture's
few dozen characters are below the timer's noise. resvg renders the same
fixture in half a millisecond in-process, so text is now about 100 times
slower rather than 3000, the same ratio as shapes.

## Array painter, word-packed byte trees and a pixel-writing effect

A profile of a 1024x1024 render put most of the time in term drops, closure
applications and color blends: the per-pixel sampler walked the scene list
for every pixel, allocating points, colors and branch closures on the way, and
the text PPM cost another sixth in string appends. Three changes address that;
none of them alters a pixel value, so all 117 saved matrices are byte-identical.

The painter (`paint.scenes`) works on a flat `Array<F32>` layer with four
premultiplied lanes per pixel and paints nodes back to front straight from
their coverage masks: a mask leaf that spans a block paints the block with one
coverage value, so a uniform interior costs one blend per pixel and a solid
brush is sampled once per shape. Direct nodes (no opacity, mask or rendered
filter) paint fill, stroke and markers in paint order and then their children;
enclosing clips travel down as the coverage limit, the same rule the per-pixel
sampler uses, which is why the two agree. Other nodes are painted into a layer
of their own (a copy of the node without those three) and composited within
their coverage box, a mask being a layer painted from the mask nodes and a
filter node reading its rendered raster. Arrays are linear, so the loops thread
them explicitly and branch through helpers that match on a Bool; the packed
pixels then go through a continuation-threaded quadtree build for the window
and a row-by-row string build for the web frame. The per-pixel `sample` stays
for pattern tiles, filter inputs, picking and the check programs.

`Bin.Bytes` gained a second leaf kind: `ByteWord` packs four bytes little-endian
and is what the file effect now builds, a quarter of the nodes and two levels
fewer per read; `ByteFlat` keeps one value per index, since the JPEG and DEFLATE
decoders store whole coefficients and code counts in a `Bytes`. A memory-mapped
file is not expressible here: arrays are linear and cannot be shared, and the
TrueType reader needs random access from pure code, so the tree stays the
shared, indexable form.

The headless renderer writes its matrix through `effs/pixels_write`, a foreign
effect that formats the packed `Array<U32>` as P3 text in C or JavaScript.

Timings, whole process, compiled renderer, best of three with the shell's own
clock. The tables in the earlier sections were taken with a stopwatch that
added about 14 ms of interpreter start-up to every figure, so their relative
gains hold but their absolute values are that much too high; these are exact.

| Fixture | 64x64 | 256x256 | 1024x1024 |
| --- | --- | --- | --- |
| empty document | 6.5 ms | 6.5 ms | 6.5 ms |
| basic | 8.6 ms | 22 ms | 227 ms |
| text-path-styles | 26 ms | 41 ms | 224 ms |
| markers-compositing | 24 ms | 87 ms | 1062 ms |

The empty document is the process floor: runtime start, the heap, the worker
threads and the header write. Render time grows about linearly with the pixel
count from 256x256 up (basic: 15 ms to 220 ms for 16 times the pixels), and
against resvg's 0.6 ms and 1.6 ms for basic the render itself is now about
3x slower at 64x64 and 10x at 256x256. A profile of markers-compositing at
1024x1024 puts half the samples in closure application (the branch lambdas in
paint.sample and clip.cover, created per pixel), a fifth in dropping the
per-pixel Point and Color terms, a tenth in the blend arithmetic, and a
twentieth each in the clip mask reads and the printf of the output; the four
frame-sized layers its opacity groups and masks allocate are the rest.

## Packed 8-bit layers

The painter's layers are now packed 8-bit premultiplied RGBA, one U32 per
pixel, and its inner loop has no constructor or lambda: a uniform mask block
of a solid, unclipped shape computes its blended front once and each pixel is
an array read, an integer over (front + back * (255 - alpha) / 255 per lane)
and a write; clipped or sampled pixels still build a point and read the clip
masks, whose reads now branch through matches rather than U.branch lambdas,
and the gradient and tile samplers are unchanged. Layers composite by scaling
their packed pixel with opacity and the mask factor, a filter node packs its
raster color, and the final pass folds every pixel over white in place. The
recorded matrices moved by at most two levels (mean under 0.12) from the
8-bit rounding of the layers; the reference verdict stays 108 of 117. The
pixel-writing effect formats bytes by hand instead of printf per pixel.

Timings, whole process, best of five, before (F32 layers, printf output)
and after:

| Fixture | 64x64 | after | 256x256 | after | 1024x1024 | after |
| --- | --- | --- | --- | --- | --- | --- |
| empty document | 6.5 ms | 6.8 ms | 6.5 ms | 6.7 ms | 6.5 ms | 6.7 ms |
| basic | 8.6 ms | 8.6 ms | 22 ms | 18.5 ms | 227 ms | 162 ms |
| stroke-vector | | 9.3 ms | | 20.5 ms | | 188 ms |
| text-path-styles | 26 ms | 28 ms | 41 ms | 39 ms | 224 ms | 167 ms |
| markers-compositing | 24 ms | 24 ms | 87 ms | 73 ms | 1062 ms | 825 ms |

The gain is a quarter to a third at 1024x1024 and small below it, and the
profile explains the ceiling: the compiled program runs its calls through the
runtime's evaluator (`corpus_eval` applying compiled closures), so a pixel's
handful of array and integer operations is a handful of dispatches, about
150 ns per pixel of a solid fill, and no rearrangement of the Bend source
changes that constant. The remaining structural cost is the frame-sized layer
each opacity group or mask allocates and composites (markers-compositing has
four, hence its 5x over basic). Beyond that the gap to resvg is the runtime's
per-call cost, not the renderer.

## Block clips, box-sized layers and cheaper masks

Stage timings showed where a plain document's time went: the coverage pass on
an empty 1024x1024 document took 88 ms, and each full-frame shape added 150
ms, while the blend loop for that shape ran in about a millisecond. Two things
caused it. Every `<svg>` clips to its viewport, so every shape had a clip and
took the per-pixel path (a point, a quadtree read and a repack per pixel),
and coverage masks were scanned densely and folded cell by cell even for the
viewport rectangle and for fills and strokes that never paint.

The painter now evaluates clips per mask block: `Cov.mask.uniform` reports a
clip's coverage over a block when it is the same everywhere in it, the block
takes the constant-front fill with that limit folded in (or is skipped when
it is zero), and a block a clip edge crosses is split in four down to eight
pixels before its pixels read the clips one by one. Layers for opacity
groups, masks and filters are sized to the node's coverage box: a `Target`
rectangle threads through the loops and indexes each layer relative to its
own origin. In the coverage pass, masks are built only for fills and strokes
that paint; a closed path of four axis-aligned edges on whole pixels (the
viewport clip and the common rect) becomes a tree of full and empty leaves
without a scan; and the scan itself records interior runs as deltas, four
writes per span however wide, summed back into coverage in one pass per row.
Outputs are byte-identical to the recorded matrices.

Timings, whole process, best of three; synthetic documents are a full-frame
rect, the same at half opacity, a rect under a circular clip, a filled circle
and a stroked circle:

| Document | 64x64 | 256x256 | 1024x1024 | 1024 before |
| --- | --- | --- | --- | --- |
| empty | 12 ms | 8 ms | 14 ms | 99 ms |
| rect | 7 ms | 7 ms | 14 ms | 259 ms |
| rect, opacity .5 | 7 ms | 8 ms | 19 ms | 264 ms |
| rect, circle clip | 9 ms | 16 ms | 112 ms | 502 ms |
| circle | 8 ms | 14 ms | 95 ms | |
| circle stroke | 32 ms | 106 ms | 466 ms | 571 ms |
| basic | 8 ms | 11 ms | 49 ms | 227 ms |
| stroke-vector | 8 ms | 12 ms | 66 ms | 242 ms |
| text-path-styles | 27 ms | 33 ms | 81 ms | 224 ms |
| markers-compositing | 21 ms | 42 ms | 347 ms | 1062 ms |

basic at 256x256 is now 11 ms against resvg's 1.6 ms in-process, and 4 ms of
that is the process. The stroked circle shows the next cost: a stroke's mask
comes from its parts (bands, joins, caps) as polygons, hundreds of lines for a
smooth curve, and a curved mask still takes the dense scan and fold, which is
what the filled circle (95 ms) and the stroke (466 ms) are paying for.

## Stroke masks: active lines and sorted crossings

A stroke's mask is scanned from its pieces as polygons: a band per flattened
segment plus a join per vertex, about 3000 lines for a circle at a 6-unit
width. Two things made that slow. Every row filtered the whole line list, and
a scanline running along a nearly horizontal stretch of the curve meets every
band and join on the way (116 to 180 crossings on the top rows of the circle,
12 across the middle), which an insertion sort turned quadratic; it was 60
percent of the stroke's time. The scan now sorts the lines by their top once
and keeps an active list per row (lines are taken from the sorted list as
their top passes and retired as their bottom does), collects each scanline's
crossings unsorted and merge sorts them, and branches through matches instead
of U.branch lambdas on the per-line paths. Outputs are byte-identical.

| Document | 64x64 | 256x256 | 1024x1024 | 1024 before |
| --- | --- | --- | --- | --- |
| circle stroke | 17 ms | 42 ms | 205 ms | 466 ms |
| circle fill | 8 ms | 12 ms | 87 ms | 95 ms |
| stroke-vector | 8 ms | 12 ms | 56 ms | 66 ms |
| text-path-styles | 27 ms | 30 ms | 64 ms | 81 ms |
| basic | 8 ms | 10 ms | 46 ms | 49 ms |

What remains for strokes is structural: the pieces overlap, so a scanline
still walks a crossing per band and join edge it meets and adds a span per
interval. A stroker that emits the offset outline as one polygon per subpath
would bring a stroke's mask to the cost of a fill's, which is the next step
if strokes matter more.

## Regular documents: run-based masks and a cheaper compile

The Ghostscript tiger (240 paths, 1208 elements, 68 KB of path data) showed
two costs the earlier rounds never touched, because they are paid by every
plain document rather than by clips, layers or filters.

**Masks from runs.** A shape's mask was a dense float array over its box
filled by the scan, then folded cell by cell into the quadtree through a
continuation per cell; on the tiger's cover stage that fold was 70 percent
of the profile. The scan now emits each row as a list of runs (a span with a
constant coverage) and the tree is built top-down from the rows: a node
whose rows are all a single run of one value across its width becomes a
leaf, and only nodes along the shape's edge are split further. The dense
array and the fold are gone; a mask costs its perimeter times the depth
rather than its area. The aligned-rectangle fast path was also fixed to
fire (rectangle edge lists carry zero-length edges, and the uniformity
sentinel was mishandled).

**The compile.** Compiling the tiger took 195 ms regardless of size. The
profile was dominated by `term_drop` under `String.eq`: Base's `String.eq`
compares through `String.cmp`, which rebuilds the compared prefix of both
strings and drops it again, and the compile compares names constantly
(every attribute lookup by name, every property keyword, every element name
test). All libraries now use `U.string.equal`, which walks both strings once
and stops at the first difference. On top of that the `resources` pass,
which resolves the 25 inherited properties for every element, looked each
one up by name in the parent's resolved list; a parent's list is in the same
fixed order, so it is now read positionally with a name lookup only for the
root's raw attributes. Attribute lookups walk the list without a lambda per
entry, numeric inherited properties (stroke-width, opacities, miterlimit)
keep the parent's number instead of printing and reparsing it, and the edge
and stroke trees are built bottom-up from leaves instead of by repeated
partitioning. Outputs are byte-identical.

Cumulative stage times on the tiger and the two-path Twemoji face, compiled:

| Stage | tiger 256 | tiger 1024 | face 256 | face 1024 |
| --- | --- | --- | --- | --- |
| parse XML | 12 ms | 12 ms | 7 ms | 7 ms |
| compile the document | +52 ms (was +195) | +53 ms (was +195) | +1 ms | +1 ms |
| coverage masks | +157 ms (was +150) | +534 ms (was +730) | +5 ms | +45 ms (was +108) |
| paint and write | +10 ms | +47 ms | +1 ms | +5 ms |

Whole-process times, best of three:

| Document | 64x64 | 256x256 | 1024x1024 | 1024 before |
| --- | --- | --- | --- | --- |
| tiger | 176 ms | 233 ms | 652 ms | 975 ms |
| twemoji face | 8 ms | 13 ms | 62 ms | 123 ms |
| openmoji bulb | 11 ms | 17 ms | 63 ms | 89 ms |
| basic | 8 ms | 10 ms | 31 ms | 49 ms |

At 256 the tiger's masks are small, so the run-based tree saves little there
and the scan itself (flattened curves, sub-scanline crossings) is what
remains; at 1024 the tree build was the larger share. The compile is now a
flat profile of attribute lookups, path parsing and bounds.

## Coverage: flattening for the output size, masks without a dense buffer

Three changes to the cover stage, in the order they matter.

**Curves are flattened for the device.** Cubics were subdivided until the
control polygon was within 0.0005 user units of the chord, whatever the
output size, and arcs took a fixed 1/128 revolution per edge scaled by the
root of the radius. The tiger's 1,883 curves became 38,216 edges at any
size, and the two-path Twemoji face (a 36-unit viewBox) 574; at 256 px a
shape 20 px across carried hundreds of lines, so every sub-scanline sorted
crossings over an active list ten times longer than its pixels justified.
The path builder now carries a tolerance in local units, derived from a
device tolerance of 0.03 px through the norm of the element's matrix: a
cubic stops splitting when both control points are within 4/3 of the
tolerance of the chord (the curve's distance from the chord is 3t(1-t)
times a mix of theirs, so at most three quarters of the larger), and an arc
takes the chord angle whose sagitta is the tolerance. Content compiled in a
frame that is not the device (pattern tiles) gets the frame's device scale
through a `scale` argument of `compile`, so a pattern with a viewBox is not
flattened in pattern units. The tiger now has 19,546 fill edges and 40,820
stroke lines at 256 px, the face 590 at 1024 px and far fewer at 64 px, and
the reference verdict is unchanged at 108/117 (a first try at 0.1 px with
the control-point distance alone cost three fixtures).

**Rows of runs straight from the crossings.** The scan wrote span deltas
into a dense float array over the mask's box and a second pass read every
cell back into runs; both were proportional to box area, 130 ms of the
tiger's 1024 px cover stage and 28 ms of the face's. Each inside span now
becomes three events (a direct contribution to each end cell and a delta
that applies from the first interior cell and stops after the last), the
sub-scanlines' descending event lists are merged, and one sweep from the
right turns them into runs: a cell's coverage is its direct contributions
minus the sum of the deltas to its right, since a row's deltas cancel. No
buffer is allocated and nothing touches a cell no span reaches.

**A tree whose nodes own their rows.** The top-down build copied the rows
list at every node (uniformity test, take, drop), which in this runtime
turns every traversal of a shared list into reference-count cells on every
node and run it passes, and the uniformity test walked whole rows. One pass
per node now computes the node's uniform value and cuts the rows into the
four quarters (each row's runs split at the middle column), so children own
their rows and a uniform node's rows are never read again. The merges and
sorts of the scan (lines by top, crossings by x, events by cell) also branch
through a small record instead of a closure per comparison.

Cumulative stage times, compiled:

| Stage | tiger 256 | tiger 1024 | face 256 | face 1024 |
| --- | --- | --- | --- | --- |
| parse XML | 12 ms | 13 ms | 7 ms | 7 ms |
| compile the document | +49 ms | +57 ms | +1 ms | +1 ms |
| coverage masks | +55 ms (was +157) | +200 ms (was +534) | +2 ms | +8 ms (was +45) |
| paint and write | +11 ms | +48 ms | +1 ms | +5 ms |

Whole-process times, best of three:

| Document | 64x64 | 256x256 | 1024x1024 | 1024 before |
| --- | --- | --- | --- | --- |
| tiger | 78 ms | 125 ms | 321 ms | 652 ms |
| twemoji face | 8 ms | 10 ms | 26 ms | 62 ms |
| openmoji bulb | 10 ms | 15 ms | 52 ms | 63 ms |
| basic | 8 ms | 9 ms | 19 ms | 31 ms |
| stroke-vector | 8 ms | 9 ms | 21 ms | 56 ms |

The cover profile is flat now. At 1024 px the tree build (splitting runs
into quarters) and the per-shape line sort are the largest items, followed
by the crossing sort and event merge per sub-scanline; reference-count
churn from the shared active line list is what is left of the runtime
overhead. The stroker still supplies two thirds of the tiger's lines as
overlapping bands and joins, which the scan must sort and walk on every
sub-scanline they reach; a stroker emitting one outline per subpath is the
next structural step for stroke-heavy documents.

## Within an order of magnitude of resvg

The target for this round was a render within ten times resvg's in-process
time on every document, measured as the whole process minus a process that
only reads the file (about 7 ms here). The reference verdict stayed at
108/117 and the C parity at 117 fixtures and 15 TrueType fixtures
throughout.

The earlier rounds (exact-area scan, Wang's flattening count, lines in
arrays ordered by top row, floats read straight from the text, resources
resolved on demand, the outline stroker, solid runs painted directly) had
taken the tiger from 125 ms to 38 ms at 256 px. A `sample` profile of a
build that renders the tiger 150 times then showed where the rest went: 28%
of the time in `term_drop` (freeing), 17% in `span_fade` and `rfc_wrap`
(walking data through a reference-counted copy), 8% applying closures. The
work was not in the algorithms but in how the data was held.

**Own what you walk.** In this runtime a `+` copy of a list costs nothing
until something walks it: then every node passed becomes a count cell, and
the last copy dropped walks the whole thing again. The parse held the text
that way in three places: `xml.name`, `attributes` and the attribute value
scanner each kept the remaining text in both arms of a `branch`, so every
character of every value was read as a copy. Each loop now decides its next
character one step ahead (`until.go`, `name.go`, `separators.go`,
`trim.go`, the attribute loop through a `Next` record) and the tail is held
once. The path parser had the same shape at a larger scale: the `d` string
sat in the element's attribute list, which every lookup copies, so the
number parser read 60 KB of the tiger as a copy and the tree drop walked it
again; `compile` now takes `d` out of the list (`attrs.take`) before the
list is shared, through a `Ready` step of its own loop, and hands it to the
path parser alone. Fills kept a second reference to their edges (the edge
tree for point queries) so the cover walked them as a copy; the fill now
keeps only its bounds, and the cover reads the scene's edges as their owner
and hands them back; measured, that one changed nothing (rebuilding the
list costs what the copy did), so the fill keeps its edge tree and the
idea stands here only as a caution. The painter copied each scene's fill and stroke for
the three paint-order pieces; `paint.pieces` matches the order and gives
each mask to exactly one painter, and the target and tint travel through
the run loops as plain numbers.

**Fewer nodes.** An edge was three heap nodes (an edge and two points) and
a stroke segment four; both are one node of numbers now, halving what the
flattener builds, the stroker walks and the drop frees. Join and cap names
became codes decided once per stroke (`Joins`), so the per-vertex code
matches numbers instead of comparing strings and allocating branch
closures. The path command loop no longer uses continuations: the argument
parser returns the numbers with what follows them already classified
(`PathNext`), and `path.run` matches that. The per-element style work lost
its round trips: paint order stays a number when the attribute is absent,
hex colors parse in one pass, a paint's keyword is decided from its first
letter, and `pathLength` only measures the subpaths when it is declared. A
file read in one chunk is no longer copied by the join, and the cover
gathers its lines' bounds and count as it makes them, skipping the
rectangle test for anything with more than five lines.

Whole-process times (best of five) against resvg-js in-process, the
process floor for a read-only run being 6.8 ms for the small files and
7.6 ms for the tiger:

| Document | bend | in-process | resvg | ratio |
| --- | --- | --- | --- | --- |
| twemoji grin 256 | 7.4 ms | 0.5 ms | 0.10 ms | 5× |
| twemoji grin 1024 | 9.2 ms | 2.4 ms | 0.77 ms | 3× |
| twemoji bulb 256 | 7.8 ms | 1.0 ms | 0.14 ms | 7× |
| twemoji bulb 1024 | 10.1 ms | 3.3 ms | 0.84 ms | 4× |
| tiger 256 | 25.9 ms | 18.3 ms | 2.60 ms | 7× |
| tiger 1024 | 44.9 ms | 37.3 ms | 8.09 ms | 4.6× |
| circles 256 | 12.0 ms | 5.0 ms | 1.88 ms | 2.7× |
| circles 1024 | 29.7 ms | 23.1 ms | 16.33 ms | 1.4× |

Stage times for the tiger at 256 px, cumulative: parse 1.5 ms, compile
+10.2 ms, cover +6.4 ms, paint +0.2 ms. The compile is now the largest
part, and its profile is still dominated by freeing: the element's
remaining attribute strings, the styles copied per element and the edge
lists after their covers are built.

**A second round.** The profile of the committed build still put a third
of the time in freeing and a sixth in walking copies, so the remaining
closure loops went: the path command dispatcher (nine branch closures per
command, every argument read by index up front) is a match on the command
code reading exactly the numbers it takes by pattern; the subpath builder
and the point cleaner decide each step ahead; an attribute lookup stops at
its first hit instead of walking the whole list and building a result per
entry. A fill keeps only its bounds and cover, the scene alone holds the
edges, and the cover build consumes them outright (the covered scene keeps
none; picking walks the compiled scene). Tiger 256 px went 24.7 to 22.8 ms
whole process (about 15 ms in-process, 5.8 times resvg), 1024 px 43.7 to
39.9 ms.

Two structural attempts measured neutral and were left out: handing the
edges back from the cover build instead of walking a copy, and having the
path builder gather the stroke polylines and bounds itself so the edge
list is built once and stored with one owner (it added a point per edge
for every shape, stroked or not, and cost what it saved). A calibration
shows why the rest is hard to move: building and freeing 400,000 heap
nodes costs under a millisecond, so the remaining freeing time is many
small drops of records and copies spread over the whole compile, not one
large structure. The one large lever left is the text itself: every
character is materialized from the read, copied into an attribute value,
and freed again; a parser over the bytes as an array would remove three
node operations per character at the cost of rewriting the XML, number and
path scanners.

