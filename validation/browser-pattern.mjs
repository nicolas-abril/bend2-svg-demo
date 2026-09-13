// The browser presents matrices; pattern parsing, picking and editing run in Bend.
import{chromium}from'playwright';import{writeFileSync}from'node:fs';import{resolve,dirname}from'node:path';
const here=dirname(import.meta.filename),browser=await chromium.launch({headless:true});
try{
 const page=await browser.newPage({viewport:{width:1180,height:850}});page.setDefaultTimeout(180000);
 const errors=[];page.on('pageerror',e=>errors.push(e.message));const started=performance.now();
 await page.goto('http://127.0.0.1:8088');await page.waitForFunction(()=>document.querySelector('#status').textContent==='Ready');
 await page.locator('#file').setInputFiles(resolve(here,'../fixtures/pattern-units.svg'));
 await page.waitForFunction(()=>document.querySelector('#source').value.includes('id="content"'));console.log('Pattern document loaded');
 const before=await page.locator('#source').inputValue(),box=await page.locator('canvas').boundingBox();
 const click=async(x,y)=>page.mouse.click(box.x+x*box.width/256,box.y+y*box.height/256);
 await click(16,12);await page.locator('#property').selectOption('fill');await page.locator('#value').fill('url(#both)');await page.locator('#set').click();
 await page.waitForFunction(()=>document.querySelector('#source').value.includes('fill:url(#both)'));console.log('Pattern fill changed');
 const patterned=await page.locator('#source').inputValue();if(!patterned.includes('id="user"')||!patterned.includes('id="both"'))throw Error('Pattern definitions were lost');
 await page.locator('#undo').click();await page.waitForFunction(expected=>document.querySelector('#source').value===expected,before);console.log('Undo restored source');
 await click(16,12);await page.locator('#value').fill('#ff0000');await page.locator('#set').click();
 await page.waitForFunction(()=>document.querySelector('#source').value.includes('fill:#ff0000'));
 const after=await page.locator('#source').inputValue();
 if(errors.length)throw Error(errors.join('\n'));
 await page.screenshot({path:resolve(here,'web-pattern-editor.png'),fullPage:true});
 writeFileSync(resolve(here,'browser-pattern-report.json'),JSON.stringify({passed:true,serverBackend:'native',durationSeconds:(performance.now()-started)/1000,checks:['open SVG pattern document','pick painted tile area','apply another pattern fill','preserve pattern definitions','undo pattern change','replace patterned fill with solid color','no browser errors'],before,patterned,after},null,2)+'\n');console.log('Pattern SVG browser interactions passed');
}finally{await browser.close();}
