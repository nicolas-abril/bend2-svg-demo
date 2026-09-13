# Validation-only glyph positions; uses the same Bend layout as the application.
import Base
import ../svg.bend as SVG
import ../state.bend as Editor

def row(+as: List<&2, SVG.Attr>, m: SVG.Matrix) -> String:
  SVG.Matrix{a, b, c, d, e, f} = m
  SVG.attr.get(as, "#text-index", "") ++ "|" ++ F32.show(e) ++ "|" ++ F32.show(f) ++ "|" ++ F32.show(a) ++ "|" ++ F32.show(b) ++ "|" ++ SVG.attr.get(as, "#glyph-advance", "0") ++ "\n"

def rows(xs: List<&2, SVG.Element>) -> String:
  match xs:
    case Nil{}: ""
    case Con{SVG.Element{n, as, kids, txt}, rest}:
      +attrs = as
      SVG.branch(String, String.eq(n, "#glyph"), _ => row(attrs, SVG.transform(SVG.attr.get(attrs, "#glyph-transform", ""), SVG.identity())), _ => "") ++ rows(kids) ++ rows(rest)

def layout(doc: SVG.Element, book: SVG.FontBook) -> String:
  SVG.Element{n, as, kids, txt} = doc
  +children = kids
  +styled = SVG.css.tree(children, SVG.css.rules(SVG.css.sheets(children, 128.0, 128.0), 128.0, 128.0), Nil{}, Nil{}, 1, SVG.css.element.count(children))
  +used = SVG.use.expand(64n, styled, styled, Nil{})
  rows(SVG.text.expand(SVG.text.path.resolve(used, used, 128.0, 96.0, True{}), SVG.text.font.default(book), 128.0, 96.0, True{}))

def main() -> IO(Unit):
  do IO<Unit>:
    book : SVG.FontBook <- Editor.read.fonts()
    path : String <- IO.try(String, IO.get_env("SVG_INPUT"))
    source : String <- Editor.read(path)
    IO.write(layout(SVG.parse(source), book))
