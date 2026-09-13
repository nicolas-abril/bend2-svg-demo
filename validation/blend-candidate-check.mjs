import{PNG}from'pngjs';import{readFileSync,writeFileSync}from'node:fs';import{spawnSync}from'node:child_process';import{resolve,dirname}from'node:path';
const here=dirname(import.meta.filename),root=resolve(here,'../blend-investigation'),report=JSON.parse(readFileSync(resolve(here,'blend-experiment-report.json'),'utf8')),ref=PNG.sync.read(readFileSync(resolve(here,'blend-experiment-opaque-chromium.png'))).data,actual=readFileSync(resolve(here,'blend-experiment-opaque.ppm'),'utf8').trim().split(/\s+/).slice(4).map(Number),calls=[],expected=[],cases=[];
for(let m=0;m<16;m++)for(const p of [0,2,3,6,7,8,9,12]){const i=(Math.floor(m/4)*16+Math.floor(p/4)*4+1)*64+(m%4)*16+(p%4)*4+1;const channels=[0,1,2].map(c=>ref[i*4+c]);const[src,bg]=report.pairs[p],packed=(channels[0]<<16)|(channels[1]<<8)|channels[2];calls.push(`run("${report.modes[m]}", "${src}", "${bg}", ${packed})`);expected.push("True");cases.push({mode:report.modes[m],source:src,backdrop:bg,expected:packed});}
const source=`import Base
import ./svg.bend as SVG

def close(+a: U32, +b: U32) -> Bool:
  U32.is_le(SVG.choose(U32, U32.is_ge(a, b), (a - b : U32), (b - a : U32)), 1)

def pixel(+a: U32, +b: U32) -> Bool:
  close((a / 65536 : U32), (b / 65536 : U32)) && close(((a / 256) % 256 : U32), ((b / 256) % 256 : U32)) && close((a % 256 : U32), (b % 256 : U32))

def run(kind: String, src: String, bg: String, expected: U32) -> IO(Unit):
  IO.print(SVG.choose(String, pixel(SVG.color.pack(SVG.filter.blend(SVG.color(src), SVG.color(bg), SVG.filter.blend.mode(kind))), expected), "True", "False"))

def main() -> IO(Unit):
  do IO<Unit>:
`+calls.map((c,i)=>'    '+(i<calls.length-1?'Unit <- ':'')+c).join('\n')+'\n\n'+expected.map(v=>'#|'+v).join('\n')+'\n';writeFileSync(resolve(root,'check-blend.bend'),source);const got=spawnSync('bun',[process.env.BEND_MAIN||'/Users/macolas/Software/bend2-core/bend2/main.ts',resolve(root,'check-blend.bend')],{encoding:'utf8'});if(got.status!==0||got.stdout!==expected.join('\n')+'\n')throw Error(got.stderr||got.stdout);const c=readFileSync(resolve(root,'probe-c.txt'),'utf8'),js=readFileSync(resolve(root,'probe-js.txt'),'utf8');if(c!==js||c.trim().split('\n').length!==1024)throw Error('Random C/JS parity failed');writeFileSync(resolve(here,'blend-candidate-check-report.json'),JSON.stringify({experimental:true,passed:true,reference:'Independent Chromium SVG cells, with at most one channel level of rounding tolerance; every selected color pair is retained',sourceSHA256:report.sourceSHA256,cases,randomNativeJavascriptCases:1024},null,2)+'\n');console.log(`${cases.length} saved independent blend cases pass; 1024 C/JavaScript colors match exactly`);
