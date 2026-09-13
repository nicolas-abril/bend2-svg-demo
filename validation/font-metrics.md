# Font metric correction

The Bend font book now accepts `m|face:name|value` records in `fonts.dat`.
The generator reads subscript/superscript offsets, typographic ascent/descent
and x-height from each bundled face's OpenType OS/2 table, normalized by units
per em. Glyph outlines and kerning rows are unchanged. The regenerated asset is
byte-for-byte reproducible with FontTools 4.59.2 and the four saved TTFs.

Noto Sans specifies subscript offset 0.075em and superscript offset 0.35em.
The previous constants were 0.2em and 0.4em. At 8px, the fixture's subscript
baseline moves from 57.6 to 56.6 and its superscript baseline from 52.8 to 53.2.
The font-selected offsets agree with resvg's glyph outlines. Missing metric
records retain the previous fallback values; the parser remains compatible
with existing glyph/kerning-only font books.

The metric field semantics are documented in the
[OpenType OS/2 specification](https://learn.microsoft.com/en-us/typography/opentype/spec/os2).
Baseline positioning follows the font-relative approach described by
[SVG text layout](https://www.w3.org/TR/SVG2/text.html).

All nine text fixtures were rendered again through JavaScript and compared with
both resvg and Chromium. Only `text-spans.svg` changed. Against its existing
resvg reference, MAE falls from 1.269 to 0.801/255 and RMSE from 6.642 to
3.333/255; two pixels have a channel difference above 32. It passes the unchanged
limits. The selected suite is now 74/89, retaining all 15 failures and alternate
reference results. The other 80 non-text matrices are retained from the verified
sampling checkpoint; the rebuilt C renderer now matches all89 JavaScript
matrices exactly.

All 32 Bend regression files pass. The eight new font-metric outputs also match
exactly in compiled C, covering face selection, sub/super signs and units,
missing-record fallback, middle and central baselines. See
`font-metrics-check-report.json`. All three native/web/render binaries build
and all32 saved checks pass. The native text window was captured, inspected and
closed. The text editor flows pass on JavaScript (76.13s) and the rebuilt C server
(18.59s), including selection, fill/font changes, movement and
exact source/pixel undo. Build and frontend reports record their own source hashes.
