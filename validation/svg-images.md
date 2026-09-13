> Earlier SVG-image integration:44 Bend checks passed; all105 C/JavaScript matrices matched
> exactly;82/105 primary reference comparisons pass. Both web backends now pass
> the extended SVG image flow, including large-document click, opacity, undo
> and save. See combined-svg-build-report.json and browser-svg-images[-js]-report.json.
> Measurements and source hashes below describe the earlier image checkpoint.

# Embedded SVG images

SVG data images are parsed and rendered in `svg.bend`. The app uses no browser
SVG functions or foreign renderer. Base64, percent-encoded and literal UTF-8
payloads are supported, with case-insensitive SVG MIME/scheme handling and
href/xlink:href lookup. Malformed root structure and mismatched/unclosed tags are
rejected; this does not imply complete XML validation.

Each image creates a private rendering subtree with separate stylesheet, font
inheritance and resource-ID scopes. Its vectors go through the existing Bend
geometry, paints and rasterizer. Inner resource IDs cannot capture outer IDs or
be referenced from outside. Nested SVG images are limited to sixteen levels.
Picking and edits target the authored image element. Internal nodes are never
serialized. The editor writes preserveAspectRatio and href as SVG attributes.

Intrinsic dimensions and ratios, viewBox, automatic dimensions and percentage
sizes are supported. Automatic dimensions are resolved in the actual containing
viewport, including nested viewports. Images without intrinsic dimensions use
the default 300×150 object size, constrained by any intrinsic ratio. Image
placement composes with transforms, opacity, clips, masks, patterns, markers and
use instances.

## Independent pixel comparisons

The seven new fixtures use the same 64×64 white-backed output and Bend AA8 as the
existing suite. Limits remain MAE ≤1/255, RMSE ≤5/255, and at most 1% of pixels
with any channel difference above32. Every pixel is included.

| Fixture | Primary reference | MAE /255 | RMSE /255 | Maximum | Verdict |
| --- | --- | ---: | ---: | ---: | --- |
| svg-image-sizing | resvg | 0.178 | 1.353 | 24 | Pass |
| svg-image-resources | Chromium | 0.314 | 1.705 | 14 | Pass |
| svg-image-nested | Chromium | 0.482 | 3.384 | 69 | Pass |
| svg-image-auto | Chromium | 7.670 | 34.942 | 187 | Fail |
| svg-image-percent | Chromium | 0.147 | 1.084 | 19 | Pass |
| svg-image-contexts | Chromium | 1.688 | 6.867 | 44 | Fail |
| svg-image-text | Chromium | 2.020 | 7.372 | 99 | Fail |

The complete suite passes **82/100** selected comparisons. Fifteen prior failures
remain. Both raw reference reports, all actual matrices and amplified differences
are retained. `coverage.json` records the reference choice for every fixture.

The sizing fixture selects resvg because the independent twelve-case
`svg-image-sizing-probe.json` records Chromium ignoring tested slice fitting and
handling no-viewBox images differently. The other six use Chromium consistently;
resvg omits or differs on automatic image dimensions in several isolated cases.
Neither renderer is treated as a universal specification oracle.

The automatic-size failure is confined to 252 pixels in the final case: the
embedded root has width/height attributes of18×18, with a stylesheet setting
12×6. Bend uses those computed dimensions; Chromium paints18×18. Other automatic
and percentage cases were corrected. This is an unresolved reference disagreement,
not a passing conformance claim.

The resource-context failure repeats a small stroked vector icon in patterns,
masks, markers and use content. Both references differ at small edges. Embedded
stroke antialiasing is a working hypothesis; the cause has not been established.
No threshold was relaxed to accept either failure.

## Regression and frontend evidence

Forty-one Bend regression files cover the integrated implementation. SVG-specific
checks exercise scope isolation, visibility/opacity, nested parsing, MIME and XML
rejection, UTF-8, automatic sizes, image ownership, resizing, aspect fitting,
href replacement and source/pixel undo.

All100 current C/JavaScript fixture matrices agree exactly. Source and binary
hashes are in `native-all-report.json` and `svg-images-build-report.json`.
The headless image-font correction emits identical C for native/web, so those
binaries were retained with explicit C equivalence evidence; the corrected
headless renderer was freshly compiled.

The compiled web flow passes in9.16 seconds: headless pixel checks, resource
isolation, width/aspect edits, drag, exact source/full-matrix undo and save. It also
loads the embedded-text fixture and checks every one of its65536 displayed AA4
pixels against the headless matrix. No SVG presentation DOM is used.
The earlier JavaScript flow passes image editing in21.02 seconds; the extended
text-image flow is being checked separately. Reports retain their source hashes.

`native-svg-images.png` shows four nested SVG-image examples in the rebuilt native
window. Outside the174 pixels affected by macOS's rounded bottom corners, all65362
canvas pixels match the headless AA4 matrix exactly. Full pixel error values,
including those corners, remain in `svg-images-native-window-report.json`.
Native input automation is unverified: targeted events produced no observed edit,
and macOS did not make the window the foreground input target. The focus guard
prevented normal input from being sent. The test window has been closed.

Headless font loading now includes text inside SVG images. The new text fixture
embeds a matching Noto subset for Chromium; Bend uses its bundled font book.
The tested resvg binding paints no text inside this image. Chromium's residual
antialiasing difference remains a primary failure. See `svg-image-fonts.md`.

The frozen initial prototype did complete native compilation and all96 C/JS
matrices agreed (93 previous plus three original SVG image fixtures).
`svg-image-native-probe-report.json` records its source and binary hashes. That
prototype predates the current sizing/parser refinements and is retained solely
as historical evidence.

## Limits

External images, SVGZ, fragment/view selection in image URLs, prefixed SVG roots,
non-UTF-8 XML encodings, scripts and animation are unsupported. Nested images have
a depth cap. Rendering support inside an SVG image follows the same incomplete
feature coverage as the main document, including text and filters. Source loading
is not a complete XML validator. SVG images are vectors; PNG/JPEG color-management
and dimension limits are separate and remain documented in their own notes.

The implementation follows [SVG2 image rendering](https://www.w3.org/TR/SVG2/embedded.html#ImageElement),
[intrinsic sizing](https://www.w3.org/TR/SVG2/coords.html#IntrinsicSizing), and the
[CSS Images default sizing algorithm](https://www.w3.org/TR/css-images-3/#default-sizing).
The reference disagreement above remains visible even where the current
implementation follows an interpretation of those rules.
