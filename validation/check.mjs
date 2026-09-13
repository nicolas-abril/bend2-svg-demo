import {readFileSync, readdirSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {dirname,resolve} from 'node:path';
const root=resolve(dirname(import.meta.filename),'..');
const bend=process.env.BEND_MAIN || resolve(root,'../../bend2-core/bend2/main.ts');
for(const file of readdirSync(root).filter(x=>/^check.*\.bend$/.test(x))){
  const path=resolve(root,file), text=readFileSync(path,'utf8');
  const expected=text.split('\n').filter(x=>x.startsWith('#|')).map(x=>x.slice(2)).join('\n')+'\n';
  const got=spawnSync('bun',[bend,path],{encoding:'utf8'});
  if(got.status!==0 || got.stdout!==expected)throw Error(`${file}\nExpected:\n${expected}\nActual:\n${got.stdout}\n${got.stderr}`);
  console.log(`PASS ${file}`);
}
