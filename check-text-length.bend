import Base
import ./svg.bend as SVG
import ./util.bend as U
import ./xml.bend as XML
import ./font.bend as Font
import ./state.bend as Editor

def metric(matrix: SVG.Matrix) -> String:
  SVG.Matrix{a, b, c, d, e, f} = matrix
  F32.show(e) ++ ":" ++ U32.show(F32.to_u32((a * 1000.0 : F32))) ++ ";"

def metrics(xs: List<&2, XML.Element>) -> String:
  match xs:
    case Nil{}: ""
    case Con{XML.Element{n, as, kids, txt}, rest}:
      U.branch(String, String.eq(n, "#glyph"), _ => metric(SVG.transform(XML.attr.get(as, "#glyph-transform", ""), SVG.identity())), _ => "") ++ metrics(kids) ++ metrics(rest)

def layout(doc: XML.Element, book: Font.FontBook) -> String:
  XML.Element{n, as, kids, txt} = doc
  metrics(SVG.text.expand(kids, SVG.text.font.default(book), 64.0, 64.0, True{}))

def run(source: String, book: Font.FontBook) -> IO(Unit):
  IO.print(layout(XML.parse("<svg font-size='10'>" ++ source ++ "</svg>"), book))

def main() -> IO(Unit):
  +book = Font.font.parse("g|0:65|600 1 0 0|M0 0H500V700H0Z\ng|0:66|600 2 0 0|M0 0H500V700H0Z\ng|0:32|300 3 0 0|\n", Font.font.empty())
  do IO<Unit>:
    Unit <- run("<text x='10' y='20' textLength='24'>AB</text>", book)
    Unit <- run("<text x='10' y='20' textLength='24' lengthAdjust='spacingAndGlyphs'>AB</text>", book)
    Unit <- run("<text x='40' y='20' textLength='24' text-anchor='middle'> AB </text>", book)
    Unit <- run("<text x='40' y='20' textLength='24' text-anchor='end' lengthAdjust='spacingAndGlyphs'>AB</text>", book)
    Unit <- run("<text x='0' y='20'>A<tspan textLength='20'>AB</tspan>B</text>", book)
    Unit <- run("<text x='0' y='20' textLength='44'>A<tspan textLength='20'>AB</tspan>B</text>", book)
    Unit <- run("<text x='0' y='20' textLength='44' lengthAdjust='spacingAndGlyphs'>A<tspan textLength='20'>AB</tspan>B</text>", book)
    Unit <- run("<text x='0' y='20' textLength='50%'>AB</text>", book)
    Unit <- run("<text x='0' y='20' textLength='-2'>AB</text>", book)
    Unit <- run("<text x='0' y='20' textLength='bad' lengthAdjust='spacingAndGlyphs'>AB</text>", book)
    Unit <- run("<text x='0' y='20' textLength='24'>A</text>", book)
    Unit <- run("<text x='0' y='20' textLength='24' lengthAdjust='spacingAndGlyphs'>A</text>", book)
    Unit <- IO.print(Editor.get.source(Editor.apply(Editor.release(Editor.press(Editor.load.fonts("<svg font-size='10'><text x='0' y='20'>AB</text></svg>", 64, 64, book), SVG.Point{1.0, 16.0})), Editor.Property{"textLength", "24"})))
    Unit <- IO.print(Editor.get.source(Editor.apply(Editor.release(Editor.press(Editor.load("<svg><path d='M0 0H20' stroke='red' stroke-width='4'/></svg>", 64, 64), SVG.Point{1.0, 1.0})), Editor.Property{"pathLength", "100"})))
    Unit <- run("<text x='40' y='20' text-anchor='end' letter-spacing='2'>AB</text>", book)
    Unit <- run("<text x='40' y='20' text-anchor='middle' letter-spacing='2'>AB</text>", book)
    IO.print(layout(XML.parse("<svg font-size='10'><text x='0' y='20' textLength='24' letter-spacing='2'>AB</text></svg>"), book))

#|10:10;28:10;
#|10:20;22:20;
#|28:10;46:10;
#|16:20;28:20;
#|0:10;6:10;20:10;26:10;
#|0:10;12:10;26:10;38:10;
#|0:20;12:10;26:10;32:20;
#|0:10;26:10;
#|0:10;6:10;
#|0:10;6:10;
#|0:10;
#|0:40;
#|<svg font-size="10"><text textLength="24" y="20" x="0">AB</text></svg>
#|<svg><path pathLength="100" stroke-width="4" stroke="red" d="M0 0H20"></path></svg>
#|26:10;34:10;
#|33:10;41:10;
#|0:10;18:10;
