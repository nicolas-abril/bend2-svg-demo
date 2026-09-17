import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtempSync,writeFileSync,readFileSync,rmSync,readdirSync,copyFileSync,symlinkSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {resolve,dirname} from 'node:path';
const root=resolve(dirname(import.meta.filename),'..'),bend=process.env.BEND_MAIN||resolve(root,'../bend2-core/bend2/main.ts');
const temp=mkdtempSync(resolve(tmpdir(),'svg-native-inspector-'));
async function run(cmd,args,env){const child=spawn(cmd,args,{cwd:root,stdio:'inherit',env:{...process.env,...env}});const timer=setTimeout(()=>child.kill('SIGTERM'),cmd==='bun'||cmd==='clang'?300000:120000);try{assert.equal(await new Promise((done,fail)=>{child.on('error',fail);child.on('exit',done);}),0);}finally{clearTimeout(timer);if(child.exitCode===null)child.kill('SIGTERM');}}
try {
 const binary=resolve(temp,'native'),input=resolve(temp,'input.svg'),output=resolve(temp,'saved.svg');
 writeFileSync(input,'<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256"><style>.shape {stroke-width:3;fill:green}</style><g fill="orange" stroke="red"><rect id="box" class="shape" x="8" y="8" width="64" height="64" style="fill:blue"/><rect x="100" y="8" width="64" height="64"/></g></svg>');
 // Keep the entry beside its modules: the current compiler's foreign symbol
 // names depend on relative import paths. Append only a test startup effect.
 for(const file of readdirSync(root).filter(f=>f.endsWith('.bend')))copyFileSync(resolve(root,file),resolve(temp,file));
 symlinkSync(resolve(root,'effs'),resolve(temp,'effs'));
 copyFileSync(resolve(root,'validation/native_inspector.c'),resolve(temp,'native_inspector.c'));
 const entry=resolve(temp,'native-test.bend');
 writeFileSync(entry,readFileSync(resolve(root,'native.bend'),'utf8').replace('def main()', 'def application()')+`

def test.start() -> IO(Unit):
  import "./native_inspector.c"

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- test.start()
    application()
`);
 await run('bun',[bend,entry,'-o',binary+'.c'],{});
 await run('clang',['-DBEND_METAL=1','-x','objective-c','-fobjc-arc','-fmodules','-std=c11','-O3',binary+'.c','-lpthread','-lm','-o',binary],{CLANG_MODULE_CACHE_PATH:resolve(temp,'clang-cache')});
 await run(binary,['--gpu','off'],{SVG_INPUT:input,SVG_OUTPUT:output,SVG_FONTS:resolve(root,'fonts')});
 assert.equal(readFileSync(output+'.test','utf8'),'PASS');
 if(process.env.SVG_TEST_ARTIFACTS){const {copyFileSync,mkdirSync}=await import('node:fs');mkdirSync(process.env.SVG_TEST_ARTIFACTS,{recursive:true});copyFileSync(output+'.panel.png',resolve(process.env.SVG_TEST_ARTIFACTS,'native-inspector.png'));}
} finally {rmSync(temp,{recursive:true,force:true});}
