# Shared application model and reducer. Frontends only deliver actions and pixels.
import Base
import ./svg.bend as SVG
import ./util.bend as U
import ./xml.bend as XML
import ./css.bend as CSS
import ./font.bend as Font
import ./bin.bend as Bin

type Camera is Data:
  Camera{matrix: SVG.Matrix}

type State is Data:
  State{document: XML.Element, scene: List<&2, SVG.Scene<SVG.Brush>>, selected: String,
    inverse: SVG.Matrix, dragging: Bool, anchor: SVG.Point, baseline: XML.Element,
    history: List<&2, XML.Element>, width: U32, height: U32, fonts: Font.FontBook, camera: Camera}

type Action is Data:
  Load{source: String}
  Source{source: String}
  Navigate{kind: U32}
  Press{x: U32, y: U32}
  Drag{x: U32, y: U32}
  Release{}
  Property{key: String, value: String}
  Translate{dx: F32, dy: F32}
  Delete{}
  Undo{}
  Nothing{}

def camera.fit.size(+size: SVG.Point, w: F32, h: F32) -> Camera:
  SVG.Point{vw, vh} = size
  Camera{SVG.document.fit.matrix(size, w, h)}

def camera.fit(doc: XML.Element, +w: F32, +h: F32) -> Camera:
  camera.fit.size(SVG.document.size(doc, w, h), w, h)

def camera.actual(doc: XML.Element, w: F32, h: F32) -> Camera:
  Camera{SVG.identity()}

def camera.render(doc: XML.Element, book: Font.FontBook, camera: Camera, w: U32, h: U32) -> List<&2, SVG.Scene<SVG.Brush>>:
  Camera{matrix} = camera
  SVG.document.natural.fonts(doc, U32.to_f32(w), U32.to_f32(h), matrix, book)

def camera.zoom(camera: Camera, factor: F32, w: F32, h: F32) -> Camera:
  Camera{SVG.Matrix{a, b, c, d, e, f}} = camera
  +old = a
  +zoom = U.clamp((old * factor : F32), 0.000001, 1000000.0)
  +ratio = (zoom / U.max(old, 0.000001) : F32)
  +cx = (w * 0.5 : F32)
  +cy = (h * 0.5 : F32)
  Camera{SVG.Matrix{zoom, (b * ratio : F32), (c * ratio : F32), (d * ratio : F32), (cx + (e - cx) * ratio : F32), (cy + (f - cy) * ratio : F32)}}

def camera.pan(camera: Camera, x: F32, y: F32) -> Camera:
  Camera{matrix} = camera
  Camera{SVG.matrix.mul(SVG.translate(x, y), matrix)}

def camera.next(+camera: Camera, +kind: U32, +doc: XML.Element, +w: F32, +h: F32) -> Camera:
  U.branch(Camera, U32.is_eq(kind, 0), _ => camera.actual(doc, w, h),
    _ => U.branch(Camera, U32.is_eq(kind, 1), _ => camera.fit(doc, w, h),
      _ => U.branch(Camera, U32.is_eq(kind, 2) || U32.is_eq(kind, 3), _ => camera.zoom(camera, U.choose(F32, U32.is_eq(kind, 2), 1.25, 0.8), w, h),
        _ => camera.pan(camera, U.choose(F32, U32.is_eq(kind, 4), 32.0, U.choose(F32, U32.is_eq(kind, 5), F32.neg(32.0), 0.0)), U.choose(F32, U32.is_eq(kind, 6), 32.0, U.choose(F32, U32.is_eq(kind, 7), F32.neg(32.0), 0.0))))))

def from.document.fonts(+doc: XML.Element, +w: U32, +h: U32, +fonts: Font.FontBook) -> State:
  +camera = camera.fit(doc, U32.to_f32(w), U32.to_f32(h))
  State{doc, camera.render(doc, fonts, camera, w, h), "", SVG.identity(), False{},
    SVG.Point{0.0, 0.0}, doc, Nil{}, w, h, fonts, camera}

def load.fonts(source: String, w: U32, h: U32, fonts: Font.FontBook) -> State:
  from.document.fonts(XML.parse(source), w, h, fonts)

def load(source: String, w: U32, h: U32) -> State:
  load.fonts(source, w, h, Font.font.empty())

def get.source(s: State) -> String:
  State{doc, scene, id, inv, down, anchor, base, history, w, h, fonts, camera} = s
  XML.serialize(doc)

def get.scene(s: State) -> List<&2, SVG.Scene<SVG.Brush>>:
  State{doc, nodes, id, inv, down, anchor, base, history, w, h, fonts, camera} = s
  nodes

def get.selected(s: State) -> String:
  State{doc, nodes, id, inv, down, anchor, base, history, w, h, fonts, camera} = s
  id

def edit.attrs(+as: List<&2, XML.Attr>, +op: U32, key: String, value: String, matrix: SVG.Matrix) -> List<&2, XML.Attr>:
  +old = CSS.properties(as)
  +newValue = U.choose(String, U32.is_eq(op, 3),
    SVG.matrix.show(SVG.matrix.mul(SVG.transform(XML.attr.get(old, "transform", ""), SVG.identity()), matrix)), value)
  +k = U.choose(String, U32.is_eq(op, 3), "transform", key)
  U.branch(List<&2, XML.Attr>, U.string.equal(k, "textLength") || U.string.equal(k, "lengthAdjust") || U.string.equal(k, "pathLength") || U.string.equal(k, "preserveAspectRatio") || U.string.equal(k, "href") || U.string.equal(k, "xlink:href"),
    _ => XML.attrs.set(as, k, newValue),
    _ => XML.attrs.set(as, "style", XML.attr.get(as, "style", "") ++ ";" ++ k ++ ":" ++ newValue))

def edit.nodes(+xs: List<&2, XML.Element>, +id: String, +op: U32, +key: String, +value: String, +matrix: SVG.Matrix) -> List<&2, XML.Element>:
  match xs:
    case Nil{}: Nil{}
    case Con{XML.Element{n, as, kids, txt}, rest}:
      +hit = U.string.equal(XML.attr.get(as, "#editor-id", ""), id)
      U.branch(List<&2, XML.Element>, hit && U32.is_eq(op, 1),
        _ => edit.nodes(rest, id, op, key, value, matrix),
        _ => Con{XML.Element{n, U.choose(List<&2, XML.Attr>, hit, edit.attrs(as, op, key, value, matrix), as),
          edit.nodes(kids, id, op, key, value, matrix), txt}, edit.nodes(rest, id, op, key, value, matrix)})

def edit.root(xs: List<&2, XML.Element>, fallback: XML.Element) -> XML.Element:
  match xs:
    case Nil{}: fallback
    case Con{h, t}: h

def edit(+doc: XML.Element, id: String, op: U32, key: String, value: String, matrix: SVG.Matrix) -> XML.Element:
  edit.root(edit.nodes(Con{doc, Nil{}}, id, op, key, value, matrix), doc)

def rebuild(+s: State, +doc: XML.Element, +history: List<&2, XML.Element>) -> State:
  State{old, nodes, id, inv, down, anchor, base, undo, w, h, fonts, camera} = s
  State{doc, camera.render(doc, fonts, camera, w, h), id, inv, down, anchor, base, history, w, h, fonts, camera}

def press.picked(+s: State, point: SVG.Point, hit: SVG.Pick) -> State:
  State{doc, nodes, id, inv, down, anchor, base, history, w, h, fonts, camera} = s
  SVG.Pick{found, sel, matrix} = hit
  State{doc, nodes, sel, matrix, found, point, doc, history, w, h, fonts, camera}

def press(+s: State, +point: SVG.Point) -> State:
  press.picked(s, point, SVG.pick(get.scene(s), point))

def drag.delta(+s: State, +delta: SVG.Point) -> State:
  State{doc, nodes, id, inv, down, anchor, base, history, w, h, fonts, camera} = s
  SVG.Point{dx, dy} = delta
  U.branch(State, F32.is_eq(dx, 0.0) && F32.is_eq(dy, 0.0),
    _ => rebuild(s, base, history),
    _ => rebuild(s, edit(base, id, 3, "", "", SVG.matrix.mul(inv,
      SVG.matrix.mul(SVG.translate(dx, dy), SVG.matrix.inverse(inv)))), history))

def move(+s: State, point: SVG.Point) -> State:
  State{doc, nodes, id, inv, down, anchor, base, history, w, h, fonts, camera} = s
  U.branch(State, down, _ => drag.delta(s, SVG.point.sub(point, anchor)), _ => s)

# A gesture creates one undo entry only when its final document differs.
def release.history(+doc: XML.Element, +base: XML.Element, down: Bool, +history: List<&2, XML.Element>) -> List<&2, XML.Element>:
  U.branch(List<&2, XML.Element>, down,
    _ => U.choose(List<&2, XML.Element>, U.string.equal(XML.serialize(doc), XML.serialize(base)), history, Con{base, history}),
    _ => history)

def release(+s: State) -> State:
  State{doc, nodes, id, inv, down, anchor, base, history, w, h, fonts, camera} = s
  +current = doc
  State{current, nodes, id, inv, False{}, anchor, current, release.history(current, base, down, history), w, h, fonts, camera}

def modify.ready(+s: State, op: U32, key: String, value: String) -> State:
  State{doc, nodes, id, inv, down, anchor, base, history, w, h, fonts, camera} = s
  U.branch(State, U.string.equal(id, ""), _ => s,
    _ => release(rebuild(s, edit(doc, id, op, key, value, SVG.identity()), Con{doc, history})))

def translate.ready(+s: State, dx: F32, dy: F32) -> State:
  State{doc, nodes, id, inv, down, anchor, base, history, w, h, fonts, camera} = s
  release(rebuild(s, edit(doc, id, 3, "", "", SVG.matrix.mul(inv,
    SVG.matrix.mul(SVG.translate(dx, dy), SVG.matrix.inverse(inv)))), Con{doc, history}))

def undo.history(+s: State, hs: List<&2, XML.Element>) -> State:
  match hs:
    case Nil{}: s
    case Con{doc, rest}: release(rebuild(s, doc, rest))

def undo.ready(+s: State) -> State:
  State{doc, nodes, id, inv, down, anchor, base, history, w, h, fonts, camera} = s
  undo.history(s, history)

def modify(s: State, op: U32, key: String, value: String) -> State:
  modify.ready(release(s), op, key, value)

def translate(s: State, dx: F32, dy: F32) -> State:
  translate.ready(release(s), dx, dy)

def undo(s: State) -> State:
  undo.ready(release(s))

def replace(s: State, text: String) -> State:
  State{doc, nodes, id, inv, down, anchor, base, history, w, h, fonts, camera} = s
  load.fonts(text, w, h, fonts)

# Applying source is an edit; opening a file still starts a new history.
def source.changed(+s: State, +doc: XML.Element) -> State:
  State{old, nodes, id, inv, down, anchor, base, history, w, h, fonts, camera} = s
  +width = w
  +height = h
  +book = fonts
  State{doc, camera.render(doc, book, camera, width, height), "", SVG.identity(), False{},
    SVG.Point{0.0, 0.0}, doc, Con{old, history}, width, height, book, camera}

def source.ready(+s: State, +text: String) -> State:
  U.branch(State, U.string.equal(text, get.source(s)), _ => s,
    _ => source.changed(s, XML.parse(text)))

def source(s: State, text: String) -> State:
  source.ready(release(s), text)

def navigate.ready(+s: State, kind: U32) -> State:
  State{doc, nodes, id, inv, down, anchor, base, history, w, h, fonts, camera} = s
  +next = camera.next(camera, kind, doc, U32.to_f32(w), U32.to_f32(h))
  State{doc, camera.render(doc, fonts, next, w, h), "", SVG.identity(), False{}, SVG.Point{0.0, 0.0}, doc, history, w, h, fonts, next}

def navigate(s: State, kind: U32) -> State:
  navigate.ready(release(s), kind)

def apply(s: State, action: Action) -> State:
  match action:
    case Load{text}: replace(s, text)
    case Source{text}: source(s, text)
    case Navigate{kind}: navigate(s, kind)
    case Press{x, y}: press(s, SVG.Point{U32.to_f32(x), U32.to_f32(y)})
    case Drag{x, y}: move(s, SVG.Point{U32.to_f32(x), U32.to_f32(y)})
    case Release{}: release(s)
    case Property{k, v}: modify(s, 2, k, v)
    case Translate{dx, dy}: translate(s, dx, dy)
    case Delete{}: modify(s, 1, "", "")
    case Undo{}: undo(s)
    case Nothing{}: s

def view(+s: State) -> State & Image:
  (s, SVG.image(8n, 0, 0, get.scene(s), 1))

# Text transport commands are interpreted here, not in either GUI.
def command.coords(+cmd: String, +vs: List<&2, F32>) -> Action:
  +x = F32.to_u32(U.max(0.0, U.nth(vs, 0n, 0.0)))
  +y = F32.to_u32(U.max(0.0, U.nth(vs, 1n, 0.0)))
  U.choose(Action, U.string.equal(cmd, "down"), Press{x, y}, Drag{x, y})

def command.property(scan: U.Scan) -> Action:
  U.Scan{k, v} = scan
  Property{k, v}

def command.split(scan: U.Scan) -> Action:
  U.Scan{cmd, body} = scan
  +c = cmd
  +b = body
  U.branch(Action, U.string.equal(c, "source"), _ => Source{b},
    _ => U.branch(Action, U.string.equal(c, "load"), _ => Load{b},
    _ => U.branch(Action, U.string.equal(c, "down") || U.string.equal(c, "move"), _ => command.coords(c, U.numbers(b)),
      _ => U.branch(Action, U.string.equal(c, "up"), _ => Release{},
        _ => U.branch(Action, U.string.equal(c, "set"), _ => command.property(U.until(b, 10, "")),
          _ => U.choose(Action, U.string.equal(c, "delete"), Delete{}, U.choose(Action, U.string.equal(c, "undo"), Undo{}, Nothing{})))))))

def command(s: String) -> Action:
  command.split(U.until(s, 10, ""))

def key.document(+code: U32) -> Action:
  U.choose(Action, U32.is_eq(code, 122), Undo{},
    U.choose(Action, U32.is_eq(code, 127) || U32.is_eq(code, 8), Delete{},
      U.choose(Action, U32.is_eq(code, 63234), Translate{F32.neg(1.0), 0.0},
        U.choose(Action, U32.is_eq(code, 63235), Translate{1.0, 0.0},
          U.choose(Action, U32.is_eq(code, 63232), Translate{0.0, F32.neg(1.0)},
            U.choose(Action, U32.is_eq(code, 63233), Translate{0.0, 1.0},
              U.choose(Action, U32.is_eq(code, 114), Property{"fill", "#e34b36"},
                U.choose(Action, U32.is_eq(code, 103), Property{"fill", "#79bd4a"},
                  U.choose(Action, U32.is_eq(code, 98), Property{"fill", "#4682b4"}, Nothing{})))))))))

def key(+code: U32) -> Action:
  +fit = U32.is_eq(code, 102)
  +zoomIn = U32.is_eq(code, 43) || U32.is_eq(code, 61)
  +zoomOut = U32.is_eq(code, 45)
  +left = U32.is_eq(code, 104)
  +right = U32.is_eq(code, 108)
  +up = U32.is_eq(code, 107)
  +down = U32.is_eq(code, 106)
  U.branch(Action, U32.is_eq(code, 48) || fit || zoomIn || zoomOut || left || right || up || down,
    _ => Navigate{U.choose(U32, fit, 1, U.choose(U32, zoomIn, 2, U.choose(U32, zoomOut, 3, U.choose(U32, left, 4, U.choose(U32, right, 5, U.choose(U32, up, 6, U.choose(U32, down, 7, 0)))))))}, _ => key.document(code))

def event(ev: Event) -> Action:
  match ev:
    case Mouse{x, y, button, down}: U.choose(Action, down, Press{x, y}, Release{})
    case Move{x, y}: Drag{x, y}
    case Key{code, down}: U.choose(Action, down, key(code), Nothing{})
    case Close{}: Nothing{}

def events(xs: List<Event>, s: State) -> State:
  match xs:
    case Nil{}: s
    case Con{ev, rest}: events(rest, apply(s, event(ev)))

# Filesystem plumbing is shared so open/save semantics agree between frontends.
def read.chunk(got: File & Result<&1, &1, U32 & String, String>, acc: String,
  next: File -> String -> IO(String)) -> IO(String):
  (file, result) = got
  match result:
    case Fail{error}:
      do IO<String>:
        Unit <- File.close(file)
        IO.pass(String, Fail{error})
    case Done{data}:
      match data:
        case SNil{}:
          do IO<String>:
            Unit <- File.close(file)
            return acc
        case SCon{c, t}: next(file)(acc ++ SCon{c, t})

@unsafe
def read.loop(file: File, acc: String) -> IO(String):
  do IO<String>:
    got : File & Result<&1, &1, U32 & String, String> <- File.read(file, 65536)
    read.chunk(got, acc, f => text => read.loop(f, text))

def read(path: String) -> IO(String):
  do IO<String>:
    file : File <- IO.try(File, File.open(path, "r"))
    read.loop(file, "")

def write.done(got: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (file, result) = got
  do IO<Unit>:
    Unit <- File.close(file)
    IO.pass(Unit, result)

def write(path: String, text: String) -> IO(Unit):
  do IO<Unit>:
    file : File <- IO.try(File, File.open(path, "w"))
    got : File & Result<&1, &1, U32 & String, Unit> <- File.write(file, text)
    write.done(got)

def example() -> String:
  "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"256\" height=\"256\" viewBox=\"0 0 256 256\">"
    ++ "<rect x=\"24\" y=\"28\" width=\"102\" height=\"82\" rx=\"12\" fill=\"#e34b36\"/>"
    ++ "<circle cx=\"178\" cy=\"87\" r=\"47\" fill=\"#4682b4\"/>"
    ++ "<path d=\"M25 217 Q64 112 100 190 T197 181 L230 225Z\" fill=\"#79bd4a\"/></svg>"

def fonts.ttf.step(rest: String, +face: U32, loaded: Font.FontBook, next: String -> U32 -> Font.FontBook -> IO(Font.FontBook)) -> IO(Font.FontBook):
  match rest:
    case SNil{}: IO.pure(Font.FontBook, loaded)
    case SCon{c, t}: next(SCon{c, t})((face + 1 : U32))(loaded)

# An unreadable font file leaves its face empty.
def fonts.ttf.got(+face: U32, got: Result<&1, &1, U32 & String, Bin.Bytes>, book: Font.FontBook) -> Font.FontBook:
  match got:
    case Fail{err}: book
    case Done{bytes}: Font.font.ttf(face, bytes, book)

@unsafe
def fonts.ttf.list(scan: U.Scan, +face: U32, book: Font.FontBook) -> IO(Font.FontBook):
  U.Scan{path, rest} = scan
  do IO<Font.FontBook>:
    got : Result<&1, &1, U32 & String, Bin.Bytes> <- Bin.bytes.read(path)
    fonts.ttf.step(rest, face, fonts.ttf.got(face, got, book), more => f => loaded => fonts.ttf.list(U.until(more, 44, ""), f, loaded))

# The four bundled Noto Sans faces in a directory, in face order.
def fonts.directory(+dir: String) -> String:
  dir ++ "/NotoSans-Regular.ttf," ++ dir ++ "/NotoSans-Bold.ttf," ++ dir ++ "/NotoSans-Italic.ttf," ++ dir ++ "/NotoSans-BoldItalic.ttf"

# SVG_FONTS lists TrueType files, one face each in order (regular, bold, italic,
# bold italic), or names a directory holding the Noto Sans files; default "fonts".
def fonts.paths(env: Result<&1, &1, U32 & String, String>) -> String:
  match env:
    case Fail{err}: fonts.directory("fonts")
    case Done{value}:
      +v = value
      U.branch(String, U.string.contains(v, ".ttf"), _ => v, _ => fonts.directory(v))

def read.fonts() -> IO(Font.FontBook):
  do IO<Font.FontBook>:
    env : Result<&1, &1, U32 & String, String> <- IO.get_env("SVG_FONTS")
    fonts.ttf.list(U.until(fonts.paths(env), 44, ""), 0, Font.font.empty())

def initial.env(env: Result<&1, &1, U32 & String, String>, +fonts: Font.FontBook) -> IO(State):
  match env:
    case Fail{err}: IO.pure(State, load.fonts(example(), 256, 256, fonts))
    case Done{path}:
      do IO<State>:
        text : String <- read(path)
        return load.fonts(text, 256, 256, fonts)

def initial() -> IO(State):
  do IO<State>:
    book : Font.FontBook <- read.fonts()
    env : Result<&1, &1, U32 & String, String> <- IO.get_env("SVG_INPUT")
    initial.env(env, book)

def output.env(s: State, env: Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match env:
    case Fail{err}: write("edited.svg", get.source(s))
    case Done{path}: write(path, get.source(s))

def save(s: State) -> IO(Unit):
  do IO<Unit>:
    env : Result<&1, &1, U32 & String, String> <- IO.get_env("SVG_OUTPUT")
    output.env(s, env)

# ASCII code-point transport avoids splitting UTF-8 sequences across TCP reads.
def wire.part(scan: U.Scan, acc: String, next: String -> String -> String) -> String:
  U.Scan{h, t} = scan
  next(t)(SCon{Chr{U.hex(h, 0)}, acc})

@unsafe
def wire.loop(s: String, acc: String) -> String:
  match s:
    case SNil{}: U.rev(acc, "")
    case SCon{c, t}: wire.part(U.until(SCon{c, t}, 32, ""), acc, tail => text => wire.loop(tail, text))

def wire.decode(s: String) -> String:
  wire.loop(s, "")

def input(+text: String) -> Action:
  U.branch(Action, U.prefix(text, "key\n"),
    _ => key(F32.to_u32(U.scalar(U.drop(text, "key\n"), 0.0))), _ => command(text))

def quality(s: State) -> U32:
  State{doc, nodes, id, inv, down, anchor, base, history, w, h, fonts, camera} = s
  U.choose(U32, down, 1, 4)

def canvas(+s: State) -> Image:
  SVG.image(8n, 0, 0, get.scene(s), quality(s))

def frame(+s: State) -> String:
  State{doc, nodes, id, inv, down, anchor, base, history, w, h, fonts, camera} = s
  SVG.ppm(w, h, nodes, quality(s))

def changed(action: Action, s: State) -> Bool:
  match action:
    case Nothing{}: False{}
    case Drag{x, y}: U32.is_eq(quality(s), 1)
    case _: True{}
