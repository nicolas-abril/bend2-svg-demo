// side.mjs NAME... : Bend | reference | diff x4, nearest-upscaled, one PNG per fixture (scratch aid)
import { readFileSync, writeFileSync } from 'node:fs';
import { PNG } from 'pngjs';
const V = new URL('.', import.meta.url).pathname;
const OUT = process.env.SIDE_OUT || V;
const ppm = (p) => { const w = readFileSync(p, 'utf8').trim().split(/\s+/); const W = +w[1], H = +w[2]; const px = w.slice(4).map(Number); return { W, H, at: (x, y, c) => px[3 * (y * W + x) + c] }; };
const png = (p) => { const im = PNG.sync.read(readFileSync(p)); return { W: im.width, H: im.height, at: (x, y, c) => im.data[4 * (y * im.width + x) + c] }; };
const k = 6;
for (const name of process.argv.slice(2)) {
  const b = ppm(`${V}/${name}.ppm`), r = png(`${V}/${name}-${process.env.SIDE_REF || "reference"}.png`);
  const W = b.W, H = b.H, out = new PNG({ width: W * k * 3 + 2 * k, height: H * k });
  out.data.fill(128);
  const put = (i, f) => { for (let y = 0; y < H * k; y++) for (let x = 0; x < W * k; x++) { const o = 4 * (y * out.width + i * (W * k + k) + x); const sx = (x / k) | 0, sy = (y / k) | 0; for (let c = 0; c < 3; c++) out.data[o + c] = f(sx, sy, c); out.data[o + 3] = 255; } };
  put(0, b.at); put(1, r.at); put(2, (x, y, c) => Math.min(255, 4 * Math.abs(b.at(x, y, c) - r.at(x, y, c))));
  writeFileSync(`${OUT}/${name}.side.png`, PNG.sync.write(out));
  console.log(name);
}
