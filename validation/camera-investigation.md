# Fitted viewing, zoom and pan

This change is integrated. The source and executable hashes are recorded in
[camera-build-report.json](camera-build-report.json).

The shared Bend state owns a camera matrix. Loading a drawing fits its natural
viewport into the output matrix. Fit, 100%, center zoom, and four pan actions
are available through native keys and browser buttons/keys. The SVG library
keeps document layout dimensions separate from output dimensions. CSS, nested
viewports, resource lookup and text layout run before the camera transform.
Navigation does not wrap or rewrite the authored SVG tree.

Picking and dragging use the camera-inclusive inverse transform; nudging moves
one output pixel. Navigation finishes an active drag, clears selection, and
preserves history. Undo restores the document with the current view. Applying
source preserves view and history, recalculating natural dimensions as needed.
Opening a file starts a new history and fits the new drawing. Camera values
never appear in the serialized SVG.

## Evidence

- 50 Bend regression files pass. `check-camera.bend` has 15 exact matrix/history
  assertions; `check-camera-sizing.bend` has seven for percentages, CSS root
  sizes, viewBox letterboxing, zero-size roots, nested percentage viewports and
  viewport media queries. Application source hashes are unchanged between runs.
- All 112 existing JavaScript matrices remain byte-identical to the preceding
  SVG implementation. Their independent-reference result remains 89/112; the
  same 23 failures are retained without changing thresholds or references.
- Three additional 256×256 wide/tall/resource drawings pass against independent
  resvg output fitted and centered on white. The largest MAE is 0.1169/255,
  RMSE 1.4089/255, and 11 of 65,536 pixels exceed a channel error of 32.
- All 112 existing and three fitted C matrices match JavaScript exactly.
- Both browser backends pass complete fitted-matrix checks, view controls,
  transformed picking/recoloring/dragging/nudging, exact undo, source edits,
  new-file history reset and save. The DOM contains no SVG presentation element.
- The native window matches the headless matrix after accounting for OS-rounded
  bottom corners and the calibrated outer-pixel border. Direct process-addressed keyboard events verify ten states across
  fit, zoom, 100%, four-direction pan, undo and save. Every displayed matrix
  and saved SVG is checked. Native pointer editing remains unverified.

See [checks](camera-check-report.json), [unchanged matrices](camera-prior-report.json),
[C parity](camera-native-all-report.json), [fitted C parity](camera-native-fit-report.json),
[reference gallery](camera-gallery.html), [reference metrics](camera-reference-report.json),
[JavaScript browser](browser-camera-js-report.json), [C browser](browser-camera-report.json),
and [native keyboard results](native-camera-keys-report.json).

## Native input method and limits

Earlier global-input attempts stopped because the test app did not acquire
foreground focus. The new helper uses Apple's
[`CGEvent.postToPid`](https://developer.apple.com/documentation/coregraphics/cgevent)
to address only an explicitly verified test process. It neither activates a
window nor posts into the global input stream. A preliminary Save probe passed
on the preceding source-undo binary. Three process-targeted mouse probes failed
to select a shape; all results remain recorded. The new native keyboard test
therefore makes no claim about pointer editing or complete input coverage.

A first pan screenshot exposed 14 lighter pixels on the window's rightmost
column. That failure is retained in `native-camera-keys-initial-report.json`.
Black, white and RGB(80,120,160) full-window captures independently measure and
validate the compositor's white edge overlay; no calibration pixels are inside
the image away from its border/corners. Subsequent comparisons retain every raw
error and allow one unit of compositor rounding only at calibrated border pixels.
Interior pixels must still match exactly. See `native-camera-calibration-report.json`.
The main SVG reference thresholds and results are unchanged.

Earlier browser scripts and reports retain their old source hashes and fixed
viewport assumptions. Use `run-browser-camera.mjs` for current frontend checks.
The native source/property panels, configurable interactive dimensions,
transparent output and the documented SVG conformance gaps remain unfinished.

The native capture programs (`run-native-camera-keys.py` and
`capture-native-camera-calibration.py`) retain the machine-specific staging
paths and known-process guards used for these recorded tests.
