// Reference renders are produced at a multiple of the comparison size and box-averaged
// down to it, so the comparison measures the engines' geometry, layout and paint rather
// than their own coverage quantization. The default is 8 (SVG_REFERENCE_SCALE overrides
// it); coverage.json sets "referenceScale": 1 for fixtures whose semantics depend on the
// output resolution (raster image sampling, device-pixel convolution and morphology).
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
export const SCALE = Number(process.env.SVG_REFERENCE_SCALE || 8);
if (!Number.isInteger(SCALE) || SCALE < 1 || SCALE > 16) throw Error('SVG_REFERENCE_SCALE must be an integer from 1 to 16');
const policy = JSON.parse(readFileSync(resolve(dirname(import.meta.filename), 'coverage.json'), 'utf8')).fixtures;
export const scaleFor = (fixture) => policy[fixture]?.referenceScale ?? SCALE;
// rgba: k*w by k*h RGBA bytes -> w by h RGBA bytes (rounded box average, opaque).
export function downsample(rgba, w, h, k) {
  const out = new Uint8Array(w * h * 4), sum = new Float64Array(w * h * 3), W = w * k;
  for (let y = 0; y < h * k; y++) for (let x = 0; x < W; x++) { const o = 3 * (((y / k) | 0) * w + ((x / k) | 0)), i = 4 * (y * W + x); sum[o] += rgba[i]; sum[o + 1] += rgba[i + 1]; sum[o + 2] += rgba[i + 2]; }
  for (let i = 0; i < w * h; i++) { for (let c = 0; c < 3; c++) out[4 * i + c] = Math.round(sum[3 * i + c] / (k * k)); out[4 * i + 3] = 255; }
  return out;
}
