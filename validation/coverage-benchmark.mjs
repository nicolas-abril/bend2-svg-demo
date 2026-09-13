// Paired runs use identical inputs and compare every output byte before timing.
import{readFileSync,writeFileSync}from'node:fs';import{spawnSync}from'node:child_process';import{createHash}from'node:crypto';import{resolve,dirname}from'node:path';
const here=dirname(import.meta.filename),root=process.env.SVG_APP_ROOT||resolve(here,'..'),baseline=process.env.SVG_BASELINE_RENDER;
if(!baseline)throw Error('Set SVG_BASELINE_RENDER to the pre-optimization C renderer');
const current=resolve(root,'build/render'),results=[];
function run(binary,fixture){const t=performance.now(),r=spawnSync(binary,['--gpu','off'],{env:{...process.env,SVG_FONTS:resolve(root,'fonts.dat'),SVG_INPUT:resolve(root,'fixtures',fixture),SVG_WIDTH:'64',SVG_HEIGHT:'64',SVG_AA:'8'},encoding:'utf8',maxBuffer:32*1024*1024});if(r.status!==0)throw Error(r.stderr||r.stdout);return{seconds:(performance.now()-t)/1000,output:r.stdout};}
const median=xs=>xs.toSorted((a,b)=>a-b)[Math.floor(xs.length/2)];
for(const fixture of ['markers-context.svg','markers-vertices.svg','text-basic.svg','pattern-nested.svg']){const old=[],now=[];for(let i=0;i<3;i++){const a=run(i%2?current:baseline,fixture),b=run(i%2?baseline:current,fixture);if(a.output!==b.output)throw Error('Matrices differ: '+fixture);(i%2?now:old).push(a.seconds);(i%2?old:now).push(b.seconds);}results.push({fixture,identical:true,beforeSeconds:old,afterSeconds:now,beforeMedian:median(old),afterMedian:median(now),speedup:median(old)/median(now)});console.log(fixture,results.at(-1).speedup.toFixed(2)+'x');}
const hash=f=>createHash('sha256').update(readFileSync(f)).digest('hex');
writeFileSync(resolve(here,'coverage-benchmark-report.json'),JSON.stringify({passed:true,width:64,height:64,aa:8,backend:'C --gpu off',method:'Median of three alternating paired process runs; identical matrices required',baselineBinarySHA256:hash(baseline),currentBinarySHA256:hash(current),sourceSHA256:hash(resolve(root,'svg.bend')),results},null,2)+'\n');
