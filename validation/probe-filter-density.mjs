import {readFileSync,writeFileSync,copyFileSync,mkdtempSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {PNG} from 'pngjs';
import {dirname,resolve} from 'node:path';
const here=dirname(import.meta.filename),root=resolve(here,'..'),candidate=mkdtempSync(resolve(tmpdir(),'bend-svg-filter-density-'));
for(const file of ['svg.bend','state.bend','render.bend','fonts/NotoSans-Regular.ttf','fonts/NotoSans-Bold.ttf','fonts/NotoSans-Italic.ttf','fonts/NotoSans-BoldItalic.ttf'])copyFileSync(resolve(root,file),resolve(candidate,file));
const source=readFileSync(resolve(root,'svg.bend'),'utf8'),needle='raster.format(area, (1.0 / max(filter.density(space), 0.000001) : F32))';
if(source.split(needle).length!==2)throw Error('Expected one unchanged filter-buffer density expression');
const variant=source.replace(needle,'raster.format(area, (0.5 / max(filter.density(space), 0.000001) : F32))');writeFileSync(resolve(candidate,'svg.bend'),variant);
const hash=s=>createHash('sha256').update(s).digest('hex');
const provenance={integrated:false,change:'Diagnostic filter buffers at twice the device density; all other algorithms unchanged',baseSHA256:hash(source),candidateSHA256:hash(variant)};
console.log('Temporary diagnostic source:',candidate);
const fixtures=['filters-basic','filters-blend','filters-blur','filters-composite','filters-nested','filters-regions','filters-transforms'];
const results=[];
for(const name of fixtures){const start=performance.now();const got=spawnSync('bun',[process.env.BEND_MAIN||resolve(root,'../bend2-core/bend2/main.ts'),candidate+'/render.bend'],{env:{...process.env,SVG_INPUT:root+'/fixtures/'+name+'.svg',SVG_WIDTH:'64',SVG_HEIGHT:'64',SVG_AA:'8',SVG_FONTS:root+'/fonts.dat'},encoding:'utf8',maxBuffer:32*1024*1024});if(got.status!==0)throw Error(got.stderr||got.stdout);writeFileSync(here+'/'+name+'-density2.ppm',got.stdout);const actual=got.stdout.trim().split(/\s+/).slice(4).map(Number);const references={};for(const ref of ['chromium','reference']){const image=PNG.sync.read(readFileSync(here+'/'+name+'-'+ref+'.png'));let sum=0,sq=0,max=0,bad=0;for(let i=0;i<4096;i++){let peak=0;for(let c=0;c<3;c++){const d=Math.abs(actual[i*3+c]-image.data[i*4+c]);sum+=d;sq+=d*d;peak=Math.max(peak,d);max=Math.max(max,d);}bad+=peak>32;}references[ref]={meanAbsoluteError:sum/12288,rootMeanSquareError:Math.sqrt(sq/12288),maxChannelError:max,pixelsAbove32:bad,passed:sum/12288<=1&&Math.sqrt(sq/12288)<=5&&bad/4096<=.01};}results.push({fixture:name+'.svg',durationSeconds:(performance.now()-start)/1000,references});console.log(name,JSON.stringify(references));writeFileSync(here+'/filter-density-probe.json',JSON.stringify({...provenance,results},null,2)+'\n');}
