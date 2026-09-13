// The Bend TrueType reader must reproduce the fonts.dat text rendering: load the four
// bundled Noto Sans faces through SVG_TTF_FONTS and compare every text fixture's matrix
// with the saved fonts.dat matrix. Usage: bun validation/ttf-parity.mjs
import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { resolve, dirname } from 'node:path';
const here = dirname(import.meta.filename), root = resolve(here, '..');
const faces = ['Regular', 'Bold', 'Italic', 'BoldItalic'];
const paths = faces.map(style => resolve(here, 'fonts', `NotoSans-${style}.ttf`));
const results = [];
{
  for (const f of readdirSync(resolve(root, 'fixtures')).filter(x => x.endsWith('.svg') && readFileSync(resolve(root, 'fixtures', x), 'utf8').includes('<text')).sort()) {
    const name = f.slice(0, -4);
    const got = spawnSync(resolve(root, 'build/render'), ['--gpu', 'off'], { env: { ...process.env, SVG_TTF_FONTS: paths.join(','), SVG_INPUT: resolve(root, 'fixtures', f), SVG_WIDTH: '64', SVG_HEIGHT: '64', SVG_AA: '8' }, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
    if (got.status !== 0) throw Error(got.stderr || got.stdout);
    const saved = readFileSync(resolve(here, `${name}.ppm`), 'utf8');
    const identical = got.stdout === saved;
    results.push({ fixture: f, identical });
    console.log(`${identical ? 'PASS' : 'FAIL'} ${f}`);
  }
}
const passed = results.every(r => r.identical);
writeFileSync(resolve(here, 'ttf-parity-report.json'), JSON.stringify({ passed, fonts: Object.fromEntries(faces.map(s => [`NotoSans-${s}.ttf`, createHash('sha256').update(readFileSync(resolve(here, 'fonts', `NotoSans-${s}.ttf`))).digest('hex')])), results }, null, 2) + '\n');
console.log(passed ? `All ${results.length} text fixtures match the fonts.dat matrices` : 'TrueType rendering differs');
if (!passed) process.exit(1);
