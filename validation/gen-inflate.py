from pathlib import Path
import zlib,base64,random
root=Path(__file__).resolve().parent.parent
rng=random.Random(917)
payloads=[b'',b'hello',b'a'*600,b'abcabcabcXYZ'*90,bytes(range(256))*3,bytes(rng.randrange(12)+65 for _ in range(1024))]
rows=[]
for name,data,level,strategy in [('empty',payloads[0],6,0),('stored',payloads[4],0,0),('fixed',payloads[3],6,zlib.Z_FIXED),('overlap',payloads[2],6,0),('dynamic',payloads[5],6,0)]:
 c=zlib.compressobj(level,zlib.DEFLATED,-15,8,strategy);packed=c.compress(data)+c.flush();rows.append((name,packed,data,True,8192));print(name,'block type',(packed[0]>>1)&3,'bytes',len(packed))
c=zlib.compressobj(6,zlib.DEFLATED,-15);packed=c.compress(b'first block')+c.flush(zlib.Z_SYNC_FLUSH)+c.compress(payloads[5])+c.flush();rows.append(('blocks',packed,b'first block'+payloads[5],True,8192))
rows += [('truncated',rows[4][1][:-3],b'',False,8192),('distance',b'\x03\x02',b'',False,8192),('invalid-type',b'\x07',b'',False,8192),('stored-complement',b'\x01\x01\x00\xff\xffx',b'',False,8192),('output-limit',rows[3][1],b'',False,32)]
s='''import Base
import ./svg.bend as SVG

def same(n: Nat, +at: U32, +a: SVG.Bytes, +b: SVG.Bytes) -> Bool:
  match n:
    case 0n: True{}
    case 1n+d: U32.is_eq(SVG.bytes.get(a, at), SVG.bytes.get(b, at)) && same(d, U32.inc(at), a, b)

def check(+result: SVG.Inflate, +expected: SVG.Bytes, valid: Bool) -> String:
  SVG.Inflate{stream, output} = result
  +out = output
  SVG.choose(String, SVG.choose(Bool, valid, SVG.bits.valid(stream) && U32.is_eq(SVG.bytes.size(out), SVG.bytes.size(expected)) && same(U32.to_nat(SVG.bytes.size(expected)), 0, out, expected), Bool.not(SVG.bits.valid(stream))), "PASS", "FAIL")

def main() -> IO(Unit):
  do IO<Unit>:
'''
for i,(name,data,expected,valid,limit) in enumerate(rows):
 b64=lambda b:base64.b64encode(b).decode()
 s+=('    Unit <- ' if i<len(rows)-1 else '    ')+f'IO.print("{name}: " ++ check(SVG.inflate(SVG.base64("{b64(data)}"), {limit}), SVG.base64("{b64(expected)}"), '+('True{}' if valid else 'False{}')+'))\n'
s+='\n'+''.join(f'#|{name}: PASS\n' for name,*_ in rows)
(root/'check-inflate.bend').write_text(s)
