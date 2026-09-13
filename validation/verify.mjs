import{readFileSync,writeFileSync,readdirSync,existsSync}from'node:fs';
import{resolve,dirname}from'node:path';
const here=dirname(import.meta.filename),read=name=>JSON.parse(readFileSync(resolve(here,name),'utf8'));
const policy=read('coverage.json');
const reports={resvg:read('report.json'),chromium:read('chromium-report.json')};
if(Object.values(policy.fixtures).some(f=>f.reference==='firefox'))reports.firefox=read(existsSync(resolve(here,'firefox-all-report.json'))?'firefox-all-report.json':'convolve-firefox-report.json');
const results=[];
for(const fixture of readdirSync(resolve(here,'../fixtures')).filter(x=>x.endsWith('.svg'))){
 const coverage=policy.fixtures[fixture];
 if(!coverage)throw Error(`Missing coverage declaration for ${fixture}`);
 const report=reports[coverage.reference],r=report.results.find(r=>r.fixture===fixture);
 if(!r)throw Error(`Missing ${coverage.reference} comparison for ${fixture}`);
 const fraction=r.fractionAbove32 ?? r.pixelsAbove32/(64*64),t=policy.thresholds;
 results.push({...r,reference:coverage.reference,features:coverage.features,passed:r.meanAbsoluteError<=t.meanAbsoluteError&&r.rootMeanSquareError<=t.rootMeanSquareError&&fraction<=t.fractionAbove32});
}
const passed=results.every(r=>r.passed);
writeFileSync(resolve(here,'summary.json'),JSON.stringify({passed,referencePolicy:policy.referencePolicy,thresholds:policy.thresholds,results},null,2)+'\n');
console.log(`${results.filter(r=>r.passed).length}/${results.length} declared fixture comparisons pass`);
if(!passed)throw Error('Failed comparisons: '+results.filter(r=>!r.passed).map(r=>r.fixture).join(', '));
