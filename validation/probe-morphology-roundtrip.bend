import Base
import ../svg.bend as SVG
import ../state.bend as Editor

def compare(+source: String) -> String:
  +once = SVG.serialize(SVG.parse(source))
  +twice = SVG.serialize(SVG.parse(once))
  +one = SVG.document(SVG.parse(source), 64.0, 64.0)
  +two = SVG.document(SVG.parse(once), 64.0, 64.0)
  SVG.choose(String, SVG.string.equal(once, twice), "SOURCE SAME\n", "SOURCE DIFFERENT\n") ++ SVG.choose(String, SVG.string.equal(SVG.ppm(64, 64, one, 4), SVG.ppm(64, 64, two, 4)), "MATRIX SAME\n", "MATRIX DIFFERENT\n") ++ once ++ "\nROUNDTRIP\n" ++ twice

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, IO.get_env("SVG_INPUT"))
    source : String <- Editor.read(path)
    IO.write(compare(source))
