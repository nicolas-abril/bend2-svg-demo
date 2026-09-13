from pathlib import Path
import json,base64
root=Path(__file__).resolve().parent.parent
cases={c['name']:c for c in json.loads((root/'validation/jpeg-cases.json').read_text())}
head='<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="64" height="64" viewBox="0 0 64 64">\n'
def image(name,attrs='',percent=False,xlink=False):
 data=cases[name]['jpeg'];uri='data:image/jpeg;base64,'+data if not percent else 'data:image/jpeg,'+''.join('%%%02X'%v for v in base64.b64decode(data))
 return f'<image {"xlink:href" if xlink else "href"}="{uri}" {attrs}/>'
features={}
def save(name,body,items):
 (root/'fixtures'/f'jpeg-{name}.svg').write_text(head+body+'\n</svg>\n')
 features[f'jpeg-{name}.svg']={'reference':'chromium','features':items}
for group,names in [('sequential',['gray','444','422','420']),('progressive',['progressive-gray','progressive-444','progressive-422','progressive-420']),('color',['rgb','cmyk','ycck','progressive-cmyk']),('encoding',['restart','progressive-restart','quant16','huffman16'])]:
 save(group,'\n'.join(image(name,f'x="{4 if i%2==0 else 36}" y="{5 if i<2 else 37}"')for i,name in enumerate(names)),['embedded JPEG '+n for n in names])
save('uris',image('444','x="4" y="5"')+image('444','x="36" y="5"',percent=True)+image('progressive-420','x="4" y="37"',xlink=True)+image('separate','x="36" y="37"'),['JPEG base64 and percent data URIs','xlink:href JPEG','separate sequential scans'])
save('compositing','''<defs><clipPath id="c"><circle cx="15" cy="15" r="10"/></clipPath><linearGradient id="g"><stop stop-color="white"/><stop offset="1" stop-color="black"/></linearGradient><mask id="m"><rect x="35" y="4" width="24" height="20" fill="url(#g)"/></mask><filter id="f"><feColorMatrix type="saturate" values="0"/></filter><pattern id="p" width="12" height="10" patternUnits="userSpaceOnUse">'''+image('progressive-420','width="12" height="10" preserveAspectRatio="none"')+'''</pattern></defs>\n'''+image('420','x="3" y="6" width="24" height="18" clip-path="url(#c)"')+image('444','x="35" y="6" width="24" height="18" mask="url(#m)"')+image('progressive-444','x="3" y="36" width="24" height="18" filter="url(#f)"')+'<rect x="35" y="35" width="24" height="24" fill="url(#p)"/>',['JPEG scaling and intrinsic aspect ratio','JPEG clipping and mask','JPEG filtering','JPEG inside pattern'])
coverage=json.loads((root/'validation/coverage.json').read_text());coverage['fixtures'].update(features)
note=' Embedded JPEG fixtures use Chromium, retaining resvg alternate comparisons. Standalone JPEG decoder probes also compare every pixel against Pillow/libjpeg.'
if note not in coverage['referencePolicy']: coverage['referencePolicy']+=note
(root/'validation/coverage.json').write_text(json.dumps(coverage,indent=2)+'\n')
