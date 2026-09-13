// Independent reference investigation; never imported by the app.
import{chromium}from'playwright';import{readFileSync,writeFileSync}from'node:fs';import{resolve,dirname}from'node:path';import{createHash}from'node:crypto';import{Resvg}from'@resvg/resvg-js';import{PNG}from'pngjs';
const here=dirname(import.meta.filename),fontPath=resolve(here,'fonts/NotoSans-Regular.ttf'),font=readFileSync(fontPath),browser=await chromium.launch({headless:true});
const cases=[
 ['line','<path id="p" d="M10 40H110"/>','','','ABCD'],
 ['offset','<path id="p" d="M10 40H110"/>','','startOffset="20"','ABCD'],
 ['percent-middle','<path id="p" d="M10 40H110"/>','text-anchor="middle"','startOffset="50%"','ABCD'],
 ['pathLength','<path id="p" d="M10 40H110" pathLength="50"/>','','startOffset="10"','ABCD'],
 ['pathLength-percent','<path id="p" d="M10 40H110" pathLength="50"/>','','startOffset="25%"','ABCD'],
 ['root-xy','<path id="p" d="M10 40H110"/>','x="7" y="9"','','ABCD'],
 ['root-dxdy','<path id="p" d="M10 40H110"/>','dx="7" dy="9"','','ABCD'],
 ['root-lists','<path id="p" d="M10 40H110"/>','x="7 25" y="9 15"','','ABCD'],
 ['spans','<path id="p" d="M10 40H110"/>','','','A<tspan dx="5" dy="4">BC</tspan>D'],
 ['rotation','<path id="p" d="M10 40L110 60"/>','rotate="20 40"','','ABCD'],
 ['curve','<path id="p" d="M10 65Q64 0 118 65"/>','','startOffset="12"','Bend SVG'],
 ['reference-transform','<path id="p" d="M0 0H100" transform="translate(10 40)"/>','','','ABCD'],
 ['ancestor-transform','<g transform="translate(10 40)"><path id="p" d="M0 0H100"/></g>','','','ABCD'],
 ['text-transform','<path id="p" d="M10 40H110"/>','transform="translate(5 10)"','','ABCD'],
 ['direct-path','<path id="p" d="M10 40H110"/>','','path="M10 60H110"','ABCD'],
 ['shape','<circle id="p" cx="64" cy="48" r="35"/>','','','Bend'],
 ['closed-wrap','<path id="p" d="M10 40H110V65H10Z"/>','','startOffset="95%"','ABCDEFGHIJKL'],
 ['side-right','<path id="p" d="M10 40H110"/>','','side="right"','ABCD'],
 ['negative-offset','<path id="p" d="M10 40H110"/>','','startOffset="-12"','ABCD'],
 ['mixed','<path id="p" d="M10 40H90"/>','x="4" y="20"','','BC','A','DE'],
 ['missing','<path id="other" d="M10 40H110"/>','x="4" y="20"','','BC','A','DE'],
 ['length-fit','<path id="p" d="M10 40H110"/>','','textLength="50" lengthAdjust="spacingAndGlyphs"','ABCD']
];
try{const page=await browser.newPage({viewport:{width:128,height:96}}),results=[];for(const[name,defs,attrs,pathAttrs,content,before='',after='']of cases){const svg=`<svg xmlns="http://www.w3.org/2000/svg" width="128" height="96"><defs>${defs}</defs><text font-family="Noto Sans" font-size="14" ${attrs}>${before}<textPath href="#p" ${pathAttrs}>${content}</textPath>${after}</text></svg>`;await page.setContent(`<style>body{margin:0}</style>${svg}`);await page.evaluate(async data=>{const font=new FontFace('Noto Sans',`url(data:font/ttf;base64,${data})`);await font.load();document.fonts.add(font);await document.fonts.ready;},font.toString('base64'));const metrics=await page.locator('text').evaluate(t=>({text:t.textContent,count:t.getNumberOfChars(),chars:Array.from({length:t.getNumberOfChars()},(_,i)=>{const s=t.getStartPositionOfChar(i),e=t.getEndPositionOfChar(i),b=t.getExtentOfChar(i);return{index:i,start:[s.x,s.y],end:[e.x,e.y],angle:t.getRotationOfChar(i),extent:[b.x,b.y,b.width,b.height]};})}));const chromiumPixels=PNG.sync.read(await page.screenshot()).data,resvgPixels=new Resvg(svg,{background:'white',font:{fontFiles:[fontPath],loadSystemFonts:false,defaultFontFamily:'Noto Sans'}}).render().pixels;let sum=0,square=0,max=0,paintChromium=0,paintResvg=0;for(let i=0;i<128*96;i++){if(chromiumPixels[i*4]<250)paintChromium++;if(resvgPixels[i*4]<250)paintResvg++;for(let c=0;c<3;c++){const d=Math.abs(chromiumPixels[i*4+c]-resvgPixels[i*4+c]);sum+=d;square+=d*d;max=Math.max(max,d);}}results.push({name,svg,chromium:metrics,pixelComparisonBetweenReferences:{meanAbsoluteError:sum/(128*96*3),rootMeanSquareError:Math.sqrt(square/(128*96*3)),maxChannelError:max,paintChromium,paintResvg}});}writeFileSync(resolve(here,'text-path-reference-probe.json'),JSON.stringify({diagnostic:'Independent textPath behavior for planning the Bend implementation; no Bend conformance claim.',chromiumVersion:await browser.version(),fontSHA256:createHash('sha256').update(font).digest('hex'),results},null,2)+'\n');for(const r of results)console.log(r.name,JSON.stringify(r.chromium.chars.map(c=>({p:c.start,a:c.angle}))),r.pixelComparisonBetweenReferences.meanAbsoluteError.toFixed(2));}finally{await browser.close();}
