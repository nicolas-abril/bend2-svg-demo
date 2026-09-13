> Earlier SVG-image integration:44 Bend checks passed; all105 C/JavaScript matrices matched
> exactly;82/105 primary reference comparisons pass. Both web backends now pass
> the extended SVG image flow, including large-document click, opacity, undo
> and save. See combined-svg-build-report.json and browser-svg-images[-js]-report.json.
> Measurements and source hashes below describe the earlier image checkpoint.

# Font loading for embedded SVG images

The headless entrypoint decides whether to load the bundled font book before
rendering. Its original scan sees authored text elements but misses text inside
an SVG image data URI, producing missing-glyph boxes. Both GUI frontends already
load the book once, so their rendered text is unaffected by this correction.

The integrated correction moves `text.present` after the SVG URI helpers and reuses
the same exact MIME/scheme detection. SVG images trigger font loading without
prematurely decoding their content. Checks cover ordinary text, SVG images,
case/whitespace variations, xlink, PNG exclusion and wrong-MIME exclusion.

The self-contained reference fixture embeds a subset of the same Noto Sans font
inside the SVG image, so Chromium does not depend on installed fonts. Bend still
uses its bundled font book; this does not implement user font-face decoding.
Before the correction, Chromium MAE is11.992/255 and RMSE35.138/255. Afterward these
fall to2.020/255 and7.372/255. The remaining difference still exceeds the declared
limits. The tested resvg binding renders no text inside this SVG image; that
alternate result is retained too. See `svg-image-fonts-report.json` and
`svg-image-fonts-comparison.png`.

Candidate library SHA256:
9078af2d90a95e8de565217a320bf19e8c659ec8343fe3ab8a1606fbe477dcbd.
The corrected headless renderer is built and installed. All100 C/JavaScript
fixture matrices match exactly, and41 Bend check files pass. The compiled browser
also matches all65536 AA4 pixels of this embedded-text image against headless
output. See `svg-images-build-report.json`, `native-all-report.json`, and
`browser-svg-images-report.json`.

`svg-image-fonts-frontend-code-probe.json` proves that the corrected library emits
byte-identical C for native and web compared with the property-reducer build.
Those binaries were retained with recorded C and binary hashes. The headless
renderer was rebuilt with the Bend CLI's default O3/Metal flags. The new primary
fixture is included in the100-case gallery and remains a failed comparison under
the unchanged limits. Its subset-font provenance is in `svg-image-font-subset.json`.
