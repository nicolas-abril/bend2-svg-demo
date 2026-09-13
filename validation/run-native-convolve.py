from pathlib import Path
import subprocess,os,time,json,hashlib
r=Path('/private/tmp/bend-svg-work');c=Path(os.environ.get('SVG_APP_ROOT',str(r/'convolve-investigation')));v=r/'validation';binary=c/'build/native';frozen=json.loads((c/'frozen-source.json').read_text());expected=json.loads((v/'native-convolve-expected-sources.json').read_text());results=[];start=time.time()
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
assert all(sha(c/f)==h for f,h in frozen.items())
report={'passed':False,'sourceSHA256':frozen,'binarySHA256':sha(binary),'results':results}
try:
 for name in ['kernels','units']:
  output=c/('native-convolve-'+name+'-saved.svg');output.unlink(missing_ok=True)
  with (c/('native-convolve-'+name+'.log')).open('w') as log:
   app=subprocess.Popen([str(binary),'--gpu','off'],cwd=c,env={**os.environ,'SVG_INPUT':str(c/'fixtures'/('convolve-'+name+'.svg')),'SVG_OUTPUT':str(output),'SVG_FONTS':str(c/'fonts')},stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT)
   try:
    wait=time.time();window=None
    while time.time()-wait<180:
     if app.poll() is not None:raise RuntimeError('Native app exited')
     probe=subprocess.run(['swift','-module-cache-path',str(r/'build/swift-cache'),str(v/'native-window-for-pid.swift'),str(app.pid)],capture_output=True,text=True)
     if probe.returncode==0:window=json.loads(probe.stdout);break
     time.sleep(1)
    if window is None:raise RuntimeError('Native window did not open')
    save=subprocess.run(['swift','-module-cache-path',str(r/'build/swift-cache'),str(v/'native-target-input.swift'),str(app.pid),'1','115'],capture_output=True,text=True)
    if save.returncode:raise RuntimeError(save.stdout+save.stderr)
    wait=time.time()
    while not output.exists():
     if time.time()-wait>30:raise RuntimeError('Native Save key did not write source')
     time.sleep(.1)
    if output.read_text()!=expected[name]:raise RuntimeError('Native saved source differs')
    shot=v/('native-convolve-'+name+'.png');comparison=None
    for attempt in range(15):
     time.sleep(.5);subprocess.run(['screencapture','-x','-l',str(window['window']),str(shot)],check=True)
     got=subprocess.run(['bun',str(v/'compare-native-camera-frame.mjs'),str(shot),str(v/('convolve-editor-'+name+'-expected.ppm'))],capture_output=True,text=True)
     if got.stdout:comparison=json.loads(got.stdout)
     if got.returncode==0:break
    if comparison is None:raise RuntimeError('No native screenshot comparison')
    result={'fixture':'convolve-'+name+'.svg','savedSourceMatches':True,'screenshot':shot.name,**comparison};results.append(result);print(json.dumps(result),flush=True)
    if not result['passed']:raise RuntimeError('Native window differs')
   finally:
    if app.poll() is None:
     app.terminate()
     try:app.wait(timeout=10)
     except subprocess.TimeoutExpired:app.kill();app.wait()
 assert all(sha(c/f)==h for f,h in frozen.items()) and sha(binary)==report['binarySHA256']
 report.update(passed=True,renderingPassed=True,keyboardSavePassed=True,pointerEditingPassed=False,method='Two independently launched native windows; process-addressed Save key and every-pixel screenshot comparison with existing calibrated OS border',durationSeconds=time.time()-start)
except Exception as e:report['error']=str(e);raise
finally:(v/'native-convolve-report.json').write_text(json.dumps(report,indent=2)+'\n')
