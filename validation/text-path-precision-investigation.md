# Text-path precision experiment (not integrated)

The saved application remains the verified105-fixture build in
combined-svg-build-report.json. This isolated experiment adds a precision field
to path parsing and increases subdivision only for text-path measurements.
Ordinary path geometry retains its original precision.

The existing straight-path/calibration/direct-path regression passes. On the
basic text-path fixture, maximum Chromium tangent-angle error falls from1.259
to0.310 degrees, but maximum glyph-origin error remains0.190 user units. The
resvg comparison changes from MAE2.832/RMSE10.108 to2.783/9.959; the Chromium
comparison changes from3.124/10.275 to3.094/10.148. Both still fail the unchanged
limits. Increased subdivision alone does not resolve this conformance failure,
so the candidate has not replaced the compiled application.

The spacing probe finds no change between Chromium's default and spacing=exact.
For the first curved glyph, Chromium reports advance6.328125 and startOffset3.
The reported glyph center differs from getPointAtLength(3 +6.328125/2) on the
same path. An independent analytic quadratic integral agrees closely with the
more precise Bend placement. This suggests differences between the reference's
text-path and geometry distance approximations; it does not establish a browser
bug or invalidate the retained pixel errors.

Artifacts: text-path-precision-probe.json, text-path-spacing-probe.json,
text-path-precision-candidate.patch. The patch is against the saved SVG source;
it is an experiment and has not had the full C build or105-fixture parity check.
The implementation follows the midpoint/tangent rule in the
[SVG2 text layout algorithm](https://www.w3.org/TR/SVG2/text.html#TextLayoutAlgorithm).
