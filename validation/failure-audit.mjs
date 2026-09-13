// Tabulate every failing primary comparison against all three saved engine renders,
// and how much the engines disagree among themselves. Reads summary.json and the
// saved *.ppm / *-reference.png (resvg) / *-chromium.png / *-firefox.png images.
// Writes failure-audit.json. Usage: bun validation/failure-audit.mjs
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { PNG } from 'pngjs';
const here = dirname(import.meta.filename);
const summary = JSON.parse(readFileSync(resolve(here, 'summary.json'), 'utf8'));
const failing = [];
(function walk(o) { if (Array.isArray(o)) o.forEach(walk); else if (o && typeof o === 'object') { if (o.fixture && o.passed === false && !failing.some(f => f.fixture === o.fixture)) failing.push(o); Object.values(o).forEach(walk); } })(summary);
const ppm = (p) => { const w = readFileSync(p, 'utf8').trim().split(/\s+/); return { w: +w[1], h: +w[2], at: (i, c) => +w[4 + 3 * i + c] }; };
const png = (p) => { const im = PNG.sync.read(readFileSync(p)); return { w: im.width, h: im.height, at: (i, c) => im.data[4 * i + c] }; };
const metrics = (a, b) => { let s = 0, q = 0, big = 0; const n = a.w * a.h; for (let i = 0; i < n; i++) { let m = 0; for (let c = 0; c < 3; c++) { const d = Math.abs(a.at(i, c) - b.at(i, c)); s += d; q += d * d; m = Math.max(m, d); } if (m > 32) big++; } return { mae: s / (3 * n), rmse: Math.sqrt(q / (3 * n)), pixelsAbove32: big }; };
const engines = { resvg: 'reference', chromium: 'chromium', firefox: 'firefox' };
const rows = [];
for (const f of failing) {
  const name = f.fixture.replace(/\.svg$/, ''), bend = ppm(resolve(here, `${name}.ppm`)), im = {};
  for (const [e, suffix] of Object.entries(engines)) { const p = resolve(here, `${name}-${suffix}.png`); if (existsSync(p)) im[e] = png(p); }
  const row = { fixture: f.fixture, primary: f.reference, bend: {}, engines: {} };
  for (const e of Object.keys(im)) row.bend[e] = metrics(bend, im[e]);
  for (const [a, b] of [['chromium', 'firefox'], ['chromium', 'resvg'], ['firefox', 'resvg']]) if (im[a] && im[b]) row.engines[`${a}~${b}`] = metrics(im[a], im[b]).mae;
  rows.push(row);
}
const fmt = (m) => m ? `${m.mae.toFixed(3)}/${m.rmse.toFixed(2)}/${m.pixelsAbove32}` : '-';
console.log('Bend versus each engine (MAE/RMSE/pixels>32), then engine-to-engine MAE');
console.log(['fixture'.padEnd(22), 'primary'.padEnd(9), 'resvg'.padEnd(17), 'chromium'.padEnd(17), 'firefox'.padEnd(17), 'chr~ffx', 'chr~resvg', 'ffx~resvg'].join(' '));
for (const r of rows) console.log([r.fixture.replace(/\.svg$/, '').padEnd(22), r.primary.padEnd(9), fmt(r.bend.resvg).padEnd(17), fmt(r.bend.chromium).padEnd(17), fmt(r.bend.firefox).padEnd(17), ...['chromium~firefox', 'chromium~resvg', 'firefox~resvg'].map(k => (r.engines[k] === undefined ? '-' : r.engines[k].toFixed(3)).padEnd(9))].join(' '));
writeFileSync(resolve(here, 'failure-audit.json'), JSON.stringify({ thresholds: summary.thresholds, results: rows }, null, 2) + '\n');
