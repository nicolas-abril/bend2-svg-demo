// Forward editor input and inspect the matrices produced entirely by Bend.
import {chromium} from 'playwright';
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {createHash} from 'node:crypto';
const here=dirname(import.meta.filename),root=process.env.SVG_APP_ROOT||resolve(here,'..');
const sourceSHA256=Object.fromEntries(['svg.bend','state.bend','web.bend','web.html','fonts.dat'].map(f=>[f,createHash('sha256').update(readFileSync(resolve(root,f))).digest('hex')]));
const reportPath=resolve(here,process.env.SVG_SERVER_BACKEND==='javascript'?'browser-source-undo-js-report.json':'browser-source-undo-report.json');
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
 let {original,before}=await load('morphology-basic');
 stage='property then source edit';await select(12,12);await property('fill','blue');const paintedSource=await source(),paintedPixels=await pixels();
 const edited=paintedSource.replace('radius="2"','radius="3"');await page.locator('#source').fill(edited);await action(()=>page.locator('#apply').click());
 if((await pixels()).join()===paintedPixels.join())throw Error('Source edit did not change the matrix');await undo(paintedSource,paintedPixels);await undo(before,original);
 stage='unchanged source apply';await select(12,12);await property('fill','blue');const sameSource=await source();await action(()=>page.locator('#apply').click());if(await source()!==sameSource)throw Error('Unchanged apply normalized source');await undo(before,original);
 stage='successive source edits';await page.locator('#source').fill(before.replace('radius="2"','radius="3"'));await action(()=>page.locator('#apply').click());const firstSource=await source(),firstPixels=await pixels();
 await page.locator('#source').fill(firstSource.replace('radius="3"','radius="4"'));await action(()=>page.locator('#apply').click());if((await pixels()).join()===firstPixels.join())throw Error('Second source edit did not change the matrix');await undo(firstSource,firstPixels);await undo(before,original);
 stage='opening a file resets history';await select(12,12);await property('fill','blue');({original,before}=await load('morphology-graph'));await undo(before,original);
 console.log('Source undo, unchanged apply, successive edits and new-file history passed');
 stage='save';const downloading=page.waitForEvent('download');await page.getByRole('button',{name:'Save SVG'}).click();const download=await downloading;if(readFileSync(await download.path(),'utf8')!==before)throw Error('Saved source differs');if(errors.length)throw Error(errors.join('\n'));await page.screenshot({path:resolve(here,'web-source-undo-editor.png'),fullPage:true});
 writeFileSync(reportPath,JSON.stringify({passed:true,serverBackend:process.env.SVG_SERVER_BACKEND||'native',binarySHA256:process.env.SVG_SERVER_BINARY_SHA256||null,sourceSHA256,durationSeconds:(performance.now()-start)/1000,checks:['two complete 65536-pixel headless AA4 matrices','no SVG presentation DOM','source edit preserves prior property history','exact source and matrix undo','unchanged source apply is a no-op','successive source edits undo independently','opening a file resets history','save preserves serialized source']},null,2)+'\n');console.log('Source undo browser flow passed');
} catch(error){writeFileSync(reportPath,JSON.stringify({passed:false,stage,sourceSHA256,error:String(error)},null,2)+'\n');throw error;} finally {await browser.close();}
