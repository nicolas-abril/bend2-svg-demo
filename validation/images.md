# Embedded PNG images

The later [sampling correction](sampling.md) fixes the aspect-ratio boundary
case described below. All seven PNG fixtures now pass; the older checkpoint
measurements are retained here as history.

`svg.bend` now decodes embedded PNG files and paints them through the shared scene
pipeline. Data may be base64 or percent encoded in a PNG data URI. The frontends
receive only the final pixel matrix; they do not decode or display image payloads.

The decoder supports all standard PNG grayscale, truecolor, indexed-color,
grayscale-alpha and RGBA formats at their legal bit depths (1, 2, 4, 8 and 16).
It handles palette/key transparency, all five scanline filter types, Adam7
interlacing, multiple IDAT chunks, and stored/fixed-Huffman/dynamic-Huffman
DEFLATE blocks. CRC32 and Adler32 validation are implemented in Bend.

The byte buffer, bit reader, Huffman decoder, backward-copy window, scanline
reconstruction and RGBA conversion live in the same SVG library. Decoded pixels
are retained in the existing compressed RGBA quadtree and sampled as a bitmap
paint. No foreign decoder is called. Implementation references are the
[PNG specification](https://www.w3.org/TR/png-3/) and
[DEFLATE specification](https://www.rfc-editor.org/rfc/rfc1951).

Image elements support x/y/width/height, intrinsic sizing when dimensions are
automatic, percentage dimensions, preserveAspectRatio alignment/meet/slice/none,
transforms, opacity, clipping, masks, filters and pattern content. Fill and stroke
properties do not alter image pixels. Image-rendering is inherited through the
shared style state. The web property menu exposes image dimensions, aspect
ratio, sampling and href. The authored data URI remains in saved SVG source.
Placement follows [SVG embedded content](https://www.w3.org/TR/SVG2/embedded.html).

## Limits

Embedded PNG and JPEG payloads are supported; [JPEG validation](jpeg.md) covers
the separate JPEG decoder. SVG image payloads and external image loading remain
to implement. The PNG dimension cap is 2048 pixels
on either axis. Color samples currently assume sRGB: embedded gamma, chromaticity,
ICC profiles and HDR metadata are not applied. APNG animation is not played; its
default PNG image is decoded. Error diagnostics, malformed chunk ordering,
singular transforms and large-file performance need broader work.

Default sampling is bilinear. Pixelated/crisp-edges/optimizeSpeed use nearest
sampling; exact ties select the lower texel. Fractional scaling and transformed
sampling can differ across engines. CSS object-fit/object-position, EXIF
orientation and visible overflow beyond the positioning rectangle are not yet
implemented. Invalid/unsupported images currently paint transparent pixels.

## Decoder and reference evidence

27 Bend regression files pass. The new tests include byte-buffer persistence and
bit-boundary reads; eleven DEFLATE tests for all block types, overlapping copies,
multiple blocks and invalid/truncated/oversized streams; and 33 PNG cases covering
all legal type/depth/interlace combinations, transparency, row filters, checksum
failure and truncation. Tests compare decoded premultiplied RGBA channels, not
only opaque RGB output. Generators are confined to validation.

Seven image fixtures are compared at 64×64 with AA8. Chromium is the primary
reference throughout this group. The original limits remain MAE ≤1/255, RMSE ≤5/255
and at most 1% of pixels with a channel error above32. Six fixtures pass and one
fails. Both complete reference reports are retained.

| Fixture | MAE /255 | RMSE /255 | Max | Pixels >32 | Verdict |
| --- | ---: | ---: | ---: | ---: | --- |
| images-aspect.svg | 0.411 | 5.820 | 99 | 30 | FAIL |
| images-basic.svg | 0.320 | 1.102 | 9 | 0 | PASS |
| images-compositing.svg | 0.450 | 2.540 | 49 | 20 | PASS |
| images-compression.svg | 0.000 | 0.000 | 0 | 0 | PASS |
| images-png-formats.svg | 0.001 | 0.034 | 1 | 0 | PASS |
| images-transforms.svg | 0.597 | 1.882 | 22 | 0 | PASS |
| images-uris.svg | 0.483 | 1.416 | 9 | 0 | PASS |

The aspect-ratio fixture fails the RMSE limit at nearest-neighbor sample
boundaries. The error is retained without changing tolerances. The 30-format PNG
fixture agrees with both references within one channel level. The compression
fixture exercises stored, fixed, dynamic and multiple blocks through the normal
file-loading/rendering path; its input block types are recorded separately.

`image-reference-probe.json` isolates resvg 2.6.2 behavior. In the first nearest
image panel, changing only pixelated to optimizeSpeed reduces its MAE from
14.274/255 to exactly zero against Bend. This binding also omits images whose
missing dimensions require SVG2 intrinsic sizing; providing explicit dimensions
restores their rendering. Alternate differences at fractional nearest boundaries
remain. These probes explain reference selection and do not replace failed
primary comparisons.

The gallery retains all images and amplified differences. `image-parity-report.json`
checks the original 76 non-image fixture matrices. `native-all-report.json`
checks C/JavaScript parity, and the browser image reports check resizing, opacity,
dragging, exact undo and preserving the embedded payload when saving.

The original 76 matrices remain byte-identical, with source hashes verified. The
JavaScript browser image flow passed in 81.68 seconds, including
exact source/pixel undo and saved data-URI preservation.

All three compiled targets build successfully, and the saved app passes all 27
regression files. All 83 C/JavaScript matrices are byte-identical. The compiled
browser flow passed in 17.76 seconds, versus 81.68 seconds on JavaScript.
Source hashes in the reports match the saved library and frontends. The native
window was opened and visually inspected; native-images.png and
web-images-editor.png record the two frontends.

A large inline payload in the inflater unit test hit Bun’s compiler stack limit
in the saved checkout. Its literal was reduced while retaining all eleven cases;
the larger file-based PNG compression fixture covers all compression paths
through both production backends. No language/compiler source was modified.

The reduced inflater test also compiles and passes all eleven cases directly on
the C backend; inflate-native-report.json records its source hashes and output.
image-editor-saved.svg is the serialized document captured by the browser save
check, preserving its embedded PNG data URI.
