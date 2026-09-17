import Base
import ./state.bend as Editor
import ./inspect.bend as Inspect

def value.show(value: Inspect.Value) -> String:
  Inspect.Value{text, origin} = value
  text ++ " (" ++ origin ++ ")"

def describe.selection(pick: Inspect.Selection, key: String, fallback: String, inherit: Bool) -> String:
  Inspect.Selection{tag, path} = pick
  value.show(Inspect.value(path, key, fallback, inherit))

def describe(s: Editor.State, key: String, fallback: String, inherit: Bool) -> String:
  describe.selection(Inspect.selected(s), key, fallback, inherit)

def identity.selection(pick: Inspect.Selection) -> String:
  Inspect.Selection{tag, path} = pick
  tag ++ " #" ++ Inspect.selection.id(path)

def identity(s: Editor.State) -> String:
  identity.selection(Inspect.selected(s))

def main() -> IO(Unit):
  +start = Editor.load("<svg width='64' height='64'><style>.shape {stroke-width:3;fill:green}</style><g stroke='red' fill='orange'><rect id='box' class='shape' x='4' y='4' width='20' height='20' style='fill:blue'/><rect x='30' y='4' width='20' height='20'/></g></svg>", 64, 64)
  +picked = Editor.apply(Editor.apply(start, Editor.Press{10, 10}), Editor.Release{})
  +painted = Editor.apply(picked, Editor.Property{"fill", "purple"})
  +anonymous = Editor.apply(start, Editor.Press{35, 10})
  do IO<Unit>:
    Unit <- IO.print(identity(picked))
    Unit <- IO.print(describe(picked, "fill", "black", True{}))
    Unit <- IO.print(describe(picked, "stroke", "none", True{}))
    Unit <- IO.print(describe(picked, "stroke-width", "1", True{}))
    Unit <- IO.print(describe(picked, "stroke-linecap", "butt", True{}))
    Unit <- IO.print(describe(picked, "textLength", "", False{}))
    Unit <- IO.print(describe(painted, "fill", "black", True{}))
    Unit <- IO.print(describe(Editor.apply(painted, Editor.Undo{}), "fill", "black", True{}))
    Unit <- IO.print(identity(anonymous))
    Unit <- IO.print(describe(anonymous, "fill", "black", True{}))
    Unit <- IO.print(identity(Editor.apply(picked, Editor.Delete{})))
    IO.print(Inspect.quote("a\"b\n\\"))

#|rect #box
#|blue (current)
#|red (inherited)
#|3 (current)
#|butt (default)
#| (example)
#|purple (current)
#|blue (current)
#|rect #
#|orange (inherited)
#| #
#|"a\"b\u000a\\"
