// End-to-end presentation test; SVG parsing and edits are performed by Bend.
import{chromium}from'playwright';
import{writeFileSync}from'node:fs';
import{resolve,dirname}from'node:path';
const here=dirname(import.meta.filename),browser=await chromium.launch({headless:true});
try {
 const page=await browser.newPage({viewport:{width:1180,height:850}});page.setDefaultTimeout(60000);
 const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto('http://127.0.0.1:8088');
 await page.waitForFunction(()=>document.querySelector('#status').textContent==='Ready');
 await page.locator('#file').setInputFiles(resolve(here,'../fixtures/use.svg'));
 await page.waitForFunction(()=>document.querySelector('#source').value.includes('id="tile"'));
 const before=await page.locator('#source').inputValue();
 const box=await page.locator('canvas').boundingBox();
 const p=(x,y)=>({x:box.x+x*box.width/256,y:box.y+y*box.height/256});
 await page.mouse.move(p(5,5).x,p(5,5).y);await page.mouse.down();
 await page.mouse.move(p(15,15).x,p(15,15).y);await page.mouse.up();
 await page.waitForFunction(()=>document.querySelector('#source').value.includes('matrix(1,0 0,1 10,10 )'));
 await page.locator('#fill').evaluate(e=>{e.value='#00ff00';e.dispatchEvent(new Event('change',{bubbles:true}));});
 await page.waitForFunction(()=>document.querySelector('#source').value.includes('fill:#00ff00'));
 const after=await page.locator('#source').inputValue();
 if((after.match(/id="tile"/g)||[]).length!==1)throw Error('Reference definition was duplicated');
 if(!after.includes('href="#tile"'))throw Error('Reference was flattened in saved source');
 if((after.match(/fill:#00ff00/g)||[]).length!==1)throw Error('Edit changed multiple instances');
 await page.locator('#undo').click();
 await page.waitForFunction(()=>!document.querySelector('#source').value.includes('fill:#00ff00'));
 if(errors.length)throw Error(errors.join('\n'));
 await page.screenshot({path:resolve(here,'web-use-editor.png'),fullPage:true});
 writeFileSync(resolve(here,'browser-use-report.json'),JSON.stringify({passed:true,checks:['open referenced SVG','drag use instance by10,10','recolor one instance','preserve definitions and href in saved source','undo instance property','no browser errors'],before,after},null,2)+'\n');
 console.log('Referenced SVG browser interactions passed');
}finally{await browser.close();}
