// Forward editor input and inspect the matrices produced entirely by Bend.
import {chromium} from 'playwright';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {createHash} from 'node:crypto';
const here=dirname(import.meta.filename),root=process.env.SVG_APP_ROOT||resolve(here,'..');
const sourceSHA256=Object.fromEntries(['svg.bend','state.bend','web.bend','web.html','fonts/NotoSans-Regular.ttf','fonts/NotoSans-Bold.ttf','fonts/NotoSans-Italic.ttf','fonts/NotoSans-BoldItalic.ttf'].map(f=>[f,createHash('sha256').update(readFileSync(resolve(root,f))).digest('hex')]));
const reportPath=resolve(here,process.env.SVG_SERVER_BACKEND==='javascript'?'browser-morphology-js-report.json':'browser-morphology-report.json');
const browser=await chromium.launch({headless:true}),start=performance.now();let stage='start';
try {
 const page=await browser.newPage({viewport:{width:1180,height:850}}),errors=[];page.setDefaultTimeout(180000);page.on('pageerror',e=>errors.push(e.message));
 await page.goto('http://127.0.0.1:8088');await page.waitForFunction(()=>document.querySelector('#status').textContent==='Ready');
 const pixels=()=>page.locator('canvas').evaluate(c=>Array.from(c.getContext('2d').getImageData(0,0,256,256).data));
 const source=()=>page.locator('#source').inputValue();
 async function action(f){const response=page.waitForResponse(r=>r.url().endsWith('/source'));await f();await(await response).finished();await page.waitForFunction(()=>document.querySelector('#status').textContent==='Ready');}
 async function point(x,y){const b=await page.locator('canvas').boundingBox();return[b.x+(x+.1)*b.width/256,b.y+(y+.1)*b.height/256];}
 async function select(x,y){await action(async()=>page.mouse.click(...await point(x,y)));}
 async function property(key,value){await page.locator('#property').selectOption(key);await page.locator('#value').fill(value);await action(()=>page.locator('#set').click());if(!(await source()).includes(`${key}:${value}`))throw Error('Property missing from serialized source');}
 async function undo(expectedSource,expectedPixels){await action(()=>page.locator('#undo').click());if(await source()!==expectedSource||(await pixels()).join()!==expectedPixels.join())throw Error('Undo source/matrix differs');}
 function unchangedOutside(before,after,right,bottom){for(let y=0;y<256;y++)for(let x=0;x<256;x++)if(x>=right||y>=bottom)for(let c=0;c<4;c++)if(before[(y*256+x)*4+c]!==after[(y*256+x)*4+c])throw Error('Edit changed another element');}
 async function load(name){stage='load '+name;await action(()=>page.locator('#file').setInputFiles(resolve(root,'fixtures',name+'.svg')));const actual=await pixels(),expected=readFileSync(resolve(here,name+'-web-expected.ppm'),'utf8').trim().split(/\s+/).slice(4).map(Number);if(expected.length!==196608)throw Error('Expected matrix size');for(let i=0;i<65536;i++)for(let c=0;c<3;c++)if(actual[i*4+c]!==expected[i*3+c])throw Error('Headless pixel differs: '+[name,i%256,Math.floor(i/256),c]);if(await page.locator('svg').count())throw Error('SVG presentation element found');return{original:actual,before:await source()};}
 let {original,before}=await load('morphology-basic');stage='filter replacement';
 await select(12,12);await property('filter','url(#dilate)');let changed=await pixels();
 const rgb=(p,x,y)=>p.slice((y*256+x)*4,(y*256+x)*4+3).join();
 if(rgb(original,4,12)!=='255,255,255'||rgb(changed,4,12)!=='204,68,51')throw Error('Replacing erosion with dilation did not expand the shape');
 unchangedOutside(original,changed,32,32);await undo(before,original);
 stage='filter drag';await action(async()=>{await page.mouse.move(...await point(12,12));await page.mouse.down();await page.mouse.move(...await point(15,14));await page.mouse.up();});
 if(await source()===before||(await pixels()).join()===original.join())throw Error('Dragging did not move filtered geometry');await undo(before,original);console.log('Morphology property editing, drag and exact undo passed');
 await load('morphology-radius');await load('morphology-units');({original,before}=await load('morphology-graph'));
 stage='filter graph source';await page.locator('#source').fill(before.replace('radius="2"','radius="4"'));await action(()=>page.locator('#apply').click());
 changed=await pixels();if(changed.join()===original.join())throw Error('Filter graph source edit did not change the matrix');unchangedOutside(original,changed,32,32);
 await page.locator('#source').fill(before);await action(()=>page.locator('#apply').click());const normalized=JSON.parse(readFileSync(resolve(here,'morphology-roundtrip-report.json'),'utf8')).secondSerialization;if(await source()!==normalized||(await pixels()).join()!==original.join())throw Error('Reloading graph source differs from Bend serialization or its original matrix');before=await source();console.log('Four exact matrices and filter graph source editing/reload passed');
 stage='save';const downloading=page.waitForEvent('download');await page.getByRole('button',{name:'Save SVG'}).click();const download=await downloading;if(readFileSync(await download.path(),'utf8')!==before)throw Error('Saved source differs');if(errors.length)throw Error(errors.join('\n'));await page.screenshot({path:resolve(here,'web-morphology-editor.png'),fullPage:true});
 writeFileSync(reportPath,JSON.stringify({passed:true,serverBackend:process.env.SVG_SERVER_BACKEND||'native',binarySHA256:process.env.SVG_SERVER_BINARY_SHA256||null,sourceSHA256,durationSeconds:(performance.now()-start)/1000,checks:['four complete 65536-pixel headless AA4 matrices','no SVG presentation DOM','replace erosion with dilation','drag filtered geometry','edit and reload filter graph through Bend source parsing','unrelated elements unchanged','exact source/matrix undo','save preserves SVG source']},null,2)+'\n');console.log('Morphology browser flow passed');
} catch(error){writeFileSync(reportPath,JSON.stringify({passed:false,stage,sourceSHA256,error:String(error)},null,2)+'\n');throw error;} finally {await browser.close();}
