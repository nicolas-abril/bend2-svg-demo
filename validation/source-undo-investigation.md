# Undoable source edits

The shared Bend reducer now treats applying SVG source as an undoable edit.
Opening a file starts a new history. The browser only sends commands; parsing,
history, selection and rasterization stay in Bend.

All 48 Bend regression files pass. Both web backends pass the complete source
undo flow, including two full 256×256 matrices, prior property history,
successive source edits, unchanged-source no-ops, exact source/pixel restoration,
file opening and save. Reports retain exact source and binary hashes in
browser-source-undo-report.json and browser-source-undo-js-report.json.

Applying exactly the current serialized source is a no-op. This avoids an extra
undo entry and avoids reordering attributes unnecessarily. A changed source
clears selection and finishes an active drag before recording the edit. The
regression verifies both undo steps after source is applied during a drag.

The SVG library is byte-identical to the verified morphology build. Independently
emitted headless C is also byte-identical, so its compiled renderer is reused
with explicit equivalence evidence in source-undo-headless-equivalence.json.
Native and web C differ and were freshly compiled and validated. The native
window screenshot matches the headless matrix except for the documented OS
rounded corners; native input automation remains unverified.

The integrated changes are saved in
[source-undo-candidate.patch](source-undo-candidate.patch). Shared-state hash:
`83513370e590e7df992d0daa684a142890585fa1e00bcd8cefa823bf9272a036`.
