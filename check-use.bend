import Base
import ./state.bend as Editor
import ./svg.bend as SVG

def main() -> IO(Unit):
  +start = Editor.load("<svg><defs><g id='tile' transform='scale(2)'><rect width='5' height='5'/></g></defs><use href='#tile' x='4' y='4' fill='red'/><use href='#tile' x='24' y='4' fill='blue'/></svg>", 64, 64)
  +picked = Editor.apply(start, Editor.Press{5, 5})
  +moved = Editor.apply(Editor.apply(picked, Editor.Drag{15, 5}), Editor.Release{})
  +painted = Editor.apply(moved, Editor.Property{"fill", "lime"})
  do IO<Unit>:
    Unit <- IO.print(Editor.get.selected(picked))
    Unit <- IO.print(U32.show(SVG.pixel(Editor.get.scene(moved), 5, 5, 1)))
    Unit <- IO.print(U32.show(SVG.pixel(Editor.get.scene(moved), 15, 5, 1)))
    Unit <- IO.print(U32.show(SVG.pixel(Editor.get.scene(painted), 15, 5, 1)))
    Unit <- IO.print(U32.show(SVG.pixel(Editor.get.scene(painted), 25, 5, 1)))
    IO.print(Editor.get.source(painted))

#|5
#|16777215
#|16711680
#|65280
#|255
#|<svg><defs><g transform="scale(2)" id="tile"><rect height="5" width="5"></rect></g></defs><use style=";transform:matrix(1,0 0,1 10,0 );fill:lime" fill="red" y="4" x="4" href="#tile"></use><use fill="blue" y="4" x="24" href="#tile"></use></svg>
