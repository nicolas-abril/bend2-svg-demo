import fs from 'node:fs';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const dir=path.dirname(fileURLToPath(import.meta.url));
const cases=JSON.parse(fs.readFileSync(path.join(dir,process.env.JPEG_CASES||'jpeg-cases.json'),'utf8'));
const report=[];
for(const c of cases.filter(c=>!process.env.JPEG_CASE_FILTER||c.name.includes(process.env.JPEG_CASE_FILTER))){
 const input=path.join(dir,'jpeg-input.tmp');fs.writeFileSync(input,c.jpeg);
 const result=spawnSync('bun',[process.env.BEND_MAIN||'/Users/macolas/Software/bend2-core/bend2/main.ts',path.join(dir,'probe-jpeg.bend')],{env:{...process.env,JPEG_INPUT:input},encoding:'utf8',maxBuffer:16*1024*1024,timeout:120000});
 if(result.status!==0)throw Error(result.stderr||result.stdout||result.error);
 const words=result.stdout.trim().split(/\s+/);if(words.shift()!=='P3')throw Error(result.stdout);
 const w=Number(words.shift()),h=Number(words.shift());words.shift();
 const actual=words.map(Number),expected=Buffer.from(c.expected,'base64');let sum=0,sq=0,max=0,bad=0;
 for(let i=0;i<expected.length;i++){const d=Math.abs((actual[i]??-10000)-expected[i]);sum+=d;sq+=d*d;max=Math.max(max,d);if(d>3)bad++;}
 let nativeEqual=null;
 if(process.env.JPEG_NATIVE){const native=spawnSync(process.env.JPEG_NATIVE,['--gpu','off'],{env:{...process.env,JPEG_INPUT:input},encoding:'utf8',maxBuffer:16*1024*1024,timeout:120000});if(native.status!==0)throw Error(native.stderr||native.stdout||native.error);nativeEqual=native.stdout===result.stdout;}
 const r={nativeEqual,name:c.name,width:w,height:h,mae:sum/expected.length,rmse:Math.sqrt(sq/expected.length),max,channelsAbove3:bad,pass:w===c.width&&h===c.height&&max<=3};report.push(r);console.log(r);
 fs.writeFileSync(path.join(dir,`jpeg-${c.name}-actual.ppm`),result.stdout);
}
fs.rmSync(path.join(dir,'jpeg-input.tmp'),{force:true});
fs.writeFileSync(path.join(dir,process.env.JPEG_REPORT||'jpeg-decode-report.json'),JSON.stringify({sourceSHA256:createHash('sha256').update(fs.readFileSync(path.join(dir,'../svg.bend'))).digest('hex'),reference:'Pillow 12.3.0 / libjpeg',cases:report},null,2)+'\n');
if(report.some(r=>!r.pass||r.nativeEqual===false))throw Error('JPEG decoder comparison failed');
