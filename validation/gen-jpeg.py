from pathlib import Path
from PIL import Image
import io,base64,json
root=Path(__file__).resolve().parent.parent
cases=[]
for name,mode,sub,restart in [('gray','L',0,0),('444','RGB',0,0),('422','RGB',1,0),('420','RGB',2,0),('restart','RGB',2,1),('progressive-gray','L',0,0),('progressive-444','RGB',0,0),('progressive-422','RGB',1,0),('progressive-420','RGB',2,0),('progressive-restart','RGB',2,1),('rgb','RGB',0,0),('cmyk','CMYK',0,0),('ycck','CMYK',0,0),('progressive-cmyk','CMYK',0,0),('noise','RGB',2,0),('progressive-noise','RGB',2,0)]:
 w,h=(19,17)
 im=Image.new(mode,(w,h))
 import random
 rng=random.Random(734)
 im.putdata([rng.randrange(256) if mode=='L' and 'noise' in name else (x*11+y*7)%256 if mode=='L' else tuple(rng.randrange(256) for _ in range(3)) if 'noise' in name else ((x*11+y*3)%256,(x*3+y*11)%256,(x*7+y*5)%256,(x*5+y*2)%256) if mode=='CMYK' else ((x*11+y*3)%256,(x*3+y*11)%256,(x*7+y*5)%256) for y in range(h) for x in range(w)])
 buf=io.BytesIO();im.save(buf,format='JPEG',quality=85,subsampling=sub,restart_marker_blocks=restart,progressive=name.startswith('progressive'),keep_rgb=name=='rgb')
 data=buf.getvalue()
 if name=='ycck':
  at=data.index(b'Adobe');data=data[:at+11]+bytes([2])+data[at+12:]
 decoded=Image.open(io.BytesIO(data)).convert('RGB')
 cases.append(dict(name=name,width=w,height=h,jpeg=base64.b64encode(data).decode(),expected=base64.b64encode(decoded.tobytes()).decode()))
# Small spec-derived streams cover separate sequential scans, 16-bit DQT,
# and the maximum Huffman code length independently of Pillow's encoder.
import struct
segment=lambda tag,payload:bytes([255,tag])+struct.pack('>H',len(payload)+2)+payload
for name,separate,wide,longcode in [('separate',True,False,False),('quant16',False,True,False),('huffman16',False,False,True)]:
 w,h=19,17
 frame=bytes([8])+struct.pack('>HH',h,w)+bytes([3,1,0x22,0,2,0x11,0,3,0x11,0])
 quant=bytes([16 if wide else 0])+(b'\0\1'*64 if wide else b'\1'*64)
 bits=16 if longcode else 1
 counts=bytes([0]*(bits-1)+[1]+[0]*(16-bits))
 table=bytes([0])+counts+bytes([0])+bytes([16])+counts+bytes([0])
 data=b'\xff\xd8'+segment(0xdb,quant)+segment(0xc4,table)+segment(0xc1 if wide else 0xc0,frame)
 for ids,blocks in [([1],9),([2],4),([3],4)] if separate else [([1,2,3],24)]:
  scan=bytes([len(ids)])+b''.join(bytes([i,0]) for i in ids)+bytes([0,63,0])
  nbits=blocks*2*bits
  entropy=b'\0'*(nbits//8)+(bytes([(1<<(8-nbits%8))-1]) if nbits%8 else b'')
  data+=segment(0xda,scan)+entropy
 data+=b'\xff\xd9'
 decoded=Image.open(io.BytesIO(data)).convert('RGB')
 cases.append(dict(name=name,width=w,height=h,jpeg=base64.b64encode(data).decode(),expected=base64.b64encode(decoded.tobytes()).decode()))
(root/'validation/jpeg-cases.json').write_text(json.dumps(cases,indent=2)+'\n')
# Every valid case compares every pixel, with a three-level per-channel bound.
source='''import Base
import ./svg.bend as SVG

def close(a: F32, b: U32) -> Bool:
  F32.is_le(F32.abs((a * 255.0 - U32.to_f32(b) : F32)), 3.001)

def pixel(c: SVG.Color, +expected: SVG.Bytes, +at: U32) -> Bool:
  SVG.Color{r, g, b, a} = c
  F32.is_eq(a, 1.0) && close(r, SVG.bytes.get(expected, at)) && close(g, SVG.bytes.get(expected, U32.inc(at))) && close(b, SVG.bytes.get(expected, (at + 2 : U32)))

def pixels(n: Nat, +index: U32, +w: U32, +raster: SVG.Raster, +expected: SVG.Bytes) -> Bool:
  match n:
    case 0n: True{}
    case 1n+d: pixel(SVG.raster.pixel(raster, U32.to_f32(U32.mod(index, w)), U32.to_f32(U32.div(index, w))), expected, (index * 3 : U32)) && pixels(d, U32.inc(index), w, raster, expected)

def check(+raster: SVG.Raster, +w: U32, +h: U32, expected: SVG.Bytes) -> String:
  SVG.Raster{origin, step, width, height, depth, linear, image} = raster
  SVG.choose(String, U32.is_eq(width, w) && U32.is_eq(height, h) && pixels(U32.to_nat((w * h : U32)), 0, w, raster, expected), "PASS", "FAIL")

def main() -> IO(Unit):
  do IO<Unit>:
'''
for i,c in enumerate(cases):
 source+=('    Unit <- ' if i<len(cases)-1 else '    ')+f'IO.print("jpeg-{c["name"]}: " ++ check(SVG.jpeg.decode(SVG.base64("{c["jpeg"]}")), {c["width"]}, {c["height"]}, SVG.base64("{c["expected"]}")))\n'
source+='\n'+''.join(f'#|jpeg-{c["name"]}: PASS\n' for c in cases)
(root/'check-jpeg.bend').write_text(source)
# Invalid streams must return an empty image rather than a partial decode.
gray=base64.b64decode(cases[0]['jpeg']);restart=base64.b64decode(next(c['jpeg'] for c in cases if c['name']=='restart'))
def alter(data,tag,offset,replacement):
 at=data.index(bytes([255,tag]))+4+offset
 return data[:at]+replacement+data[at+len(replacement):]
invalid={'signature':b'not jpeg','empty-frame':b'\xff\xd8\xff\xd9','truncated':gray[:-2],'entropy-truncated':gray[:-20]+b'\xff\xd9','zero-quant':alter(gray,0xdb,1,b'\0'),'missing-quant':gray[:2]+gray[2:].replace(gray[gray.index(b'\xff\xdb'):gray.index(b'\xff\xdb')+69],b''),'precision':alter(gray,0xc0,0,b'\x0c'),'dimensions':alter(gray,0xc0,1,b'\xff\xff\xff\xff'),'sampling':alter(gray,0xc0,7,b'\x00'),'selector':alter(gray,0xda,1,b'\xfe'),'spectral':alter(gray,0xda,3,b'\x3f\x00'),'restart':restart.replace(b'\xff\xd0',b'\xff\xd4',1),'arithmetic':gray.replace(b'\xff\xc0',b'\xff\xc9',1)}
source='''import Base
import ./svg.bend as SVG

def empty(raster: SVG.Raster) -> String:
  SVG.Raster{origin, step, w, h, depth, linear, image} = raster
  SVG.choose(String, U32.is_eq(w, 0) && U32.is_eq(h, 0), "PASS", "FAIL")

def main() -> IO(Unit):
  do IO<Unit>:
'''
for i,(name,data) in enumerate(invalid.items()):
 source+=('    Unit <- ' if i<len(invalid)-1 else '    ')+f'IO.print("jpeg-{name}: " ++ empty(SVG.jpeg.decode(SVG.base64("{base64.b64encode(data).decode()}"))))\n'
source+='\n'+''.join(f'#|jpeg-{name}: PASS\n' for name in invalid)
(root/'check-jpeg-errors.bend').write_text(source)
print('generated',len(cases),'valid and',len(invalid),'invalid JPEG cases')
