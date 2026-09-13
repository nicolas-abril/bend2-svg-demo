# Expected frames from the shared reducer, for native event-adapter validation.
import Base
import ../state.bend as Editor

def output(+dir: String, +name: String, +s: Editor.State) -> IO(Unit):
  do IO<Unit>:
    Unit <- Editor.write(dir ++ "/native-camera-" ++ name ++ "-expected.ppm", Editor.frame(s))
    Editor.write(dir ++ "/native-camera-" ++ name ++ "-expected.svg", Editor.get.source(s))

def frames(+dir: String) -> IO(Unit):
  +start = Editor.load("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"512\" height=\"256\"><rect id=\"box\" x=\"64\" y=\"64\" width=\"128\" height=\"96\" fill=\"#c43\"/><circle cx=\"400\" cy=\"128\" r=\"48\" fill=\"#29a\"/></svg>", 256, 256)
  +zoomed = Editor.apply(start, Editor.key(43))
  +panned = Editor.apply(start, Editor.key(104))
  +picked = Editor.apply(Editor.apply(panned, Editor.Press{80, 110}), Editor.Release{})
  do IO<Unit>:
    Unit <- output(dir, "start", start)
    Unit <- output(dir, "zoom", zoomed)
    Unit <- output(dir, "actual", Editor.apply(start, Editor.key(48)))
    Unit <- output(dir, "pan", panned)
    Unit <- output(dir, "up", Editor.apply(panned, Editor.key(107)))
    Unit <- output(dir, "paint", Editor.apply(picked, Editor.key(98)))
    Unit <- output(dir, "nudge", Editor.apply(picked, Editor.key(63235)))
    Unit <- output(dir, "drag", Editor.apply(Editor.apply(Editor.apply(panned, Editor.Press{80, 110}), Editor.Drag{84, 114}), Editor.Release{}))
    output(dir, "delete", Editor.apply(picked, Editor.Delete{}))

def main() -> IO(Unit):
  do IO<Unit>:
    dir : String <- IO.try(String, IO.get_env("SVG_VALIDATION_OUTPUT"))
    frames(dir)
