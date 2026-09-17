# Resizing changes only the view and its picking transform, never saved edits.
import Base
import ./state.bend as E
import ./util.bend as U

def drawing() -> String:
  "<svg width='64' height='64'><rect id='box' x='8' y='8' width='24' height='24'/></svg>"

def same(+a: E.State, +b: E.State) -> String:
  U.choose(String, U.string.equal(E.frame(a), E.frame(b)) && U.string.equal(E.get.source(a), E.get.source(b)), "PASS", "FAIL")

def source(+a: E.State, +b: E.State) -> String:
  U.choose(String, U.string.equal(E.get.source(a), E.get.source(b)), "PASS", "FAIL")

def main() -> IO(Unit):
  +initial = E.load(drawing(), 64, 64)
  +selected = E.apply(E.apply(initial, E.Press{12, 12}), E.Release{})
  +resized = E.apply(selected, E.input("resize\n128 64"))
  +painted = E.apply(resized, E.Property{"fill", "red"})
  +moved = E.apply(E.apply(E.apply(resized, E.Press{44, 12}), E.Drag{48, 16}), E.Release{})
  +dragging = E.apply(E.apply(initial, E.Press{12, 12}), E.Drag{16, 16})
  do IO<Unit>:
    Unit <- IO.print(same(resized, E.load(drawing(), 128, 64)))
    Unit <- IO.print(source(resized, initial))
    Unit <- IO.print(same(E.apply(resized, E.Resize{64, 64}), initial))
    Unit <- IO.print(same(E.undo(painted), resized))
    Unit <- IO.print(same(E.undo(moved), resized))
    Unit <- IO.print(source(E.apply(resized, E.key(63235)), E.apply(selected, E.key(63235))))
    Unit <- IO.print(source(E.apply(E.apply(selected, E.Resize{128, 128}), E.Translate{2.0, 0.0}), E.apply(selected, E.Translate{1.0, 0.0})))
    Unit <- IO.print(same(E.undo(E.apply(dragging, E.Resize{128, 64})), resized))
    Unit <- IO.print(same(E.apply(resized, E.Resize{0, 64}), resized))
    IO.print(same(E.apply(resized, E.Resize{4097, 64}), resized))

#|PASS
#|PASS
#|PASS
#|PASS
#|PASS
#|PASS
#|PASS
#|PASS
#|PASS
#|PASS
