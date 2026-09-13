// Render references at 4x resolution and box-downsample them to 64x64, then compare
// with the saved Bend matrices. Removes the reference rasterizers' own coverage
// quantization. Usage: bun validation/supersampled-probe.mjs [fixture-prefix...]
import { Resvg } from '@resvg/resvg-js';
import { chromium } from 'playwright';
import { PNG } from 'pngjs';
import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { pathToFileURL } from 'node:url';
const here = dirname(import.meta.filename), root = resolve(here, '..');
const K = Number(process.env.SUPERSAMPLE || 4), W = 64;
const prefixes = process.argv.slice(2);
const fixtures = readdirSync(resolve(root, 'fixtures')).filter(f => f.endsWith('.svg') && (!prefixes.length || prefixes.some(p => f.startsWith(p))));
const fonts = ['Regular', 'Bold', 'Italic', 'BoldItalic'];
const down = (rgba, w) => { const out = new Float64Array(W * W * 3); for (let y = 0; y < w; y++) for (let x = 0; x < w; x++) { const o = 3 * (((y / K) | 0) * W + ((x / K) | 0)); for (let c = 0; c < 3; c++) out[o + c] += rgba[4 * (y * w + x) + c]; } return Array.from(out, v => v / (K * K)); };
const metrics = (actual, ref) => { let sum = 0, sq = 0, max = 0, bad = 0; for (let i = 0; i < W * W; i++) { let peak = 0; for (let c = 0; c < 3; c++) { const d = Math.abs(actual[3 * i + c] - ref[3 * i + c]); sum += d; sq += d * d; max = Math.max(max, d); peak = Math.max(peak, d); } bad += peak > 32; } return { meanAbsoluteError: sum / (3 * W * W), rootMeanSquareError: Math.sqrt(sq / (3 * W * W)), maxChannelError: max, pixelsAbove32: bad }; };
const toPng = (px) => { const p = new PNG({ width: W, height: W }); for (let i = 0; i < W * W; i++) { for (let c = 0; c < 3; c++) p.data[4 * i + c] = Math.round(px[3 * i + c]); p.data[4 * i + 3] = 255; } return PNG.sync.write(p); };
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: W, height: W }, deviceScaleFactor: K });
const results = [];
try {
  for (const f of fixtures) {
    const name = f.slice(0, -4), input = resolve(root, 'fixtures', f);
    const actual = readFileSync(resolve(here, `${name}.ppm`), 'utf8').trim().split(/\s+/).slice(4).map(Number);
    const row = { fixture: f };
    try {
      const r = new Resvg(readFileSync(input), { background: 'white', fitTo: { mode: 'width', value: W * K }, ...(f.startsWith('text-') ? { font: { fontFiles: fonts.map(s => resolve(here, 'fonts', `NotoSans-${s}.ttf`)), loadSystemFonts: false, defaultFontFamily: 'Noto Sans' } } : {}) }).render();
      const px = down(r.pixels, W * K); row.resvg = metrics(actual, px); writeFileSync(resolve(here, `${name}-resvg-x${K}.png`), toPng(px));
    } catch (e) { row.resvg = { error: String(e.message || e) }; }
    await page.goto(pathToFileURL(input).href);
    if (f.startsWith('text-')) { const faces = fonts.map(style => ({ style, data: readFileSync(resolve(here, 'fonts', `NotoSans-${style}.ttf`)).toString('base64') })); await page.evaluate(async faces => { for (const { style, data } of faces) { const face = new FontFace('Noto Sans', `url(data:font/ttf;base64,${data})`, { weight: style.includes('Bold') ? '700' : '400', style: style.includes('Italic') ? 'italic' : 'normal' }); await face.load(); document.fonts.add(face); } await document.fonts.ready; }, faces); }
    const shot = PNG.sync.read(await page.screenshot({ omitBackground: false }));
    if (shot.width !== W * K) throw new Error(`screenshot ${shot.width}`);
    const px = down(shot.data, W * K); row.chromium = metrics(actual, px); writeFileSync(resolve(here, `${name}-chromium-x${K}.png`), toPng(px));
    results.push(row);
    const fmt = m => m.error ? 'error' : `${m.meanAbsoluteError.toFixed(3)}/${m.rootMeanSquareError.toFixed(2)}/${m.pixelsAbove32}`;
    console.log(name.padEnd(24), 'resvg', fmt(row.resvg).padEnd(16), 'chromium', fmt(row.chromium));
  }
} finally { await browser.close(); }
writeFileSync(resolve(here, `supersampled-report-x${K}.json`), JSON.stringify({ supersample: K, reference: { resvg: '@resvg/resvg-js', chromium: await browser.version?.() }, results }, null, 2) + '\n');
