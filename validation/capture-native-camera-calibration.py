from pathlib import Path
import subprocess,os,time,json,hashlib
r=Path('/private/tmp/bend-svg-work');c=r/'camera-investigation';v=r/'validation';binary=c/'build/native'
assert hashlib.sha256(binary.read_bytes()).hexdigest()=='d67764a86c1fa1f57f7105b56913c98d099fc2d9d007759efa8d6cba40c47a91'
for name,color in [('black','#000000'),('color','#5078a0'),('white','#ffffff')]:
 input=c/('calibration-'+name+'.svg');input.write_text('<svg width="256" height="256"><rect width="256" height="256" fill="'+color+'"/></svg>')
 with (c/('calibration-'+name+'.log')).open('w') as log:
  app=subprocess.Popen([str(binary),'--gpu','off'],cwd=c,env={**os.environ,'SVG_INPUT':str(input),'SVG_FONTS':str(r/'fonts.dat')},stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT)
  try:
   start=time.time();window=None
   while time.time()-start<120:
    if app.poll() is not None:raise RuntimeError('Calibration app exited')
    probe=subprocess.run(['swift','-module-cache-path',str(r/'build/swift-cache'),str(v/'native-window-for-pid.swift'),str(app.pid)],capture_output=True,text=True)
    if probe.returncode==0:window=json.loads(probe.stdout);break
    time.sleep(1)
   if window is None:raise RuntimeError('No calibration window')
   time.sleep(1)
   subprocess.run(['screencapture','-x','-l',str(window['window']),str(v/('native-camera-calibration-'+name+'.png'))],check=True)
   print('Captured',name,flush=True)
  finally:
   if app.poll() is None:
    app.terminate()
    try:app.wait(timeout=10)
    except subprocess.TimeoutExpired:app.kill();app.wait()
