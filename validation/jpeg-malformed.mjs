// Deterministic malformed-input smoke test for the compiled Bend decoder.
import{readFileSync,writeFileSync,rmSync}from'node:fs';import{spawnSync}from'node:child_process';import{resolve,dirname}from'node:path';import{createHash}from'node:crypto';
const here=dirname(import.meta.filename),binary=process.env.JPEG_NATIVE;if(!binary)throw Error('Set JPEG_NATIVE to the compiled validation/probe-jpeg.bend binary');
const cases=JSON.parse(readFileSync(resolve(here,'jpeg-cases.json'),'utf8')),results=[];let seed=58137;const random=n=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed%n;};
for(let i=0;i<100;i++){
 const base=cases[i%cases.length],bytes=Buffer.from(base.jpeg,'base64');let mutated;
 if(i%4===0)mutated=bytes.subarray(0,random(bytes.length));else{mutated=Buffer.from(bytes);for(let n=0;n<1+i%3;n++)mutated[random(mutated.length)]=random(256);}
 const input=resolve(here,'jpeg-malformed.tmp');writeFileSync(input,mutated.toString('base64'));
 const start=performance.now(),out=spawnSync(binary,['--gpu','off'],{env:{...process.env,JPEG_INPUT:input},encoding:'utf8',maxBuffer:32*1024*1024,timeout:10000});
 const passed=out.status===0&&/^P3\n\d+ \d+\n255\n/.test(out.stdout);results.push({index:i,base:base.name,inputSHA256:createHash('sha256').update(mutated).digest('hex'),passed,exitCode:out.status,signal:out.signal,durationSeconds:(performance.now()-start)/1000,error:out.error?.message});
 if(!passed){writeFileSync(resolve(here,`jpeg-malformed-${i}.json`),JSON.stringify({base:base.name,base64:mutated.toString('base64'),stderr:out.stderr},null,2));}
}
rmSync(resolve(here,'jpeg-malformed.tmp'),{force:true});writeFileSync(resolve(here,'jpeg-malformed-report.json'),JSON.stringify({sourceSHA256:createHash('sha256').update(readFileSync(resolve(here,'../svg.bend'))).digest('hex'),seed:58137,check:'100 deterministic truncations and byte mutations; successful bounded process completion, not validity classification',passed:results.every(r=>r.passed),results},null,2)+'\n');console.log(results.filter(r=>r.passed).length+'/100 decoder processes completed');if(results.some(r=>!r.passed))throw Error('Malformed JPEG decoder process failed');
