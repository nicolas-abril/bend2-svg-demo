"""Convert OFL fonts to an ASCII data asset. The app parses and renders this data in Bend."""
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
import json,hashlib
root=Path(__file__).resolve().parent.parent
source=root/'validation/fonts'
rows=[];meta=[];metric_rows=[]
for face,style in enumerate(['Regular','Bold','Italic','BoldItalic']):
 path=source/f'NotoSans-{style}.ttf';f=TTFont(path);gs=f.getGlyphSet();cm=f.getBestCmap();gids=f.getReverseGlyphMap();specific,classes=f['GPOS'].table.LookupList.Lookup[2].SubTable
 left=classes.ClassDef1.classDefs;right=classes.ClassDef2.classDefs;covered=set(classes.Coverage.glyphs)
 for cp,n in [('?', '.notdef'),*cm.items()]:
  p=SVGPathPen(gs);gs[n].draw(p)
  rows.append(f'g|{face}:{cp}|{f["hmtx"].metrics[n][0]} {gids[n]} {left.get(n,0)+1 if n in covered else 0} {right.get(n,0)}|{p.getCommands()}\n')
 for n,pairs in zip(specific.Coverage.glyphs,specific.PairSet):
  for pair in pairs.PairValueRecord:
   value=getattr(pair.Value1,'XAdvance',0) if pair.Value1 else 0
   rows.append(f'k|{face}:{16777216+gids[n]*4096+gids[pair.SecondGlyph]}|{value}\n')
 for i,row in enumerate(classes.Class1Record):
  for j,col in enumerate(row.Class2Record):
   value=getattr(col.Value1,'XAdvance',0) if col.Value1 else 0
   if value:rows.append(f'k|{face}:{(i+1)*128+j}|{value}\n')
 units=f['head'].unitsPerEm;os2=f['OS/2']
 metrics={key:getattr(os2,field)/units for key,field in [('subscript','ySubscriptYOffset'),('superscript','ySuperscriptYOffset'),('ascender','sTypoAscender'),('descender','sTypoDescender'),('xheight','sxHeight')]}
 for key,val in metrics.items():metric_rows.append(f'm|{face}:{key}|{val}\n')
 meta.append({'metrics':metrics,'file':path.name,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'unicodeMappings':len(cm),'unitsPerEm':f['head'].unitsPerEm,'version':f['name'].getDebugName(5),'source':'https://github.com/notofonts/noto-fonts/tree/main/hinted/ttf/NotoSans'})
data=''.join(rows+metric_rows).encode();(root/'fonts.dat').write_bytes(data)
(root/'validation/font-manifest.json').write_text(json.dumps({'generator':'fontTools 4.59.2; static outlines, horizontal GPOS pair data and OS/2 metrics','asset':'fonts.dat','assetSHA256':hashlib.sha256(data).hexdigest(),'faces':meta},indent=2)+'\n');print('Font asset bytes',len(data))
