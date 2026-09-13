# View navigation is independent of document edits and their history.
import Base
import ./state.bend as Editor
import ./svg.bend as SVG
import ./util.bend as U
import ./xml.bend as XML

def drawing() -> String:
  "<svg width='128' height='64'><rect x='32' y='16' width='32' height='32' fill='red'/></svg>"

def rectangle(x: String, y: String, width: String, height: String, color: String) -> String:
  "<rect x='" ++ x ++ "' y='" ++ y ++ "' width='" ++ width ++ "' height='" ++ height ++ "' fill='" ++ color ++ "'/>"

def equal(s: Editor.State, body: String) -> String:
  U.choose(String, U.string.equal(Editor.frame(s), SVG.ppm(64, 64, SVG.document(XML.parse("<svg>" ++ body ++ "</svg>"), 64.0, 64.0), 4)), "PASS", "FAIL")

def same(+a: Editor.State, +b: Editor.State) -> String:
  U.choose(String, U.string.equal(Editor.frame(a), Editor.frame(b)) && U.string.equal(Editor.get.source(a), Editor.get.source(b)), "PASS", "FAIL")

def stroke(effect: String) -> Editor.State:
  Editor.load("<svg width='128' height='64'><path d='M32 32H96' stroke='red' stroke-width='4' " ++ effect ++ "/></svg>", 64, 64)

def main() -> IO(Unit):
  +start = Editor.load(drawing(), 64, 64)
  +zoomed = Editor.apply(start, Editor.key(43))
  +panned = Editor.apply(start, Editor.key(104))
  +picked = Editor.apply(Editor.apply(panned, Editor.Press{56, 32}), Editor.Release{})
  +moved = Editor.apply(Editor.apply(Editor.apply(panned, Editor.Press{56, 32}), Editor.Drag{60, 36}), Editor.Release{})
  +painted = Editor.apply(Editor.apply(Editor.apply(start, Editor.Press{20, 28}), Editor.Release{}), Editor.Property{"fill", "blue"})
  +resized = Editor.apply(start, Editor.Source{"<svg width='256' height='128'><rect width='100%' height='100%' fill='red'/></svg>"})
  do IO<Unit>:
    Unit <- IO.print(equal(start, rectangle("16", "24", "16", "16", "red")))
    Unit <- IO.print(equal(zoomed, rectangle("12", "22", "20", "20", "red")))
    Unit <- IO.print(same(Editor.apply(zoomed, Editor.key(45)), start))
    Unit <- IO.print(equal(panned, rectangle("48", "24", "16", "16", "red")))
    Unit <- IO.print(equal(Editor.apply(picked, Editor.Property{"fill", "blue"}), rectangle("48", "24", "16", "16", "blue")))
    Unit <- IO.print(equal(moved, rectangle("52", "28", "16", "16", "red")))
    Unit <- IO.print(same(Editor.undo(moved), panned))
    Unit <- IO.print(equal(Editor.apply(picked, Editor.key(63235)), rectangle("49", "24", "16", "16", "red")))
    Unit <- IO.print(equal(Editor.apply(start, Editor.key(48)), rectangle("32", "16", "32", "32", "red")))
    Unit <- IO.print(same(Editor.apply(Editor.apply(panned, Editor.key(43)), Editor.key(102)), start))
    Unit <- IO.print(same(Editor.undo(Editor.apply(painted, Editor.key(43))), zoomed))
    Unit <- IO.print(equal(resized, rectangle("0", "16", "128", "64", "red")))
    Unit <- IO.print(same(Editor.undo(resized), start))
    Unit <- IO.print(equal(stroke(""), rectangle("16", "31", "32", "2", "red")))
    IO.print(equal(stroke("vector-effect='non-scaling-stroke'"), rectangle("16", "30", "32", "4", "red")))

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
#|PASS
#|PASS
#|PASS
#|PASS
#|PASS
