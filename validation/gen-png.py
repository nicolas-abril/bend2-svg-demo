from pathlib import Path
import zlib,struct,base64
root=Path(__file__).resolve().parent.parent
pack=lambda n:struct.pack('>I',n)
def chunk(name,data):return pack(len(data))+name+data+pack(zlib.crc32(name+data))
def paeth(a,b,c):
 p=a+b-c;pa,pb,pc=abs(p-a),abs(p-b),abs(p-c)
 return a if pa<=pb and pa<=pc else b if pb<=pc else c
passes=[(0,0,8,8),(4,0,8,8),(0,4,4,8),(2,0,4,4),(0,2,2,4),(1,0,2,2),(0,1,1,2)]
def make(kind,depth,interlace,w=9,h=7):
 channels={0:1,2:3,3:1,4:2,6:4}[kind];top=(1<<depth)-1;pal=[(240,40,60),(20,180,90),(50,80,230),(250,220,20)][:min(4,1<<depth)];palalpha=[0,96,255,180][:len(pal)]
 pixels=[];expected=bytearray()
 for y in range(h):
  row=[]
  for x in range(w):
   vals=[((x*7+y*11+c*5)%(top+1)) for c in range(channels)]
   if kind==3:vals=[(x+y)%len(pal)];r,g,b=pal[vals[0]];a=palalpha[vals[0]];rgba=[r*257,g*257,b*257,a*257]
   elif kind==0:gray=vals[0];rgba=[gray*65535//top]*3+[0 if gray==0 else 65535]
   elif kind==2:rgba=[v*65535//top for v in vals]+[0 if vals==[0,5% (top+1),10%(top+1)] else 65535]
   elif kind==4:rgba=[vals[0]*65535//top]*3+[vals[1]*65535//top]
   else:rgba=[v*65535//top for v in vals]
   row.append(vals);expected.extend(struct.pack('>4H',*rgba))
  pixels.append(row)
 raw=bytearray();bpp=max(1,channels*depth//8)
 for px,py,dx,dy in passes if interlace else [(0,0,1,1)]:
  if px>=w or py>=h:continue
  prev=None
  for yy,y in enumerate(range(py,h,dy)):
   samples=sum([pixels[y][x] for x in range(px,w,dx)],[]);buf=bytearray()
   if depth==16:buf.extend(b''.join(struct.pack('>H',v)for v in samples))
   elif depth==8:buf.extend(samples)
   else:
    for start in range(0,len(samples),8//depth):
     word=0
     for i,v in enumerate(samples[start:start+8//depth]):word|=v<<(8-depth*(i+1))
     buf.append(word)
   f=yy%5;raw.append(f)
   for i,v in enumerate(buf):
    a=buf[i-bpp] if i>=bpp else 0;b=prev[i] if prev else 0;c=prev[i-bpp]if prev and i>=bpp else 0
    pred=[0,a,b,(a+b)//2,paeth(a,b,c)][f];raw.append((v-pred)%256)
   prev=buf
 ihdr=pack(w)+pack(h)+bytes([depth,kind,0,0,interlace]);png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',ihdr)
 if kind==3:png+=chunk(b'PLTE',bytes(sum((list(p) for p in pal),[])))+chunk(b'tRNS',bytes(palalpha))
 elif kind==0:png+=chunk(b'tRNS',struct.pack('>H',0))
 elif kind==2:png+=chunk(b'tRNS',struct.pack('>3H',0,5%(top+1),10%(top+1)))
 png+=chunk(b'tEXt',b'Test\0Bend PNG decoder')
 compressed=zlib.compress(raw);cut=len(compressed)//2;png+=chunk(b'IDAT',compressed[:cut])+chunk(b'IDAT',compressed[cut:])+chunk(b'IEND',b'')
 return png,bytes(expected)
rows=[]
for kind,depths in [(0,[1,2,4,8,16]),(2,[8,16]),(3,[1,2,4,8]),(4,[8,16]),(6,[8,16])]:
 for depth in depths:
  for interlace in [0,1]:
   png,expected=make(kind,depth,interlace);rows.append((f'png-{kind}-{depth}-{interlace}',png,expected,9,7))
png,expected=make(6,8,1,1,1);rows.append(('png-tiny-adam7',png,expected,1,1))
base=rows[-1][1];bad=bytearray(base);bad[29]^=1;rows+=[('png-bad-crc',bytes(bad),b'',0,0),('png-truncated',base[:-8],b'',0,0)]
s='''import Base
import ./svg.bend as SVG

def close(+a: F32, b: F32) -> Bool:
  F32.is_lt(F32.abs((a - b : F32)), 0.00002)

def pixel(c: SVG.Color, +expected: SVG.Bytes, +at: U32) -> Bool:
  SVG.Color{r, g, b, a} = c
  +alpha = (U32.to_f32(SVG.bytes.be(expected, (at + 6 : U32), 2n, 0)) / 65535.0 : F32)
  close(a, alpha) && close(r, (U32.to_f32(SVG.bytes.be(expected, at, 2n, 0)) / 65535.0 * alpha : F32)) && close(g, (U32.to_f32(SVG.bytes.be(expected, (at + 2 : U32), 2n, 0)) / 65535.0 * alpha : F32)) && close(b, (U32.to_f32(SVG.bytes.be(expected, (at + 4 : U32), 2n, 0)) / 65535.0 * alpha : F32))

def pixels(n: Nat, +index: U32, +w: U32, +raster: SVG.Raster, +expected: SVG.Bytes) -> Bool:
  match n:
    case 0n: True{}
    case 1n+d: pixel(SVG.raster.pixel(raster, U32.to_f32(U32.mod(index, w)), U32.to_f32(U32.div(index, w))), expected, (index * 8 : U32)) && pixels(d, U32.inc(index), w, raster, expected)

def check(+raster: SVG.Raster, expected: SVG.Bytes, +w: U32, +h: U32) -> String:
  SVG.Raster{origin, step, width, height, depth, linear, image} = raster
  SVG.choose(String, U32.is_eq(width, w) && U32.is_eq(height, h) && pixels(U32.to_nat((w * h : U32)), 0, w, raster, expected), "PASS", "FAIL")

def main() -> IO(Unit):
  do IO<Unit>:
'''
for i,(name,png,expected,w,h) in enumerate(rows):
 b64=lambda b:base64.b64encode(b).decode()
 s+=('    Unit <- 'if i<len(rows)-1 else'    ')+f'IO.print("{name}: " ++ check(SVG.png.decode(SVG.base64("{b64(png)}")), SVG.base64("{b64(expected)}"), {w}, {h}))\n'
s+='\n'+''.join(f'#|{name}: PASS\n'for name,*_ in rows);(root/'check-png.bend').write_text(s)
# Reference-renderer fixture covers the same legal PNG formats at native size.
svg='<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64"><g image-rendering="pixelated">\n'
for i,(name,png,expected,w,h)in enumerate(rows[:30]):
 uri='data:image/png;base64,'+base64.b64encode(png).decode();svg+=f'<image href="{uri}" x="{2+(i%6)*10}" y="{2+(i//6)*12}" width="9" height="7"/>\n'
svg+='</g></svg>\n';(root/'fixtures/images-png-formats.svg').write_text(svg)
