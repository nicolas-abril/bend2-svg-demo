import{Resvg}from'@resvg/resvg-js';import{readFileSync}from'node:fs';
const src=readFileSync(new URL('../fixtures/gradient-stops.svg',import.meta.url),'utf8');
for(const y of [8,22,36,50]){let rows=[];for(const s of [src,src.replaceAll("url('#a')",'url(#a)').replace('25%','.25')]){let a=new Resvg(s,{background:'white'}).render().pixels;rows.push([10,20,40,50].map(x=>Array.from(a.slice((y*64+x)*4,(y*64+x)*4+3))));}console.log(y,rows);}
