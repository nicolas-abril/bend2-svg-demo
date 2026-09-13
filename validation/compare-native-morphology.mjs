import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {PNG} from 'pngjs';
const root='/private/tmp/bend-svg-work',v=root+'/validation',candidate=root+'/morphology-investigation';
const png=PNG.sync.read(readFileSync(v+'/native-morphology-preview.png'));
const ppm=readFileSync(v+'/morphology-basic-web-expected.ppm','utf8').trim().split(/\s+/).slice(4).map(Number);
const differences=[];let max=0,sum=0;
for(let y=0;y<256;y++)for(let x=0;x<256;x++){let peak=0;for(let c=0;c<3;c++){const d=Math.abs(png.data[((y+58)*png.width+x+34)*4+c]-ppm[(y*256+x)*3+c]);peak=Math.max(peak,d);max=Math.max(max,d);sum+=d;}if(peak)differences.push({x,y,maxChannelError:peak});}
const cornersOnly=differences.every(({x,y})=>y>=233&&(x<24||x>=232)&&png.data[((y+58)*png.width+x+34)*4+3]<255);
const sha=p=>createHash('sha256').update(readFileSync(p)).digest('hex');
const report={renderingPassed:cornersOnly,inputPassed:false,inputStatus:'Screenshot validation only; no mouse or keyboard events sent. Native input remains unverified.',sourceSHA256:sha(candidate+'/svg.bend'),binarySHA256:sha(candidate+'/build/native'),screenshot:'native-morphology-preview.png',expected:'morphology-basic-web-expected.ppm',width:256,height:256,pixelsCompared:65536,differingPixels:differences.length,meanAbsoluteError:sum/(65536*3),maxChannelError:max,differencesOnlyInOSRoundedBottomCorners:cornersOnly,differences};
writeFileSync(v+'/native-morphology-report.json',JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({...report,differences:undefined},null,2));if(!cornersOnly)process.exit(1);
