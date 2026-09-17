// Generate current headless expectations, then run the existing complete
// browser editing flow through PNG frames without changing saved references.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,readFileSync,writeFileSync,copyFileSync,symlinkSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {resolve,dirname} from 'node:path';
const here=dirname(import.meta.filename),root=process.env.SVG_APP_ROOT||resolve(here,'..');
const bend=process.env.BEND_MAIN||resolve(root,'../bend2-core/bend2/main.ts');
const temp=mkdtempSync(resolve(tmpdir(),'svg-png-browser-'));
try {
 const cases=JSON.parse(readFileSync(resolve(root,'validation/camera-cases.json'),'utf8'));
 copyFileSync(resolve(root,'validation/camera-cases.json'),resolve(temp,'camera-cases.json'));
 for(const item of cases){
  const input=resolve(temp,item.name+'.svg');writeFileSync(input,item.svg);
  const got=spawnSync('bun',[bend,resolve(root,'render.bend')],{cwd:root,env:{...process.env,SVG_INPUT:input,SVG_FONTS:resolve(root,'fonts'),SVG_WIDTH:'256',SVG_HEIGHT:'256',SVG_AA:'4'},encoding:'utf8',maxBuffer:4*1024*1024});
  assert.equal(got.status,0,got.stderr);assert.match(got.stdout,/^P3\n256 256\n255\n/);
  writeFileSync(resolve(temp,item.name+'-expected.ppm'),got.stdout);
 }
 for(const file of ['browser-camera.mjs','run-browser-camera.mjs'])copyFileSync(resolve(root,'validation',file),resolve(temp,file));
 symlinkSync(resolve(root,'validation/node_modules'),resolve(temp,'node_modules'));
 const child=spawn('bun',[resolve(temp,'run-browser-camera.mjs')],{stdio:'inherit',env:{...process.env,BEND_MAIN:bend,SVG_APP_ROOT:root,SVG_VALIDATION_PREFIX:'png',SVG_SERVER_BACKEND:process.env.SVG_SERVER_BACKEND||'javascript'}});
 const code=await new Promise((done,fail)=>{child.on('error',fail);child.on('exit',done);});assert.equal(code,0);
 console.log('PASS PNG browser editing and three complete current headless matrices');
} finally {rmSync(temp,{recursive:true,force:true});}
