import {PNG} from 'pngjs';import {readFileSync,writeFileSync} from 'node:fs';
const names=['length','length-spans'];const output=new PNG({width:64*3*4,height:64*names.length*4});
for(let r=0;r<names.length;r++)for(let col=0;col<3;col++){
 const name=`text-${names[r]}`;const pixels=col?PNG.sync.read(readFileSync(new URL(`${name}-${col===1?'reference':'chromium'}.png`,import.meta.url))).data:readFileSync(new URL(`${name}.ppm`,import.meta.url),'utf8').trim().split(/\s+/).slice(4).map(Number);
 for(let y=0;y<256;y++)for(let x=0;x<256;x++){const src=(Math.floor(y/4)*64+Math.floor(x/4))*(col?4:3),dst=((r*256+y)*output.width+col*256+x)*4;for(let c=0;c<3;c++)output.data[dst+c]=pixels[src+c];output.data[dst+3]=255;}
}writeFileSync(new URL('text-length-panel.png',import.meta.url),PNG.sync.write(output));
