import{Resvg}from'@resvg/resvg-js';import{readFileSync,writeFileSync}from'node:fs';
const results=[];
for(const[f,pattern]of [['stroke-calibration',/ pathLength="[^"]+"/g],['stroke-vector',/ vector-effect="non-scaling-stroke"/g]]){
 const src=readFileSync(new URL('../fixtures/'+f+'.svg',import.meta.url),'utf8');
 const a=new Resvg(src,{background:'white'}).render().pixels,b=new Resvg(src.replace(pattern,''),{background:'white'}).render().pixels;
 let max=0;for(let i=0;i<a.length;i++)max=Math.max(max,Math.abs(a[i]-b[i]));results.push({fixture:f,maxChangeWhenRemovingProperty:max});
}
writeFileSync(new URL('resvg-stroke-probe.json',import.meta.url),JSON.stringify(results,null,2)+'\n');console.table(results);
