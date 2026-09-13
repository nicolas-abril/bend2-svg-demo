# Isolated filter blend candidate

Historical candidate evidence: this source is now integrated into the app;
see [current blend validation](blends.md). `blend-candidate.patch` applies to the
font-metric source f644682ed6296f42698293a7c387c2492bb2274dbdeb036dc1ea4259ec0dba16.
It implements overlay, color-dodge, color-burn, hard-light, soft-light, difference,
exclusion, hue, saturation, color and luminosity alongside the existing five
feBlend modes. It does not add CSS mix-blend-mode or group isolation.

Blend formulas follow [W3C Compositing and Blending](https://www.w3.org/TR/compositing-1/#blending).
Inputs are unpremultiplied for color mixing, then combined using source-over
alpha composition. Nonseparable modes use luminosity/saturation adjustments
with gamut clipping. The existing filter graph selects sRGB or linearRGB.

Three 64x64 matrices cover all16 modes with16 color pairs each: opaque sRGB,
varied source/backdrop alpha, and opaque linearRGB. Compared with Chromium,
maximum channel errors are1,1 and5; MAE values are0.012,0.076 and0.290/255.
All satisfy the established fixture limits. Raw resvg comparisons remain in
`blend-experiment-report.json`; its largest differences occur in nonseparable
and boundary cases, and the alternate results are not substituted for Chromium.

The isolated probe produces1024 matching C/JavaScript colors.128 cases use saved
Chromium pixels with one channel level of rounding tolerance. The candidate
and checks live under the temporary `blend-investigation` directory; the scripts
currently target that directory. All128 saved reference cases also pass through compiled C. All seven existing filter
fixture matrices are unchanged; see `blend-existing-fixtures-report.json`. The current integration is tracked in `blends.md`.
