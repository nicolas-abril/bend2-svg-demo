# Text layout and reference sampling

These measurements use the installed SVG source recorded in
combined-svg-build-report.json. The application and its original8x8 comparison
suite are unchanged by these diagnostic runs.

With all four matching Noto Sans faces loaded, Chromium's glyph origins differ
from Bend by at most0.034 user units for text-position.svg and0.014 for
text-style.svg. Nested textLength spans differ by up to15.893 units; the prior
probe already isolates Chromium's extra gap after a fitted descendant. See
text-layout-position-probe.json. These are layout measurements, separate from
the pixel comparisons.

Increasing Bend's sampling from8x8 to32x32 on text-style.svg changes the resvg
comparison from MAE1.508/RMSE5.150 to1.445/4.411; maximum error falls from43 to32.
Sampling density alone does not bring its mean error under the original limit.
Drawing the exact bundled outlines at Bend's positions in resvg produces the
same pixels as resvg text. A fractional rectangle with boundaries43.308 and
44.364 produces resvg coverage levels0.75 and0.25, exposing quarter-pixel
quantization even for straight geometry. The denser Bend coverage is closer to
the exact fractional area in this isolated case. Raw results are retained in
text-style-aa-probe.json, font-normal-outline-probe.json and
resvg-subpixel-probe.json. This does not excuse unrelated layout or paint errors.

The current Rust resvg0.47.0 release was downloaded from its official GitHub
release and verified against the published SHA-256. All105 fixtures were
compared again with the same saved Bend8x8 matrices. The newer reference changes
23 fixture measurements, including focal-radius gradients, nested SVG images
and markers, but reproduces all of the text measurements exactly. It passes
50/105 raw comparisons; the mixed-reference primary suite remains82/105.
See resvg-current-report.json and resvg-current-provenance.json. The binary is
only a temporary validation tool; it is not part of the Bend application.
Run compare-resvg-current.mjs with RESVG_BINARY set to a verified resvg CLI.

The actual interactive app's4x4 idle sampling was also tested on all105 fixtures,
using the same reference assignments and thresholds:84 pass and21 fail. Four
previously failing cases pass at4x4 (stroke-vector, text-path-shapes, text-style,
text-unicode), while filters-regions and stroke-dash-curves fail. Both complete
sets are retained; the8x8 primary results have not been replaced. See
interactive-sampling-report.json and the *-aa4.ppm matrices.


## Fitted text layout isolation

The installed paint-order source was used for a separate text-length position
probe. All 16 character origins differ from Chromium by at most 0.04477 pixels.
The browser uses the same bundled font files. This does not prove equality of
rasterization or of nested text-length behavior.

The same four fitted rows were reconstructed as font outlines at Bend's glyph
positions, preserving vertical scale independently from horizontal fitting.
When resvg renders these outlines, three rows are exactly identical to its
original text rendering. The middle-anchored spacing row differs substantially:
a horizontal shift of 0.227333 pixels makes that row pixel-identical too. This
shift is half the absolute spacing adjustment for the fitted run. This identifies an anchor
placement disagreement rather than a font-outline mismatch in that row. The
fixed scan and a half-spacing candidate are both retained; neither alters the
Bend implementation or the chosen primary reference.

The corresponding Bend/outline-reference MAEs are 1.160, 1.490, 1.188 and 0.882
for the four rows. Those remaining differences come from rendering the same
outlines, subject to the recorded source/coordinate precision. They remain
failures where they exceed the existing limits. See
[text-length-position-probe.json](text-length-position-probe.json),
[text-length-outline-probe.json](text-length-outline-probe.json), and
[text-length-anchor-probe.json](text-length-anchor-probe.json) for raw results,
source hashes and the complete reconstructed SVG.
