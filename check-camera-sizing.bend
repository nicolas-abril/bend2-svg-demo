# Fitting uses the natural viewport while percentages and CSS remain document-local.
import Base
import ./state.bend as Editor
import ./svg.bend as SVG
import ./util.bend as U
import ./xml.bend as XML

def equal(source: String, body: String) -> String:
  U.choose(String, U.string.equal(Editor.frame(Editor.load(source, 64, 64)), SVG.ppm(64, 64, SVG.document(XML.parse("<svg>" ++ body ++ "</svg>"), 64.0, 64.0), 4)), "PASS", "FAIL")

def main() -> IO(Unit):
  do IO<Unit>:
    Unit <- IO.print(equal("<svg width='50%' height='25%'><rect width='100%' height='100%' fill='red'/></svg>", "<rect y='16' width='64' height='32' fill='red'/>"))
    Unit <- IO.print(equal("<svg width='64' height='64'><style>svg {width:128px;height:64px}</style><rect width='100%' height='100%' fill='red'/></svg>", "<rect y='16' width='64' height='32' fill='red'/>"))
    Unit <- IO.print(equal("<svg width='128' height='64' viewBox='0 0 64 64'><rect width='64' height='64' fill='red'/></svg>", "<rect x='16' y='16' width='32' height='32' fill='red'/>"))
    Unit <- IO.print(equal("<svg width='0' height='64'><rect width='100%' height='100%' fill='red'/></svg>", ""))
    Unit <- IO.print(equal("<svg width='128' height='64'><svg width='50%' height='100%' viewBox='0 0 16 16'><rect width='16' height='16' fill='red'/></svg></svg>", "<rect y='16' width='32' height='32' fill='red'/>"))
    Unit <- IO.print(equal("<svg width='128' height='64'><style>rect {fill:blue} @media (min-width:100px) {rect {fill:red}}</style><rect width='100%' height='100%'/></svg>", "<rect y='16' width='64' height='32' fill='red'/>"))
    IO.print(equal("<svg viewBox='0 0 128 64'><rect width='128' height='64' fill='red'/></svg>", "<rect y='16' width='64' height='32' fill='red'/>"))

#|PASS
#|PASS
#|PASS
#|PASS
#|PASS
#|PASS
#|PASS
