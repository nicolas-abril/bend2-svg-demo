// Compare the optimized Bend JavaScript renderer with saved pre-optimization matrices.
import{readFileSync,writeFileSync,readdirSync}from'node:fs';import{spawnSync}from'node:child_process';import{createHash}from'node:crypto';import{resolve,dirname}from'node:path';
const here=dirname(import.meta.filename),root=resolve(here,'..'),results=[],bend=process.env.BEND_MAIN||resolve(root,'../../bend2-core/bend2/main.ts');
for(const fixture of readdirSync(resolve(root,'fixtures')).filter(f=>f.endsWith('.svg')).sort()){
 const expected=readFileSync(resolve(here,fixture.replace('.svg','.ppm')),'utf8'),start=performance.now();
 const got=spawnSync('bun',[bend,resolve(root,'render.bend')],{env:{...process.env,SVG_FONTS:resolve(root,'fonts.dat'),SVG_INPUT:resolve(root,'fixtures',fixture),SVG_WIDTH:'64',SVG_HEIGHT:'64',SVG_AA:'8'},encoding:'utf8',maxBuffer:32*1024*1024});if(got.status!==0)throw Error(got.stderr||got.stdout);
 const passed=got.stdout===expected;results.push({fixture,passed,durationSeconds:(performance.now()-start)/1000,sha256:createHash('sha256').update(got.stdout).digest('hex')});console.log(`${passed?'PASS':'FAIL'} ${fixture}`);if(!passed)writeFileSync(resolve(here,fixture.replace('.svg','-coverage.ppm')),got.stdout);
}
const sourceSHA256=Object.fromEntries(['svg.bend','state.bend','render.bend','fonts.dat'].map(f=>[f,createHash('sha256').update(readFileSync(resolve(root,f))).digest('hex')])),passed=results.every(r=>r.passed);
writeFileSync(resolve(here,'coverage-parity-report.json'),JSON.stringify({passed,check:'Optimized JavaScript matrices versus all saved pre-optimization 64x64 AA8 fixture matrices',sourceSHA256,results},null,2)+'\n');if(!passed)throw Error('Coverage culling changed pixels');
