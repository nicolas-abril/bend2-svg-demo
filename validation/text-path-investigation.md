# Text on paths

Integrated in the saved application alongside the large-document serialization fix.
All44 Bend checks pass and all105 C/JavaScript fixture matrices are identical.
Both browser backends pass selection, recoloring, font-weight changes, dragging,
saving and exact source/full-matrix undo; see browser-text-path-report.json and
browser-text-path-js-report.json. Build hashes are in combined-svg-build-report.json.

The library resolves local path references after use/image expansion, including
separate embedded-image resource scopes. Glyphs use the existing Bend font layout,
then map their centers and orientations onto flattened path geometry. Numeric and
percentage startOffset, pathLength calibration, root/span position lists, anchors,
kerning/spacing, baseline offsets, glyph rotation, referenced-element transforms,
direct path data, basic-shape references and textLength fitting are implemented
in the application. Following ordinary text resumes at the path endpoint.

The 22-case `text-path-reference-probe.json` records independent Chromium glyph
positions and rotations plus Chromium/resvg pixel disagreements. The first
candidate's glyph origins agree within 0.03 user units for tested straight,
offset, positioned, rotated and referenced paths. The tested curve differs by
up to0.105 units. Direct path data and calibrated offsets expose resvg omissions;
Chromium does not render the tested basic-shape reference. Missing-reference
following-text behavior remains different.

All five experimental 64×64 pixel fixtures exceed at least one unchanged primary
threshold. Keep both raw results in `text-path-experiment-report.json`; these are
not passing conformance claims. A straight textPath matrix is byte-identical to
an equivalent ordinary Bend text element, isolating part of the pixel error to
the existing font rasterizer. The five comparison images remain visible alongside
the raw matrices.

The regression suite includes full-matrix equivalence for straight paths,
calibrated offsets and direct path data, plus ownership, translation, reference
preservation and exact source/pixel undo. The complete primary suite passes82/105,
with all five text-path fixtures exceeding at least one unchanged threshold.
The original experimental reports retain their original source hashes; fresh
integrated comparisons are in report.json, chromium-report.json and summary.json.

A fresh probe of the three-line basic fixture finds Chromium glyph-origin errors
up to0.191 user units and rotation errors up to1.259 degrees. Drawing the same
outlines at Bend's positions in resvg reduces RMSE from10.108 to3.485/255,
indicating that path placement contributes more than the remaining outline
rasterization in this fixture. See text-path-basic-position-probe.json and
text-path-outline-probe.json. This diagnostic does not replace the failed
primary comparison.

Unfinished behavior includes SVG2 closed-path wrapping, side=right, method=stretch,
vertical text, complex shaping/RTL, invalid direct-path fallback, and some nested
textLength/anchor combinations. Neither new feature support nor mathematical
placement probes replace every-pixel comparison.

The implementation plan follows the [SVG2 text layout algorithm](https://www.w3.org/TR/SVG2/text.html#TextLayoutAlgorithm)
and [text on a path](https://www.w3.org/TR/SVG2/text.html#TextOnAPath). The independent
reference disagreements are preserved even where the candidate follows one
interpretation of those rules.
