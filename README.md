# Bend SVG Studio

Standalone repository: [nicolas-abril/bend2-svg-demo](https://github.com/nicolas-abril/bend2-svg-demo).
Extracted from `bend3-demos/svg` with its Git history.

Keep this checkout beside `bend2-core` for the default build paths.

A native and web SVG viewer/editor with SVG parsing, geometry, painting,
rasterization, hit testing and editing written in Bend. Both frontends use the
same document reducer. The server sends lossless PNG frames encoded from Bend's
RGB pixels. The browser decodes and displays those bitmaps; it does not render
SVG. Independent SVG libraries are used only by validation.

The implementation runs and supports a broad SVG subset. Pixel conformance is
unfinished: **108 of 117 reference fixtures pass**, with all failures retained.

## Structure

| File | Responsibility |
| --- | --- |
| `svg.bend` | The SVG library: geometry, styles, layout, paint servers, filters, rasterization |
| `xml.bend` | XML tokens, element tree, entities, attributes and serialization |
| `css.bend` | Stylesheets, selectors, specificity, media queries and the cascade |
| `font.bend` | Font book (outlines, advances, kerning, metrics) and the TrueType reader |
| `cover.bend` | Scan-converted area coverage of line lists into sparse masks |
| `png.bend`, `jpeg.bend` | PNG and JPEG decoders producing `img.bend` pictures |
| `bin.bend`, `img.bend`, `util.bend` | Bytes/DEFLATE/base64 and the `effs/` raw file read, colors and pixel quadtrees, text scanning helpers |
| `state.bend` | Shared document, view, input reducer, picking, edits, undo and file IO |
| `inspect.bend` | Shared selection, property values, defaults and finite choices |
| `native.bend` | Native canvas and AppKit property inspector |
| `web.bend` | HTTP server forwarding requests to the shared reducer |
| `web.html` | Browser controls, input transport and matrix presentation |
| `render.bend` | Headless matrix export |
| `fonts/` | The four Noto Sans TrueType files, read on demand by `font.bend` |
| `check*.bend`, `validation/` | Regression checks, comparisons and recorded evidence |

## Run

Requires Bun, the neighboring `bend2-core` checkout and a C toolchain. The C web
server also links zlib (`-lz`, included in the macOS SDK). The native
window requires a macOS graphical session. Rendering runs on the CPU. The
libraries import each other by relative path (`import ./xml.bend as XML`); each
of `util`, `xml`, `css`, `bin`, `img`, `png`, `jpeg` and `font` depends only on
the ones listed before it, never on `svg.bend`.

```sh
cd bend2-svg-demo
make check
make all                    # compiles all three executables (about a minute)
make native                 # opens the native window
make web                    # http://127.0.0.1:8088
make web-js                 # optional Bun/JavaScript backend
```

Set `BEND_MAIN=/absolute/path/bend2/main.ts` for another core checkout. Run from
this directory, or set `SVG_FONTS` to the absolute path of the `fonts` directory.
`SVG_FONTS=a.ttf,b.ttf,...` names other TrueType files instead (regular, bold,
italic, bold italic in that order). Files are read through `Bin.bytes.read`, a
small foreign effect under `effs/` that returns a file's bytes as a byte tree,
and a face is kept as those bytes: glyph outlines, advances and kerning are
decoded from the tables when text first uses them, so loading a face costs a
table-directory read.
Set `SVG_INPUT=/absolute/path/drawing.svg` to load a document at startup.
The web server maintains one shared editor state and processes requests
sequentially. HTTP carries the input/response protocol.
`/frame` and `/event` return compressed binary `image/png` bodies; `/source`
returns SVG text. `/inspector` returns the shared selection and property metadata
as JSON. The PNG send effects only encode the already rasterized
pixels, using RGB8, a Sub row filter and fast DEFLATE compression. PNG decoding
in the browser replaces decimal pixel formatting and parsing on the web path.

Open SVG files in the web UI or paste and apply source. Source edits are
undoable; opening a new file resets history. Click to select, drag to
move, use arrow keys to nudge, Delete to remove, and Z or Undo to undo. A drag
creates one undo entry; a click or a drag back to the origin preserves source.
The property controls support paints, strokes, transforms, dimensions, fonts,
resource references and image fitting. Save downloads Bend's serialized SVG.
Both property editors show the selected element's authored SVG `id`, or its tag
and “no id” if it has none. Private selection IDs are never presented as authored
IDs or added to saved files. Property fields show the current attribute or
cascaded value, including inheritance; absent values show a labeled default or
an example placeholder. Finite choices use dropdowns, preserving an existing
unlisted value. Selection, edits, delete and undo refresh the displayed values.
The native app opens an AppKit property panel beside its canvas, with Apply,
Undo, Delete and Save SVG controls. Native R/G/B keys still recolor; S and the
Save SVG button save to `edited.svg` or `SVG_OUTPUT`.

Documents fit the window when opened. Both frontends support F to fit, 0 for
100%, +/− to zoom about the window center, and H/J/K/L to pan left/down/up/right.
The web UI also has view buttons. Panning moves by 32 output pixels; arrow-key
nudging moves a selected shape by one output pixel at any zoom. Navigation
preserves document source and edit history. Source edits preserve the current
view; opening a file resets it.

Both frontends rasterize at the canvas’s backing pixel dimensions (logical
size × display scale), including Retina displays. Drag the web canvas’s
bottom-right corner, or resize the native window by its edges or corners.
Rectangular views are supported, up to 4096 pixels per side. Resize keeps the
existing zoom and pan relative to the fitted document, selection and edit
history; it never changes the saved SVG. Stale frames are cleared while the
replacement is rendered, and pixels are displayed without upscaling. The web
transport remains lossless compressed binary PNG; the native view receives
packed pixels directly and repaints only when needed.

Shapes are rasterized with
scan-converted coverage masks and painted back to front into a flat RGBA array
straight from those masks (one blend per covered pixel, a solid brush sampled
once per shape), so a frame costs about the same idle or dragging. The native
window currently lacks the web UI’s source panel.

Headless export supports rectangular output and dimensions 1–1024. `SVG_AA`
(1–8) sets the scanlines per pixel row of the coverage rasterizer (never below
four), the supersampling of rotated pattern tiles and the sub-sampling of
fractional filter-region edges; coverage is exact along x at any setting:

```sh
SVG_INPUT=fixtures/basic.svg SVG_WIDTH=64 SVG_HEIGHT=64 SVG_AA=8 \
  ./build/render --gpu off > drawing.ppm
```

The output fits the natural SVG viewport into a white-backed RGB PPM matrix,
centering any remaining space. Root dimensions, percentages and viewBox layout
are resolved before fitting. Transparent export is unfinished.

## SVG coverage

- XML entities, comments, CDATA, mixed text and source round trips.
- Basic shapes; every path command family, curves and elliptical arcs;
  transform lists, nested viewports, viewBox fitting and overflow clipping.
- Fill rules; strokes, caps, joins, miter limits, dashes, pathLength and
  non-scaling strokes.
- All 148 CSS named colors; hex, RGB, HSL, HWB, alpha and currentColor;
  inheritance, group opacity and visibility.
- Embedded stylesheets, common selectors and combinators, specificity,
  inline styles, `!important` and screen/viewport media queries.
- Linear/radial gradients, units, transforms, templates, spread modes,
  focal radius, and sRGB/linearRGB interpolation.
- Local use/symbol references; masks, clips and patterns with resource
  inheritance, units, transforms, nesting and bounded cycles.
- Text and spans using four bundled Noto Sans faces, kerning, character
  positions/rotations, spacing, anchors, baseline shifts and textLength.
  A TrueType reader in `font.bend` builds the same font book from `glyf`,
  `loca`, `hmtx`, `cmap` (formats 4 and 12), `OS/2` and GPOS pair kerning,
  including composite glyphs; `validation/ttf-parity.mjs` shows the four
  bundled TTFs reproduce every text fixture matrix byte for byte.
- Text on paths with local references, direct path data, basic-shape
  references, startOffset, pathLength calibration and glyph tangent rotation.
  Selecting its pixels edits the authored text and preserves path references.
- Markers with analytic endpoint tangents, units, fitting, orientation and
  context paints; marker pixels select the owning shape.
- Filter chains: flood, offset, Gaussian blur, drop shadow, color matrix,
  component transfer, composite, all sixteen blend modes, merge, morphology
  (erosion/dilation) and convolution (rectangular kernels, normalization, bias,
  alpha preservation, edge modes and explicit/fractional kernel spacing).
- All six paint orders for fills, strokes and markers, including strokes beneath
  text. Overlapping glyphs with a shared style receive one fill and one stroke.
- Embedded PNG data images, including Adam7 and legal color/bit-depth modes;
  baseline and progressive Huffman JPEG, grayscale, RGB, YCbCr and Adobe CMYK.
- SVG data images with UTF-8/base64/percent decoding, intrinsic sizing,
  viewport fitting, separate resource/style scopes and nested images.
  Embedded vector images are rendered directly by the Bend pipeline.

All decoded images, font outlines, filter buffers and pixels are processed by
Bend. User-supplied font files, external URLs, scripting and animation are not
implemented. The font fallback is always Noto Sans; Latin, Greek and Cyrillic
are bundled. Shaping, RTL, vertical text, text decoration, SVG2 closed-path
text wrapping, side/stretch options, advanced filter primitives and wide-gamut
CSS colors remain unfinished. Some fitting, masks, marker and edge-sampling
cases differ from the reference engines. Detailed limits and investigation
history are in [NOTES.md](NOTES.md).

## Validation

The integrated sources pass **56 Bend regression files (588 assertions)**.
The current C and JavaScript headless renderers produce **byte-identical
matrices for all 117 fixtures**. Both current web backends pass fit, zoom, pan,
transformed picking/dragging/nudging, property and source undo, opening and saving.
Their displayed matrices exactly match the three 256×256 fitted headless
expectations retained from the camera checkpoint. Both
also pass loading convolution fixtures, changing kernels through source editing,
undo, opening a new file and saving, with five full 256×256 matrix comparisons
each. Current native convolution windows and process-addressed Save keys pass
for kernel and explicit-spacing drawings.

The preceding camera build's native keyboard fit, zoom, pan, undo and save passed
process-addressed event tests, including ten full window-matrix comparisons. Differences are explained by the
OS's rounded corners and an independently calibrated outer-pixel border. Native mouse editing remains unverified: separate
process-addressed mouse probes did not select a shape. Browser pointer tests and
shared-reducer gesture checks pass. Earlier frontend reports retain their
original source hashes and viewport assumptions.

Independent 64×64 comparisons use resvg, Chromium and Firefox, matching font files and a
white background, rendered at eight times the output size and box-averaged down so
the engines' own coverage quantization drops out (resolution-dependent fixtures keep
1x references). The fixed limits are MAE ≤1/255, RMSE ≤5/255 and at most 1% of
pixels with a channel difference above 32. **108 pass and 9 fail.** Four of the five
text-path cases exceed at least one limit. No failing fixture, error pixel or
alternate-reference result is discarded. The chosen reference and reasons are
recorded per fixture; the engines also disagree on some SVG behavior.
Firefox is used for explicit convolution kernel spacing because the other two
references ignore kernelUnitLength, and for the zero-length dash fixture because it
alone paints the zero-length closed dash with its cap. The transparent-bias discrepancy remains a
failure; Bend follows the SVG working group's alpha-scaled bias formula.

- [Visual comparison gallery](validation/gallery.html)
- [Selected results and thresholds](validation/summary.json)
- [C/JavaScript parity](validation/native-all-report.json)
- [Build provenance](validation/convolve-build-report.json)
- [Regression checks](validation/convolve-check-report.json)
- [Text-path investigation](validation/text-path-investigation.md)
- [SVG image investigation](validation/svg-images.md)
- [Paint-order validation](validation/paint-order-investigation.md)
- [Morphology validation](validation/morphology-investigation.md)
- [Convolution validation and reference disagreements](validation/convolve-investigation.md)
- [Convolution comparison gallery](validation/convolve-gallery.html)
- [Source-edit undo](validation/source-undo-investigation.md)
- [Fit, zoom and pan](validation/camera-investigation.md)
- [Fitted viewport comparison gallery](validation/camera-gallery.html)
- [Native keyboard validation](validation/native-camera-keys-report.json)

```sh
make compare                         # exits unsuccessfully while fixtures fail
make check-frames                    # C/JS PNG transport and current browser pixels
make check-resize                    # both web backends, DPR changes and AppKit resize
make check-inspector                 # both web backends and AppKit controls (macOS)
bun validation/native-all.mjs
bun validation/run-browser-camera.mjs
bun validation/run-browser-convolve.mjs
bun validation/native-camera-fit.mjs
```

The comparison command installs development-only reference dependencies.
`check-frames` uses the same installed `validation/` dependencies. It checks PNG
checksums, HTTP lengths and exact RGB values through both compiled send effects,
then runs the browser editing flow against freshly generated headless matrices.
It writes temporary results outside the repository and preserves saved references.
`check-inspector` uses the same dependencies plus a macOS graphical session. Its
native test exercises the real canvas input handlers and AppKit controls inside
its own app process, including selection, defaults, dropdown edits, save, delete
and undo; it sends no global keyboard or mouse events. `check-resize` additionally
checks both web backends at display scales 1 and 2, the visible resize grip,
rectangular frames against headless rendering, displayed screenshot pixels,
display-scale changes and saved movement after resizing.
`SVG_SERVER_BACKEND=javascript` selects the optional backend for browser tests.
The test launchers start and stop their own local server on port 8088. Older
browser scripts and reports preserve earlier checkpoints; their fixed coordinates
and matrices predate automatic fitting.

Fonts are distributed under the [SIL Open Font License](FONT-LICENSE.txt).
`make ttf` checks that the on-demand TrueType faces reproduce every saved text
fixture matrix.

Additional sampling and reference diagnostics are recorded in
[text rasterization notes](validation/text-rasterization-investigation.md).
The preceding 105-fixture build passed 84/105 comparisons at 4×4 idle sampling
and 82/105 at 8×8. Those complete diagnostic datasets remain available. A separate resvg 0.47.0 run retains another
complete reference result set.
