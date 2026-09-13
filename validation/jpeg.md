# Embedded JPEG images

The later [sampling correction](sampling.md) adds the narrow-plane box fallback.
All twelve current stress cases pass; the original failing reports are retained
with `-before-sampling` suffixes.

`svg.bend` decodes JPEG payloads inside base64 or percent-encoded image data
URIs. Frontends receive the final raster matrix; neither frontend invokes an
image decoder. The shared SVG image pipeline handles placement, intrinsic
sizes, aspect fitting, sampling, transforms, opacity, clips, masks, filters and
pattern content.

The decoder implements 8-bit Huffman sequential and progressive JPEG: frame
and scan headers, canonical Huffman tables up to 16 bits, escaped entropy bytes,
DC prediction, AC runs, spectral selection, successive approximation, EOB runs,
restart markers, and separate/interleaved scans. Quantization tables may contain
8- or 16-bit entries. A separable floating-point inverse DCT reconstructs each
component plane, followed by centered bilinear chroma upsampling. Grayscale,
YCbCr, explicit RGB, and Adobe CMYK/YCCK conversions are supported.

The implementation follows [ITU-T T.81](https://www.w3.org/Graphics/JPEG/itu-t81.pdf),
particularly Annexes B/C/F/G. Color conventions were checked against
[libjpeg-turbo's color conversion source](https://github.com/libjpeg-turbo/libjpeg-turbo/blob/main/src/jdcolor.c).
Validation images are generated with [Pillow's JPEG encoder](https://pillow.readthedocs.io/en/stable/handbook/image-file-formats.html#jpeg),
plus small spec-derived streams for separate sequential scans, 16-bit DQT and
16-bit Huffman codes. Pillow is a validation dependency only.

## Evidence

- `check-jpeg.bend` compares all pixels of 19 JPEG samples to independently
  decoded Pillow 12.3.0/libjpeg pixels. Cases include grayscale, 4:4:4, 4:2:2,
  4:2:0, progressive refinement, noisy content, restart markers, RGB, CMYK/YCCK,
  separate scans and extended table encodings. All are within two channel levels.
- `check-jpeg-errors.bend` rejects 13 malformed/unsupported streams: bad
  signatures, missing EOI, truncated entropy, missing/zero quantization,
  unsupported precision, oversized dimensions, invalid sampling/selectors,
  invalid scan bands, out-of-order restart markers and arithmetic frames.
- `check-jpeg-bits.bend` checks MSB-first reads, byte stuffing, marker rejection,
  JPEG sign extension and zigzag ordering.
- `jpeg-decode-report.json` records every-pixel errors and exact C/JavaScript
  matrix parity for all 19 samples, with the SVG library source hash.
- `jpeg-stress-report.json` covers twelve file-based cases: one-pixel/narrow/short
  images, partial MCUs, flat progressive data, restart-marker wraparound,
  quality extremes, and a 128×96 progressive image. All twelve meet the
  three-level Pillow bound and have exact C/JavaScript parity. The original
  1×17 failure (max23) and its correction are documented in [sampling.md](sampling.md).
  [libjpeg-turbo's upsampler](https://github.com/libjpeg-turbo/libjpeg-turbo/blob/main/src/jdsample.c)
  switches to box upsampling for horizontally doubled components at most two
  samples wide; Bend now follows that fallback. `jpeg-reference-probe.json`
  records independent Chromium measurements.
- `jpeg-malformed-report.json` records 100 deterministic truncations and byte
  mutations run through the compiled decoder. Every process completed without
  a crash or timeout. This checks bounded completion, not whether every mutation
  should be rejected; JPEG has no whole-file integrity checksum.
- `jpeg-parity-report.json` confirms all 83 pre-JPEG 64×64 AA8 matrices are
  unchanged, with source hashes.
- All six `jpeg-*.svg` fixtures pass the unchanged primary Chromium limits
  (MAE ≤1/255, RMSE ≤5/255, at most 1% of pixels above 32 channel error).
  Raw resvg comparisons are retained. Its color fixture disagrees substantially
  on CMYK/YCCK, while Chromium and Pillow agree closely with Bend.

At the original JPEG checkpoint, the native app, web server and headless renderer
all built; all 30 Bend
regression files pass. `native-all-report.json` records exact C/JavaScript parity
for all 89 SVG fixtures. Browser JPEG editing, full-matrix/source undo and save
pass on C (16.74s) and JavaScript (89.57s). The native JPEG window was
captured and visually inspected. See `jpeg-build-report.json`,
`browser-jpeg-report.json`, `browser-jpeg-js-report.json` and
`jpeg-native-window-report.json` for source hashes and checks.

## Limits

Decoding is limited to 2048 pixels per axis. Lossless, arithmetic, hierarchical,
12-bit and JPEG-LS/JPEG2000 streams are unsupported. ICC color management and
EXIF orientation are not applied. Unmarked four-component JPEGs use the common
Adobe inverted-CMYK convention. Large-image speed and malformed-input coverage
need broader validation. Unsupported or rejected input produces an empty image;
there is no decoder error UI yet.

Inverse DCT rounding and chroma reconstruction vary between decoders. The
three-channel-level standalone bound is separate from the unchanged SVG
comparison thresholds; it is not a claim of universal bit-exact JPEG output.

To regenerate:

```sh
python3 -m venv validation/venv
validation/venv/bin/pip install Pillow==12.3.0
validation/venv/bin/python validation/gen-jpeg.py
python3 validation/gen-jpeg-images.py
mkdir -p build
bun ../../bend2-core/bend2/main.ts validation/probe-jpeg.bend -o build/jpeg-probe
JPEG_NATIVE="$PWD/build/jpeg-probe" bun validation/jpeg-decode.mjs
SVG_COMPARE_FILTER=jpeg- bun validation/compare.mjs
SVG_COMPARE_FILTER=jpeg- bun validation/compare-browser.mjs
bun validation/verify.mjs
```

`verify.mjs` still reports the remaining SVG discrepancies. The
initial JPEG checkpoint had 72 passing comparisons out of 89 fixtures.
The sampling correction increases that to 73/89.

Extended probes use `gen-jpeg-stress.py` and `jpeg-malformed.mjs`. Run the stress
comparison with `JPEG_CASES=jpeg-stress-cases.json` and
`JPEG_REPORT=jpeg-stress-report.json`; the corrected twelve-case set passes, including the narrow-image comparisons.
