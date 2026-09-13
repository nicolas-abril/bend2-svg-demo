import Base
import ./state.bend as Editor
import ./svg.bend as SVG

def main() -> IO(Unit):
  +start = Editor.load("<svg viewBox='0 0 64 64'><rect x='4' y='4' width='20' height='20' fill='red'/></svg>", 64, 64)
  +picked = Editor.apply(start, Editor.Press{10, 10})
  +moved = Editor.apply(Editor.apply(picked, Editor.Drag{20, 15}), Editor.Release{})
  +painted = Editor.apply(moved, Editor.Property{"fill", "blue"})
  do IO<Unit>:
    Unit <- IO.print(Editor.get.selected(picked))
    Unit <- IO.print(U32.show(SVG.pixel(Editor.get.scene(moved), 6, 6, 1)))
    Unit <- IO.print(U32.show(SVG.pixel(Editor.get.scene(painted), 20, 15, 1)))
    Unit <- IO.print(U32.show(SVG.pixel(Editor.get.scene(Editor.apply(painted, Editor.Undo{})), 20, 15, 1)))
    IO.print(Editor.get.source(painted))

#|2
#|16777215
#|255
#|16711680
#|<svg viewBox="0 0 64 64"><rect style=";transform:matrix(1,0 0,1 10,5 );fill:blue" fill="red" height="20" width="20" y="4" x="4"></rect></svg>
