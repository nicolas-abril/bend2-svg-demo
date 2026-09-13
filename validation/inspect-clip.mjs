import{PNG}from'pngjs';import{readFileSync}from'node:fs';
const name='clipping-transforms';const actual=readFileSync(new URL(name+'.ppm',import.meta.url),'utf8').trim().split(/\s+/).slice(4).map(Number);const ref=PNG.sync.read(readFileSync(new URL(name+'-chromium.png',import.meta.url))).data;
const cases=[];for(let y=0;y<64;y++)for(let x=0;x<64;x++){let i=y*64+x;let a=actual.slice(i*3,i*3+3),b=Array.from(ref.slice(i*4,i*4+3));if(Math.max(...a.map((v,c)=>Math.abs(v-b[c])))>32)cases.push({x,y,a,b});}console.log(cases.slice(0,45));
