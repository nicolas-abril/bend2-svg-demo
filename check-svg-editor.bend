import Base
import ./svg.bend as SVG
import ./util.bend as U
import ./state.bend as Editor

def boolean(yes: Bool) -> IO(Unit):
  IO.print(U.choose(String, yes, "True", "False"))

def main() -> IO(Unit):
  +selected = Editor.release(Editor.press(Editor.load("<svg width=\"16\" height=\"16\"><image width=\"16\" height=\"16\" href=\"data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTYiIGhlaWdodD0iMTYiPjxyZWN0IHdpZHRoPSIxNiIgaGVpZ2h0PSIxNiIgZmlsbD0icmVkIi8+PC9zdmc+\"/></svg>", 16, 16), SVG.Point{8.0, 8.0}))
  +before = Editor.get.source(selected)
  +edited = Editor.apply(selected, Editor.Property{"width", "8"})
  +after = Editor.get.source(edited)
  +fitted = Editor.apply(edited, Editor.Property{"preserveAspectRatio", "none"})
  +relinked = Editor.apply(selected, Editor.Property{"href", "data:image/svg+xml,%3Csvg%20width=%2216%22%20height=%2216%22%3E%3Crect%20width=%2216%22%20height=%2216%22%20fill=%22blue%22/%3E%3C/svg%3E"})
  +restored = Editor.apply(edited, Editor.Undo{})
  do IO<Unit>:
    Unit <- boolean(Bool.not(String.eq(Editor.get.selected(selected), "")))
    Unit <- boolean(U.string.contains(after, "width:8"))
    Unit <- boolean(U.string.contains(after, "data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMTYiIGhlaWdodD0iMTYiPjxyZWN0IHdpZHRoPSIxNiIgaGVpZ2h0PSIxNiIgZmlsbD0icmVkIi8+PC9zdmc+"))
    Unit <- boolean(Bool.not(U.string.contains(after, "#svg-image")))
    Unit <- boolean(String.eq(before, Editor.get.source(restored)))
    Unit <- IO.print(U32.show(SVG.pixel(Editor.get.scene(edited), 12, 8, 1)))
    Unit <- IO.print(U32.show(SVG.pixel(Editor.get.scene(restored), 12, 8, 1)))
    Unit <- boolean(U.string.contains(Editor.get.source(fitted), "preserveAspectRatio=\"none\""))
    Unit <- IO.print(U32.show(SVG.pixel(Editor.get.scene(edited), 4, 2, 1)))
    Unit <- IO.print(U32.show(SVG.pixel(Editor.get.scene(fitted), 4, 2, 1)))
    IO.print(U32.show(SVG.pixel(Editor.get.scene(relinked), 8, 8, 1)))

#|True
#|True
#|True
#|True
#|True
#|16777215
#|16711680
#|True
#|16777215
#|16711680
#|255
