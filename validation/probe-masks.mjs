// Reference-only probes; no dependencies from this script are used by the app.
import{Resvg}from'@resvg/resvg-js';import{readFileSync,writeFileSync}from'node:fs';
const source=n=>readFileSync(new URL('../fixtures/'+n,import.meta.url),'utf8');
const render=s=>Buffer.from(new Resvg(s,{background:'white',fitTo:{mode:'width',value:64}}).render().pixels);
function changed(a,b){let n=0;for(let i=0;i<a.length;i+=4)if(a[i]!==b[i]||a[i+1]!==b[i+1]||a[i+2]!==b[i+2])n++;return n;}
const alpha=source('mask-alpha.svg'),linear=source('mask-linear-rgb.svg');
const results=[{probe:'Remove mask-mode:alpha override',changedPixels:changed(render(alpha),render(alpha.replace(';mask-mode:alpha','')))},{probe:'Remove mask color-interpolation=linearRGB',changedPixels:changed(render(linear),render(linear.replace(' color-interpolation="linearRGB"','')))}];
writeFileSync(new URL('resvg-mask-probe.json',import.meta.url),JSON.stringify({reference:'@resvg/resvg-js 2.6.2',results},null,2)+'\n');console.table(results);
