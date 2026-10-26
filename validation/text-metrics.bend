# Validation-only glyph positions; uses the same Bend layout as the application.
import Base
import gralha-svg-render@0.1.0.1/svg.bend as SVG
import gralha-css-style@0.1.0.1/css.bend as CSS
import gralha-text-scan@0.1.0.1/scan.bend as U
import gralha-truetype@0.1.0.1/font.bend as Font
import gralha-xml-doc@0.1.0.1/xml.bend as XML
import ../state.bend as Editor

def row(+as: List<&2, XML.Attr>, m: SVG.Matrix) -> String:
  SVG.Matrix{a, b, c, d, e, f} = m
  XML.attr.get(as, "#text-index", "") ++ "|" ++ F32.show(e) ++ "|" ++ F32.show(f) ++ "|" ++ F32.show(a) ++ "|" ++ F32.show(b) ++ "|" ++ XML.attr.get(as, "#glyph-advance", "0") ++ "\n"

def rows(xs: List<&2, XML.Element>) -> String:
  match xs:
    case Nil{}: ""
    case Con{XML.Element{n, as, kids, txt}, rest}:
      +attrs = as
      U.branch(String, String.eq(n, "#glyph"), _ => row(attrs, SVG.transform(XML.attr.get(attrs, "#glyph-transform", ""), SVG.identity())), _ => "") ++ rows(kids) ++ rows(rest)

def layout(doc: XML.Element, book: Font.FontBook) -> String:
  XML.Element{n, as, kids, txt} = doc
  +children = kids
  +styled = CSS.css.tree(children, CSS.css.rules(CSS.css.sheets(children, 64.0, 64.0), 64.0, 64.0), Nil{}, Nil{}, 1, CSS.css.element.count(children))
  rows(SVG.text.expand(SVG.use.expand(64n, styled, styled, Nil{}), SVG.text.font.default(book), 64.0, 64.0, True{}))

def main() -> IO(Unit):
  do IO<Unit>:
    book : Font.FontBook <- Editor.read.fonts()
    path : String <- IO.try(String, IO.get_env("SVG_INPUT"))
    source : String <- Editor.read(path)
    IO.write(layout(XML.parse(source), book))
