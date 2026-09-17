import assert from 'node:assert/strict';
import {chromium} from 'playwright';
const browser=await chromium.launch({headless:true});
try {
 const page=await browser.newPage({viewport:{width:1180,height:850}});
 const errors=[];page.on('pageerror',e=>errors.push(e.message));page.setDefaultTimeout(60000);
 await page.goto('http://127.0.0.1:8088/');await page.waitForFunction(()=>document.querySelector('#status').textContent==='Ready');
 const svg=`<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256"><style>.shape {stroke-width:3;fill:green}</style><g fill="orange" stroke="red"><rect id="box" class="shape" x="8" y="8" width="64" height="64" style="fill:blue"/><rect x="100" y="8" width="64" height="64"/></g></svg>`;
 async function action(fn){const response=page.waitForResponse(r=>r.url().endsWith('/inspector'));await fn();await(await response).finished();await page.waitForFunction(()=>document.querySelector('#status').textContent==='Ready');}
 const load=text=>action(()=>page.locator('#file').setInputFiles({name:'inspector.svg',mimeType:'image/svg+xml',buffer:Buffer.from(text)}));
 async function click(x,y){const b=await page.locator('canvas').boundingBox();await action(()=>page.mouse.click(b.x+x*b.width/256,b.y+y*b.height/256));}
 const property=key=>page.locator('#property').selectOption(key);
 const value=()=>page.locator('#value').inputValue();
 const hint=()=>page.locator('#valueHint').textContent();
 await load(svg);assert(await page.locator('#set').isDisabled());
 await click(20,20);assert.equal(await page.locator('#selectedId').textContent(),'— #box');
 assert.equal(await value(),'blue');assert.equal(await page.locator('#fill').inputValue(),'#0000ff');
 await property('stroke');assert.equal(await value(),'red');assert.match(await hint(),/Inherited/);
 await property('stroke-width');assert.equal(await value(),'3');assert.equal(await hint(),'Current value');
 await property('stroke-linecap');assert(await page.locator('#value').isHidden());assert.equal(await page.locator('#valueOptions').inputValue(),'butt');assert.match(await hint(),/Default/);
 assert.deepEqual(await page.locator('#valueOptions option').allTextContents(),['butt','round','square']);
 await page.locator('#valueOptions').selectOption('round');await action(()=>page.locator('#set').click());assert.equal(await page.locator('#valueOptions').inputValue(),'round');assert.equal(await hint(),'Current value');
 await action(()=>page.locator('#undo').click());assert.equal(await page.locator('#valueOptions').inputValue(),'butt');
 await property('textLength');assert.equal(await value(),'');assert.equal(await page.locator('#value').getAttribute('placeholder'),'100');assert.match(await hint(),/Example/);
 await property('fill');await page.locator('#value').fill('purple');await action(()=>page.locator('#set').click());assert.equal(await value(),'purple');
 await click(120,20);assert.equal(await page.locator('#selectedId').textContent(),'— rect (no id)');assert.equal(await value(),'orange');assert.match(await hint(),/Inherited/);
 await action(()=>page.locator('#delete').click());assert(await page.locator('#set').isDisabled());assert.equal(await page.locator('#selectedId').textContent(),'— None');
 await action(()=>page.locator('#undo').click());assert.equal(await value(),'orange');assert(!(await page.locator('#set').isDisabled()));
 await load(svg.replace('id="box"','id="box &quot;α"'));await click(20,20);assert.equal(await page.locator('#selectedId').textContent(),'— #box "α');
 for(const key of ['paint-order','stroke-linejoin','vector-effect','mask-mode','fill-rule','preserveAspectRatio','image-rendering','lengthAdjust','font-style','text-anchor']){
  await property(key);assert(await page.locator('#valueOptions').isVisible(),key);assert((await page.locator('#valueOptions option').count())>1,key);
 }
 await click(240,240);assert(await page.locator('#valueOptions').isDisabled());
 assert.deepEqual(errors,[]);console.log('PASS web inspector: IDs, inherited/stylesheet values, defaults, examples, enum editing, selection changes, delete and undo');
} finally {await browser.close();}
