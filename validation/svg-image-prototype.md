# Embedded SVG image prototype

This is isolated, unmerged work. The current app still supports PNG/JPEG image
payloads only. `svg-image-prototype.patch` applies to the integrated blend source;
the prototype is in the temporary `svg-image-investigation` directory.

The prototype expands data-URI SVGs into vector subdocuments inside Bend. It
reuses geometry, paint and rasterization; neither frontend parses or renders SVG.
Each image has local resource lookup, use expansion, styles and font inheritance.
Authored data URIs stay intact; internal descendants lose editor IDs so picking
can select the owning image. Recursion is bounded to16 embedded images. Both
base64 and percent data support UTF-8, including literal Unicode in a data URI.
Image visibility, opacity, placement, aspect fitting and clipping are represented
in the existing scene graph. Percentage positions/sizes remain deferred to the
viewport pass when both dimensions are explicit.

All33 existing Bend files and4 prototype files pass. The new checks cover a
simple image pixel, base64/percent/literal Unicode, style isolation, resource
lookup in both directions, opacity and hidden images. An editor check confirms owning-image selection, width changes, data-URI
preservation, exact source undo and restored pixels. Native prototype validation
has not completed; its headless C renderer is compiling. See `svg-image-prototype-checks.json`.

Three complete prototype matrices are compared with both resvg and Chromium in
`svg-image-experiment-report.json`. The sizing case passes resvg (MAE0.178,
RMSE1.353/255) but differs substantially from Chromium's image fitting. The local
resource case passes Chromium (MAE0.314,RMSE1.705), as does the nested image with
transform, clip and group opacity (MAE0.482,RMSE3.384). Alternate errors are retained;
these measurements have not been added to the main conformance verdict.
The12-case `svg-image-sizing-probe.json` independently records differences for
missing viewBox, mismatched intrinsic dimensions and slice fitting.

The normative reference is [SVG2 image processing and placement](https://www.w3.org/TR/SVG2/embedded.html#ImageElement).
Before integration: broaden intrinsic/auto sizing and percentage contexts;
check embedded images in patterns, masks, markers and use instances; validate
font behavior, invalid payloads and deeply nested inputs; broaden editor regressions;
verify unchanged existing matrices and native output. The differing reference
behavior must stay visible rather than being hidden by relaxed thresholds.
