// Compile the actual foreign frame sender against both runtimes, then decode
// its HTTP/PNG bytes independently. No SVG library or saved image is involved.
import assert from 'node:assert/strict';
import {createConnection,createServer} from 'node:net';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {resolve,dirname,relative} from 'node:path';
import {setTimeout as pause} from 'node:timers/promises';
import {PNG} from 'pngjs';
const root=resolve(dirname(import.meta.filename),'..');
const bend=process.env.BEND_MAIN||resolve(root,'../bend2-core/bend2/main.ts');
const temp=mkdtempSync(resolve(tmpdir(),'svg-frame-transport-'));
function command(cmd,args){const r=spawnSync(cmd,args,{encoding:'utf8'});assert.equal(r.status,0,r.stderr||r.stdout);}
async function freePort(){const s=createServer();await new Promise(r=>s.listen(0,'127.0.0.1',r));const p=s.address().port;await new Promise(r=>s.close(r));return p;}
async function response(port){for(let i=0;i<100;i++){try{return await new Promise((done,fail)=>{const parts=[],socket=createConnection({host:'127.0.0.1',port});socket.on('data',d=>parts.push(d));socket.on('error',fail);socket.on('end',()=>done(Buffer.concat(parts)));socket.setTimeout(10000,()=>socket.destroy(Error('Frame timeout')));});}catch(e){if(e.code!=='ECONNREFUSED')throw e;await pause(50);}}throw Error('Server did not start');}
const cases=[{w:3,h:2,pattern:true},{w:256,h:256,pattern:false},{w:32,h:32,pattern:true},{w:1536,h:1,pattern:true}];
const color=i=>(i*2654435761)>>>0;
try {
 for(const [index,item] of cases.entries()){
  const port=await freePort(),path=resolve(temp,'frame.bend'),binary=resolve(temp,'frame');
  const count=item.w*item.h,capacity=2**Math.ceil(Math.log2(count));
  writeFileSync(path,`import Base

def frame.send(socket: Socket, pixels: Array<U32>, +w: U32, +h: U32) -> IO(Socket & Result<&1, &1, U32 & String, Unit>):
  import "${relative(temp,resolve(root,'effs/frame_send.c'))}"
  import "${relative(temp,resolve(root,'effs/frame_send.js'))}"

@unsafe
def pixels(n: Nat, a: Array<U32>, +i: U32) -> Array<U32>:
  match n:
    case 0n: a
    case 1n+d: pixels(d, Array.set(U32, a, i, (i * 2654435761 : U32)), (i + 1 : U32))

def finish(got: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (socket, result) = got
  do IO<Unit>:
    Unit <- IO.pass(Unit, result)
    Socket.close(socket)

def accepted(got: Listener & Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  (listener, result) = got
  do IO<Unit>:
    socket : Socket <- IO.pass(Socket, result)
    got : Socket & Result<&1, &1, U32 & String, Unit> <- frame.send(socket, ${item.pattern?`pixels(${count}n, [0 : U32*${capacity}n], 0)`:`[1122867 : U32*${capacity}n]`}, ${item.w}, ${item.h})
    finish(got)

def main() -> IO(Unit):
  do IO<Unit>:
    listener : Listener <- IO.try(Listener, TCP.listen(${port}))
    got : Listener & Result<&1, &1, U32 & String, Socket> <- TCP.accept(listener)
    accepted(got)
`);
  command('bun',[bend,path,'-o',binary+'.c']);
  command(process.env.CC||'clang',['-std=c11','-O2',binary+'.c','-lpthread','-lm','-lz','-o',binary]);
  for(const backend of ['c','javascript']){
   const child=spawn(backend==='c'?binary:'bun',backend==='c'?['--gpu','off']:[bend,path],{stdio:['ignore','pipe','pipe']});
   let stderr='';child.stderr.on('data',d=>stderr+=d);
   const exited=new Promise(r=>child.on('exit',(code,signal)=>r({code,signal})));
   try {
    const wire=await response(port),end=wire.indexOf('\r\n\r\n');assert(end>0);
    const header=wire.subarray(0,end).toString(),body=wire.subarray(end+4);
    assert.match(header,/^HTTP\/1.1 200 OK/);assert.match(header,/Content-Type: image\/png\r\n/);
    assert.equal(Number(header.match(/Content-Length: (\d+)/)[1]),body.length);
    assert.deepEqual([...body.subarray(0,8)],[137,80,78,71,13,10,26,10]);
    const png=PNG.sync.read(body,{checkCRC:true});assert.equal(png.width,item.w);assert.equal(png.height,item.h);
    for(let i=0;i<count;i++){const p=item.pattern?color(i):1122867;assert.deepEqual([...png.data.subarray(i*4,i*4+4)],[(p>>>16)&255,(p>>>8)&255,p&255,255]);}
    if(!item.pattern)assert(body.length<count,'Flat frame should compress');
    const status=await exited;assert.equal(status.code,0,stderr);
    console.log(`PASS ${backend} ${item.w}x${item.h} ${item.pattern?'pattern':'flat'}: ${body.length} PNG bytes, ${count} exact pixels`);
   } finally {if(child.exitCode===null)child.kill('SIGTERM');}
  }
 }
} finally {rmSync(temp,{recursive:true,force:true});}
