from pathlib import Path
import subprocess,os,time,json,hashlib
r=Path('/private/tmp/bend-svg-work');c=r/'camera-investigation';v=r/'validation';binary=c/'build/native';output=c/'native-key-save.svg';frozen=json.loads((c/'frozen-source.json').read_text());results=[];start=time.time()
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
while not (v/'native-camera-report.json').exists():
 if time.time()-start>5400:raise RuntimeError('Native presentation validation did not complete')
 time.sleep(2)
assert all(sha(c/f)==h for f,h in frozen.items())
assert json.loads((v/'native-camera-report.json').read_text())['binarySHA256']==sha(binary)
expected=json.loads((v/'native-camera-expected-sources.json').read_text())
input=c/'native-key-input.svg';input.write_text(json.loads((v/'camera-cases.json').read_text())[0]['svg'])
with (c/'native-key-app.log').open('w') as log:
 app=subprocess.Popen([str(binary),'--gpu','off'],cwd=c,env={**os.environ,'SVG_INPUT':str(input),'SVG_OUTPUT':str(output),'SVG_FONTS':str(r/'fonts.dat')},stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT)
 def key(code,char):
  p=subprocess.run(['swift','-module-cache-path',str(r/'build/swift-cache'),str(v/'native-target-input.swift'),str(app.pid),str(code),str(char)],capture_output=True,text=True)
  if p.returncode:raise RuntimeError(p.stdout+p.stderr)
 def capture(name,expectedName):
  output.unlink(missing_ok=True);key(1,115)
  wait=time.time()
  while not output.exists():
   if time.time()-wait>15:raise RuntimeError('Save key produced no document at '+name)
   time.sleep(.1)
  if output.read_text()!=expected[expectedName]:raise RuntimeError('Saved source differs at '+name)
  shot=v/('native-camera-key-'+name+'.png');comparison=None
  for attempt in range(10):
   time.sleep(.3)
   subprocess.run(['screencapture','-x','-l',str(window['window']),str(shot)],check=True)
   got=subprocess.run(['bun',str(v/'compare-native-camera-frame.mjs'),str(shot),str(v/('native-camera-'+expectedName+'-expected.ppm'))],capture_output=True,text=True)
   if got.stdout:comparison=json.loads(got.stdout)
   if got.returncode==0:break
  if comparison is None:raise RuntimeError('No screenshot comparison at '+name)
  result={'stage':name,'expected':expectedName,'savedSourceMatches':True,'screenshot':shot.name,**comparison};results.append(result);print(json.dumps(result),flush=True)
  if not result['passed']:raise RuntimeError('Native frame differs at '+name)
 try:
  wait=time.time();window=None
  while time.time()-wait<120:
   if app.poll() is not None:raise RuntimeError('Native app exited')
   probe=subprocess.run(['swift','-module-cache-path',str(r/'build/swift-cache'),str(v/'native-window-for-pid.swift'),str(app.pid)],capture_output=True,text=True)
   if probe.returncode==0:window=json.loads(probe.stdout);break
   time.sleep(1)
  if window is None:raise RuntimeError('No native key test window')
  capture('start','start')
  for name,expectedName,code,char in [('zoom','zoom',24,43),('unzoom','start',27,45),('actual','actual',29,48),('fit','start',3,102),('left','pan',4,104),('up','up',40,107),('down','pan',38,106),('right','start',37,108),('undo','start',6,122)]:
   key(code,char);capture(name,expectedName)
  report={'passed':True,'sourceSHA256':frozen,'binarySHA256':sha(binary),'method':'CGEvent.postToPid, addressed only to known SVG test process; no activation or global events','keyboardNavigationPassed':True,'keyboardSavePassed':True,'pointerEditingPassed':False,'pointerStatus':'Separate process-targeted mouse probes did not select a shape; mouse editing remains unverified in the native frontend.','durationSeconds':time.time()-start,'results':results}
 except Exception as error:
  report={'passed':False,'error':str(error),'sourceSHA256':frozen,'binarySHA256':sha(binary),'results':results};raise
 finally:
  (v/'native-camera-keys-report.json').write_text(json.dumps(report,indent=2)+'\n')
  if app.poll() is None:
   app.terminate()
   try:app.wait(timeout=10)
   except subprocess.TimeoutExpired:app.kill();app.wait()
