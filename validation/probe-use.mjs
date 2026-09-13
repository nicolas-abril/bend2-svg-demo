// Validation only: isolate limitations of the installed resvg binding.
import{Resvg}from'@resvg/resvg-js';
import{readFileSync,writeFileSync}from'node:fs';
const root=new URL('../fixtures/',import.meta.url);
const render=s=>Buffer.from(new Resvg(s,{background:'white',fitTo:{mode:'width',value:64}}).render().pixels);
const delta=(a,b)=>{let pixels=0;for(let i=0;i<a.length;i+=4)if(a[i]!==b[i]||a[i+1]!==b[i+1]||a[i+2]!==b[i+2])pixels++;return pixels;};
const source=name=>readFileSync(new URL(name,root),'utf8');
const sizes=source('use-inheritance.svg');
const viewport=source('viewports-nested.svg');
const inherited='<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><defs fill="red"><g id="tile"><rect width="20" height="20" fill="inherit"/></g></defs><use href="#tile" fill="teal"/></svg>';
const rows=[
 {probe:'Changing symbol default width/height from 16 to 32',changedPixels:delta(render(sizes),render(sizes.replace('id="stamp" width="16" height="16"','id="stamp" width="32" height="32"')))},
 {probe:'Removing both zero-size nested viewport elements',changedPixels:delta(render(viewport),render(viewport.replace(/<svg width="0" height="20">.*?<\/svg>/,'').replace(/<svg width="20" height="20" viewBox="0 0 0 10">.*?<\/svg>/,'')))},
 {probe:'Removing explicit fill=inherit from referenced content',changedPixels:delta(render(inherited),render(inherited.replace(' fill="inherit"','')))}
];
writeFileSync(new URL('resvg-use-probe.json',import.meta.url),JSON.stringify({reference:'@resvg/resvg-js 2.6.2',results:rows},null,2)+'\n');
console.table(rows);
