# Validation-only supersampling diagnostic; uses the unchanged SVG library.
# Headless renderer. Emits an RGB matrix as a portable PPM image.
import Base
import ../svg.bend as SVG
import ../state.bend as Editor

def env.value(result: Result<&1, &1, U32 & String, String>, fallback: String) -> String:
  match result:
    case Fail{err}: fallback
    case Done{text}: text

def env(name: String, fallback: String) -> IO(String):
  do IO<String>:
    result : Result<&1, &1, U32 & String, String> <- IO.get_env(name)
    return env.value(result, fallback)

def output(doc: SVG.Element, +w: U32, +h: U32, aa: U32, fonts: SVG.FontBook) -> String:
  SVG.ppm(w, h, SVG.document.fonts(doc, U32.to_f32(w), U32.to_f32(h), fonts), aa)

def render.document(+doc: SVG.Element) -> IO(Unit):
  do IO<Unit>:
    book : SVG.FontBook <- SVG.branch(IO(SVG.FontBook), SVG.text.present(Con{doc, Nil{}}), _ => Editor.read.fonts(), _ => IO.pure(SVG.FontBook, SVG.font.empty()))
    width : String <- env("SVG_WIDTH", "256")
    height : String <- env("SVG_HEIGHT", "256")
    samples : String <- env("SVG_AA", "4")
    w : U32 = F32.to_u32(SVG.clamp(SVG.scalar(width, 256.0), 1.0, 1024.0))
    h : U32 = F32.to_u32(SVG.clamp(SVG.scalar(height, 256.0), 1.0, 1024.0))
    aa : U32 = F32.to_u32(SVG.clamp(SVG.scalar(samples, 4.0), 1.0, 32.0))
    IO.write(output(doc, w, h, aa, book))

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, IO.get_env("SVG_INPUT"))
    text : String <- Editor.read(path)
    render.document(SVG.parse(text))
