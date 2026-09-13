import Base
import ./svg.bend as SVG
import ./util.bend as U
import ./xml.bend as XML
import ./state.bend as Editor

def yes(b: Bool) -> IO(Unit):
  IO.print(U.choose(String, b, "True", "False"))

def same.row(n: Nat, +x: U32, +y: U32, +a: List<&2, SVG.Scene<SVG.Brush>>, +b: List<&2, SVG.Scene<SVG.Brush>>) -> Bool:
  match n:
    case Zero{}: True{}
    case Succ{d}: U32.is_eq(SVG.pixel(a, x, y, 1), SVG.pixel(b, x, y, 1)) && same.row(d, U32.inc(x), y, a, b)

def same.rows(n: Nat, +y: U32, +a: List<&2, SVG.Scene<SVG.Brush>>, +b: List<&2, SVG.Scene<SVG.Brush>>) -> Bool:
  match n:
    case Zero{}: True{}
    case Succ{d}: same.row(64n, 0, y, a, b) && same.rows(d, U32.inc(y), a, b)

def main() -> IO(Unit):
  +track = XML.parse("<svg><defs><path id=\"p\" d=\"M2 16H62\"/></defs><text font-size=\"10\" fill=\"red\"><textPath href=\"#p\">Bend</textPath></text></svg>")
  +plain = XML.parse("<svg><text x=\"2\" y=\"16\" font-size=\"10\" fill=\"red\">Bend</text></svg>")
  +offset = XML.parse("<svg><defs><path id=\"p\" d=\"M2 16H62\" pathLength=\"30\"/></defs><text font-size=\"10\" fill=\"red\"><textPath href=\"#p\" startOffset=\"3\">Bend</textPath></text></svg>")
  +shifted = XML.parse("<svg><text x=\"8\" y=\"16\" font-size=\"10\" fill=\"red\">Bend</text></svg>")
  +direct = XML.parse("<svg><text font-size=\"10\" fill=\"red\"><textPath path=\"M2 16H62\">Bend</textPath></text></svg>")
  +bad = XML.parse("<svg><defs><path id=\"p\" d=\"M2 16H62\"/></defs><text font-size=\"10\"><textPath href=\"p\">Bend</textPath></text></svg>")
  do IO<Unit>:
    Unit <- yes(same.rows(32n, 0, SVG.document(track, 64.0, 32.0), SVG.document(plain, 64.0, 32.0)))
    Unit <- yes(same.rows(32n, 0, SVG.document(offset, 64.0, 32.0), SVG.document(shifted, 64.0, 32.0)))
    Unit <- yes(same.rows(32n, 0, SVG.document(direct, 64.0, 32.0), SVG.document(plain, 64.0, 32.0)))
    IO.print(U32.show(SVG.pixel(SVG.document(bad, 64.0, 32.0), 4, 12, 1)))

#|True
#|True
#|True
#|16777215
