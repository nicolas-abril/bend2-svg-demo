from pathlib import Path
from PIL import Image
import io,base64,json,random
root=Path(__file__).resolve().parent
specs=[('one-pixel',1,1,'L',0,85,False,0),('narrow',1,17,'RGB',2,85,False,0),('narrow-2',2,17,'RGB',2,85,False,0),('narrow-3',3,17,'RGB',2,85,False,0),('narrow-4',4,17,'RGB',2,85,False,0),('short',17,1,'RGB',2,85,False,0),('partial-mcu',5,9,'RGB',2,85,False,0),('progressive-flat',64,64,'RGB',2,85,True,0),('restart-wrap',64,80,'RGB',2,85,False,1),('low-quality',37,29,'RGB',1,1,False,0),('high-quality',37,29,'RGB',0,100,False,0),('progressive-large',128,96,'RGB',2,85,True,3)]
cases=[]
for name,w,h,mode,sub,quality,progressive,restart in specs:
 rng=random.Random(82379);im=Image.new(mode,(w,h));im.putdata([127 if mode=='L' else (80,140,190) if name=='progressive-flat' else tuple(rng.randrange(256)for _ in range(3))for _ in range(w*h)])
 buf=io.BytesIO();im.save(buf,format='JPEG',quality=quality,subsampling=sub,progressive=progressive,restart_marker_blocks=restart);data=buf.getvalue();decoded=Image.open(io.BytesIO(data)).convert('RGB')
 cases.append(dict(name=name,width=w,height=h,jpeg=base64.b64encode(data).decode(),expected=base64.b64encode(decoded.tobytes()).decode()))
(root/'jpeg-stress-cases.json').write_text(json.dumps(cases,indent=2)+'\n')
print('Generated',len(cases),'extended JPEG cases')
