import Base
import ./svg.bend as SVG
import ./util.bend as U
import ./xml.bend as XML
import ./state.bend as Editor

def source() -> String:
  "<svg width='64' height='64'><defs><marker id='dot' markerWidth='8' markerHeight='8' refX='4' refY='4' markerUnits='userSpaceOnUse'><rect width='8' height='8' fill='context-stroke'/></marker></defs><path id='target' d='M12 20L48 20' stroke='red' stroke-opacity='0' marker-end='url(#dot)'/></svg>"

def picked(p: SVG.Pick) -> String:
  SVG.Pick{found, id, inverse} = p
  U.choose(String, found, id, "missing")

def main() -> IO(Unit):
  +scene = SVG.document(XML.parse(source()), 64.0, 64.0)
  do IO<Unit>:
    Unit <- IO.print(U32.show(SVG.pixel(scene, 47, 19, 1)))
    Unit <- IO.print(picked(SVG.pick(scene, SVG.Point{47.0, 19.0})))
    IO.print(U32.show(SVG.pixel(scene, 30, 19, 1)))

#|16711680
#|5
#|16777215
