import Base
import ../svg.bend as SVG
import ../state.bend as Editor

def pixel(c: SVG.Color) -> String:
  SVG.Color{r, g, b, a} = c
  U32.show(F32.to_u32(F32.floor((r * 255.0 + 0.5 : F32)))) ++ " " ++ U32.show(F32.to_u32(F32.floor((g * 255.0 + 0.5 : F32)))) ++ " " ++ U32.show(F32.to_u32(F32.floor((b * 255.0 + 0.5 : F32)))) ++ "\n"

def pixels(n: Nat, +index: U32, +w: U32, +raster: SVG.Raster) -> String:
  match n:
    case 0n: ""
    case 1n+d: pixel(SVG.raster.pixel(raster, U32.to_f32(U32.mod(index, w)), U32.to_f32(U32.div(index, w)))) ++ pixels(d, U32.inc(index), w, raster)

def output(+raster: SVG.Raster) -> String:
  SVG.Raster{origin, step, w, h, depth, linear, image} = raster
  "P3\n" ++ U32.show(w) ++ " " ++ U32.show(h) ++ "\n255\n" ++ pixels(U32.to_nat((w * h : U32)), 0, w, raster)

def main() -> IO(Unit):
  do IO<Unit>:
    path : String <- IO.try(String, IO.get_env("JPEG_INPUT"))
    encoded : String <- Editor.read(path)
    IO.write(output(SVG.jpeg.decode(SVG.base64(encoded))))
