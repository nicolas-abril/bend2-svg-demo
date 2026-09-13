import Base
import ./state.bend as Editor

def size(s: Editor.State) -> String:
  Editor.State{doc, nodes, id, inv, down, anchor, base, history, w, h, fonts, camera} = s
  U32.show(w) ++ "x" ++ U32.show(h)

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.print(Editor.wire.decode("41 20 26 20 1f600 a 42"))
    IO.print(size(Editor.apply(Editor.load("<svg/>", 64, 32), Editor.Load{"<svg><rect/></svg>"})))

#|A & 😀
#|B
#|64x32
