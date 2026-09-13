import Base
import ./svg.bend as SVG
import ./util.bend as U
import ./xml.bend as XML
import ./font.bend as Font
import ./state.bend as Editor

def yes(b: Bool) -> IO(Unit):
  IO.print(U.choose(String, b, "True", "False"))

def owner(found: Maybe<&2, XML.Element>) -> String:
  match found:
    case None{}: ""
    case Some{XML.Element{n, as, kids, txt}}: XML.attr.get(as, "#editor-id", "")

def main() -> IO(Unit):
  +book = Font.font.parse("g|0:65|600 1 1 0|M0 0H500V700H0Z\n", Font.font.empty())
  +source = {"<svg><defs><path id=\"p\" d=\"M2 16H62\"/></defs><text id=\"label\" font-size=\"10\" fill=\"red\"><textPath href=\"#p\">A</textPath></text></svg>" : String}
  +expected = owner(XML.element.find(Con{XML.parse(source), Nil{}}, "label"))
  +s = Editor.release(Editor.press(Editor.load.fonts(source, 64, 32, book), SVG.Point{4.0, 12.0}))
  +moved = Editor.apply(s, Editor.Translate{4.0, 0.0})
  +restored = Editor.apply(moved, Editor.Undo{})
  do IO<Unit>:
    Unit <- yes(String.eq(Editor.get.selected(s), expected))
    Unit <- yes(U.string.contains(Editor.get.source(moved), "href=\"#p\""))
    Unit <- IO.print(U32.show(SVG.pixel(Editor.get.scene(moved), 4, 12, 1)))
    Unit <- IO.print(U32.show(SVG.pixel(Editor.get.scene(moved), 8, 12, 1)))
    Unit <- yes(String.eq(Editor.get.source(s), Editor.get.source(restored)))
    IO.print(U32.show(SVG.pixel(Editor.get.scene(restored), 4, 12, 1)))

#|True
#|True
#|16777215
#|16711680
#|True
#|16711680
