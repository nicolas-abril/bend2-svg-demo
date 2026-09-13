import{PNG}from'pngjs';import{readFileSync}from'node:fs';
for(const file of ['text-position','text-length-spans']){
 const a=readFileSync(`validation/${file}.ppm`,'utf8').trim().split(/\s+/).slice(4).map(Number);
 const variants={bend:a};for(const name of ['reference','chromium']){const p=PNG.sync.read(readFileSync(`validation/${file}-${name}.png`));variants[name]=[...p.data].filter((_,i)=>i%4!==3);}
 for(let row=0;row<4;row++){const y0=file==='text-position'?[0,18,36,51][row]:row*15,y1=file==='text-position'?[18,36,51,64][row]:Math.min(64,(row+1)*15);const result={};for(const [name,p]of Object.entries(variants)){let mass=0,mx=0,my=0,xmin=64,xmax=0;for(let y=y0;y<y1;y++)for(let x=0;x<64;x++){const alpha=(255-Math.min(...p.slice((y*64+x)*3,(y*64+x)*3+3)))/255;mass+=alpha;mx+=alpha*x;my+=alpha*y;if(alpha>.1){xmin=Math.min(xmin,x);xmax=Math.max(xmax,x);}}result[name]={mass,x:mx/mass,y:my/mass,xmin,xmax};}console.log(file,row,result);}
}
