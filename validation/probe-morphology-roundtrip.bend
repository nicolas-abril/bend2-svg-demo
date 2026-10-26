import Base
import gralha-svg-render@0.1.0.1/svg.bend as SVG
import gralha-text-scan@0.1.0.1/scan.bend as U
import gralha-xml-doc@0.1.0.1/xml.bend as XML
import ../state.bend as Editor

def compare(+source: String) -> String:
  +once = XML.serialize(XML.parse(source))
  +twice = XML.serialize(XML.parse(once))
  +one = SVG.document(XML.parse(source), 64.0, 64.0)
  +two = SVG.document(XML.parse(once), 64.0, 64.0)
  U.choose(String, U.string.equal(once, twice), "SOURCE SAME\n", "SOURCE DIFFERENT\n") ++ U.choose(String, U.string.equal(SVG.ppm(64, 64, one, 4), SVG.ppm(64, 64, two, 4)), "MATRIX SAME\n", "MATRIX DIFFERENT\n") ++ once ++ "\nROUNDTRIP\n" ++ twice

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, IO.get_env("SVG_INPUT"))
    source : String <- Editor.read(path)
    IO.write(compare(source))
