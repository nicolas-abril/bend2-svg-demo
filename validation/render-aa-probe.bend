# Validation-only supersampling diagnostic; uses the unchanged SVG library.
# Headless renderer. Emits an RGB matrix as a portable PPM image.
import Base
import gralha-svg-render@0.1.0.1/svg.bend as SVG
import gralha-text-scan@0.1.0.1/scan.bend as U
import gralha-truetype@0.1.0.1/font.bend as Font
import gralha-xml-doc@0.1.0.1/xml.bend as XML
import ../state.bend as Editor

def env.value(result: Result<&1, &1, U32 & String, String>, fallback: String) -> String:
  match result:
    case Fail{err}: fallback
    case Done{text}: text

def env(name: String, fallback: String) -> IO(String):
  do IO<String>:
    result : Result<&1, &1, U32 & String, String> <- IO.get_env(name)
    return env.value(result, fallback)

def output(doc: XML.Element, +w: U32, +h: U32, aa: U32, fonts: Font.FontBook) -> String:
  SVG.ppm(w, h, SVG.document.fonts(doc, U32.to_f32(w), U32.to_f32(h), fonts), aa)

def render.document(+doc: XML.Element) -> IO(Unit):
  do IO<Unit>:
    book : Font.FontBook <- U.branch(IO(Font.FontBook), SVG.text.present(Con{doc, Nil{}}), _ => Editor.read.fonts(), _ => IO.pure(Font.FontBook, Font.font.empty()))
    width : String <- env("SVG_WIDTH", "256")
    height : String <- env("SVG_HEIGHT", "256")
    samples : String <- env("SVG_AA", "4")
    w : U32 = F32.to_u32(U.clamp(U.scalar(width, 256.0), 1.0, 1024.0))
    h : U32 = F32.to_u32(U.clamp(U.scalar(height, 256.0), 1.0, 1024.0))
    aa : U32 = F32.to_u32(U.clamp(U.scalar(samples, 4.0), 1.0, 32.0))
    IO.write(output(doc, w, h, aa, book))

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, IO.get_env("SVG_INPUT"))
    text : String <- Editor.read(path)
    render.document(XML.parse(text))
