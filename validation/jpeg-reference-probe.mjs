// Independent browser decoding is used only to investigate reference differences.
import{chromium}from'playwright';import{readFileSync,writeFileSync}from'node:fs';import{resolve,dirname}from'node:path';
const here=dirname(import.meta.filename),cases=JSON.parse(readFileSync(resolve(here,'jpeg-stress-cases.json'),'utf8')),browser=await chromium.launch({headless:true});
try{const page=await browser.newPage(),results=[];for(const c of cases){
 const decoded=await page.evaluate(async c=>{const image=new Image();image.src='data:image/jpeg;base64,'+c.jpeg;await image.decode();const canvas=document.createElement('canvas');canvas.width=c.width;canvas.height=c.height;const ctx=canvas.getContext('2d');ctx.drawImage(image,0,0);return Array.from(ctx.getImageData(0,0,c.width,c.height).data).filter((_,i)=>i%4!==3);},c);
 const pillow=Buffer.from(c.expected,'base64'),words=readFileSync(resolve(here,`jpeg-${c.name}-actual.ppm`),'utf8').trim().split(/\s+/).slice(4).map(Number);
 const error=(a,b)=>{let sum=0,sq=0,max=0;for(let i=0;i<a.length;i++){const d=Math.abs(a[i]-b[i]);sum+=d;sq+=d*d;max=Math.max(max,d);}return{mae:sum/a.length,rmse:Math.sqrt(sq/a.length),max};};
 results.push({name:c.name,chromiumVersusPillow:error(decoded,pillow),bendVersusChromium:error(words,decoded)});
 }writeFileSync(resolve(here,'jpeg-reference-probe.json'),JSON.stringify({purpose:'Characterize standalone JPEG chroma reconstruction differences; no application decoder dependency',results},null,2)+'\n');console.log(results.find(r=>r.name==='narrow'));
}finally{await browser.close();}
