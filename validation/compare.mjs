// Reference renderer is confined to this validation tool.
import { Resvg } from '@resvg/resvg-js';
import { PNG } from 'pngjs';
import { SCALE, scaleFor, downsample } from './reference-scale.mjs';
import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { resolve, dirname } from 'node:path';
const here = dirname(import.meta.filename);
const root = resolve(here, '..');
const bend = process.env.BEND_MAIN || resolve(root, '../../bend2-core/bend2/main.ts');
const filter = process.env.SVG_COMPARE_FILTER;
// SVG_RENDER_BIN points at a compiled build/render to skip the interpreter (the C parity run still checks the two agree).
const binary = process.env.SVG_RENDER_BIN ? resolve(process.env.SVG_RENDER_BIN) : null;
const previous = filter ? JSON.parse(readFileSync(resolve(here, 'report.json'), 'utf8')) : null;
if (previous && previous.supersampling !== Number(process.env.SVG_COMPARE_AA || 8)) throw Error('Filtered comparison must use the existing report sampling level');
const report = previous ? previous.results.filter(r => !r.fixture.startsWith(filter)) : [];
const aa = Number(process.env.SVG_COMPARE_AA || 8);
if (!Number.isInteger(aa) || aa<1 || aa>8) throw Error("SVG_COMPARE_AA must be 1–8");
for (const file of readdirSync(resolve(root, 'fixtures')).filter(x => x.endsWith('.svg') && (!filter || x.startsWith(filter)))) {
  const name = file.slice(0, -4), input = resolve(root, 'fixtures', file);
  const [cmd, args] = binary ? [binary, ['--gpu', 'off']] : ['bun', [bend, resolve(root, 'render.bend')]];
  const result = spawnSync(cmd, args, {
    env: {...process.env, SVG_FONTS:resolve(root,'fonts'), SVG_INPUT: input, SVG_WIDTH:'64', SVG_HEIGHT:'64', SVG_AA:String(aa)}, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024,
  });
  if (result.status) throw new Error(result.stderr || result.stdout);
  writeFileSync(resolve(here, `${name}.ppm`), result.stdout);
  const words = result.stdout.trim().split(/\s+/);
  if (words.shift() !== 'P3') throw new Error('Expected a P3 matrix from Bend');
  const w = +words.shift(), h = +words.shift(), max = +words.shift();
  if (max !== 255 || words.length !== w*h*3) throw new Error('Invalid matrix dimensions');
  const actual = words.map(Number);
  let reference;
  try {
    reference = new Resvg(readFileSync(input), {
      background:'white', fitTo:{mode:'width',value:w*scaleFor(file)},
      ...(file.startsWith('text-') ? {font:{fontFiles:['Regular','Bold','Italic','BoldItalic'].map(style=>resolve(here,'fonts',`NotoSans-${style}.ttf`)),loadSystemFonts:false,defaultFontFamily:'Noto Sans'}} : {}),
    }).render();
  } catch(error) {
    report.push({fixture:file,width:w,height:h,error:String(error.message||error)});
    continue;
  }
  if (reference.width !== w*scaleFor(file) || reference.height !== h*scaleFor(file)) throw new Error('Reference size mismatch');
  const referencePixels = downsample(reference.pixels, w, h, scaleFor(file));
  const png = new PNG({width:w, height:h}); png.data.set(referencePixels); writeFileSync(resolve(here, `${name}-reference.png`), PNG.sync.write(png));
  let sum = 0, sq = 0, worst = 0, changed = 0, bad = 0;
  const difference = [];
  for (let i=0; i<w*h; ++i) {
    let pmax = 0;
    for (let c=0; c<3; ++c) {
      const d = Math.abs(actual[3*i+c] - referencePixels[4*i+c]);
      sum += d; sq += d*d; worst = Math.max(worst,d); pmax = Math.max(pmax,d);
      difference.push(Math.min(255,d*4));
    }
    changed += pmax>0; bad += pmax>32;
  }
  writeFileSync(resolve(here, `${name}-diff.ppm`), `P3\n${w} ${h}\n255\n${difference.join(' ')}\n`);
  report.push({fixture:file, width:w, height:h, meanAbsoluteError:sum/(w*h*3),
    rootMeanSquareError:Math.sqrt(sq/(w*h*3)), maxChannelError:worst,
    differingPixels:changed, pixelsAbove32:bad, fractionAbove32:bad/(w*h)});
}
writeFileSync(resolve(here, 'report.json'), JSON.stringify({reference:'@resvg/resvg-js 2.6.2',background:'white',supersampling:aa,referenceScale:SCALE,results:report},null,2)+'\n');
console.table(report);
