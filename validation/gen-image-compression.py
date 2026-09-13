from pathlib import Path
import zlib,struct,base64,random,json
root=Path(__file__).resolve().parent.parent
rng=random.Random(572);w=h=24
raw=b''.join(b'\0'+bytes(v for x in range(w)for v in (rng.randrange(12)*20,rng.randrange(12)*20,rng.randrange(12)*20,128 if(x+y)%4==0 else 255))for y in range(h))
def chunk(k,d):return struct.pack('>I',len(d))+k+d+struct.pack('>I',zlib.crc32(k+d))
rows=[];svg='<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">\n'
for i,(name,level,strategy,multi)in enumerate([('dynamic',6,0,False),('stored',0,0,False),('fixed',6,zlib.Z_FIXED,False),('multiple-blocks',6,0,True)]):
 c=zlib.compressobj(level,zlib.DEFLATED,15,8,strategy)
 data=c.compress(raw[:len(raw)//2])+c.flush(zlib.Z_SYNC_FLUSH)+c.compress(raw[len(raw)//2:])+c.flush()if multi else c.compress(raw)+c.flush()
 rows.append({'name':name,'firstBlockType':(data[2]>>1)&3,'compressedBytes':len(data)})
 png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>II5B',w,h,8,6,0,0,0))+chunk(b'IDAT',data)+chunk(b'IEND',b'')
 svg+=f'<image href="data:image/png;base64,{base64.b64encode(png).decode()}" x="{3+(i%2)*32}" y="{3+(i//2)*32}" width="24" height="24"/>\n'
assert rows[0]['firstBlockType']==2 and rows[1]['firstBlockType']==0 and rows[2]['firstBlockType']==1
(root/'fixtures/images-compression.svg').write_text(svg+'</svg>\n');(root/'validation/image-compression-inputs.json').write_text(json.dumps(rows,indent=2)+'\n');print(rows)
