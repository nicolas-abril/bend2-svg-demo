import{readFileSync,writeFileSync}from'node:fs';import{spawnSync}from'node:child_process';import{PNG}from'pngjs';import{resolve,dirname}from'node:path';
const here=dirname(import.meta.filename),root=resolve(here,'..'),policy=JSON.parse(readFileSync(resolve(here,'coverage.json'),'utf8')),results=[];
for(const fixture of ['text-style.svg','text-unicode.svg','stroke-vector.svg','basic.svg','clipping.svg','pattern-transform.svg','markers-compositing.svg']){
 const out=spawnSync('bun',['/Users/macolas/Software/bend2-core/bend2/main.ts',resolve(root,'sample-investigation/render.bend')],{cwd:root,env:{...process.env,SVG_INPUT:resolve(root,'fixtures',fixture),SVG_FONTS:resolve(root,'fonts'),SVG_WIDTH:'64',SVG_HEIGHT:'64',SVG_AA:'8'},encoding:'utf8',maxBuffer:32*1024*1024});if(out.status!==0)throw Error(out.stdout||out.stderr);
 const a=out.stdout.trim().split(/\s+/).slice(4).map(Number),name=fixture.slice(0,-4),reference=policy.fixtures[fixture].reference,b=PNG.sync.read(readFileSync(resolve(here,`${name}-${reference==='resvg'?'reference':'chromium'}.png`))).data;let sum=0,sq=0,max=0,bad=0;
 for(let i=0;i<4096;i++){let peak=0;for(let c=0;c<3;c++){const d=Math.abs(a[i*3+c]-b[i*4+c]);sum+=d;sq+=d*d;max=Math.max(max,d);peak=Math.max(peak,d);}bad+=peak>32;}
 const r={fixture,reference,mae:sum/12288,rmse:Math.sqrt(sq/12288),max,pixelsAbove32:bad};results.push(r);writeFileSync(resolve(here,`${name}-coverage-experiment.ppm`),out.stdout);console.log(r);
}
writeFileSync(resolve(here,'coverage-samples-experiment.json'),JSON.stringify({experimental:true,samplesPerPixel:64,description:'one point per 8x8 cell with 64 distinct x/y strata and central symmetry',results},null,2)+'\n');
