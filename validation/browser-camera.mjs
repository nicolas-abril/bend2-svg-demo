import {chromium} from 'playwright';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {createHash} from 'node:crypto';
const here=dirname(import.meta.filename),root=process.env.SVG_APP_ROOT||resolve(here,'..');
const sourceSHA256=Object.fromEntries(['svg.bend','state.bend','web.bend','web.html','fonts.dat'].map(f=>[f,createHash('sha256').update(readFileSync(resolve(root,f))).digest('hex')]));
const prefix=process.env.SVG_VALIDATION_PREFIX||'camera';
const reportPath=resolve(here,`browser-${prefix}${process.env.SVG_SERVER_BACKEND==='javascript'?'-js':''}-report.json`);
const cases=JSON.parse(readFileSync(resolve(here,'camera-cases.json'),'utf8'));
const browser=await chromium.launch({headless:true}),start=performance.now();let stage='start';
try {
 const page=await browser.newPage({viewport:{width:1180,height:850}}),errors=[];page.setDefaultTimeout(180000);page.on('pageerror',e=>errors.push(e.message));
 await page.goto('http://127.0.0.1:8088');await page.waitForFunction(()=>document.querySelector('#status').textContent==='Ready');
 const pixels=()=>page.locator('canvas').evaluate(c=>Array.from(c.getContext('2d').getImageData(0,0,256,256).data));
 const source=()=>page.locator('#source').inputValue();
 const same=(a,b,label)=>{if(a.join()!==b.join())throw Error(label+' matrix differs');};
 async function action(f){const response=page.waitForResponse(r=>r.url().endsWith('/source'));await f();await(await response).finished();await page.waitForFunction(()=>document.querySelector('#status').textContent==='Ready');}
 const button=id=>action(()=>page.locator('#'+id).click());
 async function point(x,y){const b=await page.locator('canvas').boundingBox();return[b.x+(x+.1)*b.width/256,b.y+(y+.1)*b.height/256];}
 async function select(x,y){await action(async()=>page.mouse.click(...await point(x,y)));}
 async function property(key,value){await page.locator('#property').selectOption(key);await page.locator('#value').fill(value);await button('set');if(!(await source()).includes(`${key}:${value}`))throw Error('Property missing');}
 async function undo(s,p){await button('undo');if(await source()!==s)throw Error('Undo source differs');same(await pixels(),p,'Undo');}
 async function load(name){stage='load '+name;const item=cases.find(c=>c.name===name);await action(()=>page.locator('#file').setInputFiles({name:name+'.svg',mimeType:'image/svg+xml',buffer:Buffer.from(item.svg)}));const actual=await pixels(),expected=readFileSync(resolve(here,name+'-expected.ppm'),'utf8').trim().split(/\s+/).slice(4).map(Number);if(expected.length!==196608)throw Error('Expected matrix size');for(let i=0;i<65536;i++)for(let c=0;c<3;c++)if(actual[i*4+c]!==expected[i*3+c])throw Error('Fitted headless pixel differs: '+[name,i%256,Math.floor(i/256),c]);if(await page.locator('svg').count())throw Error('SVG DOM found');return{original:actual,before:await source()};}
 let {original,before}=await load('camera-wide');
 stage='fit and zoom';await button('zoomIn');const zoomed=await pixels();if(zoomed.join()===original.join())throw Error('Zoom did not change view');await button('zoomOut');same(await pixels(),original,'Inverse zoom');await button('actual');if((await pixels()).join()===original.join())throw Error('Actual size did not change view');await button('fit');same(await pixels(),original,'Fit');if(await source()!==before)throw Error('Navigation changed source');await undo(before,original);
 stage='pan and transformed editing';await button('panLeft');const panned=await pixels();if(panned.join()===original.join())throw Error('Pan did not change view');await select(80,110);await property('fill','blue');const paintedSource=await source(),painted=await pixels();if(painted.join()===panned.join())throw Error('Picking after pan failed');await undo(before,panned);
 await action(async()=>{await page.mouse.move(...await point(80,110));await page.mouse.down();await page.mouse.move(...await point(84,114));await page.mouse.up();});if((await pixels()).join()===panned.join())throw Error('Drag after pan failed');await undo(before,panned);
 await select(80,110);await action(()=>page.locator('canvas').press('ArrowRight'));if((await pixels()).join()===panned.join())throw Error('Nudge after pan failed');await undo(before,panned);
 stage='navigation preserves editing history';await button('fit');await select(48,110);await property('fill','blue');await button('zoomIn');await undo(before,zoomed);await button('fit');same(await pixels(),original,'Fit after undo');
 stage='source edits after navigation';await button('panLeft');await page.locator('#source').fill(before.replace('width="128"','width="160"'));await button('apply');if((await pixels()).join()===panned.join())throw Error('Source edit failed');await undo(before,panned);await button('apply');if(await source()!==before)throw Error('Unchanged source apply changed source');
 stage='all pan directions';await button('panUp');await button('panDown');same(await pixels(),panned,'Vertical inverse pan');await button('panRight');same(await pixels(),original,'Horizontal inverse pan');
 stage='keyboard navigation';await page.locator('canvas').focus();await action(()=>page.locator('canvas').press('+'));same(await pixels(),zoomed,'Keyboard zoom');await action(()=>page.locator('canvas').press('f'));same(await pixels(),original,'Keyboard fit');
 ({original,before}=await load('camera-tall'));await undo(before,original);({original,before}=await load('camera-resources'));await undo(before,original);
 stage='save';const downloading=page.waitForEvent('download');await page.getByRole('button',{name:'Save SVG'}).click();const download=await downloading;if(readFileSync(await download.path(),'utf8')!==before)throw Error('Saved source differs');if(errors.length)throw Error(errors.join('\n'));await page.screenshot({path:resolve(here,`web-${prefix}-editor.png`),fullPage:true});
 writeFileSync(reportPath,JSON.stringify({passed:true,serverBackend:process.env.SVG_SERVER_BACKEND||'native',binarySHA256:process.env.SVG_SERVER_BINARY_SHA256||null,sourceSHA256,durationSeconds:(performance.now()-start)/1000,checks:['three complete 65536-pixel fitted headless AA4 matrices','no SVG presentation DOM','fit, actual size, center zoom and inverse zoom','four pan directions and exact inverse pan','pick, recolor, drag, nudge and undo after pan','navigation preserves document source and edit history','source editing and unchanged apply after pan','keyboard zoom and fit','opening a file resets history','save excludes view changes']},null,2)+'\n');console.log('Camera browser flow passed');
} catch(error){writeFileSync(reportPath,JSON.stringify({passed:false,stage,sourceSHA256,error:String(error)},null,2)+'\n');throw error;} finally {await browser.close();}
