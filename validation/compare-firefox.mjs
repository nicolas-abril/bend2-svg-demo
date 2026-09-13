// Independent SVG reference, used only for conformance validation.
import {firefox} from 'playwright';
import {PNG} from 'pngjs';
import {readFileSync,writeFileSync,readdirSync}from'node:fs';
import {dirname,resolve}from'node:path';
import{pathToFileURL}from'node:url';
import{SCALE,scaleFor,downsample}from'./reference-scale.mjs';
const here=dirname(import.meta.filename), root=process.env.SVG_APP_ROOT||resolve(here,'..');
const browser=await firefox.launch({headless:true});
let page=null,pageScale=0;
const filter=process.env.SVG_COMPARE_FILTER;
const rows=filter?JSON.parse(readFileSync(resolve(here,'firefox-all-report.json'),'utf8')).results.filter(r=>!r.fixture.startsWith(filter)):[];
try {
for(const f of readdirSync(resolve(root,'fixtures')).filter(f=>f.endsWith('.svg')&&(!filter||f.startsWith(filter)))){
 const k=scaleFor(f);if(k!==pageScale){if(page)await page.close();page=await browser.newPage({viewport:{width:64,height:64},deviceScaleFactor:k});pageScale=k;}
 await page.goto(pathToFileURL(resolve(root,'fixtures',f)).href);
 if(f.startsWith('text-')){const faces=['Regular','Bold','Italic','BoldItalic'].map(style=>({style,data:readFileSync(resolve(here,'fonts',`NotoSans-${style}.ttf`)).toString('base64')}));await page.evaluate(async faces=>{for(const {style,data}of faces){const face=new FontFace('Noto Sans',`url(data:font/ttf;base64,${data})`,{weight:style.includes('Bold')?'700':'400',style:style.includes('Italic')?'italic':'normal'});document.fonts.add(await face.load());}await document.fonts.ready;},faces);}
 const name=f.slice(0,-4),shot=PNG.sync.read(await page.screenshot({omitBackground:false}));
 if(shot.width!==64*k||shot.height!==64*k)throw Error('Reference size mismatch');
 const ref=downsample(shot.data,64,64,k),png=new PNG({width:64,height:64});png.data.set(ref);
 writeFileSync(resolve(here,name+'-firefox.png'),PNG.sync.write(png));
 const actual=readFileSync(resolve(here,name+'.ppm'),'utf8').trim().split(/\s+/).slice(4).map(Number);
 let sum=0,sq=0,max=0,bad=0;const diff=[];
 for(let i=0;i<64*64;i++){let peak=0;for(let c=0;c<3;c++){const d=Math.abs(actual[3*i+c]-ref[4*i+c]);sum+=d;sq+=d*d;max=Math.max(max,d);peak=Math.max(peak,d);diff.push(Math.min(255,d*4));}bad+=peak>32;}
 rows.push({fixture:f,meanAbsoluteError:sum/12288,rootMeanSquareError:Math.sqrt(sq/12288),maxChannelError:max,pixelsAbove32:bad});
 writeFileSync(resolve(here,name+'-firefox-diff.ppm'),`P3\n64 64\n255\n${diff.join(' ')}\n`);
}
writeFileSync(resolve(here,'firefox-all-report.json'),JSON.stringify({reference:await browser.version(),referenceScale:SCALE,results:rows},null,2)+'\n');
console.table(rows);
} finally {await browser.close();}
