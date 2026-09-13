# Image sampling corrections

Inverse F32 transforms sometimes put an exact texel boundary a few units in the
last place above its integer value. The nearest sampler then chose the adjacent
texel despite its lower-texel tie rule. The sampler now snaps coordinates only
within that small floating-point rounding neighborhood before resolving ties.
`check-image-boundaries.bend` covers three pixel failures from the actual SVG
fixture, including middle/max aspect alignment and translated images.

All seven PNG fixtures were re-rendered and compared to Chromium. Only the
30 previously incorrect pixels in `images-aspect.svg` changed. Its MAE fell from
0.410889 to 0.018229, RMSE from 5.820286 to 0.150952, and maximum channel error
from 99 to 2. It now passes the original thresholds. The SVG suite is 73/89;
the other sixteen failed comparisons are retained.

JPEG reconstruction now follows libjpeg's box-sampling fallback for horizontally
doubled component planes that are at most two samples wide. The original 1×17
failure now matches Pillow exactly. The extended set includes widths 1–4;
all twelve cases meet the unchanged three-channel-level standalone bound and
all twelve C/JavaScript matrices are byte-identical. Prior failed reports remain
in `jpeg-stress-report-before-sampling.json` and
`jpeg-reference-probe-before-sampling.json`. The independent Chromium probe
confirms the corrected narrow-image output.

The fallback follows [libjpeg-turbo's upsampler selection](https://github.com/libjpeg-turbo/libjpeg-turbo/blob/main/src/jdsample.c).
It does not change full-width or vertically-only doubled components.

## Other discrepancy probes

`stroke-vector-reference-probe.json` compares identical non-scaling-stroke
geometry expressed three ways. Chromium changes its rasterization between a
flattened stroked rectangle and an equivalent filled outline; the latter matches
its original non-scaling output exactly. The flattened rectangle is closer to
Bend (rectangle RMSE 1.324 versus 5.635). The primary fixture and its failed
verdict remain unchanged. No stroke geometry was altered to compensate.

`text-layout-probe.json` records Chromium's glyph positions with the bundled
Noto Sans fonts. For `A<tspan textLength="30">BC</tspan>D`, B begins at 10.03125,
C ends at 40.03125, and D begins at 55.921875. This isolates an additional gap
after the fitted span from glyph antialiasing. Text behavior is unchanged in this
sampling correction; the measurements support further compatibility work.
The normative reference remains the [SVG text layout algorithm](https://www.w3.org/TR/SVG2/text.html#TextLayoutAlgorithm).

The sampling checkpoint builds all three binaries and passes all 31 Bend
regression files. All 89 C/JavaScript fixture matrices match exactly. PNG editor
flows pass on C (18.23s) and JavaScript (70.06s), including resize, opacity, drag,
undo and save. The corrected native aspect-ratio window was captured, inspected
and closed. `sampling-build-report.json` and the frontend/backend reports record
the source hashes. The gallery loads all267 images and retains16 failure cards.
