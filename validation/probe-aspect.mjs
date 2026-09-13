import{PNG}from'pngjs';import{readFileSync}from'node:fs';
const actual=readFileSync('validation/images-aspect.ppm','utf8').trim().split(/\s+/).slice(4).map(Number),ref=PNG.sync.read(readFileSync('validation/images-aspect-chromium.png')).data;
for(let y=0;y<64;y++)for(let x=0;x<64;x++){const a=actual.slice((y*64+x)*3,(y*64+x)*3+3),b=[...ref.slice((y*64+x)*4,(y*64+x)*4+3)];if(Math.max(...a.map((v,i)=>Math.abs(v-b[i])))>32)console.log(x,y,a,b);}
