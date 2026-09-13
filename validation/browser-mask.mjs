// Presentation-only app check; Bend handles masking, picking and document edits.
import{chromium}from'playwright';import{writeFileSync}from'node:fs';import{resolve,dirname}from'node:path';
const here=dirname(import.meta.filename),browser=await chromium.launch({headless:true});
try{
 const page=await browser.newPage({viewport:{width:1180,height:850}});page.setDefaultTimeout(120000);
 const errors=[];page.on('pageerror',e=>errors.push(e.message));const started=performance.now();
 await page.goto('http://127.0.0.1:8088');await page.waitForFunction(()=>document.querySelector('#status').textContent==='Ready');
 await page.locator('#file').setInputFiles(resolve(here,'../fixtures/mask-units.svg'));
 await page.waitForFunction(()=>document.querySelector('#source').value.includes('id="half"'));
 const before=await page.locator('#source').inputValue(),box=await page.locator('canvas').boundingBox();
 const click=async(x,y)=>page.mouse.click(box.x+x*box.width/256,box.y+y*box.height/256);
 await click(25,10);await page.locator('#property').selectOption('mask');await page.locator('#value').fill('none');await page.locator('#set').click();
 await page.waitForFunction(()=>document.querySelector('#status').textContent==='Ready');
 if(await page.locator('#source').inputValue()!==before)throw Error('Masked-out click selected and edited a shape');
 await click(8,10);await page.locator('#set').click();
 await page.waitForFunction(()=>document.querySelector('#source').value.includes('mask:none'));
 const after=await page.locator('#source').inputValue();if(!after.includes('id="half"'))throw Error('Mask definition was lost');
 await page.locator('#undo').click();await page.waitForFunction(()=>!document.querySelector('#source').value.includes('mask:none'));
 if(errors.length)throw Error(errors.join('\n'));
 await page.screenshot({path:resolve(here,'web-mask-editor.png'),fullPage:true});
 writeFileSync(resolve(here,'browser-mask-report.json'),JSON.stringify({passed:true,durationSeconds:(performance.now()-started)/1000,checks:['open masked SVG','masked-out picking leaves document unchanged','select visible part','remove mask using property control','preserve mask definitions','undo mask edit','no browser errors'],before,after},null,2)+'\n');console.log('Masked SVG browser interactions passed');
}finally{await browser.close();}
