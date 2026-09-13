import Base
import ./state.bend as Editor

def main() -> IO(Unit):
  +start = Editor.load("<svg><rect width='20' height='20' fill='red'/></svg>", 64, 64)
  +clicked = Editor.apply(Editor.apply(Editor.apply(start, Editor.Press{5, 5}), Editor.Drag{5, 5}), Editor.Release{})
  +painted = Editor.apply(clicked, Editor.Property{"fill", "blue"})
  +again = Editor.apply(Editor.apply(painted, Editor.Press{5, 5}), Editor.Release{})
  +returned = Editor.apply(Editor.apply(Editor.apply(Editor.apply(start, Editor.Press{5, 5}), Editor.Drag{10, 5}), Editor.Drag{5, 5}), Editor.Release{})
  +moved = Editor.apply(Editor.apply(Editor.apply(start, Editor.Press{5, 5}), Editor.Drag{10, 5}), Editor.Release{})
  do IO<Unit>:
    Unit <- IO.print(Editor.get.source(clicked))
    Unit <- IO.print(Editor.get.source(Editor.apply(again, Editor.Undo{})))
    Unit <- IO.print(Editor.get.source(returned))
    IO.print(Editor.get.source(Editor.apply(moved, Editor.Undo{})))

#|<svg><rect fill="red" height="20" width="20"></rect></svg>
#|<svg><rect fill="red" height="20" width="20"></rect></svg>
#|<svg><rect fill="red" height="20" width="20"></rect></svg>
#|<svg><rect fill="red" height="20" width="20"></rect></svg>
