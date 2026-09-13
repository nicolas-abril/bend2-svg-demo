# Morphology filters

The morphology implementation is integrated in the single Bend SVG library.
All 47 Bend checks pass, all 112 C/JavaScript fixture matrices are identical,
and both web backends pass the complete editor flow. All 108 earlier matrices
are unchanged. The selected reference suite passes 89/112, with the same 23
retained failures. Build and source hashes are in morphology-build-report.json.

The implementation follows the component-wise minimum/maximum operation on
premultiplied RGBA in [Filter Effects Level 1](https://www.w3.org/TR/filter-effects-1/#feMorphologyElement).
It supports erosion, dilation, independent radii, primitive coordinate systems,
SourceAlpha, named graph inputs/results and primitive clipping. Two separable
passes follow the transformed primitive axes. The existing filter color-space,
mask, opacity and nested-scene pipeline remains in use.

Radii are rounded to the nearest intermediate-buffer pixel. Nonpositive radii
disable their axis; a zero horizontal radius can still allow vertical erosion.
The independent 28-case [reference probe](morphology-reference-probe.json)
records Chromium's behavior, including negative axes, and the older resvg
binding's shifted kernel and different fractional-radius behavior. This follows
the browser's axis-wise interpretation of disabled radii; the specification's
wording is not an unambiguous definition of these discrete sampling details.

All four new primary comparisons pass the unchanged thresholds at 64×64, AA8:

| Fixture | MAE /255 | RMSE /255 | Maximum channel error | Pixels above 32 |
| --- | ---: | ---: | ---: | ---: |
| morphology-basic | 0.110 | 0.332 | 1 | 0 |
| morphology-radius | 0 | 0 | 0 | 0 |
| morphology-graph | 0.035 | 0.188 | 1 | 0 |
| morphology-units | 0.889 | 4.117 | 49 | 24 |

[morphology-reference-report.json](morphology-reference-report.json) retains
both engines' complete measurements, fixture source and hashes. All resvg
alternate failures are retained. No existing failure or threshold is changed.
The complete selected suite passes 89/112, with the same 23 earlier failures.

All 47 Bend regression files pass. The new Bend regression compares complete matrices with independently
constructed eroded/dilated rectangles, including one-axis radii and SourceAlpha.
Two adjacent translucent colors independently test channel-wise extrema on
premultiplied values. It checks expansion, erosion and exact zero-radius copy.

Filter buffers retain their existing 1024-pixel dimension limit. A morphology
pass samples at most 4097 points per axis; beyond the finite buffer diagonal,
additional samples can only be transparent. Large radii remain expensive.
Rotated/skewed sampling uses bilinear interpolation and is approximate; arbitrary
transforms, extremely large radii and complex nested effects need more coverage.

The integrated source change is saved in
[morphology-candidate.patch](morphology-candidate.patch). Application source
hash: `6f07e3f729ee9d6a62951eb3eb529087d0321ea06270dc4c7add2af5db7c7cf4`.

The first JavaScript web attempt exceeded its 60-second startup limit while
three compilers and four fixture workers were active. It performed no browser
checks and is not counted as a passing flow. The final complete run passes.

At the morphology checkpoint, applying source loaded a new document and reset
history. That earlier browser
flow checks undo for property changes and dragging; it restores the graph source
by reloading the original and comparing the complete matrix. Undo across source edits is now integrated; see source-undo-investigation.md.

The first full JavaScript flow passed the four complete matrices and property/
drag undo, then exposed an overstrict reload assertion: parsing reverses XML
attribute-list order, so serialization changes byte order on reload. The
isolated Bend roundtrip has identical pixels and unchanged attribute values.
The corrected test compares the reloaded source with Bend’s second serialization,
retains every-pixel equality, and saves that exact source. This normalization is
recorded in morphology-roundtrip-report.json; earlier failed runs are not passes.
