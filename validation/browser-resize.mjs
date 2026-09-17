import assert from 'node:assert/strict';
import {chromium} from 'playwright';
import {PNG} from 'pngjs';
import {mkdtempSync,writeFileSync,rmSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {resolve,dirname} from 'node:path';
const root=process.env.SVG_APP_ROOT||resolve(dirname(import.meta.filename),'..');
const bend=process.env.BEND_MAIN||resolve(root,'../bend2-core/bend2/main.ts');
const temp=mkdtempSync(resolve(tmpdir(),'svg-resize-pixels-'));
const svg='<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256"><rect id="box" x="32" y="32" width="64" height="64" fill="red"/><rect x="128" width="1" height="256"/><path d="M160 30L230 140L170 220Z" fill="blue"/></svg>';
const input=resolve(temp,'drawing.svg');writeFileSync(input,svg);
const browser=await chromium.launch({headless:true});
try {
 for(const scale of [1,2]) {
  const page=await browser.newPage({viewport:{width:1280,height:1000},deviceScaleFactor:scale});
  page.setDefaultTimeout(120000);const errors=[];page.on('pageerror',e=>errors.push(String(e)));
  await page.goto('http://127.0.0.1:8088');
  const rendered=(w,h,dpr=scale)=>page.waitForFunction(({w,h,dpr})=>document.querySelector('canvas').dataset.rendered===`${w*dpr}x${h*dpr}@${dpr}`&&document.querySelector('#status').textContent==='Ready',{w,h,dpr});
  await rendered(512,512);
  assert.equal(await page.locator('#viewport').evaluate(v=>getComputedStyle(v).resize),'both');
  async function action(fn){const r=page.waitForResponse(r=>r.url().endsWith('/source'));await fn();await(await r).finished();await page.waitForFunction(()=>document.querySelector('#status').textContent==='Ready');}
  const load=()=>action(()=>page.locator('#file').setInputFiles({name:'drawing.svg',mimeType:'image/svg+xml',buffer:Buffer.from(svg)}));
  await load();const original=await page.locator('#source').inputValue();
  // Exercise the actual CSS corner handle.
  const corner=await page.locator('#viewport').boundingBox();
  await page.mouse.move(corner.x+corner.width-3,corner.y+corner.height-3);await page.mouse.down();
  await page.mouse.move(corner.x+corner.width-67,corner.y+corner.height-35,{steps:4});await page.mouse.up();
  await page.waitForFunction(()=>document.querySelector('#viewport').clientWidth<512);
  // Rapid size changes must settle on the newest request, preserving source.
  await page.locator('#viewport').evaluate(v=>{v.style.width='400px';v.style.height='300px';});
  await page.locator('#viewport').evaluate(v=>{v.style.width='384px';v.style.height='256px';});
  await rendered(384,256);assert.equal(await page.locator('#source').inputValue(),original);
  await action(()=>page.locator('#fit').click());
  const size=await page.locator('canvas').evaluate(c=>({w:c.width,h:c.height,cssW:c.getBoundingClientRect().width,cssH:c.getBoundingClientRect().height}));
  assert.deepEqual(size,{w:384*scale,h:256*scale,cssW:384,cssH:256});
  const expected=spawnSync('bun',[bend,resolve(root,'render.bend')],{cwd:root,env:{...process.env,SVG_INPUT:input,SVG_FONTS:resolve(root,'fonts'),SVG_WIDTH:String(size.w),SVG_HEIGHT:String(size.h),SVG_AA:'4'},encoding:'utf8',maxBuffer:20*1024*1024});
  assert.equal(expected.status,0,expected.stderr);
  const rgb=expected.stdout.trim().split(/\s+/).slice(4).map(Number);
  const actual=await page.locator('canvas').evaluate(c=>Array.from(c.getContext('2d').getImageData(0,0,c.width,c.height).data));
  assert.equal(rgb.length,size.w*size.h*3);
  for(let i=0;i<size.w*size.h;i++)for(let c=0;c<3;c++)assert.equal(actual[i*4+c],rgb[i*3+c],`DPR ${scale}: pixel ${i}, channel ${c}`);
  const bounds=await page.locator('canvas').boundingBox();
  const screenshot=PNG.sync.read(await page.screenshot());
  const originX=Math.round(bounds.x*scale),originY=Math.round(bounds.y*scale);
  for(let y=0;y<size.h;y++)for(let x=0;x<size.w;x++){
    if(x>=size.w-16*scale&&y>=size.h-16*scale)continue; // Native CSS resize grip overlays the corner.
    for(let c=0;c<4;c++){const i=(y*size.w+x)*4+c;assert.equal(screenshot.data[((y+originY)*screenshot.width+x+originX)*4+c],actual[i],`Displayed pixel ${x},${y},${c} must match the raster`);}
  }
  // Selected shape inverse transforms must follow the resize, too.
  const b=await page.locator('canvas').boundingBox();
  await action(()=>page.mouse.click(b.x+110,b.y+50));
  assert.match(await page.locator('#selectedId').textContent(),/#box/);
  await page.locator('#viewport').evaluate(v=>{v.style.width='512px';v.style.height='512px';});
  await rendered(512,512);
  assert.match(await page.locator('#selectedId').textContent(),/#box/);
  await action(()=>page.locator('canvas').press('ArrowRight'));
  assert.match(await page.locator('#source').inputValue(),/transform:matrix/);
  await action(()=>page.locator('#undo').click());assert.equal(await page.locator('#source').inputValue(),original);
  const c=await page.locator('canvas').boundingBox();
  await action(async()=>{await page.mouse.move(c.x+100,c.y+100);await page.mouse.down();await page.mouse.move(c.x+116,c.y+108);await page.mouse.up();});
  const moved=await page.locator('#source').inputValue();
  const viewer=await browser.newPage();await viewer.goto('data:image/svg+xml;base64,'+Buffer.from(moved).toString('base64'));
  assert.deepEqual(await viewer.locator('#box').evaluate(e=>{const m=e.getCTM();return[m.e,m.f];}),[8,4]);await viewer.close();
  await action(()=>page.locator('#undo').click());assert.equal(await page.locator('#source').inputValue(),original);
  // A DPR change without changing the CSS dimensions still requests a frame.
  const session=await page.context().newCDPSession(page),other=scale===1?2:1;
  await session.send('Emulation.setDeviceMetricsOverride',{width:1280,height:1000,deviceScaleFactor:other,mobile:false});
  await rendered(512,512,other);
  assert.deepEqual(errors,[]);await page.close();
  console.log(`PASS resize DPR ${scale}: corner handle, rectangular pixels match headless, selection, drag/save/undo, display-scale change`);
 }
} finally {await browser.close();rmSync(temp,{recursive:true,force:true});}
