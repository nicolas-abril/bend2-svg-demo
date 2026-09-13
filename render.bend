# Headless renderer. Emits an RGB matrix as a portable PPM image.
import Base
import ./svg.bend as SVG
import ./util.bend as U
import ./xml.bend as XML
import ./font.bend as Font
import ./state.bend as Editor

def env.value(result: Result<&1, &1, U32 & String, String>, fallback: String) -> String:
  match result:
    case Fail{err}: fallback
    case Done{text}: text

def env(name: String, fallback: String) -> IO(String):
  do IO<String>:
    result : Result<&1, &1, U32 & String, String> <- IO.get_env(name)
    return env.value(result, fallback)

# The packed pixels of a document, written as a PPM matrix by a foreign effect
# (formatting 65 thousand pixels as text in Bend cost more than painting them).
def pixels.write(a: Array<U32>, +w: U32, +h: U32) -> IO(Array<U32> & Result<&1, &1, U32 & String, Unit>):
  import "./effs/pixels_write.c"
  import "./effs/pixels_write.js"

def written(got: Array<U32> & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (pixels, result) = got
  match result:
    case Fail{err}: IO.print("write failed")
    case Done{unit}: IO.pure(Unit, Unit{})

def render.write(doc: XML.Element, book: Font.FontBook, +w: U32, +h: U32, +aa: U32) -> IO(Unit):
  do IO<Unit>:
    got : Array<U32> & Result<&1, &1, U32 & String, Unit> <- pixels.write(SVG.paint.packed(SVG.document.fitted.fonts(doc, U32.to_f32(w), U32.to_f32(h), book), w, h, aa), w, h)
    written(got)

def render.document(+doc: XML.Element) -> IO(Unit):
  do IO<Unit>:
    book : Font.FontBook <- U.branch(IO(Font.FontBook), SVG.text.present(Con{doc, Nil{}}), _ => Editor.read.fonts(), _ => IO.pure(Font.FontBook, Font.font.empty()))
    width : String <- env("SVG_WIDTH", "256")
    height : String <- env("SVG_HEIGHT", "256")
    samples : String <- env("SVG_AA", "4")
    w : U32 = F32.to_u32(U.clamp(U.scalar(width, 256.0), 1.0, 1024.0))
    h : U32 = F32.to_u32(U.clamp(U.scalar(height, 256.0), 1.0, 1024.0))
    aa : U32 = F32.to_u32(U.clamp(U.scalar(samples, 4.0), 1.0, 8.0))
    render.write(doc, book, w, h, aa)

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, IO.get_env("SVG_INPUT"))
    text : String <- Editor.read(path)
    render.document(XML.parse(text))
