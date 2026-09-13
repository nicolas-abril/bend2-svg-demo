from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
import re
"""Regenerate check-ttf.bend: subset NotoSans-Regular with fontTools and record what the
Bend TrueType reader must produce for it (fontTools outlines normalized to M/L/Q/Z)."""
from fontTools import subset
from pathlib import Path
import base64, io
root=Path(__file__).resolve().parent.parent
opts=subset.Options(); opts.layout_features=['kern']; opts.hinting=False; opts.glyph_names=True; opts.notdef_outline=True
f=TTFont(root/'validation/fonts/NotoSans-Regular.ttf'); sub=subset.Subsetter(opts); sub.populate(text='AVTo.,Wé'); sub.subset(f)
buf=io.BytesIO(); f.save(buf); data=buf.getvalue(); b64=base64.b64encode(data).decode()
f=TTFont(io.BytesIO(data)); gs=f.getGlyphSet(); cm=f.getBestCmap(); gids=f.getReverseGlyphMap()
def num(v):
    v=float(v); return str(int(v)) if v.is_integer() else repr(v)
def normalize(cmds):
    out=''; cx=cy=sx=sy=0.0
    for m in re.finditer(r'([MLHVQCZ])([^MLHVQCZ]*)', cmds):
        c=m.group(1); nums=[float(x) for x in re.findall(r'-?\d+\.?\d*', m.group(2))]
        if c=='M':
            cx,cy=nums[0],nums[1]; sx,sy=cx,cy; out+='M'+num(cx)+' '+num(cy)
            for k in range(2,len(nums),2): cx,cy=nums[k],nums[k+1]; out+='L'+num(cx)+' '+num(cy)
        elif c=='L':
            for k in range(0,len(nums),2): cx,cy=nums[k],nums[k+1]; out+='L'+num(cx)+' '+num(cy)
        elif c=='H':
            for x in nums: cx=x; out+='L'+num(cx)+' '+num(cy)
        elif c=='V':
            for y in nums: cy=y; out+='L'+num(cx)+' '+num(cy)
        elif c=='Q':
            for k in range(0,len(nums),4): out+='Q'+num(nums[k])+' '+num(nums[k+1])+' '+num(nums[k+2])+' '+num(nums[k+3]); cx,cy=nums[k+2],nums[k+3]
        elif c=='Z': out+='Z'; cx,cy=sx,sy
        else: raise Exception(c)
    return out
lk=f['GPOS'].table.LookupList.Lookup; pair=[l for l in lk if l.LookupType==2][0]
cl=[s for s in pair.SubTable if s.Format==2]; sp=[s for s in pair.SubTable if s.Format==1]
left=cl[0].ClassDef1.classDefs if cl else {}; right=cl[0].ClassDef2.classDefs if cl else {}; cov=set(cl[0].Coverage.glyphs) if cl else set()
kern={}
if cl:
    c=cl[0]
    for i,row in enumerate(c.Class1Record):
        for j,col in enumerate(row.Class2Record):
            v=getattr(col.Value1,'XAdvance',0) if col.Value1 else 0
            if v: kern[(i+1)*128+j]=v
for s in sp:
    for n,ps in zip(s.Coverage.glyphs, s.PairSet):
        for r in ps.PairValueRecord: kern[16777216+gids[n]*4096+gids[r.SecondGlyph]]=getattr(r.Value1,'XAdvance',0) if r.Value1 else 0
lines=[]; calls=[]
for cp,n in [('?','.notdef'),*[(k,v) for k,v in sorted(cm.items())]]:
    p=SVGPathPen(gs); gs[n].draw(p)
    key = '?' if cp=='?' else str(cp)
    lines.append(f"g|0:{key}|{f['hmtx'].metrics[n][0]} {gids[n]} {left.get(n,0)+1 if n in cov else 0} {right.get(n,0)}|{normalize(p.getCommands())}")
    calls.append(f'    Unit <- IO.print(glyph(book, {0 if cp=="?" else cp}))')
for k,v in sorted(kern.items()):
    lines.append(f"k|0:{k}|{v}"); calls.append(f'    Unit <- IO.print(kern(book, {k}))')
os2=f['OS/2']; u=f['head'].unitsPerEm
for name,val in [('subscript',os2.ySubscriptYOffset),('superscript',os2.ySuperscriptYOffset),('ascender',os2.sTypoAscender),('descender',os2.sTypoDescender),('xheight',os2.sxHeight)]:
    lines.append(f"m|0:{name}|{num(val/u)}"); calls.append(f'    Unit <- IO.print(metric(book, "{name}"))')
calls[-1]=calls[-1].replace('    Unit <- ','    ')
src=f'''import Base
import ./util.bend as U
import ./bin.bend as Bin
import ./font.bend as Font

# A Noto Sans subset (fontTools, "AVTo.,We" plus e-acute, kern feature kept) read
# back as a font book face; expectations come from fontTools' outlines, metrics
# and GPOS pair data, formatted like fonts.dat.
def glyph.show(+cp: U32, g: Font.FontGlyph) -> String:
  Font.FontGlyph{{advance, outline, gid, leftClass, rightClass}} = g
  "g|0:" ++ U.choose(String, U32.is_eq(cp, 0), "?", U32.show(cp)) ++ "|" ++ F32.show(advance) ++ " " ++ U32.show(gid) ++ " " ++ U32.show(leftClass) ++ " " ++ U32.show(rightClass) ++ "|" ++ outline

def glyph(+book: Font.FontBook, +cp: U32) -> String:
  glyph.show(cp, Font.font.glyph(book, 0, cp))

def kern(+book: Font.FontBook, +key: U32) -> String:
  Font.FontBook{{glyphs, kerning, metrics}} = book
  "k|0:" ++ U32.show(key) ++ "|" ++ F32.show(Font.font.number.result(Map.get(F32, 1000000.0, kerning, "0:" ++ U32.show(key))))

def metric(+book: Font.FontBook, +name: String) -> String:
  "m|0:" ++ name ++ "|" ++ F32.show(Font.font.metric(book, 0, name, 1000000.0))

def main() -> IO(Unit):
  +book = Font.font.ttf.base64(0, "{b64}", Font.font.empty())
  do IO<Unit>:
{chr(10).join(calls)}

'''+'\n'.join('#|'+l for l in lines)+'\n'
(root/'check-ttf.bend').write_text(src); print('written', len(lines), 'expectations')
