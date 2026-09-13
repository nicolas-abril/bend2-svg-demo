# Scene coverage optimization

All 69 fixture matrices remain byte-identical in both C and JavaScript. All 20
Bend regression files pass. The original reference verdict remains 55/69.

The rasterizer skips scene subtrees outside conservative coverage bounds, including
descendant strokes and markers. Object bounding boxes used by SVG paint servers
are preserved.

Paired C runs at 64×64, AA8, GPU off: three alternating before/after pairs per
fixture; every pair must produce identical bytes. Times include process startup.

| Fixture | Before median | After median | Ratio |
|---|---:|---:|---:|
| markers-context.svg | 2.672s | 0.613s | 4.36× |
| markers-vertices.svg | 4.586s | 0.599s | 7.66× |
| text-basic.svg | 3.784s | 1.951s | 1.94× |
| pattern-nested.svg | 1.641s | 1.550s | 1.06× |

The nested-pattern result is roughly unchanged. These selected fixture timings
do not establish a universal speedup.

The marker browser flow passes on the compiled server in 23.55s
(previously108.09s), and on JavaScript in 239.50s (previously446.09s).
These end-to-end observations ran separately from the controlled paired benchmark.
The full C fixture run takes 58.11s
(previously137.43s).

Machine-readable evidence: [paired benchmark](coverage-benchmark-report.json),
[unchanged JavaScript output](coverage-parity-report.json),
[C/JavaScript parity](native-all-report.json), and
[compiled editor flow](browser-markers-report.json). Reports identify source hashes;
the paired benchmark also identifies both binary hashes.
