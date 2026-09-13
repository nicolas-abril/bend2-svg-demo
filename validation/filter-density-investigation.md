# Filter buffer density diagnostic

Doubling the intermediate buffer density does not resolve the two existing
filter failures and introduces a failure in the previously passing blur fixture.
The installed renderer is unchanged. The candidate and base source hashes are
recorded in [filter-density-probe.json](filter-density-probe.json), alongside all
seven complete comparisons against Chromium and resvg. Sampling remains AA8
and the original primary thresholds remain fixed.

| Fixture | Original MAE | Double-density MAE | Double-density RMSE | Verdict |
| --- | ---: | ---: | ---: | --- |
| filters-basic.svg | 0.109 | 0.109 | 0.330 | PASS |
| filters-blend.svg | 0.439 | 0.434 | 2.060 | PASS |
| filters-blur.svg | 0.953 | 1.172 | 4.049 | FAIL |
| filters-composite.svg | 0.680 | 0.678 | 3.776 | PASS |
| filters-nested.svg | 1.811 | 1.731 | 6.637 | FAIL |
| filters-regions.svg | 0.473 | 0.473 | 4.122 | PASS |
| filters-transforms.svg | 1.221 | 1.143 | 3.551 | FAIL |

Transformed filters improve slightly, while nested filtering still exceeds the
RMSE and error-pixel thresholds. Finer intermediate sampling alone is therefore
insufficient to fix these cases. This experiment does not establish which
engine is more faithful to continuous Gaussian convolution.

The one-line source change is retained as
[filter-density-candidate.patch](filter-density-candidate.patch). Run
`bun validation/probe-filter-density.mjs` to reproduce the seven comparisons;
it creates temporary Bend sources, invokes the neighboring Bend CLI and writes
`*-density2.ppm` matrices and the complete report. Set `BEND_MAIN` if needed.
No alternate result replaces a failing primary comparison.
