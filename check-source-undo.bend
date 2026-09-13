import Base
import ./state.bend as Editor
import ./svg.bend as SVG
import ./util.bend as U

def ok(value: Bool) -> String:
  U.choose(String, value, "PASS", "FAIL")

def same(+a: Editor.State, +b: Editor.State) -> Bool:
  U.string.equal(Editor.get.source(a), Editor.get.source(b)) && U.string.equal(Editor.frame(a), Editor.frame(b))

def replacement() -> String:
  "<svg width='16' height='16'><title>é &amp; 🙂</title><rect x='8' y='2' width='6' height='10' fill='green'/></svg>"

def main() -> IO(Unit):
  +start = Editor.load("<svg width='16' height='16'><rect x='2' y='2' width='6' height='10' fill='red'/></svg>", 16, 16)
  +painted = Editor.apply(Editor.apply(Editor.apply(start, Editor.Press{4, 4}), Editor.Release{}), Editor.Property{"fill", "blue"})
  +changed = Editor.apply(painted, Editor.input("source\n" ++ replacement()))
  +unchanged = Editor.apply(painted, Editor.Source{Editor.get.source(painted)})
  +drag = Editor.apply(Editor.apply(start, Editor.Press{4, 4}), Editor.Drag{6, 5})
  +afterDrag = Editor.apply(drag, Editor.Source{replacement()})
  +opened = Editor.apply(painted, Editor.Load{replacement()})
  do IO<Unit>:
    Unit <- IO.print(ok(Bool.not(U.string.equal(Editor.frame(changed), Editor.frame(painted)))))
    Unit <- IO.print(ok(same(Editor.undo(changed), painted)))
    Unit <- IO.print(ok(same(Editor.undo(Editor.undo(changed)), start)))
    Unit <- IO.print(ok(same(Editor.undo(unchanged), start)))
    Unit <- IO.print(ok(String.eq(Editor.get.selected(changed), "")))
    Unit <- IO.print(ok(U32.is_eq(Editor.quality(changed), 4)))
    Unit <- IO.print(ok(same(Editor.undo(afterDrag), Editor.release(drag))))
    Unit <- IO.print(ok(same(Editor.undo(Editor.undo(afterDrag)), start)))
    IO.print(ok(same(Editor.undo(opened), opened)))

#|PASS
#|PASS
#|PASS
#|PASS
#|PASS
#|PASS
#|PASS
#|PASS
#|PASS
