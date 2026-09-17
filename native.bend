# Native presentation adapter. Bend renders at the view's backing pixel size.
import Base
import ./state.bend as Editor
import ./inspect.bend as Inspect
import ./svg.bend as SVG
import ./util.bend as U

def canvas.present(pixels: Array<U32>, w: U32, h: U32) -> IO(Unit):
  import "./effs/canvas.c"

def canvas.poll() -> IO(String):
  import "./effs/canvas.c"

def inspector.step(info: String) -> IO(String):
  import "./effs/inspector_step.c"
  import "./effs/inspector_step.js"

def present(+s: Editor.State, dirty: Bool) -> IO(Unit):
  Editor.State{doc, nodes, id, inv, down, anchor, base, history, w, h, fonts, camera} = s
  match dirty:
    case False{}: IO.pure(Unit, Unit{})
    case True{}: canvas.present(SVG.paint.packed(nodes, w, h, Editor.quality(s)), w, h)

def command(+text: String) -> IO(String):
  U.branch(IO(String), U.string.equal(text, ""), _ => canvas.poll(), _ => IO.pure(String, text))

def save.key(save: Bool, state: Editor.State) -> IO(Unit):
  match save:
    case False{}: IO.pure(Unit, Unit{})
    case True{}: Editor.save(state)

def loop.command(+state: Editor.State, +info: String, +text: String, close: Bool,
  next: Editor.State -> String -> Bool -> IO(Unit)) -> IO(Unit):
  match close:
    case True{}:
      do IO<Unit>:
        ignored : String <- inspector.step("")
        return Unit{}
    case False{}:
      +action = Editor.input(text)
      +changed = Editor.changed(action, state)
      +updated = Editor.apply(state, action)
      do IO<Unit>:
        Unit <- save.key(U.string.equal(text, "save") || U.string.equal(text, "key\n115"), state)
        next(updated)(U.branch(String, changed, _ => Inspect.json(updated), _ => info))(changed)

def loop.text(state: Editor.State, info: String, +text: String, next: Editor.State -> String -> Bool -> IO(Unit)) -> IO(Unit):
  loop.command(state, info, text, U.string.equal(text, "close"), next)

@unsafe
def loop(+state: Editor.State, +info: String, dirty: Bool) -> IO(Unit):
  do IO<Unit>:
    Unit <- present(state, dirty)
    panel : String <- inspector.step(info)
    text : String <- command(panel)
    loop.text(state, info, text, s => i => d => loop(s, i, d))

def start(+state: Editor.State) -> IO(Unit):
  do IO<Unit>:
    text : String <- canvas.poll()
    loop.text(state, Inspect.json(state), text, s => i => d => loop(s, i, d))

def main() -> IO(Unit):
  do IO<Unit>:
    state : Editor.State <- Editor.initial()
    start(state)
