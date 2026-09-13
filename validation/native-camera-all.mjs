// The saved C renderer must preserve the existing JavaScript fixture matrices.
import{readFileSync,writeFileSync,readdirSync}from'node:fs';import{spawnSync}from'node:child_process';import{createHash}from'node:crypto';import{resolve,dirname}from'node:path';
const here=dirname(import.meta.filename),root=process.env.SVG_APP_ROOT||resolve(here,'..'),results=[];
const hash=f=>createHash('sha256').update(readFileSync(resolve(root,f))).digest('hex'),sourceFiles=['svg.bend','state.bend','render.bend','fonts.dat'],sourceSHA256=Object.fromEntries(sourceFiles.map(f=>[f,hash(f)])),binarySHA256=hash('build/render');
for(const fixture of readdirSync(resolve(root,'fixtures')).filter(f=>f.endsWith('.svg')).sort()){
 const expected=readFileSync(resolve(here,fixture.replace('.svg','.ppm')),'utf8'),start=performance.now();
 const got=spawnSync(resolve(root,'build/render'),['--gpu','off'],{env:{...process.env,SVG_FONTS:resolve(root,'fonts.dat'),SVG_INPUT:resolve(root,'fixtures',fixture),SVG_WIDTH:'64',SVG_HEIGHT:'64',SVG_AA:'8'},encoding:'utf8',maxBuffer:32*1024*1024});if(got.status!==0)throw Error(got.stderr||got.stdout);
 const passed=got.stdout===expected;let maxChannelError=0;if(!passed){const a=expected.trim().split(/\s+/).slice(4).map(Number),b=got.stdout.trim().split(/\s+/).slice(4).map(Number);if(a.length!==b.length)throw Error('Matrix dimensions differ');for(let i=0;i<a.length;i++)maxChannelError=Math.max(maxChannelError,Math.abs(a[i]-b[i]));writeFileSync(resolve(here,fixture.replace('.svg','-native.ppm')),got.stdout);}
 results.push({fixture,passed,maxChannelError,durationSeconds:(performance.now()-start)/1000,sha256:createHash('sha256').update(got.stdout).digest('hex')});console.log(`${passed?'PASS':'FAIL'} ${fixture}`);
}
if(sourceFiles.some(f=>hash(f)!==sourceSHA256[f])||hash('build/render')!==binarySHA256)throw Error('Source or renderer changed during validation');
const passed=results.every(r=>r.passed);
writeFileSync(resolve(here,'camera-native-all-report.json'),JSON.stringify({passed,check:'Saved C backend versus the JavaScript-produced 64x64 AA8 matrices for every fixture',sourceSHA256,binarySHA256,results},null,2)+'\n');if(!passed)throw Error('Backend matrix differences: '+results.filter(r=>!r.passed).map(r=>r.fixture).join(', '));console.log(`All ${results.length} C/JavaScript matrices match exactly`);
