from pathlib import Path
import zlib,struct,base64
root=Path(__file__).resolve().parent.parent
pack=lambda n:struct.pack('>I',n)
def chunk(k,d):return pack(len(d))+k+d+pack(zlib.crc32(k+d))
w,h=8,6
raw=b''.join(b'\0'+bytes(v for x in range(w)for v in ((230 if x<4 else 40),(60 if y<3 else 190),(40 if x<4 else 220),(255 if (x+y)%4 else 128)))for y in range(h))
png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',pack(w)+pack(h)+bytes([8,6,0,0,0]))+chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b'')
uri='data:image/png;base64,'+base64.b64encode(png).decode()
head='<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="64" height="64" viewBox="0 0 64 64">\n'
def image(attrs='',href='href'):return f'<image {href}="{uri}" {attrs}/>'
def save(name,body):(root/'fixtures'/f'images-{name}.svg').write_text(head+body+'\n</svg>\n')
save('basic','\n'.join([image('x="3" y="3" width="24" height="18" image-rendering="pixelated"'),image('x="36" y="3" width="24" height="18"'),image('x="3" y="35" width="24" height="18" fill="none" stroke="black" stroke-width="4" fill-opacity="0"'),image('x="36" y="35" width="24" height="18" opacity=".6"','xlink:href')]))
save('aspect','\n'.join([f'<rect x="{x}" y="{y}" width="18" height="22" fill="#eee"/>'+image(f'x="{x}" y="{y}" width="18" height="22" preserveAspectRatio="{aspect}" image-rendering="pixelated"')for x,y,aspect in [(2,2,'xMinYMin meet'),(23,2,'xMidYMid meet'),(44,2,'xMaxYMax meet'),(2,36,'xMidYMid slice'),(23,36,'none')]])+'\n'+image('x="44" y="36" width="18" image-rendering="pixelated"')+'\n'+image('x="44" y="52" image-rendering="pixelated"'))
save('compositing','''<defs><clipPath id="c"><circle cx="15" cy="15" r="10"/></clipPath><linearGradient id="g"><stop stop-color="white"/><stop offset="1" stop-color="black"/></linearGradient><mask id="m"><rect x="35" y="4" width="24" height="20" fill="url(#g)"/></mask><filter id="f"><feColorMatrix type="saturate" values="0"/></filter><pattern id="p" width="12" height="9" patternUnits="userSpaceOnUse">'''+image('width="12" height="9" image-rendering="pixelated"')+'''</pattern></defs>\n'''+image('x="3" y="6" width="24" height="18" clip-path="url(#c)"')+'\n'+image('x="35" y="6" width="24" height="18" mask="url(#m)"')+'\n'+image('x="3" y="36" width="24" height="18" filter="url(#f)"')+'\n<rect x="35" y="35" width="24" height="24" fill="url(#p)"/>')
save('transforms','''<style>.nearest{image-rendering:pixelated}</style><g transform="translate(16 16) rotate(22)">'''+image('x="-10" y="-8" width="20" height="16" preserveAspectRatio="none"')+'</g><g class="nearest" transform="translate(46 16) rotate(-18)">'+image('x="-10" y="-8" width="20" height="16" preserveAspectRatio="none"')+'</g><g transform="translate(5 36) skewX(22)">'+image('width="20" height="15"')+'</g>'+image('x="55%" y="60%" width="36%" height="25%" preserveAspectRatio="none"'))
percent='data:image/png,'+''.join('%%%02X'%c for c in png)
save('uris',image('x="3" y="3" width="24" height="18"')+f'<image href="{percent}" x="36" y="3" width="24" height="18"/>'+image('x="3" y="36" width="24" height="18"','xlink:href')+f'<image href="{uri}" xlink:href="data:image/png;base64,invalid" x="36" y="36" width="24" height="18"/>')
# Small exact pixel placement regression uses one opaque red texel.
red=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',pack(1)+pack(1)+bytes([8,6,0,0,0]))+chunk(b'IDAT',zlib.compress(b'\0\xff\0\0\xff'))+chunk(b'IEND',b'')
u='data:image/png;base64,'+base64.b64encode(red).decode()
s='''import Base
import ./svg.bend as SVG

def main() -> IO(Unit):
  +scene = SVG.document(SVG.parse("<svg width='16' height='16'><image href='''+'"'+"'"+u+"' x='2' y='3' width='4' height='6' preserveAspectRatio='none' fill='none' fill-opacity='0'/></svg>"+'"'+'''), 16.0, 16.0)
  do IO<Unit>:
    Unit <- IO.print(U32.show(SVG.pixel(scene, 2, 3, 4)))
    Unit <- IO.print(U32.show(SVG.pixel(scene, 5, 8, 4)))
    Unit <- IO.print(U32.show(SVG.pixel(scene, 1, 3, 4)))
    IO.print(U32.show(SVG.pixel(scene, 6, 8, 4)))

#|16711680
#|16711680
#|16777215
#|16777215
'''
# Keep the SVG in one Bend string literal.
s=s.replace("href=\"'", "href='")
(root/'check-images.bend').write_text(s)
