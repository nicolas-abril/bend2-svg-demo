# SVG parsing, geometry, painting and rasterization. No foreign code.
import Base
import ./util.bend as U
import ./xml.bend as XML
import ./css.bend as CSS
import ./bin.bend as Bin
import ./img.bend as Img
import ./png.bend as PNG
import ./jpeg.bend as JPEG
import ./cover.bend as Cov
import ./font.bend as Font

def length.go(s: String, acc: U32) -> U32:
  match s:
    case SNil{}: acc
    case SCon{c, t}: length.go(t, U32.inc(acc))

def length(s: String) -> U32:
  length.go(s, 0)

# Affine transforms, composed in SVG's column - vector order.
type Matrix is Data:
  Matrix{a: F32, b: F32, c: F32, d: F32, e: F32, f: F32}

def identity() -> Matrix:
  Matrix{1.0, 0.0, 0.0, 1.0, 0.0, 0.0}

def matrix.mul(+m: Matrix, +n: Matrix) -> Matrix:
  Matrix{a, b, c, d, e, f} = m
  Matrix{g, h, i, j, k, l} = n
  Matrix{(a * g + c * h : F32), (b * g + d * h : F32), (a * i + c * j : F32),
    (b * i + d * j : F32), (a * k + c * l + e : F32), (b * k + d * l + f : F32)}

def matrix.inverse.values(+m: Matrix, +det: F32) -> Matrix:
  Matrix{a, b, c, d, e, f} = m
  Matrix{(d / det : F32), (0.0 - b / det : F32), (0.0 - c / det : F32),
    (a / det : F32), ((c * f - d * e) / det : F32), ((b * e - a * f) / det : F32)}

def matrix.inverse(+m: Matrix) -> Matrix:
  Matrix{a, b, c, d, e, f} = m
  matrix.inverse.values(m, (a * d - b * c : F32))

type Point is Data:
  Point{x: F32, y: F32}

def matrix.point(+m: Matrix, +p: Point) -> Point:
  Matrix{a, b, c, d, e, f} = m
  Point{x, y} = p
  Point{(a * x + c * y + e : F32), (b * x + d * y + f : F32)}

def translate(x: F32, y: F32) -> Matrix:
  Matrix{1.0, 0.0, 0.0, 1.0, x, y}

def scale(x: F32, y: F32) -> Matrix:
  Matrix{x, 0.0, 0.0, y, 0.0, 0.0}

def rotate(+angle: F32) -> Matrix:
  +r = (angle * 0.017453292519943295 : F32)
  Matrix{F32.cos(r), F32.sin(r), F32.neg(F32.sin(r)), F32.cos(r), 0.0, 0.0}

def transform.one(+name: String, +v: List<&2, F32>) -> Matrix:
  +x = U.nth(v, 0n, 0.0)
  +y = U.nth(v, 1n, 0.0)
  +z = U.nth(v, 2n, 0.0)
  U.branch(Matrix, String.eq(name, "translate"), _ => translate(x, y),
    _ => U.branch(Matrix, String.eq(name, "scale"), _ => scale(x, U.nth(v, 1n, x)),
      _ => U.branch(Matrix, String.eq(name, "rotate"),
        _ => matrix.mul(translate(y, z), matrix.mul(rotate(x), translate(F32.neg(y), F32.neg(z)))),
        _ => U.branch(Matrix, String.eq(name, "matrix"),
          _ => Matrix{x, y, z, U.nth(v, 3n, 1.0), U.nth(v, 4n, 0.0), U.nth(v, 5n, 0.0)},
          _ => U.branch(Matrix, String.eq(name, "skewX"),
            _ => Matrix{1.0, 0.0, F32.tan((x * 0.017453292519943295 : F32)), 1.0, 0.0, 0.0},
            _ => U.branch(Matrix, String.eq(name, "skewY"),
              _ => Matrix{1.0, F32.tan((x * 0.017453292519943295 : F32)), 0.0, 1.0, 0.0, 0.0},
              _ => identity()))))))

def transform.args(n: String, s: U.Scan, m: Matrix, next: String -> Matrix -> Matrix) -> Matrix:
  U.Scan{h, t} = s
  next(t)(matrix.mul(m, transform.one(n, U.numbers(h))))

def transform.name(s: U.Scan, m: Matrix, next: String -> Matrix -> Matrix) -> Matrix:
  U.Scan{h, t} = s
  transform.args(h, U.until(t, 41, ""), m, next)

@unsafe
def transform(+s: String, +m: Matrix) -> Matrix:
  U.branch(Matrix, String.eq(U.trim(s), ""), _ => m,
    _ => transform.name(U.until(U.separators(s), 40, ""), m, t => n => transform(t, n)))

# Paths are flattened in user coordinates. The fill-only closing edge of an
# open subpath is kept separate from its stroked edges.
type Edge is Data:
  Edge{p: Point, q: Point, stroke: Bool, closed: Bool}

# ---- analytic coverage ----
# A cover is a pixel-space coverage mask (see cover.bend) together with the raster
# grid it was built for, so device points map straight to its cells.
type Cover is Data:
  Cover{mask: Cov.CovMask, origin: Point, step: F32}

def cover.none() -> Cover:
  Cover{Cov.mask.none(), Point{0.0, 0.0}, 1.0}

def cover.present(+c: Cover) -> Bool:
  Cover{mask, origin, step} = c
  Cov.mask.present(mask)

def cover.at(+c: Cover, +p: Point) -> F32:
  Cover{mask, Point{ox, oy}, step} = c
  Point{x, y} = p
  Cov.mask.at(mask, ((x - ox) / step : F32), ((y - oy) / step : F32))

def point.add(p: Point, q: Point) -> Point:
  Point{x, y} = p
  Point{u, v} = q
  Point{(x + u : F32), (y + v : F32)}

def point.sub(p: Point, q: Point) -> Point:
  Point{x, y} = p
  Point{u, v} = q
  Point{(x - u : F32), (y - v : F32)}

def point.scale(p: Point, +s: F32) -> Point:
  Point{x, y} = p
  Point{(x * s : F32), (y * s : F32)}

def point.dot(p: Point, q: Point) -> F32:
  Point{x, y} = p
  Point{u, v} = q
  (x * u + y * v : F32)

def point.mid(p: Point, q: Point) -> Point:
  point.scale(point.add(p, q), 0.5)

def point.distance(+p: Point, +q: Point) -> F32:
  +d = point.sub(p, q)
  F32.sqrt(point.dot(d, d))

def cubic.flat(+p: Point, +a: Point, +b: Point, +q: Point) -> Bool:
  F32.is_lt((point.distance(p, a) + point.distance(a, b) + point.distance(b, q)
    - point.distance(p, q) : F32), 0.0005)

def cubic(depth: Nat, +p: Point, +a: Point, +b: Point, +q: Point,
  +edges: List<&2, Edge>) -> List<&2, Edge>:
  match depth:
    case 0n: Con{Edge{p, q, True{}, False{}}, edges}
    case 1n+d:
      +dd = d
      +pa = point.mid(p, a)
      +ab = point.mid(a, b)
      +bq = point.mid(b, q)
      +l = point.mid(pa, ab)
      +r = point.mid(ab, bq)
      +m = point.mid(l, r)
      U.branch(List<&2, Edge>, cubic.flat(p, a, b, q), _ => Con{Edge{p, q, True{}, False{}}, edges},
        _ => cubic(dd, m, r, bq, q, cubic(dd, p, pa, l, m, edges)))

type Params is Data:
  Params{values: List<&2, F32>, tail: String, valid: Bool}

def params.cons(x: F32, ps: Params) -> Params:
  Params{vs, t, ok} = ps
  Params{Con{x, vs}, t, ok}

def params.push(+num: U.Number, next: String -> Params) -> Params:
  U.Number{x, t, valid} = num
  U.choose(Unit -> Params, valid,
    _ => params.cons(x, next(t)), _ => Params{Nil{}, t, False{}})(Unit{})

def params(n: Nat, s: String) -> Params:
  match n:
    case 0n: Params{Nil{}, s, True{}}
    case 1n+d: params.push(U.number(s), t => params(d, t))

def arc.flag(+s: String) -> U.Number:
  match s:
    case SNil{}: U.Number{0.0, "", False{}}
    case SCon{Chr{c}, t}: U.Number{U.choose(F32, U32.is_eq(c, 49), 1.0, 0.0), t, U32.is_eq(c, 48) || U32.is_eq(c, 49)}

def path.arguments(+n: Nat, +s: String, +arc: Bool) -> Params:
  match n:
    case 0n: Params{Nil{}, s, True{}}
    case 1n+d:
      params.push(U.branch(U.Number, arc && (U32.is_eq(U32.from_nat(n), 4) || U32.is_eq(U32.from_nat(n), 3)),
        _ => arc.flag(U.separators(s)), _ => U.number(s)), t => path.arguments(d, t, arc))

# Preserve source segment endpoints and analytic tangents only when requested.
type MarkerSegment is Data:
  MarkerSegment{p: Point, q: Point, outgoing: Point, incoming: Point, kind: U32}

def marker.segment(trace: Maybe<&2, List<&2, MarkerSegment>>, segment: MarkerSegment) -> Maybe<&2, List<&2, MarkerSegment>>:
  match trace:
    case None{}: None{}
    case Some{segments}: Some{Con{segment, segments}}

def marker.nonzero(+v: Point) -> Bool:
  F32.is_gt(point.dot(v, v), 0.000000000001)

def marker.vector(+a: Point, b: Point) -> Point:
  U.choose(Point, marker.nonzero(a), a, b)

def marker.cubic(+p: Point, +a: Point, +b: Point, +q: Point) -> MarkerSegment:
  MarkerSegment{p, q, marker.vector(point.sub(a, p), marker.vector(point.sub(b, p), point.sub(q, p))),
    marker.vector(point.sub(q, b), marker.vector(point.sub(q, a), point.sub(q, p))), 0}

def marker.line(+p: Point, +q: Point, kind: U32) -> MarkerSegment:
  MarkerSegment{p, q, point.sub(q, p), point.sub(q, p), kind}

def marker.arc.tangent(+rx: F32, +ry: F32, +phi: F32, +theta: F32, +delta: F32) -> Point:
  +direction = U.choose(F32, F32.is_lt(delta, 0.0), F32.neg(1.0), 1.0)
  Point{((F32.neg(rx) * F32.cos(phi) * F32.sin(theta) - ry * F32.sin(phi) * F32.cos(theta)) * direction : F32),
    ((F32.neg(rx) * F32.sin(phi) * F32.sin(theta) + ry * F32.cos(phi) * F32.cos(theta)) * direction : F32)}

type Path is Data:
  Path{current: Point, start: Point, control: Point, command: U32, previous: U32, edges: List<&2, Edge>, trace: Maybe<&2, List<&2, MarkerSegment>>}

def upper(+c: U32) -> U32:
  U.choose(U32, U32.is_ge(c, 97) && U32.is_le(c, 122), (c - 32 : U32), c)

def relative(+cmd: U32, +current: Point, p: Point) -> Point:
  point.add(U.choose(Point, U32.is_ge(cmd, 97), current, Point{0.0, 0.0}), p)

def path.move(+p: Path, +q: Point, cmd: U32) -> Path:
  Path{cur, start, ctrl, old, prev, es, trace} = p
  Path{q, q, q, U.choose(U32, U32.is_ge(cmd, 97), 108, 76), 77,
    U.choose(List<&2, Edge>, U32.is_eq(prev, 0), es, Con{Edge{cur, start, False{}, False{}}, es}), marker.segment(trace, marker.line(q, q, 1))}

def path.line(+p: Path, +q: Point, +cmd: U32) -> Path:
  Path{cur, start, ctrl, old, prev, es, trace} = p
  Path{q, start, q, cmd, upper(cmd), Con{Edge{cur, q, True{}, False{}}, es}, marker.segment(trace, marker.line(cur, q, 0))}

def path.cubic(+p: Path, +a: Point, +b: Point, +q: Point, +cmd: U32) -> Path:
  Path{cur, start, ctrl, old, prev, es, trace} = p
  Path{q, start, b, cmd, upper(cmd), cubic(10n, cur, a, b, q, es), marker.segment(trace, marker.cubic(cur, a, b, q))}

def path.quad(+p: Path, +a: Point, +q: Point, +cmd: U32) -> Path:
  Path{cur, start, ctrl, old, prev, es, trace} = p
  ca = point.add(cur, point.scale(point.sub(a, cur), 0.6666666666666666))
  cb = point.add(q, point.scale(point.sub(a, q), 0.6666666666666666))
  Path{q, start, a, cmd, upper(cmd), cubic(10n, cur, ca, cb, q, es), marker.segment(trace, marker.cubic(cur, a, a, q))}

def path.close(+p: Path) -> Path:
  Path{cur, start, ctrl, old, prev, es, trace} = p
  Path{start, start, start, 0, 90, Con{Edge{cur, start, True{}, True{}}, es}, marker.segment(trace, marker.line(cur, start, 2))}

def path.h(+cur: Point, +v: F32, cmd: U32) -> Point:
  Point{x, y} = cur
  Point{U.choose(F32, U32.is_ge(cmd, 97), (x + v : F32), v), y}

def path.v(+cur: Point, +v: F32, cmd: U32) -> Point:
  Point{x, y} = cur
  Point{x, U.choose(F32, U32.is_ge(cmd, 97), (y + v : F32), v)}

# Endpoint-to-center conversion from SVG's elliptical arc implementation notes.
def arc.point(+center: Point, +rx: F32, +ry: F32, +phi: F32, +t: F32) -> Point:
  point.add(center, Point{(rx * F32.cos(phi) * F32.cos(t) - ry * F32.sin(phi) * F32.sin(t) : F32),
    (rx * F32.sin(phi) * F32.cos(t) + ry * F32.cos(phi) * F32.sin(t) : F32)})

def arc.edges(+n: Nat, +i: F32, +step: F32, +theta: F32, +center: Point,
  +rx: F32, +ry: F32, +phi: F32, +endpoint: Point, p: Point, edges: List<&2, Edge>) -> List<&2, Edge>:
  match n:
    case 0n: edges
    case 1n+d:
      +q = U.choose(Point, U32.is_zero(U32.from_nat(d)), endpoint, arc.point(center, rx, ry, phi, (theta + i * step : F32)))
      arc.edges(d, (i + 1.0 : F32), step, theta, center, rx, ry, phi, endpoint, q, Con{Edge{p, q, True{}, False{}}, edges})

def arc.draw(+p: Path, +q: Point, +cmd: U32, +rx: F32, +ry: F32, +phi: F32,
  +center: Point, +theta: F32, +delta: F32) -> Path:
  Path{cur, start, ctrl, old, prev, es, trace} = p
  # At most 1/128 revolution per edge, further refined for larger radii.
  +count = U.max(1.0, F32.ceil((F32.abs(delta) * F32.sqrt(U.max(rx, ry)) * 8.0 : F32)))
  Path{q, start, q, cmd, 65, arc.edges(U32.to_nat(F32.to_u32(U.min(4096.0, count))),
    1.0, (delta / U.min(4096.0, count) : F32), theta, center, rx, ry, phi, q, cur, es), marker.segment(trace, MarkerSegment{cur, q, marker.arc.tangent(rx, ry, phi, theta, delta), marker.arc.tangent(rx, ry, phi, (theta + delta : F32), delta), 0})}

def arc.angles(+p: Path, +q: Point, +cmd: U32, +rx: F32, +ry: F32, +phi: F32,
  +xp: F32, +yp: F32, +cx: F32, +cy: F32, +center: Point, sweep: F32) -> Path:
  +ux = ((xp - cx) / rx : F32)
  +uy = ((yp - cy) / ry : F32)
  +vx = ((0.0 - xp - cx) / rx : F32)
  +vy = ((0.0 - yp - cy) / ry : F32)
  +delta = F32.atan2((ux * vy - uy * vx : F32), (ux * vx + uy * vy : F32))
  +sw = F32.is_gt(sweep, 0.0)
  arc.draw(p, q, cmd, rx, ry, phi, center, F32.atan2(uy, ux),
    U.choose(F32, sw && F32.is_lt(delta, 0.0), (delta + 6.283185307179586 : F32),
      U.choose(F32, Bool.not(sw) && F32.is_gt(delta, 0.0), (delta - 6.283185307179586 : F32), delta)))

def arc.center(+p: Path, +q: Point, +cmd: U32, +rx: F32, +ry: F32, +phi: F32,
  +xp: F32, +yp: F32, +coef: F32, sweep: F32) -> Path:
  Path{cur, start, ctrl, old, prev, es, trace} = p
  +cx = (coef * rx * yp / ry : F32)
  +cy = (0.0 - coef * ry * xp / rx : F32)
  center = point.add(point.mid(cur, q), Point{(F32.cos(phi) * cx - F32.sin(phi) * cy : F32),
    (F32.sin(phi) * cx + F32.cos(phi) * cy : F32)})
  arc.angles(p, q, cmd, rx, ry, phi, xp, yp, cx, cy, center, sweep)

def arc.radii(+p: Path, +q: Point, +cmd: U32, +rx: F32, +ry: F32, +phi: F32,
  +xp: F32, +yp: F32, +large: F32, +sweep: F32) -> Path:
  +ratio = U.max(1.0, F32.sqrt((xp * xp / (rx * rx) + yp * yp / (ry * ry) : F32)))
  +r = (rx * ratio : F32)
  +s = (ry * ratio : F32)
  +den = (r * r * yp * yp + s * s * xp * xp : F32)
  +factor = F32.sqrt(U.max(0.0, ((r * r * s * s - den) / den : F32)))
  arc.center(p, q, cmd, r, s, phi, xp, yp,
    U.choose(F32, F32.is_eq(large, sweep), F32.neg(factor), factor), sweep)

def arc.prepare(+p: Path, +q: Point, cmd: U32, rx: F32, ry: F32, +phi: F32,
  large: F32, sweep: F32, delta: Point) -> Path:
  Point{x, y} = delta
  +dx = x
  +dy = y
  arc.radii(p, q, cmd, rx, ry, phi, (F32.cos(phi) * dx + F32.sin(phi) * dy : F32),
    (0.0 - F32.sin(phi) * dx + F32.cos(phi) * dy : F32), large, sweep)

def path.arc(+p: Path, +q: Point, +cmd: U32, +rx: F32, +ry: F32, phi: F32,
  large: F32, sweep: F32) -> Path:
  Path{cur, start, ctrl, old, prev, es, trace} = p
  U.branch(Path, F32.is_lt(point.distance(cur, q), 0.000001), _ => Path{q, start, q, cmd, 65, es, trace},
    _ => U.branch(Path, F32.is_eq(rx, 0.0) || F32.is_eq(ry, 0.0), _ => path.line(p, q, cmd),
      _ => arc.prepare(p, q, cmd, F32.abs(rx), F32.abs(ry), (phi * 0.017453292519943295 : F32),
        large, sweep, point.scale(point.sub(cur, q), 0.5))))

def path.apply(+p: Path, +cmd: U32, +vs: List<&2, F32>) -> Path:
  Path{cur, start, ctrl, old, prev, es, trace} = p
  +c = upper(cmd)
  +x = U.nth(vs, 0n, 0.0)
  +y = U.nth(vs, 1n, 0.0)
  +a = relative(cmd, cur, Point{x, y})
  +b = relative(cmd, cur, Point{U.nth(vs, 2n, 0.0), U.nth(vs, 3n, 0.0)})
  +q = relative(cmd, cur, Point{U.nth(vs, 4n, 0.0), U.nth(vs, 5n, 0.0)})
  +cs = U.choose(Point, U32.is_eq(prev, 67) || U32.is_eq(prev, 83),
    point.sub(point.scale(cur, 2.0), ctrl), cur)
  +qs = U.choose(Point, U32.is_eq(prev, 81) || U32.is_eq(prev, 84),
    point.sub(point.scale(cur, 2.0), ctrl), cur)
  U.branch(Path, U32.is_eq(c, 77), _ => path.move(p, a, cmd),
    _ => U.branch(Path, U32.is_eq(c, 76), _ => path.line(p, a, cmd),
    _ => U.branch(Path, U32.is_eq(c, 72), _ => path.line(p, path.h(cur, x, cmd), cmd),
    _ => U.branch(Path, U32.is_eq(c, 86), _ => path.line(p, path.v(cur, x, cmd), cmd),
    _ => U.branch(Path, U32.is_eq(c, 67), _ => path.cubic(p, a, b, q, cmd),
    _ => U.branch(Path, U32.is_eq(c, 83), _ => path.cubic(p, cs, a, b, cmd),
    _ => U.branch(Path, U32.is_eq(c, 81), _ => path.quad(p, a, b, cmd),
    _ => U.branch(Path, U32.is_eq(c, 84), _ => path.quad(p, qs, a, cmd),
    _ => U.branch(Path, U32.is_eq(c, 65), _ => path.arc(p, relative(cmd, cur, Point{U.nth(vs, 5n, 0.0), U.nth(vs, 6n, 0.0)}), cmd, x, y, U.nth(vs, 2n, 0.0), U.nth(vs, 3n, 0.0), U.nth(vs, 4n, 0.0)),
    _ => p)))))))))

def path.arity(+c: U32) -> Nat:
  U.choose(Nat, U32.is_eq(c, 72) || U32.is_eq(c, 86), 1n,
    U.choose(Nat, U32.is_eq(c, 67), 6n,
      U.choose(Nat, U32.is_eq(c, 83) || U32.is_eq(c, 81), 4n,
        U.choose(Nat, U32.is_eq(c, 65), 7n, 2n))))

def path.params(p: Path, cmd: U32, ps: Params, next: String -> Path -> Path) -> Path:
  Params{vs, tail, valid} = ps
  +state = p
  U.choose(Unit -> Path, valid,
    _ => next(tail)(path.apply(state, cmd, vs)), _ => state)(Unit{})

def path.command(+s: String, +cmd: U32, +p: Path, next: String -> Path -> Path) -> Path:
  # Choosing the continuation first avoids duplicating its affine closure.
  action = U.choose((String -> Path -> Path) -> Path, U32.is_eq(upper(cmd), 90),
    k => k(s)(path.close(p)),
    k => path.params(p, cmd, path.arguments(path.arity(upper(cmd)), s, U32.is_eq(upper(cmd), 65)), k))
  action(next)

def path.scan(+p: Path, s: String, next: String -> Path -> Path) -> Path:
  Path{cur, start, ctrl, cmd, prev, es, trace} = p
  match s:
    case SNil{}: p
    case SCon{Chr{c}, t}:
      +ch = c
      +tail = t
      +letter = (U32.is_ge(ch, 65) && U32.is_le(ch, 90)) || (U32.is_ge(ch, 97) && U32.is_le(ch, 122))
      action = U.choose((String -> Path -> Path) -> Path, letter,
        k => path.command(tail, ch, p, k),
        k => U.choose(Unit -> Path, U32.is_eq(cmd, 0), _ => p,
          _ => path.command(SCon{Chr{ch}, tail}, cmd, p, k))(Unit{}))
      action(next)

@unsafe
def path.loop(s: String, p: Path) -> Path:
  path.scan(p, U.separators(s), t => next => path.loop(t, next))

def path.finish(+p: Path) -> List<&2, Edge>:
  Path{cur, start, ctrl, cmd, prev, es, trace} = p
  U.choose(List<&2, Edge>, U32.is_eq(prev, 0), Nil{}, Con{Edge{cur, start, False{}, False{}}, es})

def path(s: String) -> List<&2, Edge>:
  path.finish(path.loop(s, Path{Point{0.0, 0.0}, Point{0.0, 0.0}, Point{0.0, 0.0}, 0, 0, Nil{}, None{}}))

# Geometry queries use half-open crossings, supporting both SVG fill rules.
def edge.cross(+edge: Edge, +p: Point) -> F32:
  Edge{Point{x1, y1}, Point{x2, y2}, stroked, closed} = edge
  Point{x, y} = p
  U.branch(F32, (F32.is_le(y1, y) && F32.is_gt(y2, y)) || (F32.is_le(y2, y) && F32.is_gt(y1, y)),
    _ => U.choose(F32, F32.is_gt((x1 + (y - y1) * (x2 - x1) / (y2 - y1) : F32), x),
      U.choose(F32, F32.is_gt(y2, y1), 1.0, F32.neg(1.0)), 0.0), _ => 0.0)

def winding(edges: List<&2, Edge>, +p: Point) -> F32:
  match edges:
    case Nil{}: 0.0
    case Con{h, t}: (edge.cross(h, p) + winding(t, p) : F32)

def fill.inside(edges: List<&2, Edge>, p: Point, even: Bool) -> Bool:
  +w = winding(edges, p)
  F32.is_gt(F32.abs(U.choose(F32, even, (w % 2.0 : F32), w)), 0.5)

def edge.distance(+e: Edge, +p: Point) -> F32:
  Edge{a, b, stroked, closed} = e
  +ab = point.sub(b, a)
  +den = point.dot(ab, ab)
  +t = U.clamp((point.dot(point.sub(p, a), ab) / U.max(0.000000000001, den) : F32), 0.0, 1.0)
  U.choose(F32, stroked, point.distance(p, point.add(a, point.scale(ab, t))), 100000000000000000000.0)

def stroke.inside(edges: List<&2, Edge>, +p: Point, +radius: F32) -> Bool:
  match edges:
    case Nil{}: False{}
    case Con{h, t}:
      U.branch(Bool, F32.is_le(edge.distance(h, p), radius), _ => True{},
        _ => stroke.inside(t, p, radius))

type Bounds is Data:
  Bounds{x0: F32, y0: F32, x1: F32, y1: F32}

def bounds.point(+b: Bounds, +p: Point) -> Bounds:
  Bounds{x0, y0, x1, y1} = b
  Point{x, y} = p
  Bounds{U.min(x0, x), U.min(y0, y), U.max(x1, x), U.max(y1, y)}

def bounds(edges: List<&2, Edge>, box: Bounds) -> Bounds:
  match edges:
    case Nil{}: box
    case Con{Edge{a, b, stroked, closed}, t}: bounds(t, bounds.point(bounds.point(box, a), b))

def bounds.inside(b: Bounds, +p: Point, +margin: F32) -> Bool:
  Bounds{x0, y0, x1, y1} = b
  Point{x, y} = p
  F32.is_ge(x, (x0 - margin : F32)) && F32.is_ge(y, (y0 - margin : F32))
    && F32.is_le(x, (x1 + margin : F32)) && F32.is_le(y, (y1 + margin : F32))

def inflate(+data: Bin.Bytes, limit: U32) -> Bin.Inflate:
  Bin.inflate.blocks(Bin.BitStream{data, 0, (Bin.bytes.size(data) * 8 : U32), True{}}, Bin.bytes.empty(), limit)

def color.fade(c: Img.Color, +opacity: F32) -> Img.Color:
  Img.Color{r, g, b, a} = c
  Img.Color{(r * opacity : F32), (g * opacity : F32), (b * opacity : F32), (a * opacity : F32)}

def color.over(+front: Img.Color, back: Img.Color) -> Img.Color:
  Img.Color{r, g, b, a} = front
  Img.Color{x, y, z, w} = back
  Img.Color{(r + x * (1.0 - a) : F32), (g + y * (1.0 - a) : F32),
    (b + z * (1.0 - a) : F32), (a + w * (1.0 - a) : F32)}

def color.add(c: Img.Color, d: Img.Color) -> Img.Color:
  Img.Color{r, g, b, a} = c
  Img.Color{x, y, z, w} = d
  Img.Color{(r + x : F32), (g + y : F32), (b + z : F32), (a + w : F32)}

def byte(+x: U32, n: U32) -> F32:
  (U32.to_f32(U32.mod(U32.div(x, n), 256)) / 255.0 : F32)

type Raster is Data:
  Raster{origin: Point, step: F32, width: U32, height: U32, depth: Nat, linear: Bool, pixels: Img.Pixels}

def color.rgb(+x: U32) -> Img.Color:
  Img.rgba(byte(x, 65536), byte(x, 256), byte(x, 1), 1.0)

def nibble(+x: U32, n: U32) -> F32:
  (U32.to_f32(U32.mod(U32.div(x, n), 16)) / 15.0 : F32)

def color.hex.short(+x: U32, len: U32) -> Img.Color:
  U.choose(Img.Color, U32.is_eq(len, 4), Img.rgba(nibble(x, 4096), nibble(x, 256), nibble(x, 16), nibble(x, 1)),
    Img.rgba(nibble(x, 256), nibble(x, 16), nibble(x, 1), 1.0))

def color.hex(+x: U32, +len: U32) -> Img.Color:
  U.branch(Img.Color, U32.is_eq(len, 3) || U32.is_eq(len, 4),
    _ => color.hex.short(x, len),
    _ => U.choose(Img.Color, U32.is_eq(len, 8), Img.rgba(byte(x, 16777216), byte(x, 65536), byte(x, 256), byte(x, 1)), color.rgb(x)))

def color.named.a(+s: String) -> U32:
  U.branch(U32, String.eq(s, "aliceblue"), _ => 15792383, _ => U.branch(U32, String.eq(s, "antiquewhite"), _ => 16444375, _ => U.branch(U32, String.eq(s, "aqua"), _ => 65535, _ => U.branch(U32, String.eq(s, "aquamarine"), _ => 8388564, _ => U.branch(U32, String.eq(s, "azure"), _ => 15794175, _ => 16777216)))))

def color.named.b(+s: String) -> U32:
  U.branch(U32, String.eq(s, "beige"), _ => 16119260, _ => U.branch(U32, String.eq(s, "bisque"), _ => 16770244, _ => U.branch(U32, String.eq(s, "black"), _ => 0, _ => U.branch(U32, String.eq(s, "blanchedalmond"), _ => 16772045, _ => U.branch(U32, String.eq(s, "blue"), _ => 255, _ => U.branch(U32, String.eq(s, "blueviolet"), _ => 9055202, _ => U.branch(U32, String.eq(s, "brown"), _ => 10824234, _ => U.branch(U32, String.eq(s, "burlywood"), _ => 14596231, _ => 16777216))))))))

def color.named.c(+s: String) -> U32:
  U.branch(U32, String.eq(s, "cadetblue"), _ => 6266528, _ => U.branch(U32, String.eq(s, "chartreuse"), _ => 8388352, _ => U.branch(U32, String.eq(s, "chocolate"), _ => 13789470, _ => U.branch(U32, String.eq(s, "coral"), _ => 16744272, _ => U.branch(U32, String.eq(s, "cornflowerblue"), _ => 6591981, _ => U.branch(U32, String.eq(s, "cornsilk"), _ => 16775388, _ => U.branch(U32, String.eq(s, "crimson"), _ => 14423100, _ => U.branch(U32, String.eq(s, "cyan"), _ => 65535, _ => 16777216))))))))

def color.named.d(+s: String) -> U32:
  U.branch(U32, String.eq(s, "darkblue"), _ => 139, _ => U.branch(U32, String.eq(s, "darkcyan"), _ => 35723, _ => U.branch(U32, String.eq(s, "darkgoldenrod"), _ => 12092939, _ => U.branch(U32, String.eq(s, "darkgray"), _ => 11119017, _ => U.branch(U32, String.eq(s, "darkgreen"), _ => 25600, _ => U.branch(U32, String.eq(s, "darkgrey"), _ => 11119017, _ => U.branch(U32, String.eq(s, "darkkhaki"), _ => 12433259, _ => U.branch(U32, String.eq(s, "darkmagenta"), _ => 9109643, _ => U.branch(U32, String.eq(s, "darkolivegreen"), _ => 5597999, _ => U.branch(U32, String.eq(s, "darkorange"), _ => 16747520, _ => U.branch(U32, String.eq(s, "darkorchid"), _ => 10040012, _ => U.branch(U32, String.eq(s, "darkred"), _ => 9109504, _ => U.branch(U32, String.eq(s, "darksalmon"), _ => 15308410, _ => U.branch(U32, String.eq(s, "darkseagreen"), _ => 9419919, _ => U.branch(U32, String.eq(s, "darkslateblue"), _ => 4734347, _ => U.branch(U32, String.eq(s, "darkslategray"), _ => 3100495, _ => U.branch(U32, String.eq(s, "darkslategrey"), _ => 3100495, _ => U.branch(U32, String.eq(s, "darkturquoise"), _ => 52945, _ => U.branch(U32, String.eq(s, "darkviolet"), _ => 9699539, _ => U.branch(U32, String.eq(s, "deeppink"), _ => 16716947, _ => U.branch(U32, String.eq(s, "deepskyblue"), _ => 49151, _ => U.branch(U32, String.eq(s, "dimgray"), _ => 6908265, _ => U.branch(U32, String.eq(s, "dimgrey"), _ => 6908265, _ => U.branch(U32, String.eq(s, "dodgerblue"), _ => 2003199, _ => 16777216))))))))))))))))))))))))

def color.named.f(+s: String) -> U32:
  U.branch(U32, String.eq(s, "firebrick"), _ => 11674146, _ => U.branch(U32, String.eq(s, "floralwhite"), _ => 16775920, _ => U.branch(U32, String.eq(s, "forestgreen"), _ => 2263842, _ => U.branch(U32, String.eq(s, "fuchsia"), _ => 16711935, _ => 16777216))))

def color.named.g(+s: String) -> U32:
  U.branch(U32, String.eq(s, "gainsboro"), _ => 14474460, _ => U.branch(U32, String.eq(s, "ghostwhite"), _ => 16316671, _ => U.branch(U32, String.eq(s, "gold"), _ => 16766720, _ => U.branch(U32, String.eq(s, "goldenrod"), _ => 14329120, _ => U.branch(U32, String.eq(s, "gray"), _ => 8421504, _ => U.branch(U32, String.eq(s, "green"), _ => 32768, _ => U.branch(U32, String.eq(s, "greenyellow"), _ => 11403055, _ => U.branch(U32, String.eq(s, "grey"), _ => 8421504, _ => 16777216))))))))

def color.named.h(+s: String) -> U32:
  U.branch(U32, String.eq(s, "honeydew"), _ => 15794160, _ => U.branch(U32, String.eq(s, "hotpink"), _ => 16738740, _ => 16777216))

def color.named.i(+s: String) -> U32:
  U.branch(U32, String.eq(s, "indianred"), _ => 13458524, _ => U.branch(U32, String.eq(s, "indigo"), _ => 4915330, _ => U.branch(U32, String.eq(s, "ivory"), _ => 16777200, _ => 16777216)))

def color.named.k(+s: String) -> U32:
  U.branch(U32, String.eq(s, "khaki"), _ => 15787660, _ => 16777216)

def color.named.l(+s: String) -> U32:
  U.branch(U32, String.eq(s, "lavender"), _ => 15132410, _ => U.branch(U32, String.eq(s, "lavenderblush"), _ => 16773365, _ => U.branch(U32, String.eq(s, "lawngreen"), _ => 8190976, _ => U.branch(U32, String.eq(s, "lemonchiffon"), _ => 16775885, _ => U.branch(U32, String.eq(s, "lightblue"), _ => 11393254, _ => U.branch(U32, String.eq(s, "lightcoral"), _ => 15761536, _ => U.branch(U32, String.eq(s, "lightcyan"), _ => 14745599, _ => U.branch(U32, String.eq(s, "lightgoldenrodyellow"), _ => 16448210, _ => U.branch(U32, String.eq(s, "lightgray"), _ => 13882323, _ => U.branch(U32, String.eq(s, "lightgreen"), _ => 9498256, _ => U.branch(U32, String.eq(s, "lightgrey"), _ => 13882323, _ => U.branch(U32, String.eq(s, "lightpink"), _ => 16758465, _ => U.branch(U32, String.eq(s, "lightsalmon"), _ => 16752762, _ => U.branch(U32, String.eq(s, "lightseagreen"), _ => 2142890, _ => U.branch(U32, String.eq(s, "lightskyblue"), _ => 8900346, _ => U.branch(U32, String.eq(s, "lightslategray"), _ => 7833753, _ => U.branch(U32, String.eq(s, "lightslategrey"), _ => 7833753, _ => U.branch(U32, String.eq(s, "lightsteelblue"), _ => 11584734, _ => U.branch(U32, String.eq(s, "lightyellow"), _ => 16777184, _ => U.branch(U32, String.eq(s, "lime"), _ => 65280, _ => U.branch(U32, String.eq(s, "limegreen"), _ => 3329330, _ => U.branch(U32, String.eq(s, "linen"), _ => 16445670, _ => 16777216))))))))))))))))))))))

def color.named.m(+s: String) -> U32:
  U.branch(U32, String.eq(s, "magenta"), _ => 16711935, _ => U.branch(U32, String.eq(s, "maroon"), _ => 8388608, _ => U.branch(U32, String.eq(s, "mediumaquamarine"), _ => 6737322, _ => U.branch(U32, String.eq(s, "mediumblue"), _ => 205, _ => U.branch(U32, String.eq(s, "mediumorchid"), _ => 12211667, _ => U.branch(U32, String.eq(s, "mediumpurple"), _ => 9662683, _ => U.branch(U32, String.eq(s, "mediumseagreen"), _ => 3978097, _ => U.branch(U32, String.eq(s, "mediumslateblue"), _ => 8087790, _ => U.branch(U32, String.eq(s, "mediumspringgreen"), _ => 64154, _ => U.branch(U32, String.eq(s, "mediumturquoise"), _ => 4772300, _ => U.branch(U32, String.eq(s, "mediumvioletred"), _ => 13047173, _ => U.branch(U32, String.eq(s, "midnightblue"), _ => 1644912, _ => U.branch(U32, String.eq(s, "mintcream"), _ => 16121850, _ => U.branch(U32, String.eq(s, "mistyrose"), _ => 16770273, _ => U.branch(U32, String.eq(s, "moccasin"), _ => 16770229, _ => 16777216)))))))))))))))

def color.named.n(+s: String) -> U32:
  U.branch(U32, String.eq(s, "navajowhite"), _ => 16768685, _ => U.branch(U32, String.eq(s, "navy"), _ => 128, _ => 16777216))

def color.named.o(+s: String) -> U32:
  U.branch(U32, String.eq(s, "oldlace"), _ => 16643558, _ => U.branch(U32, String.eq(s, "olive"), _ => 8421376, _ => U.branch(U32, String.eq(s, "olivedrab"), _ => 7048739, _ => U.branch(U32, String.eq(s, "orange"), _ => 16753920, _ => U.branch(U32, String.eq(s, "orangered"), _ => 16729344, _ => U.branch(U32, String.eq(s, "orchid"), _ => 14315734, _ => 16777216))))))

def color.named.p(+s: String) -> U32:
  U.branch(U32, String.eq(s, "palegoldenrod"), _ => 15657130, _ => U.branch(U32, String.eq(s, "palegreen"), _ => 10025880, _ => U.branch(U32, String.eq(s, "paleturquoise"), _ => 11529966, _ => U.branch(U32, String.eq(s, "palevioletred"), _ => 14381203, _ => U.branch(U32, String.eq(s, "papayawhip"), _ => 16773077, _ => U.branch(U32, String.eq(s, "peachpuff"), _ => 16767673, _ => U.branch(U32, String.eq(s, "peru"), _ => 13468991, _ => U.branch(U32, String.eq(s, "pink"), _ => 16761035, _ => U.branch(U32, String.eq(s, "plum"), _ => 14524637, _ => U.branch(U32, String.eq(s, "powderblue"), _ => 11591910, _ => U.branch(U32, String.eq(s, "purple"), _ => 8388736, _ => 16777216)))))))))))

def color.named.r(+s: String) -> U32:
  U.branch(U32, String.eq(s, "rebeccapurple"), _ => 6697881, _ => U.branch(U32, String.eq(s, "red"), _ => 16711680, _ => U.branch(U32, String.eq(s, "rosybrown"), _ => 12357519, _ => U.branch(U32, String.eq(s, "royalblue"), _ => 4286945, _ => 16777216))))

def color.named.s(+s: String) -> U32:
  U.branch(U32, String.eq(s, "saddlebrown"), _ => 9127187, _ => U.branch(U32, String.eq(s, "salmon"), _ => 16416882, _ => U.branch(U32, String.eq(s, "sandybrown"), _ => 16032864, _ => U.branch(U32, String.eq(s, "seagreen"), _ => 3050327, _ => U.branch(U32, String.eq(s, "seashell"), _ => 16774638, _ => U.branch(U32, String.eq(s, "sienna"), _ => 10506797, _ => U.branch(U32, String.eq(s, "silver"), _ => 12632256, _ => U.branch(U32, String.eq(s, "skyblue"), _ => 8900331, _ => U.branch(U32, String.eq(s, "slateblue"), _ => 6970061, _ => U.branch(U32, String.eq(s, "slategray"), _ => 7372944, _ => U.branch(U32, String.eq(s, "slategrey"), _ => 7372944, _ => U.branch(U32, String.eq(s, "snow"), _ => 16775930, _ => U.branch(U32, String.eq(s, "springgreen"), _ => 65407, _ => U.branch(U32, String.eq(s, "steelblue"), _ => 4620980, _ => 16777216))))))))))))))

def color.named.t(+s: String) -> U32:
  U.branch(U32, String.eq(s, "tan"), _ => 13808780, _ => U.branch(U32, String.eq(s, "teal"), _ => 32896, _ => U.branch(U32, String.eq(s, "thistle"), _ => 14204888, _ => U.branch(U32, String.eq(s, "tomato"), _ => 16737095, _ => U.branch(U32, String.eq(s, "turquoise"), _ => 4251856, _ => 16777216)))))

def color.named.v(+s: String) -> U32:
  U.branch(U32, String.eq(s, "violet"), _ => 15631086, _ => 16777216)

def color.named.w(+s: String) -> U32:
  U.branch(U32, String.eq(s, "wheat"), _ => 16113331, _ => U.branch(U32, String.eq(s, "white"), _ => 16777215, _ => U.branch(U32, String.eq(s, "whitesmoke"), _ => 16119285, _ => 16777216)))

def color.named.y(+s: String) -> U32:
  U.branch(U32, String.eq(s, "yellow"), _ => 16776960, _ => U.branch(U32, String.eq(s, "yellowgreen"), _ => 10145074, _ => 16777216))

def color.named.code(+s: String) -> U32:
  U.branch(U32, U.prefix(s, "a"), _ => color.named.a(s), _ => U.branch(U32, U.prefix(s, "b"), _ => color.named.b(s), _ => U.branch(U32, U.prefix(s, "c"), _ => color.named.c(s), _ => U.branch(U32, U.prefix(s, "d"), _ => color.named.d(s), _ => U.branch(U32, U.prefix(s, "f"), _ => color.named.f(s), _ => U.branch(U32, U.prefix(s, "g"), _ => color.named.g(s), _ => U.branch(U32, U.prefix(s, "h"), _ => color.named.h(s), _ => U.branch(U32, U.prefix(s, "i"), _ => color.named.i(s), _ => U.branch(U32, U.prefix(s, "k"), _ => color.named.k(s), _ => U.branch(U32, U.prefix(s, "l"), _ => color.named.l(s), _ => U.branch(U32, U.prefix(s, "m"), _ => color.named.m(s), _ => U.branch(U32, U.prefix(s, "n"), _ => color.named.n(s), _ => U.branch(U32, U.prefix(s, "o"), _ => color.named.o(s), _ => U.branch(U32, U.prefix(s, "p"), _ => color.named.p(s), _ => U.branch(U32, U.prefix(s, "r"), _ => color.named.r(s), _ => U.branch(U32, U.prefix(s, "s"), _ => color.named.s(s), _ => U.branch(U32, U.prefix(s, "t"), _ => color.named.t(s), _ => U.branch(U32, U.prefix(s, "v"), _ => color.named.v(s), _ => U.branch(U32, U.prefix(s, "w"), _ => color.named.w(s), _ => U.branch(U32, U.prefix(s, "y"), _ => color.named.y(s), _ => 16777216))))))))))))))))))))

def color.named(s: String) -> Img.Color:
  +code = color.named.code(s)
  color.rgb(U.choose(U32, U32.is_lt(code, 16777216), code, 0))

# Img.Color arguments retain separators and units; unlike SVG coordinates, these
# functions do not permit adjacent numbers or mixed comma/slash syntax.
type ColorToken is Data:
  ColorToken{value: F32, kind: U32, separator: U32}

def color.word(+s: String, +acc: String) -> U.Scan:
  match s:
    case SNil{}: U.Scan{U.rev(acc, ""), ""}
    case SCon{Chr{c}, tail}:
      U.branch(U.Scan, U.space(c) || U32.is_eq(c, 44) || U32.is_eq(c, 47) || U32.is_eq(c, 41),
        _ => U.Scan{U.rev(acc, ""), s}, _ => color.word(tail, SCon{Chr{c}, acc}))

def color.token.number(num: U.Number, sep: U32) -> ColorToken:
  U.Number{x, unitName, ok} = num
  +u = unitName
  ColorToken{x, U.choose(U32, Bool.not(ok), 7, U.choose(U32, String.eq(u, ""), 0, U.choose(U32, String.eq(u, "%"), 1,
    U.choose(U32, String.eq(u, "deg"), 2, U.choose(U32, String.eq(u, "rad"), 3, U.choose(U32, String.eq(u, "grad"), 4,
      U.choose(U32, String.eq(u, "turn"), 5, 7))))))), sep}

def color.token(+word: String, +sep: U32) -> ColorToken:
  U.branch(ColorToken, String.eq(word, "none"), _ => ColorToken{0.0, 6, sep}, _ => color.token.number(U.number(word), sep))

def color.tokens.word(+scan: U.Scan, next: String -> List<&2, ColorToken>) -> List<&2, ColorToken>:
  U.Scan{word, rest} = scan
  +s = U.trim(rest)
  +token = word
  +comma = U.prefix(s, ",")
  +slash = U.prefix(s, "/")
  +end = U.prefix(s, ")") && String.eq(U.trim(U.drop(s, ")")), "")
  +spaced = Bool.not(String.eq(rest, s))
  +sep = U.choose(U32, end, 0, U.choose(U32, comma, 2, U.choose(U32, slash, 3, U.choose(U32, spaced, 1, 9))))
  +tail = U.choose(String, comma, U.drop(s, ","), U.choose(String, slash, U.drop(s, "/"), s))
  Con{color.token(token, sep), U.choose(Unit -> List<&2, ColorToken>, end || U32.is_eq(sep, 9), _ => Nil{}, _ => next(tail))(Unit{})}

def color.tokens(fuel: Nat, s: String) -> List<&2, ColorToken>:
  match fuel:
    case 0n: Con{ColorToken{0.0, 7, 9}, Nil{}}
    case 1n+n: color.tokens.word(color.word(U.trim(s), ""), rest => color.tokens(n, rest))

def color.component(+kind: U32) -> Bool:
  U32.is_eq(kind, 0) || U32.is_eq(kind, 1) || U32.is_eq(kind, 6)

def color.hue(+x: F32, +kind: U32) -> F32:
  +degrees = U.choose(F32, U32.is_eq(kind, 3), (x * 57.29577951308232 : F32), U.choose(F32, U32.is_eq(kind, 4), (x * 0.9 : F32), U.choose(F32, U32.is_eq(kind, 5), (x * 360.0 : F32), x)))
  (degrees - 360.0 * F32.floor((degrees / 360.0 : F32)) : F32)

def color.hsl.channel(+h: F32, +s: F32, +l: F32, n: F32) -> F32:
  +turn = (n + h / 30.0 : F32)
  +k = (turn - 12.0 * F32.floor((turn / 12.0 : F32)) : F32)
  (l - s * U.min(l, (1.0 - l : F32)) * U.max(F32.neg(1.0), U.min(U.min((k - 3.0 : F32), (9.0 - k : F32)), 1.0)) : F32)

def color.hsl(+h: F32, +s: F32, +l: F32, a: F32) -> Img.Color:
  +sat = U.clamp(s, 0.0, 1.0)
  +light = U.clamp(l, 0.0, 1.0)
  Img.rgba(color.hsl.channel(h, sat, light, 0.0), color.hsl.channel(h, sat, light, 8.0), color.hsl.channel(h, sat, light, 4.0), a)

def color.hwb.mix(c: Img.Color, +white: F32, +black: F32, alpha: F32) -> Img.Color:
  Img.Color{r, g, b, a} = c
  +remaining = (1.0 - white - black : F32)
  Img.rgba((r * remaining + white : F32), (g * remaining + white : F32), (b * remaining + white : F32), alpha)

def color.hwb(h: F32, +w: F32, +b: F32, +a: F32) -> Img.Color:
  +white = U.clamp(w, 0.0, 1.0)
  +black = U.clamp(b, 0.0, 1.0)
  +sum = (white + black : F32)
  +gray = (white / U.max(sum, 0.000001) : F32)
  U.branch(Img.Color, F32.is_ge(sum, 1.0), _ => Img.rgba(gray, gray, gray, a), _ => color.hwb.mix(color.hsl(h, 1.0, 0.5, 1.0), white, black, a))

def color.function.channels(+r: ColorToken, +g: ColorToken, +b: ColorToken, +a: ColorToken, +mode: U32, +alpha: Bool) -> Img.Color:
  ColorToken{rr, kr, sr} = r
  ColorToken{gg, kg, sg} = g
  ColorToken{bb, kb, sb} = b
  ColorToken{aa, ka, sa} = a
  +legacy = U32.is_eq(sr, 2) && U32.is_eq(sg, 2) && U32.is_eq(sb, U.choose(U32, alpha, 2, 0)) && U32.is_eq(sa, 0)
  +modern = U32.is_eq(sr, 1) && U32.is_eq(sg, 1) && U32.is_eq(sb, U.choose(U32, alpha, 3, 0)) && U32.is_eq(sa, 0)
  +rgb = U32.is_eq(mode, 0)
  +hue = U32.is_lt(kr, 7) && Bool.not(U32.is_eq(kr, 1))
  +kinds = color.component(kg) && color.component(kb) && color.component(ka) && U.choose(Bool, rgb, color.component(kr), hue)
  +oldKinds = U32.is_lt(ka, 6) && U.choose(Bool, rgb, U32.is_lt(kr, 2) && U32.is_eq(kr, kg) && U32.is_eq(kr, kb), U32.is_lt(kr, 6) && U32.is_eq(kg, 1) && U32.is_eq(kb, 1))
  +valid = kinds && (modern || (legacy && oldKinds && Bool.not(U32.is_eq(mode, 2))))
  +opacity = U.clamp(U.choose(F32, U32.is_eq(ka, 1), (aa / 100.0 : F32), aa), 0.0, 1.0)
  U.branch(Img.Color, valid,
    _ => U.branch(Img.Color, rgb, _ => Img.rgba(U.clamp((rr / U.choose(F32, U32.is_eq(kr, 1), 100.0, 255.0) : F32), 0.0, 1.0),
      U.clamp((gg / U.choose(F32, U32.is_eq(kg, 1), 100.0, 255.0) : F32), 0.0, 1.0), U.clamp((bb / U.choose(F32, U32.is_eq(kb, 1), 100.0, 255.0) : F32), 0.0, 1.0), opacity),
      _ => U.branch(Img.Color, U32.is_eq(mode, 1), _ => color.hsl(color.hue(rr, kr), (gg / 100.0 : F32), (bb / 100.0 : F32), opacity),
        _ => color.hwb(color.hue(rr, kr), (gg / 100.0 : F32), (bb / 100.0 : F32), opacity))), _ => color.rgb(0))

def color.function.args(xs: List<&2, ColorToken>, mode: U32) -> Img.Color:
  match xs:
    case Con{r, Con{g, Con{b, Nil{}}}}: color.function.channels(r, g, b, ColorToken{1.0, 0, 0}, mode, False{})
    case Con{r, Con{g, Con{b, Con{a, Nil{}}}}}: color.function.channels(r, g, b, a, mode, True{})
    case _: color.rgb(0)

def color.hex.valid(s: String) -> Bool:
  match s:
    case SNil{}: True{}
    case SCon{Chr{c}, rest}:
      +ch = c
      (U.digit(ch) || (U32.is_ge(ch, 97) && U32.is_le(ch, 102))) && color.hex.valid(rest)

def color.hex.string(+s: String) -> Img.Color:
  +n = length(s)
  U.branch(Img.Color, (U32.is_eq(n, 3) || U32.is_eq(n, 4) || U32.is_eq(n, 6) || U32.is_eq(n, 8)) && color.hex.valid(s),
    _ => color.hex(U.hex(s, 0), n), _ => color.rgb(0))

def color.parse(+s: String) -> Img.Color:
  U.branch(Img.Color, U.prefix(s, "#"), _ => color.hex.string(U.drop(s, "#")),
    _ => U.branch(Img.Color, U.prefix(s, "rgb(") || U.prefix(s, "rgba("), _ => color.function.args(color.tokens(4n, U.drop(s, U.choose(String, U.prefix(s, "rgba("), "rgba(", "rgb("))), 0),
    _ => U.branch(Img.Color, U.prefix(s, "hsl(") || U.prefix(s, "hsla("), _ => color.function.args(color.tokens(4n, U.drop(s, U.choose(String, U.prefix(s, "hsla("), "hsla(", "hsl("))), 1),
    _ => U.branch(Img.Color, U.prefix(s, "hwb("), _ => color.function.args(color.tokens(4n, U.drop(s, "hwb(")), 2),
    _ => U.branch(Img.Color, String.eq(s, "none") || String.eq(s, "transparent"), _ => Img.clear(), _ => color.named(s))))))

def color(s: String) -> Img.Color:
  color.parse(CSS.css.lower(U.trim.both(s)))

def color.opacity.number(num: U.Number, fallback: F32) -> F32:
  U.Number{x, tail, ok} = num
  +u = U.trim.both(tail)
  U.clamp(U.choose(F32, ok && (String.eq(u, "") || String.eq(u, "%")), (x / U.choose(F32, String.eq(u, "%"), 100.0, 1.0) : F32), fallback), 0.0, 1.0)

def color.opacity(s: String, fallback: F32) -> F32:
  color.opacity.number(U.number(s), fallback)

def dimension(attrs: List<&2, XML.Attr>, key: String, ref: F32, fallback: String) -> F32:
  U.unit(U.number(XML.attr.get(attrs, key, fallback)), ref)

def xy(x: F32, y: F32) -> String:
  F32.show(x) ++ "," ++ F32.show(y) ++ " "

def shape.rect.path(+x: F32, +y: F32, +w: F32, +h: F32, +rx: F32, +ry: F32) -> String:
  +a = xy(rx, ry) ++ "0 0 1 "
  "M" ++ xy((x + rx : F32), y) ++ "H" ++ F32.show((x + w - rx : F32))
    ++ "A" ++ a ++ xy((x + w : F32), (y + ry : F32)) ++ "V" ++ F32.show((y + h - ry : F32))
    ++ "A" ++ a ++ xy((x + w - rx : F32), (y + h : F32)) ++ "H" ++ F32.show((x + rx : F32))
    ++ "A" ++ a ++ xy(x, (y + h - ry : F32)) ++ "V" ++ F32.show((y + ry : F32))
    ++ "A" ++ a ++ xy((x + rx : F32), y) ++ "Z"

def shape.rect(+as: List<&2, XML.Attr>, +vw: F32, +vh: F32) -> String:
  +w = dimension(as, "width", vw, "0")
  +h = dimension(as, "height", vh, "0")
  +rx = U.min((w / 2.0 : F32), U.max(0.0, dimension(as, "rx", vw, XML.attr.get(as, "ry", "0"))))
  +ry = U.min((h / 2.0 : F32), U.max(0.0, dimension(as, "ry", vh, XML.attr.get(as, "rx", "0"))))
  U.branch(String, F32.is_gt(w, 0.0) && F32.is_gt(h, 0.0),
    _ => shape.rect.path(dimension(as, "x", vw, "0"), dimension(as, "y", vh, "0"), w, h, rx, ry), _ => "")

def shape.ellipse.path(+x: F32, +y: F32, +rx: F32, +ry: F32) -> String:
  U.branch(String, F32.is_gt(rx, 0.0) && F32.is_gt(ry, 0.0),
    _ => "M" ++ xy((x + rx : F32), y) ++ "A" ++ xy(rx, ry) ++ "0 1 1 " ++ xy((x - rx : F32), y)
      ++ "A" ++ xy(rx, ry) ++ "0 1 1 " ++ xy((x + rx : F32), y) ++ "Z", _ => "")

def edges.transform(es: List<&2, Edge>, +m: Matrix) -> List<&2, Edge>:
  match es:
    case Nil{}: Nil{}
    case Con{Edge{a, b, stroked, closed}, rest}:
      Con{Edge{matrix.point(m, a), matrix.point(m, b), stroked, closed}, edges.transform(rest, m)}

def shape.data(+name: String, +as: List<&2, XML.Attr>, +vw: F32, +vh: F32) -> String:
  U.branch(String, String.eq(name, "path"), _ => XML.attr.get(as, "d", ""),
    _ => U.branch(String, String.eq(name, "rect") || String.eq(name, "image") || String.eq(name, "#svg-image"), _ => shape.rect(as, vw, vh),
      _ => U.branch(String, String.eq(name, "circle"),
        _ => shape.ellipse.path(dimension(as, "cx", vw, "0"), dimension(as, "cy", vh, "0"),
          dimension(as, "r", F32.sqrt(((vw * vw + vh * vh) / 2.0 : F32)), "0"),
          dimension(as, "r", F32.sqrt(((vw * vw + vh * vh) / 2.0 : F32)), "0")),
        _ => U.branch(String, String.eq(name, "ellipse"),
          _ => shape.ellipse.path(dimension(as, "cx", vw, "0"), dimension(as, "cy", vh, "0"),
            dimension(as, "rx", vw, "0"), dimension(as, "ry", vh, "0")),
          _ => U.branch(String, String.eq(name, "line"),
            _ => "M" ++ xy(dimension(as, "x1", vw, "0"), dimension(as, "y1", vh, "0"))
              ++ "L" ++ xy(dimension(as, "x2", vw, "0"), dimension(as, "y2", vh, "0")),
            _ => U.branch(String, String.eq(name, "polygon") || String.eq(name, "polyline"),
              _ => "M" ++ XML.attr.get(as, "points", "") ++ U.choose(String, String.eq(name, "polygon"), "Z", ""),
              _ => ""))))))

def shape(+name: String, +as: List<&2, XML.Attr>, +vw: F32, +vh: F32) -> List<&2, Edge>:
  U.branch(List<&2, Edge>, String.eq(name, "#glyph"),
    _ => edges.transform(path(XML.attr.get(as, "d", "")), transform(XML.attr.get(as, "#glyph-transform", ""), identity())),
    _ => path(shape.data(name, as, vw, vh)))

# Paint adjacent glyphs with one shared style as one geometry. This keeps all
# fills together and all strokes together, including overlapping glyphs.
def glyph.edges.append(xs: List<&2, Edge>, ys: List<&2, Edge>) -> List<&2, Edge>:
  match xs:
    case Nil{}: ys
    case Con{h, t}: Con{h, glyph.edges.append(t, ys)}

def glyph.edges(xs: List<&2, XML.Element>) -> List<&2, Edge>:
  match xs:
    case Nil{}: Nil{}
    case Con{XML.Element{n, as, kids, txt}, rest}:
      +attrs = as
      glyph.edges.append(edges.transform(path(XML.attr.get(attrs, "d", "")), transform(XML.attr.get(attrs, "#glyph-transform", ""), identity())), glyph.edges(rest))

def shape.children(+name: String, as: List<&2, XML.Attr>, kids: List<&2, XML.Element>, vw: F32, vh: F32) -> List<&2, Edge>:
  U.branch(List<&2, Edge>, String.eq(name, "#glyph-run"), _ => glyph.edges(kids), _ => shape(name, as, vw, vh))

type MarkerSubpath is Data:
  MarkerSubpath{start: Point, segments: List<&2, MarkerSegment>, closed: Bool}

def marker.segments.reverse(xs: List<&2, MarkerSegment>, acc: List<&2, MarkerSegment>) -> List<&2, MarkerSegment>:
  match xs:
    case Nil{}: acc
    case Con{h, t}: marker.segments.reverse(t, Con{h, acc})

def marker.subpaths.reverse(xs: List<&2, MarkerSubpath>, acc: List<&2, MarkerSubpath>) -> List<&2, MarkerSubpath>:
  match xs:
    case Nil{}: acc
    case Con{h, t}: marker.subpaths.reverse(t, Con{h, acc})

def marker.subpaths(+xs: List<&2, MarkerSegment>, +start: Point, +acc: List<&2, MarkerSegment>, +have: Bool, +done: List<&2, MarkerSubpath>) -> List<&2, MarkerSubpath>:
  match xs:
    case Nil{}: marker.subpaths.reverse(U.choose(List<&2, MarkerSubpath>, have, Con{MarkerSubpath{start, marker.segments.reverse(acc, Nil{}), False{}}, done}, done), Nil{})
    case Con{segment, rest}:
      MarkerSegment{p, q, outgoing, incoming, kind} = segment
      +seg = {MarkerSegment{p, q, outgoing, incoming, kind} : MarkerSegment}
      U.branch(List<&2, MarkerSubpath>, U32.is_eq(kind, 1),
        _ => marker.subpaths(rest, q, Nil{}, True{}, U.choose(List<&2, MarkerSubpath>, have, Con{MarkerSubpath{start, marker.segments.reverse(acc, Nil{}), False{}}, done}, done)),
        _ => U.branch(List<&2, MarkerSubpath>, U32.is_eq(kind, 2),
          _ => marker.subpaths(rest, q, Nil{}, False{}, Con{MarkerSubpath{U.choose(Point, have, start, p), marker.segments.reverse(Con{seg, acc}, Nil{}), True{}}, done}),
          _ => marker.subpaths(rest, U.choose(Point, have, start, p), Con{seg, acc}, True{}, done)))

def marker.first(xs: List<&2, MarkerSegment>, fallback: Point) -> Point:
  match xs:
    case Nil{}: fallback
    case Con{MarkerSegment{p, q, outgoing, incoming, kind}, rest}:
      +v = outgoing
      U.branch(Point, marker.nonzero(v), _ => v, _ => marker.first(rest, fallback))

def marker.last(xs: List<&2, MarkerSegment>, fallback: Point) -> Point:
  match xs:
    case Nil{}: fallback
    case Con{MarkerSegment{p, q, outgoing, incoming, kind}, rest}:
      marker.last(rest, marker.vector(incoming, fallback))

def marker.angle.vector(v: Point) -> F32:
  Point{x, y} = v
  (F32.atan2(y, x) * 57.29577951308232 : F32)

def marker.angle.mean(+a: F32, +b: F32) -> F32:
  +wrap = F32.is_gt(F32.abs((a - b : F32)), 180.0)
  ((a + U.choose(F32, wrap && F32.is_lt(a, b), 360.0, 0.0) + b + U.choose(F32, wrap && F32.is_lt(b, a), 360.0, 0.0)) / 2.0 : F32)

def marker.direction(+incoming: Point, +outgoing: Point) -> F32:
  marker.angle.mean(marker.angle.vector(marker.vector(incoming, outgoing)), marker.angle.vector(marker.vector(outgoing, incoming)))

type MarkerVertex is Data:
  MarkerVertex{point: Point, angle: F32}

@unsafe
def marker.vertices.tail(xs: List<&2, MarkerSegment>, previous: Point, +first: Point, +endAngle: F32) -> List<&2, MarkerVertex>:
  match xs:
    case Nil{}: Nil{}
    case Con{MarkerSegment{p, q, outgoing, incoming, kind}, Nil{}}: Con{MarkerVertex{q, endAngle}, Nil{}}
    case Con{MarkerSegment{p, q, outgoing, incoming, kind}, Con{head, tail}}:
      +before = marker.vector(incoming, previous)
      +remaining = {Con{head, tail} : List<&2, MarkerSegment>}
      Con{MarkerVertex{q, marker.direction(before, marker.first(remaining, first))}, marker.vertices.tail(remaining, before, first, endAngle)}

def marker.vertices.one(+subpath: MarkerSubpath) -> List<&2, MarkerVertex>:
  MarkerSubpath{start, segments, closed} = subpath
  +zero = {Point{0.0, 0.0} : Point}
  +outgoing = marker.first(segments, zero)
  +incoming = marker.last(segments, zero)
  +joined = marker.direction(incoming, outgoing)
  +startAngle = U.choose(F32, closed, joined, marker.angle.vector(outgoing))
  +endAngle = U.choose(F32, closed, joined, marker.angle.vector(incoming))
  Con{MarkerVertex{start, startAngle}, marker.vertices.tail(segments, U.choose(Point, closed, incoming, zero), U.choose(Point, closed, outgoing, zero), endAngle)}

def marker.vertices.append(xs: List<&2, MarkerVertex>, ys: List<&2, MarkerVertex>) -> List<&2, MarkerVertex>:
  match xs:
    case Nil{}: ys
    case Con{h, t}: Con{h, marker.vertices.append(t, ys)}

def marker.vertices(xs: List<&2, MarkerSubpath>) -> List<&2, MarkerVertex>:
  match xs:
    case Nil{}: Nil{}
    case Con{h, t}: marker.vertices.append(marker.vertices.one(h), marker.vertices(t))

def marker.trace.result(trace: Maybe<&2, List<&2, MarkerSegment>>) -> List<&2, MarkerVertex>:
  match trace:
    case None{}: Nil{}
    case Some{segments}: marker.vertices(marker.subpaths(marker.segments.reverse(segments, Nil{}), Point{0.0, 0.0}, Nil{}, False{}, Nil{}))

def marker.trace.path(p: Path) -> List<&2, MarkerVertex>:
  Path{cur, start, ctrl, cmd, prev, es, trace} = p
  marker.trace.result(trace)

def marker.trace(s: String) -> List<&2, MarkerVertex>:
  marker.trace.path(path.loop(s, Path{Point{0.0, 0.0}, Point{0.0, 0.0}, Point{0.0, 0.0}, 0, 0, Nil{}, Some{Nil{}}}))

# Stroke geometry is compiled once. Overlapping parts form a union, so alpha
# is applied once even at joins, caps and self intersections.
type StrokeSettings is Data:
  StrokeSettings{cap: String, join: String, limit: F32, dash: String, offset: String, vector: String}

def stroke.settings() -> StrokeSettings:
  StrokeSettings{"butt", "miter", 4.0, "none", "0", "none"}

def style.value(+as: List<&2, XML.Attr>, key: String, +fallback: String, +initial: String, +inherited: Bool) -> String:
  +v = XML.attr.get(as, key, U.choose(String, inherited, fallback, initial))
  +keyword = CSS.css.lower(U.trim.both(v))
  U.choose(String, String.eq(keyword, "inherit") || (inherited && String.eq(keyword, "unset")), fallback,
    U.choose(String, String.eq(keyword, "initial") || String.eq(keyword, "unset"), initial, v))

def stroke.inherit(s: StrokeSettings, +as: List<&2, XML.Attr>) -> StrokeSettings:
  StrokeSettings{cap, join, limit, dash, offset, vector} = s
  +lim = limit
  StrokeSettings{style.value(as, "stroke-linecap", cap, "butt", True{}), style.value(as, "stroke-linejoin", join, "miter", True{}),
    U.max(0.0, U.scalar(style.value(as, "stroke-miterlimit", F32.show(lim), "4", True{}), lim)),
    style.value(as, "stroke-dasharray", dash, "none", True{}), style.value(as, "stroke-dashoffset", offset, "0", True{}),
    style.value(as, "vector-effect", vector, "none", False{})}

type StrokePart is Data:
  StrokeBand{origin: Point, direction: Point, length: F32, radius: F32}
  StrokeCircle{center: Point, radius: F32}
  StrokeTriangle{a: Point, b: Point, c: Point}
  StrokeSector{center: Point, radius: F32, a: Point, b: Point, sign: F32}

def point.cross(p: Point, q: Point) -> F32:
  Point{x, y} = p
  Point{u, v} = q
  (x * v - y * u : F32)

def point.normal(p: Point) -> Point:
  Point{x, y} = p
  Point{F32.neg(y), x}

def point.unit(+p: Point) -> Point:
  point.scale(p, (1.0 / U.max(0.0000001, F32.sqrt(point.dot(p, p))) : F32))

def stroke.triangle(+a: Point, +b: Point, +c: Point, +p: Point) -> Bool:
  +x = point.cross(point.sub(b, a), point.sub(p, a))
  +y = point.cross(point.sub(c, b), point.sub(p, b))
  +z = point.cross(point.sub(a, c), point.sub(p, c))
  ((F32.is_ge(x, 0.0) && F32.is_ge(y, 0.0) && F32.is_ge(z, 0.0))
    || (F32.is_le(x, 0.0) && F32.is_le(y, 0.0) && F32.is_le(z, 0.0)))
    && F32.is_gt(F32.abs(point.cross(point.sub(b, a), point.sub(c, a))), 0.00000001)

def stroke.part(part: StrokePart, +p: Point) -> Bool:
  match part:
    case StrokeBand{origin, dir, len, r}:
      +q = point.sub(p, origin)
      +u = dir
      +along = point.dot(q, u)
      F32.is_ge(along, 0.0) && F32.is_le(along, len) && F32.is_le(F32.abs(point.cross(q, u)), r)
    case StrokeCircle{center, radius}:
      +q = point.sub(p, center)
      +r = radius
      F32.is_le(point.dot(q, q), (r * r : F32))
    case StrokeTriangle{a, b, c}: stroke.triangle(a, b, c, p)
    case StrokeSector{center, radius, a, b, sign}:
      +q = point.sub(p, center)
      +r = radius
      +sgn = sign
      F32.is_le(point.dot(q, q), (r * r : F32))
        && F32.is_ge((sgn * point.cross(a, q) : F32), 0.0)
        && F32.is_ge((sgn * point.cross(q, b) : F32), 0.0)

def stroke.contains(parts: List<&2, StrokePart>, +p: Point) -> Bool:
  match parts:
    case Nil{}: False{}
    case Con{h, t}: U.branch(Bool, stroke.part(h, p), _ => True{}, _ => stroke.contains(t, p))

def stroke.append(xs: List<&2, StrokePart>, ys: List<&2, StrokePart>) -> List<&2, StrokePart>:
  match xs:
    case Nil{}: ys
    case Con{h, t}: Con{h, stroke.append(t, ys)}

def stroke.cap(+p: Point, +dir: Point, +r: F32, +cap: String, parts: List<&2, StrokePart>) -> List<&2, StrokePart>:
  +rest = parts
  U.branch(List<&2, StrokePart>, String.eq(cap, "round"), _ => Con{StrokeSector{p, r, point.scale(point.normal(dir), F32.neg(1.0)), point.normal(dir), 1.0}, rest},
    _ => U.branch(List<&2, StrokePart>, String.eq(cap, "square"), _ => Con{StrokeBand{p, dir, r, r}, rest}, _ => rest))

def stroke.miter.clipped(+p: Point, +a: Point, +b: Point, +m: Point, +limit: F32,
  parts: List<&2, StrokePart>) -> List<&2, StrokePart>:
  +n = point.unit(point.sub(m, p))
  +distance = point.distance(m, p)
  +da = point.dot(point.sub(a, p), n)
  +db = point.dot(point.sub(b, p), n)
  +ca = point.add(a, point.scale(point.sub(m, a), U.clamp(((limit - da) / (distance - da) : F32), 0.0, 1.0)))
  +cb = point.add(b, point.scale(point.sub(m, b), U.clamp(((limit - db) / (distance - db) : F32), 0.0, 1.0)))
  Con{StrokeTriangle{p, a, ca}, Con{StrokeTriangle{p, ca, cb}, Con{StrokeTriangle{p, cb, b}, parts}}}

def stroke.miter(+p: Point, +a: Point, +b: Point, +u: Point, +v: Point, +r: F32, +limit: F32,
  +join: String, +parts: List<&2, StrokePart>) -> List<&2, StrokePart>:
  +m = point.add(a, point.scale(u, (point.cross(point.sub(b, a), v) / point.cross(u, v) : F32)))
  +distance = point.distance(p, m)
  +bevel = {Con{StrokeTriangle{p, a, b}, parts} : List<&2, StrokePart>}
  U.branch(List<&2, StrokePart>, F32.is_le(distance, (limit * r : F32)),
    _ => Con{StrokeTriangle{p, a, m}, Con{StrokeTriangle{p, m, b}, parts}},
    _ => U.branch(List<&2, StrokePart>, String.eq(join, "miter-clip"),
      _ => stroke.miter.clipped(p, a, b, m, (r * limit : F32), parts), _ => bevel))

def stroke.join(+p: Point, +u: Point, +v: Point, +r: F32, +settings: StrokeSettings,
  +parts: List<&2, StrokePart>) -> List<&2, StrokePart>:
  StrokeSettings{cap, join, limit, dash, offset, vector} = settings
  +turn = point.cross(u, v)
  +sign = U.choose(F32, F32.is_ge(turn, 0.0), 1.0, F32.neg(1.0))
  +n1 = point.scale(point.normal(u), F32.neg(sign))
  +n2 = point.scale(point.normal(v), F32.neg(sign))
  +a = point.add(p, point.scale(n1, r))
  +b = point.add(p, point.scale(n2, r))
  U.branch(List<&2, StrokePart>, F32.is_lt(F32.abs(turn), 0.000001),
    _ => U.choose(List<&2, StrokePart>, String.eq(join, "round") && F32.is_lt(point.dot(u, v), 0.0),
      Con{StrokeSector{p, r, point.scale(point.normal(u), F32.neg(1.0)), point.normal(u), 1.0}, parts}, parts),
    _ => U.branch(List<&2, StrokePart>, String.eq(join, "round"),
      _ => Con{StrokeSector{p, r, n1, n2, sign}, parts},
      _ => U.branch(List<&2, StrokePart>, String.eq(join, "bevel"),
        _ => Con{StrokeTriangle{p, a, b}, parts},
        _ => stroke.miter(p, a, b, u, v, r, limit, join, parts))))

type Subpath is Data:
  Subpath{points: List<&2, Point>, closed: Bool}

def points.rev(xs: List<&2, Point>, acc: List<&2, Point>) -> List<&2, Point>:
  match xs:
    case Nil{}: acc
    case Con{h, t}: points.rev(t, Con{h, acc})

def points.clean(+xs: List<&2, Point>, +previous: Point) -> List<&2, Point>:
  match xs:
    case Nil{}: Nil{}
    case Con{h, t}:
      U.branch(List<&2, Point>, F32.is_lt(point.distance(h, previous), 0.0000001),
        _ => points.clean(t, previous), _ => Con{h, points.clean(t, h)})

def subpath.finish(points: List<&2, Point>, closed: Bool, paths: List<&2, Subpath>) -> List<&2, Subpath>:
  match points:
    case Nil{}: paths
    case Con{h, t}:
      +p = h
      Con{Subpath{points.rev(Con{p, points.clean(t, p)}, Nil{}), closed}, paths}

def edges.rev(es: List<&2, Edge>, acc: List<&2, Edge>) -> List<&2, Edge>:
  match es:
    case Nil{}: acc
    case Con{h, t}: edges.rev(t, Con{h, acc})

def points.add(points: List<&2, Point>, a: Point, b: Point) -> List<&2, Point>:
  match points:
    case Nil{}: Con{b, Con{a, Nil{}}}
    case Con{h, t}: Con{b, Con{h, t}}

def subpaths(+es: List<&2, Edge>, +points: List<&2, Point>, +paths: List<&2, Subpath>) -> List<&2, Subpath>:
  match es:
    case Nil{}: subpath.finish(points, False{}, paths)
    case Con{Edge{a, b, stroked, closed}, rest}:
      +ps = points.add(points, a, b)
      U.branch(List<&2, Subpath>, stroked,
        _ => U.branch(List<&2, Subpath>, closed,
          _ => subpaths(rest, Nil{}, subpath.finish(ps, True{}, paths)),
          _ => subpaths(rest, ps, paths)),
        _ => subpaths(rest, Nil{}, subpath.finish(points, False{}, paths)))

type Segment is Data:
  Segment{p: Point, q: Point, direction: Point, length: F32, distance: F32}

def segments(+points: List<&2, Point>, +distance: F32) -> List<&2, Segment>:
  match points:
    case Nil{}: Nil{}
    case Con{p, Nil{}}: Nil{}
    case Con{p, Con{q, rest}}:
      +len = point.distance(p, q)
      Con{Segment{p, q, point.unit(point.sub(q, p)), len, distance}, segments(Con{q, rest}, (distance + len : F32))}

def segments.length(xs: List<&2, Segment>) -> F32:
  match xs:
    case Nil{}: 0.0
    case Con{Segment{p, q, dir, len, distance}, rest}: (len + segments.length(rest) : F32)

def stroke.previous(previous: Maybe<&2, Segment>, p: Point, dir: Point, r: F32,
  settings: StrokeSettings, parts: List<&2, StrokePart>) -> List<&2, StrokePart>:
  match previous:
    case None{}: parts
    case Some{Segment{a, b, u, len, distance}}: stroke.join(p, u, dir, r, settings, parts)

def stroke.solid.parts(+xs: List<&2, Segment>, previous: Maybe<&2, Segment>, +r: F32,
  +settings: StrokeSettings, parts: List<&2, StrokePart>) -> List<&2, StrokePart>:
  match xs:
    case Nil{}: parts
    case Con{Segment{p, q, dir, len, distance}, rest}:
      stroke.solid.parts(rest, Some{Segment{p, q, dir, len, distance}}, r, settings,
        stroke.previous(previous, p, dir, r, settings, Con{StrokeBand{p, dir, len, r}, parts}))

def stroke.ends(+first: Segment, last: Segment, +closed: Bool, +r: F32, +settings: StrokeSettings,
  +parts: List<&2, StrokePart>) -> List<&2, StrokePart>:
  Segment{a, b, u, flen, fdist} = first
  Segment{p, q, v, len, distance} = last
  StrokeSettings{cap, join, limit, dash, offset, vector} = settings
  +end = q
  +dir = v
  U.branch(List<&2, StrokePart>, closed, _ => stroke.join(a, dir, u, r, settings, parts),
    _ => stroke.cap(end, dir, r, cap, stroke.cap(a, point.scale(u, F32.neg(1.0)), r, cap, parts)))

def segments.last(xs: List<&2, Segment>, fallback: Segment) -> Segment:
  match xs:
    case Nil{}: fallback
    case Con{h, t}: segments.last(t, h)

def stroke.solid.path(+xs: List<&2, Segment>, point: Point, closed: Bool, +r: F32,
  +settings: StrokeSettings, +parts: List<&2, StrokePart>) -> List<&2, StrokePart>:
  match xs:
    case Nil{}:
      StrokeSettings{cap, join, limit, dash, offset, vector} = settings
      +p = point
      stroke.cap(p, Point{1.0, 0.0}, r, cap, stroke.cap(p, Point{F32.neg(1.0), 0.0}, r, cap, parts))
    case Con{h, t}: stroke.ends(h, segments.last(t, h), closed, r, settings, stroke.solid.parts(xs, None{}, r, settings, parts))

def stroke.paths(paths: List<&2, Subpath>, +r: F32, +settings: StrokeSettings, parts: List<&2, StrokePart>) -> List<&2, StrokePart>:
  match paths:
    case Nil{}: parts
    case Con{Subpath{Nil{}, closed}, rest}: stroke.paths(rest, r, settings, parts)
    case Con{Subpath{Con{p, ps}, closed}, rest}:
      +first = p
      stroke.paths(rest, r, settings, stroke.solid.path(segments(Con{first, ps}, 0.0), first, closed, r, settings, parts))

# Dash intervals are measured along each flattened subpath. A dash crossing a
# vertex gets a join; a dash ending there gets a cap instead.
type DashPattern is Data:
  DashPattern{values: List<&2, F32>, period: F32, offset: F32}

type DashCursor is Data:
  DashCursor{remaining: F32, rest: List<&2, F32>, painted: Bool}

type DashRun is Data:
  DashRun{start: F32, end: F32}

def floats.append(xs: List<&2, F32>, ys: List<&2, F32>) -> List<&2, F32>:
  match xs:
    case Nil{}: ys
    case Con{h, t}: Con{h, floats.append(t, ys)}

def floats.count(xs: List<&2, F32>) -> U32:
  match xs:
    case Nil{}: 0
    case Con{h, t}: U32.inc(floats.count(t))

def floats.sum(xs: List<&2, F32>) -> F32:
  match xs:
    case Nil{}: 0.0
    case Con{h, t}: (h + floats.sum(t) : F32)

def floats.negative(xs: List<&2, F32>) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{h, t}: F32.is_lt(h, 0.0) || floats.negative(t)

def dash.skip.units(+s: String) -> String:
  match s:
    case SNil{}: ""
    case SCon{Chr{c}, t}:
      U.branch(String, (U32.is_ge(c, 65) && U32.is_le(c, 90)) || (U32.is_ge(c, 97) && U32.is_le(c, 122)) || U32.is_eq(c, 37),
        _ => dash.skip.units(t), _ => s)

def dash.value(+n: U.Number, ref: F32, next: String -> List<&2, F32>) -> List<&2, F32>:
  U.Number{x, t, valid} = n
  U.choose(Unit -> List<&2, F32>, valid, _ => Con{U.unit(n, ref), next(dash.skip.units(t))}, _ => Nil{})(Unit{})

@unsafe
def dash.values(s: String, +ref: F32) -> List<&2, F32>:
  dash.value(U.number(s), ref, t => dash.values(t, ref))

def dash.pattern.values(+values: List<&2, F32>, offset: F32) -> DashPattern:
  +vs = U.choose(List<&2, F32>, U32.is_eq((floats.count(values) % 2 : U32), 1), floats.append(values, values), values)
  DashPattern{vs, U.choose(F32, floats.negative(vs), 0.0, floats.sum(vs)), offset}

def floats.scale(xs: List<&2, F32>, +factor: F32) -> List<&2, F32>:
  match xs:
    case Nil{}: Nil{}
    case Con{h, t}: Con{(h * factor : F32), floats.scale(t, factor)}

def dash.pattern(settings: StrokeSettings, +ref: F32, +factor: F32) -> DashPattern:
  StrokeSettings{cap, join, limit, dash, offset, vector} = settings
  dash.pattern.values(floats.scale(dash.values(dash, ref), factor), (U.unit(U.number(offset), ref) * factor : F32))

def dash.seek(xs: List<&2, F32>, +offset: F32, +painted: Bool) -> DashCursor:
  match xs:
    case Nil{}: DashCursor{0.0, Nil{}, painted}
    case Con{h, t}:
      +len = h
      +tail = t
      U.branch(DashCursor, F32.is_le(offset, len), _ => DashCursor{(len - offset : F32), tail, painted},
        _ => dash.seek(tail, (offset - len : F32), Bool.not(painted)))

def dash.next(xs: List<&2, F32>, all: List<&2, F32>, painted: Bool) -> DashCursor:
  match xs:
    case Nil{}: dash.seek(all, 0.0, painted)
    case Con{h, t}: DashCursor{h, t, painted}

@unsafe
def dash.walk(+cursor: DashCursor, +all: List<&2, F32>, +position: F32, +total: F32) -> List<&2, DashRun>:
  DashCursor{remaining, rest, painted} = cursor
  +end = U.min(total, (position + remaining : F32))
  +tail = U.branch(List<&2, DashRun>, F32.is_ge(end, total), _ => Nil{},
    _ => dash.walk(dash.next(rest, all, Bool.not(painted)), all, end, total))
  U.choose(List<&2, DashRun>, painted, Con{DashRun{position, end}, tail}, tail)

def dash.runs(+pattern: DashPattern, +total: F32) -> List<&2, DashRun>:
  DashPattern{values, period, offset} = pattern
  U.branch(List<&2, DashRun>, F32.is_le(period, 0.0000001), _ => Con{DashRun{0.0, total}, Nil{}},
    _ => dash.walk(dash.seek(values, (offset - period * F32.floor((offset / period : F32)) : F32), True{}), values, 0.0, total))

def dash.crosses(xs: List<&2, DashRun>, +t: F32) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{DashRun{a, b}, rest}:
      (F32.is_lt(a, t) && F32.is_gt(b, t)) || dash.crosses(rest, t)

def dash.start(xs: List<&2, DashRun>) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{DashRun{a, b}, rest}:
      (F32.is_le(a, 0.0) && F32.is_gt(b, 0.0)) || dash.start(rest)

def dash.end(xs: List<&2, DashRun>, +total: F32) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{DashRun{a, b}, rest}:
      (F32.is_lt(a, total) && F32.is_ge(b, total)) || dash.end(rest, total)

def stroke.run(+seg: Segment, +run: DashRun, +total: F32, +seam: Bool, +r: F32, +cap: String,
  +parts: List<&2, StrokePart>) -> List<&2, StrokePart>:
  Segment{p, q, dir, len, distance} = seg
  DashRun{start, end} = run
  +segEnd = (distance + len : F32)
  +left = U.max(distance, start)
  +right = U.min(segEnd, end)
  +a = point.add(p, point.scale(dir, (left - distance : F32)))
  +b = point.add(p, point.scale(dir, (right - distance : F32)))
  +body = U.choose(List<&2, StrokePart>, F32.is_gt(right, left), Con{StrokeBand{a, dir, (right - left : F32), r}, parts}, parts)
  +withStart = U.choose(List<&2, StrokePart>, F32.is_ge(start, distance) && F32.is_lt(start, segEnd)
    && Bool.not(seam && F32.is_eq(start, 0.0)), stroke.cap(a, point.scale(dir, F32.neg(1.0)), r, cap, body), body)
  U.branch(List<&2, StrokePart>, F32.is_ge(right, left),
    _ => U.choose(List<&2, StrokePart>, (F32.is_gt(end, distance) || (F32.is_eq(start, end) && F32.is_eq(start, distance))) && F32.is_le(end, segEnd)
      && Bool.not(seam && F32.is_eq(end, total)), stroke.cap(b, dir, r, cap, withStart), withStart), _ => parts)

def stroke.runs(xs: List<&2, DashRun>, +seg: Segment, +total: F32, +seam: Bool, +r: F32, +cap: String,
  parts: List<&2, StrokePart>) -> List<&2, StrokePart>:
  match xs:
    case Nil{}: parts
    case Con{h, t}: stroke.runs(t, seg, total, seam, r, cap, stroke.run(seg, h, total, seam, r, cap, parts))

def stroke.dashed.parts(+xs: List<&2, Segment>, previous: Maybe<&2, Segment>, +runs: List<&2, DashRun>,
  +total: F32, +seam: Bool, +r: F32, +settings: StrokeSettings, +parts: List<&2, StrokePart>) -> List<&2, StrokePart>:
  match xs:
    case Nil{}: parts
    case Con{Segment{p, q, dir, len, distance}, rest}:
      StrokeSettings{cap, join, limit, dash, offset, vector} = settings
      +joins = U.choose(List<&2, StrokePart>, dash.crosses(runs, distance),
        stroke.previous(previous, p, dir, r, settings, parts), parts)
      stroke.dashed.parts(rest, Some{Segment{p, q, dir, len, distance}}, runs, total, seam, r, settings,
        stroke.runs(runs, Segment{p, q, dir, len, distance}, total, seam, r, cap, joins))

def dash.any(xs: List<&2, DashRun>) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{h, t}: True{}

def stroke.dashed.path(+xs: List<&2, Segment>, point: Point, closed: Bool, +r: F32,
  +settings: StrokeSettings, +pattern: DashPattern, +parts: List<&2, StrokePart>) -> List<&2, StrokePart>:
  match xs:
    case Nil{}: U.branch(List<&2, StrokePart>, dash.any(dash.runs(pattern, 0.0)),
      _ => stroke.solid.path(xs, point, closed, r, settings, parts), _ => parts)
    case Con{h, t}:
      +total = segments.length(xs)
      +runs = dash.runs(pattern, total)
      +seam = closed && dash.start(runs) && dash.end(runs, total)
      +body = stroke.dashed.parts(xs, None{}, runs, total, seam, r, settings, parts)
      U.branch(List<&2, StrokePart>, seam, _ => stroke.ends(h, segments.last(t, h), True{}, r, settings, body), _ => body)

def stroke.dashed.paths(paths: List<&2, Subpath>, +r: F32, +settings: StrokeSettings, +pattern: DashPattern,
  parts: List<&2, StrokePart>) -> List<&2, StrokePart>:
  match paths:
    case Nil{}: parts
    case Con{Subpath{Nil{}, closed}, rest}: stroke.dashed.paths(rest, r, settings, pattern, parts)
    case Con{Subpath{Con{p, ps}, closed}, rest}:
      +first = p
      stroke.dashed.paths(rest, r, settings, pattern, stroke.dashed.path(segments(Con{first, ps}, 0.0), first, closed, r, settings, pattern, parts))

def subpaths.length(paths: List<&2, Subpath>) -> F32:
  match paths:
    case Nil{}: 0.0
    case Con{Subpath{points, closed}, rest}: (segments.length(segments(points, 0.0)) + subpaths.length(rest) : F32)

def stroke.compile.paths(+paths: List<&2, Subpath>, r: F32, +settings: StrokeSettings, ref: F32, +declared: F32) -> List<&2, StrokePart>:
  +factor = U.choose(F32, F32.is_gt(declared, 0.0), (subpaths.length(paths) / declared : F32), 1.0)
  stroke.dashed.paths(paths, r, settings, dash.pattern(settings, ref, factor), Nil{})

def stroke.compile(es: List<&2, Edge>, r: F32, settings: StrokeSettings, ref: F32, declared: F32) -> List<&2, StrokePart>:
  stroke.compile.paths(subpaths(edges.rev(es, Nil{}), Nil{}, Nil{}), r, settings, ref, declared)

# Balanced bounds hierarchy skips stroke pieces outside the sample's neighborhood.
type StrokeTree is Data:
  StrokeEmpty{}
  StrokeLeaf{box: Bounds, part: StrokePart}
  StrokeFork{box: Bounds, left: StrokeTree, right: StrokeTree}

def bounds.empty() -> Bounds:
  Bounds{1000000000.0, 1000000000.0, F32.neg(1000000000.0), F32.neg(1000000000.0)}

def bounds.merge(a: Bounds, b: Bounds) -> Bounds:
  Bounds{x0, y0, x1, y1} = a
  Bounds{u0, v0, u1, v1} = b
  Bounds{U.min(x0, u0), U.min(y0, v0), U.max(x1, u1), U.max(y1, v1)}

# Ray queries skip edge branches whose bounds cannot cross the sample's row.
type EdgeTree is Data:
  EdgeEmpty{}
  EdgeLeaf{box: Bounds, edge: Edge}
  EdgeFork{box: Bounds, left: EdgeTree, right: EdgeTree}

def edge.tree.bounds(t: EdgeTree) -> Bounds:
  match t:
    case EdgeEmpty{}: bounds.empty()
    case EdgeLeaf{box, edge}: box
    case EdgeFork{box, left, right}: box

def edge.tree.fork(+a: EdgeTree, +b: EdgeTree) -> EdgeTree:
  EdgeFork{bounds.merge(edge.tree.bounds(a), edge.tree.bounds(b)), a, b}

def edges.count(xs: List<&2, Edge>) -> U32:
  match xs:
    case Nil{}: 0
    case Con{h, t}: U32.inc(edges.count(t))

def edges.take(n: Nat, xs: List<&2, Edge>) -> List<&2, Edge>:
  match n xs:
    case 0n _: Nil{}
    case 1n+d Nil{}: Nil{}
    case 1n+d Con{h, t}: Con{h, edges.take(d, t)}

def edges.drop(n: Nat, xs: List<&2, Edge>) -> List<&2, Edge>:
  match n xs:
    case 0n _: xs
    case 1n+d Nil{}: Nil{}
    case 1n+d Con{h, t}: edges.drop(d, t)

@unsafe
def edge.tree.build(+xs: List<&2, Edge>, +count: U32) -> EdgeTree:
  match xs:
    case Nil{}: EdgeEmpty{}
    case Con{h, t}:
      +half = U32.div(count, 2)
      U.branch(EdgeTree, U32.is_le(count, 1), _ => EdgeLeaf{bounds(Con{h, Nil{}}, bounds.empty()), h},
        _ => edge.tree.fork(edge.tree.build(edges.take(U32.to_nat(half), xs), half),
          edge.tree.build(edges.drop(U32.to_nat(half), xs), (count - half : U32))))

def edge.tree(+es: List<&2, Edge>) -> EdgeTree:
  edge.tree.build(es, edges.count(es))

def bounds.ray(b: Bounds, p: Point) -> Bool:
  Bounds{x0, y0, x1, y1} = b
  Point{x, y} = p
  +py = y
  F32.is_ge(py, y0) && F32.is_lt(py, y1) && F32.is_le(x, x1)

def edge.tree.winding(t: EdgeTree, +p: Point) -> F32:
  match t:
    case EdgeEmpty{}: 0.0
    case EdgeLeaf{box, edge}: edge.cross(edge, p)
    case EdgeFork{box, left, right}: U.branch(F32, bounds.ray(box, p),
      _ => (edge.tree.winding(left, p) + edge.tree.winding(right, p) : F32), _ => 0.0)

def edge.tree.inside(t: EdgeTree, p: Point, even: Bool) -> Bool:
  +w = edge.tree.winding(t, p)
  F32.is_gt(F32.abs(U.choose(F32, even, (w % 2.0 : F32), w)), 0.5)

# A fill keeps its edge tree for point queries and picking; a cover, once built
# for a raster, gives each pixel its exact coverage.
type Fill is Data:
  Fill{tree: EdgeTree, cover: Cover}

def fill.new(+es: List<&2, Edge>) -> Fill:
  Fill{edge.tree(es), cover.none()}

def fill.bounds(f: Fill) -> Bounds:
  Fill{tree, cover} = f
  edge.tree.bounds(tree)

def fill.coverage(f: Fill, +q: Point, +p: Point, +even: Bool) -> F32:
  Fill{tree, cover} = f
  +cov = cover
  U.branch(F32, cover.present(cov), _ => cover.at(cov, p), _ => U.choose(F32, edge.tree.inside(tree, q, even), 1.0, 0.0))

def bounds.disk(p: Point, +r: F32) -> Bounds:
  Point{x, y} = p
  +px = x
  +py = y
  Bounds{(px - r : F32), (py - r : F32), (px + r : F32), (py + r : F32)}

def stroke.bounds(+part: StrokePart) -> Bounds:
  match part:
    case StrokeBand{origin, dir, len, r}:
      +p = origin
      +q = point.add(p, point.scale(dir, len))
      +n = point.scale(point.normal(dir), r)
      bounds.point(bounds.point(bounds.point(bounds.point(bounds.empty(), point.add(p, n)), point.sub(p, n)), point.add(q, n)), point.sub(q, n))
    case StrokeCircle{p, r}: bounds.disk(p, r)
    case StrokeSector{p, r, a, b, sign}: bounds.disk(p, r)
    case StrokeTriangle{a, b, c}: bounds.point(bounds.point(bounds.point(bounds.empty(), a), b), c)

def stroke.tree.bounds(t: StrokeTree) -> Bounds:
  match t:
    case StrokeEmpty{}: bounds.empty()
    case StrokeLeaf{box, part}: box
    case StrokeFork{box, left, right}: box

def stroke.tree.fork(+a: StrokeTree, +b: StrokeTree) -> StrokeTree:
  StrokeFork{bounds.merge(stroke.tree.bounds(a), stroke.tree.bounds(b)), a, b}

def stroke.count(xs: List<&2, StrokePart>) -> U32:
  match xs:
    case Nil{}: 0
    case Con{h, t}: U32.inc(stroke.count(t))

def stroke.take(n: Nat, xs: List<&2, StrokePart>) -> List<&2, StrokePart>:
  match n xs:
    case 0n _: Nil{}
    case 1n+d Nil{}: Nil{}
    case 1n+d Con{h, t}: Con{h, stroke.take(d, t)}

def stroke.drop(n: Nat, xs: List<&2, StrokePart>) -> List<&2, StrokePart>:
  match n xs:
    case 0n _: xs
    case 1n+d Nil{}: Nil{}
    case 1n+d Con{h, t}: stroke.drop(d, t)

@unsafe
def stroke.tree(+xs: List<&2, StrokePart>, +count: U32) -> StrokeTree:
  match xs:
    case Nil{}: StrokeEmpty{}
    case Con{h, t}:
      +half = U32.div(count, 2)
      U.branch(StrokeTree, U32.is_le(count, 1), _ => StrokeLeaf{stroke.bounds(h), h},
        _ => stroke.tree.fork(stroke.tree(stroke.take(U32.to_nat(half), xs), half),
          stroke.tree(stroke.drop(U32.to_nat(half), xs), (count - half : U32))))

def stroke.tree.inside(t: StrokeTree, +p: Point) -> Bool:
  match t:
    case StrokeEmpty{}: False{}
    case StrokeLeaf{box, part}: U.branch(Bool, bounds.inside(box, p, 0.00001), _ => stroke.part(part, p), _ => False{})
    case StrokeFork{box, left, right}: U.branch(Bool, bounds.inside(box, p, 0.00001),
      _ => U.branch(Bool, stroke.tree.inside(left, p), _ => True{}, _ => stroke.tree.inside(right, p)), _ => False{})

type StrokeMesh is Data:
  StrokeMesh{tree: StrokeTree, inverse: Matrix, cover: Cover}

def stroke.mesh(+parts: List<&2, StrokePart>, inverse: Matrix) -> StrokeMesh:
  StrokeMesh{stroke.tree(parts, stroke.count(parts)), inverse, cover.none()}

def stroke.mesh.inside(mesh: StrokeMesh, p: Point) -> Bool:
  StrokeMesh{stree, inv, cover} = mesh
  stroke.tree.inside(stree, matrix.point(inv, p))

def stroke.coverage(mesh: StrokeMesh, +p: Point) -> F32:
  StrokeMesh{stree, inv, cover} = mesh
  +cov = cover
  U.branch(F32, cover.present(cov), _ => cover.at(cov, p), _ => U.choose(F32, stroke.tree.inside(stree, matrix.point(inv, p)), 1.0, 0.0))

type MarkerStyle is Data:
  MarkerStyle{start: String, middle: String, end: String}

def marker.style(ms: MarkerStyle, +as: List<&2, XML.Attr>) -> MarkerStyle:
  MarkerStyle{start, middle, end} = ms
  MarkerStyle{style.value(as, "marker-start", start, "none", True{}), style.value(as, "marker-mid", middle, "none", True{}), style.value(as, "marker-end", end, "none", True{})}

# Normalize the small CSS paint-order vocabulary; omitted operations follow in
# default fill/stroke/markers order. Invalid values retain the inherited order.
def paint.order.normalize(s: String, +out: String, +gap: Bool) -> String:
  match s:
    case SNil{}: out
    case SCon{Chr{c}, rest}:
      +ch = c
      +tail = rest
      U.branch(String, U.space(ch), _ => paint.order.normalize(tail, out, Bool.not(String.eq(out, ""))),
        _ => paint.order.normalize(tail, out ++ U.choose(String, gap, " ", "") ++ SCon{Chr{ch}, SNil{}}, False{}))

def paint.order.name(+order: U32) -> String:
  U.choose(String, U32.is_eq(order, 1), "fill markers stroke", U.choose(String, U32.is_eq(order, 2), "stroke fill markers",
    U.choose(String, U32.is_eq(order, 3), "stroke markers fill", U.choose(String, U32.is_eq(order, 4), "markers fill stroke",
      U.choose(String, U32.is_eq(order, 5), "markers stroke fill", "normal")))))

def paint.order.value(+s: String, fallback: U32) -> U32:
  +v = paint.order.normalize(CSS.css.lower(U.trim.both(s)), "", False{})
  U.choose(U32, String.eq(v, "normal") || String.eq(v, "fill") || String.eq(v, "fill stroke") || String.eq(v, "fill stroke markers"), 0,
    U.choose(U32, String.eq(v, "fill markers") || String.eq(v, "fill markers stroke"), 1,
      U.choose(U32, String.eq(v, "stroke") || String.eq(v, "stroke fill") || String.eq(v, "stroke fill markers"), 2,
        U.choose(U32, String.eq(v, "stroke markers") || String.eq(v, "stroke markers fill"), 3,
          U.choose(U32, String.eq(v, "markers") || String.eq(v, "markers fill") || String.eq(v, "markers fill stroke"), 4,
            U.choose(U32, String.eq(v, "markers stroke") || String.eq(v, "markers stroke fill"), 5, fallback))))))

# Compilation resolves geometry and inherited presentation once per edit.
type Style is Data:
  Style{fill: String, stroke: String, color: String, fillOpacity: F32,
    strokeOpacity: F32, width: F32, even: Bool, visible: Bool, strokeSettings: StrokeSettings, markers: MarkerStyle, imageRendering: String, paintOrder: U32}

def style.default() -> Style:
  Style{"black", "none", "black", 1.0, 1.0, 1.0, False{}, True{}, stroke.settings(), MarkerStyle{"none", "none", "none"}, "auto", 0}

def style.inherit(+s: Style, +as: List<&2, XML.Attr>, ref: F32) -> Style:
  Style{fill, stroke, col, fo, so, width, even, visible, ss, ms, rendering, order} = s
  +po = order
  Style{style.value(as, "fill", fill, "black", True{}), style.value(as, "stroke", stroke, "none", True{}), style.value(as, "color", col, "black", True{}),
    color.opacity(style.value(as, "fill-opacity", F32.show(fo), "1", True{}), fo),
    color.opacity(style.value(as, "stroke-opacity", F32.show(so), "1", True{}), so),
    U.max(0.0, U.unit(U.number(style.value(as, "stroke-width", F32.show(width), "1", True{})), ref)),
    String.eq(style.value(as, "fill-rule", U.choose(String, even, "evenodd", "nonzero"), "nonzero", True{}), "evenodd"),
    String.eq(style.value(as, "visibility", U.choose(String, visible, "visible", "hidden"), "visible", True{}), "visible"), stroke.inherit(ss, as), marker.style(ms, as), style.value(as, "image-rendering", rendering, "auto", True{}), paint.order.value(style.value(as, "paint-order", paint.order.name(po), "normal", True{}), po)}

# Gradient resources are compiled into paint functions before rasterization.
type Stop is Data:
  Stop{offset: F32, color: Img.Color}

type Clip is Data:
  ClipAll{}
  ClipShape{edges: EdgeTree, inverse: Matrix, even: Bool, cover: Cover}
  ClipUnion{left: Clip, right: Clip}
  ClipIntersect{left: Clip, right: Clip}

type Paint<-B: Data> is Data:
  Paint{fill: B, stroke: B}

type FilterEffect is Data:
  NoFilter{}
  FilterSpec{region: Bounds, units: Matrix, viewport: Point, attrs: List<&2, XML.Attr>, primitives: List<&2, XML.Element>}
  FilterImage{raster: Raster}

type Scene<-B: Data> is Data:
  Scene{edges: List<&2, Edge>, bounds: Bounds, inverse: Matrix, style: Style,
    opacity: F32, children: List<&2, Scene<B>>, id: String, paint: Paint<B>, clip: Clip, outline: StrokeMesh, fill: Fill, maskNodes: List<&2, Scene<B>>, maskMode: U32, markerNodes: List<&2, Scene<B>>, coverage: Bounds, effect: FilterEffect}

type Brush is Data:
  Bitmap{raster: Raster, inverse: Matrix, nearest: Bool}
  Solid{value: Img.Color, source: Img.Color}
  PendingContext{stroke: Bool, opacity: F32}
  ContextPaint{source: Brush, matrix: Matrix, opacity: F32}
  Pattern{inverse: Matrix, width: F32, height: F32, opacity: F32, nodes: List<&2, Scene<Brush>>}
  Tile{raster: Raster, inverse: Matrix, width: F32, height: F32, opacity: F32, u: Point, v: Point, grid: U32}
  Gradient{inverse: Matrix, radial: Bool, start: Point, end: Point, radius: F32,
    focalRadius: F32, stops: List<&2, Stop>, spread: U32, opacity: F32, linear: Bool}

def gradient.has.stops(xs: List<&2, XML.Element>) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{XML.Element{n, as, kids, txt}, rest}: String.eq(n, "stop") || gradient.has.stops(rest)

def gradient.merge(local: XML.Element, template: XML.Element) -> XML.Element:
  XML.Element{n, as, kids, txt} = local
  XML.Element{tn, tas, tkids, ttxt} = template
  +children = kids
  XML.Element{n, XML.attrs.append(as, tas), U.choose(List<&2, XML.Element>, gradient.has.stops(children), children, tkids), txt}

def gradient.reference(+node: XML.Element, result: Maybe<&2, XML.Element>, next: XML.Element -> XML.Element) -> XML.Element:
  match result:
    case None{}: node
    case Some{e}: gradient.merge(node, next(e))

def gradient.resolve(depth: Nat, +node: XML.Element, +all: List<&2, XML.Element>) -> XML.Element:
  match depth:
    case 0n: node
    case 1n+d:
      XML.Element{n, as, kids, txt} = node
      +href = XML.attr.get(as, "href", XML.attr.get(as, "xlink:href", ""))
      U.branch(XML.Element, U.prefix(href, "#"),
        _ => gradient.reference(node, XML.element.find(all, U.drop(href, "#")), e => gradient.resolve(d, e, all)), _ => node)

def srgb.linear(+v: F32) -> F32:
  U.branch(F32, F32.is_le(v, 0.04045), _ => (v / 12.92 : F32), _ => F32.pow(((v + 0.055) / 1.055 : F32), 2.4))

def linear.srgb(+v: F32) -> F32:
  U.branch(F32, F32.is_le(v, 0.0031308), _ => (v * 12.92 : F32),
    _ => (1.055 * F32.pow(v, 0.4166666666666667) - 0.055 : F32))

def stop.color(c: Img.Color, opacity: F32, +linear: Bool) -> Img.Color:
  Img.Color{r, g, b, a} = c
  +alpha = a
  +rr = (r / U.max(0.0000001, alpha) : F32)
  +gg = (g / U.max(0.0000001, alpha) : F32)
  +bb = (b / U.max(0.0000001, alpha) : F32)
  Img.Color{U.choose(F32, linear, srgb.linear(rr), rr), U.choose(F32, linear, srgb.linear(gg), gg),
    U.choose(F32, linear, srgb.linear(bb), bb), (alpha * opacity : F32)}

def property.value(+as: List<&2, XML.Attr>, +parent: List<&2, XML.Attr>, +key: String, +initial: String, inherited: Bool) -> String:
  style.value(as, key, XML.attr.get(parent, key, initial), initial, inherited)

def resources.markers(+as: List<&2, XML.Attr>, +parent: List<&2, XML.Attr>) -> List<&2, XML.Attr>:
  Con{XML.Attr{"marker-start", property.value(as, parent, "marker-start", "none", True{})}, Con{XML.Attr{"marker-mid", property.value(as, parent, "marker-mid", "none", True{})}, Con{XML.Attr{"marker-end", property.value(as, parent, "marker-end", "none", True{})}, as}}}

def resources.filter.colors(+as: List<&2, XML.Attr>, +parent: List<&2, XML.Attr>) -> List<&2, XML.Attr>:
  Con{XML.Attr{"image-rendering", property.value(as, parent, "image-rendering", "auto", True{})}, Con{XML.Attr{"color-interpolation-filters", property.value(as, parent, "color-interpolation-filters", "linearRGB", True{})}, Con{XML.Attr{"flood-color", property.value(as, parent, "flood-color", "black", False{})}, Con{XML.Attr{"flood-opacity", property.value(as, parent, "flood-opacity", "1", False{})}, resources.markers(as, parent)}}}}

def resources.paint(+as: List<&2, XML.Attr>, +parent: List<&2, XML.Attr>) -> List<&2, XML.Attr>:
  Con{XML.Attr{"fill", property.value(as, parent, "fill", "black", True{})},
    Con{XML.Attr{"stroke", property.value(as, parent, "stroke", "none", True{})},
    Con{XML.Attr{"stroke-width", property.value(as, parent, "stroke-width", "1", True{})},
    Con{XML.Attr{"fill-opacity", property.value(as, parent, "fill-opacity", "1", True{})},
    Con{XML.Attr{"stroke-opacity", property.value(as, parent, "stroke-opacity", "1", True{})},
    Con{XML.Attr{"fill-rule", property.value(as, parent, "fill-rule", "nonzero", True{})},
    Con{XML.Attr{"clip-rule", property.value(as, parent, "clip-rule", "nonzero", True{})},
    Con{XML.Attr{"stroke-linecap", property.value(as, parent, "stroke-linecap", "butt", True{})},
    Con{XML.Attr{"stroke-linejoin", property.value(as, parent, "stroke-linejoin", "miter", True{})},
    Con{XML.Attr{"stroke-miterlimit", property.value(as, parent, "stroke-miterlimit", "4", True{})},
    Con{XML.Attr{"stroke-dasharray", property.value(as, parent, "stroke-dasharray", "none", True{})},
    Con{XML.Attr{"stroke-dashoffset", property.value(as, parent, "stroke-dashoffset", "0", True{})},
    Con{XML.Attr{"visibility", property.value(as, parent, "visibility", "visible", True{})},
    Con{XML.Attr{"opacity", property.value(as, parent, "opacity", "1", False{})}, resources.filter.colors(as, parent)}}}}}}}}}}}}}}

def resources(xs: List<&2, XML.Element>, +parent: List<&2, XML.Attr>) -> List<&2, XML.Element>:
  match xs:
    case Nil{}: Nil{}
    case Con{XML.Element{n, attrs, kids, txt}, rest}:
      +as = CSS.properties(attrs)
      +props = {Con{XML.Attr{"color", property.value(as, parent, "color", "black", True{})},
        Con{XML.Attr{"color-interpolation", property.value(as, parent, "color-interpolation", "sRGB", True{})},
          Con{XML.Attr{"stop-color", property.value(as, parent, "stop-color", "black", False{})},
            Con{XML.Attr{"stop-opacity", property.value(as, parent, "stop-opacity", "1", False{})}, resources.paint(as, parent)}}}} : List<&2, XML.Attr>}
      Con{XML.Element{n, props, resources(kids, props), txt}, resources(rest, parent)}

def gradient.stops(xs: List<&2, XML.Element>, +as: List<&2, XML.Attr>, +previous: F32, +linear: Bool) -> List<&2, Stop>:
  match xs:
    case Nil{}: Nil{}
    case Con{XML.Element{n, attrs, kids, txt}, rest}:
      +props = CSS.properties(attrs)
      +offset = U.max(previous, U.clamp(U.unit(U.number(XML.attr.get(props, "offset", "0")), 1.0), 0.0, 1.0))
      +col = XML.attr.get(props, "stop-color", "black")
      +tail = rest
      U.branch(List<&2, Stop>, String.eq(n, "stop"),
        _ => Con{Stop{offset, stop.color(color(U.choose(String, String.eq(CSS.css.lower(U.trim.both(col)), "currentcolor"),
          XML.attr.get(props, "color", XML.attr.get(as, "color", "black")), col)), U.clamp(U.unit(U.number(XML.attr.get(props, "stop-opacity", "1")), 1.0), 0.0, 1.0), linear)},
          gradient.stops(tail, as, offset, linear)}, _ => gradient.stops(tail, as, previous, linear))

def gradient.mix(+a: Img.Color, +b: Img.Color, +t: F32) -> Img.Color:
  color.add(color.fade(a, (1.0 - t : F32)), color.fade(b, t))

def gradient.interval(xs: List<&2, Stop>, +previous: Stop, +t: F32) -> Img.Color:
  match xs:
    case Nil{}:
      Stop{o, c} = previous
      c
    case Con{Stop{o, c}, rest}:
      Stop{po, pc} = previous
      +offset = o
      +ink = c
      U.branch(Img.Color, F32.is_lt(t, offset),
        _ => gradient.mix(pc, ink, U.clamp(((t - po) / U.max(0.0000001, (offset - po : F32)) : F32), 0.0, 1.0)),
        _ => gradient.interval(rest, Stop{offset, ink}, t))

def gradient.color(xs: List<&2, Stop>, +t: F32) -> Img.Color:
  match xs:
    case Nil{}: Img.clear()
    case Con{Stop{o, c}, rest}:
      +ink = c
      +offset = o
      U.branch(Img.Color, F32.is_lt(t, offset), _ => ink,
        _ => gradient.interval(rest, Stop{offset, ink}, t))

def gradient.spread(+t: F32, +mode: U32) -> F32:
  +repeat = (t - F32.floor(t) : F32)
  +period = (t - 2.0 * F32.floor((t / 2.0 : F32)) : F32)
  U.choose(F32, U32.is_eq(mode, 1), repeat,
    U.choose(F32, U32.is_eq(mode, 2), (1.0 - F32.abs((period - 1.0 : F32)) : F32), U.clamp(t, 0.0, 1.0)))

def gradient.finish(c: Img.Color, opacity: F32, +linear: Bool) -> Img.Color:
  Img.Color{r, g, b, a} = c
  +rr = r
  +gg = g
  +bb = b
  Img.rgba(U.choose(F32, linear, linear.srgb(rr), rr), U.choose(F32, linear, linear.srgb(gg), gg),
    U.choose(F32, linear, linear.srgb(bb), bb), (a * opacity : F32))

type Parameter is Data:
  Parameter{value: F32, valid: Bool}

def radial.roots(+a: F32, +b: F32, +c: F32, +fr: F32, +dr: F32) -> Parameter:
  +disc = (b * b - 4.0 * a * c : F32)
  +root = F32.sqrt(U.max(0.0, disc))
  +t0 = ((0.0 - b - root) / (2.0 * a) : F32)
  +t1 = ((0.0 - b + root) / (2.0 * a) : F32)
  +t = U.max(t0, t1)
  Parameter{t, F32.is_ge(disc, 0.0) && F32.is_ge((fr + t * dr : F32), 0.0)}

def radial.parameter(+p: Point, +start: Point, +end: Point, +r: F32, +fr: F32) -> Parameter:
  +q = point.sub(p, start)
  +d = point.sub(end, start)
  +dr = (r - fr : F32)
  +a = (point.dot(d, d) - dr * dr : F32)
  +b = (0.0 - 2.0 * (point.dot(q, d) + fr * dr) : F32)
  +c = (point.dot(q, q) - fr * fr : F32)
  U.branch(Parameter, F32.is_lt(r, 0.0000001), _ => Parameter{1.0, True{}},
    _ => U.branch(Parameter, F32.is_lt(F32.abs(a), 0.0000001),
      _ => Parameter{(0.0 - c / b : F32), F32.is_gt(F32.abs(b), 0.0000001)},
      _ => radial.roots(a, b, c, fr, dr)))

def linear.parameter(+p: Point, +start: Point, +end: Point) -> Parameter:
  +d = point.sub(end, start)
  +den = point.dot(d, d)
  Parameter{U.choose(F32, F32.is_lt(den, 0.0000000001), 1.0,
    (point.dot(point.sub(p, start), d) / den : F32)), True{}}

def gradient.at(param: Parameter, stops: List<&2, Stop>, spread: U32, opacity: F32, linear: Bool) -> Img.Color:
  Parameter{t, valid} = param
  U.branch(Img.Color, valid, _ => gradient.finish(gradient.color(stops, gradient.spread(t, spread)), opacity, linear), _ => Img.clear())

# Wrap coverage and paint coordinates by the same tile, including negative tiles.
def pattern.at(p: Point, +paintPoint: Point, +w: F32, +h: F32, opacity: F32,
  nodes: List<&2, Scene<Brush>>, paint: List<&2, Scene<Brush>> -> Point -> Point -> Img.Color) -> Img.Color:
  Point{x, y} = p
  +px = x
  +py = y
  +shift = {Point{(F32.floor((px / w : F32)) * w : F32), (F32.floor((py / h : F32)) * h : F32)} : Point}
  color.fade(paint(nodes)(point.sub(Point{px, py}, shift))(point.sub(paintPoint, shift)), opacity)

def brush.solid(+c: Img.Color, opacity: F32) -> Brush:
  Solid{color.fade(c, opacity), c}

def color.space(+c: Img.Color, linear: Bool) -> Img.Color:
  Img.Color{r, g, b, a} = c
  U.branch(Img.Color, linear,
    _ => Img.Color{(srgb.linear((r / U.max(a, 0.0000001) : F32)) * a : F32),
      (srgb.linear((g / U.max(a, 0.0000001) : F32)) * a : F32),
      (srgb.linear((b / U.max(a, 0.0000001) : F32)) * a : F32), a}, _ => c)

def raster.pixel(+r: Raster, +x: F32, +y: F32) -> Img.Color:
  Raster{origin, step, width, height, depth, pixelsLinear, pixels} = r
  U.branch(Img.Color, F32.is_ge(x, 0.0) && F32.is_ge(y, 0.0) && F32.is_lt(x, U32.to_f32(width)) && F32.is_lt(y, U32.to_f32(height)),
    _ => Img.pixels.get(pixels, U32.shln(1, depth), F32.to_u32(x), F32.to_u32(y)), _ => Img.clear())

def color.mix(a: Img.Color, b: Img.Color, +t: F32) -> Img.Color:
  color.add(color.fade(a, (1.0 - t : F32)), color.fade(b, t))

def raster.horizontal(+r: Raster, +x: F32, +y: F32, +dx: F32) -> Img.Color:
  U.branch(Img.Color, F32.is_eq(dx, 0.0), _ => raster.pixel(r, x, y),
    _ => color.mix(raster.pixel(r, x, y), raster.pixel(r, (x + 1.0 : F32), y), dx))

def raster.sample(+r: Raster, p: Point) -> Img.Color:
  Raster{Point{ox, oy}, step, width, height, depth, pixelsLinear, pixels} = r
  Point{x, y} = p
  +fx = ((x - ox) / step - 0.5 : F32)
  +fy = ((y - oy) / step - 0.5 : F32)
  +ix = F32.floor(fx)
  +iy = F32.floor(fy)
  +dx = (fx - ix : F32)
  +dy = (fy - iy : F32)
  U.branch(Img.Color, F32.is_eq(dy, 0.0), _ => raster.horizontal(r, ix, iy, dx),
    _ => color.mix(raster.horizontal(r, ix, iy, dx), raster.horizontal(r, ix, (iy + 1.0 : F32), dx), dy))

def color.from.linear(+c: Img.Color) -> Img.Color:
  Img.Color{r, g, b, a} = c
  Img.Color{(linear.srgb((r / U.max(a, 0.0000001) : F32)) * a : F32), (linear.srgb((g / U.max(a, 0.0000001) : F32)) * a : F32), (linear.srgb((b / U.max(a, 0.0000001) : F32)) * a : F32), a}

def raster.color(+r: Raster, p: Point, +linear: Bool) -> Img.Color:
  Raster{origin, step, width, height, depth, pixelsLinear, pixels} = r
  +c = raster.sample(r, p)
  U.branch(Img.Color, U.choose(Bool, pixelsLinear, linear, Bool.not(linear)), _ => c,
    _ => U.branch(Img.Color, pixelsLinear, _ => color.from.linear(c), _ => color.space(c, True{})))

def raster.image(image: Img.Picture) -> Raster:
  Img.Picture{w, h, depth, pixels} = image
  Raster{Point{0.0, 0.0}, 1.0, w, h, depth, False{}, pixels}

def bitmap.bytes(+mime: String, +data: String) -> Bin.Bytes:
  U.branch(Bin.Bytes, U.string.contains(mime, ";base64"), _ => Bin.base64(data), _ => Bin.uri.bytes(data, Bin.bytes.empty()))

def bitmap.empty() -> Raster:
  Raster{Point{0.0, 0.0}, 1.0, 0, 0, 0n, False{}, Img.Flat{Img.clear()}}

def bitmap.uri(scan: U.Scan) -> Raster:
  U.Scan{header, content} = scan
  +mime = CSS.css.lower(header)
  +data = content
  U.branch(Raster, U.prefix(mime, "image/png") || U.prefix(mime, "image/apng"),
    _ => raster.image(PNG.png.decode(bitmap.bytes(mime, data))), _ => U.branch(Raster, U.prefix(mime, "image/jpeg") || U.prefix(mime, "image/jpg"), _ => raster.image(JPEG.jpeg.decode(bitmap.bytes(mime, data))), _ => bitmap.empty()))

def bitmap.decode(+href: String) -> Raster:
  U.branch(Raster, U.prefix(href, "data:"), _ => bitmap.uri(U.until(U.drop(href, "data:"), 44, "")), _ => bitmap.empty())

# Inverse F32 transforms can place an exact texel boundary a few ulps above
# its integer value. Snap only that rounding neighborhood before tie-breaking.
def bitmap.nearest(+q: F32) -> F32:
  +integer = F32.floor((q + 0.5 : F32))
  +close = F32.is_le(F32.abs((q - integer : F32)), (U.max(1.0, F32.abs(q)) * 0.000000476837158203125 : F32))
  F32.ceil((U.choose(F32, close, integer, q) - 1.0 : F32))

def bitmap.sample(+raster: Raster, +p: Point, +center: Point, nearest: Bool) -> Img.Color:
  Raster{origin, step, width, height, depth, linear, pixels} = raster
  Point{x, y} = p
  Point{cx, cy} = center
  +w = U32.to_f32(width)
  +h = U32.to_f32(height)
  U.branch(Img.Color, nearest, _ => raster.pixel(raster, U.clamp(bitmap.nearest(cx), 0.0, (w - 1.0 : F32)), U.clamp(bitmap.nearest(cy), 0.0, (h - 1.0 : F32))),
    _ => raster.sample(raster, Point{U.clamp(cx, 0.5, (w - 0.5 : F32)), U.clamp(cy, 0.5, (h - 0.5 : F32))}))

# Pattern tiles (see cover.brush): wrap into the tile and read its raster
# bilinearly, wrapping at the seams so neighbouring tiles join without a border.
def tile.wrap(+q: F32, +size: F32) -> F32:
  (q - F32.floor((q / size : F32)) * size : F32)

def tile.index(+i: F32, +n: U32) -> U32:
  U32.mod(F32.to_u32((i + U32.to_f32(n) : F32)), n)

def tile.corner(+pixels: Img.Pixels, +side: U32, +x: U32, +y: U32, +weight: F32) -> Img.Color:
  color.fade(Img.pixels.get(pixels, side, x, y), weight)

def tile.blend(+pixels: Img.Pixels, +side: U32, +width: U32, +height: U32, +fx: F32, +fy: F32) -> Img.Color:
  +ix = F32.floor(fx)
  +iy = F32.floor(fy)
  +dx = (fx - ix : F32)
  +dy = (fy - iy : F32)
  +x0 = tile.index(ix, width)
  +x1 = tile.index((ix + 1.0 : F32), width)
  +y0 = tile.index(iy, height)
  +y1 = tile.index((iy + 1.0 : F32), height)
  color.add(color.add(tile.corner(pixels, side, x0, y0, ((1.0 - dx) * (1.0 - dy) : F32)), tile.corner(pixels, side, x1, y0, (dx * (1.0 - dy) : F32))),
    color.add(tile.corner(pixels, side, x0, y1, ((1.0 - dx) * dy : F32)), tile.corner(pixels, side, x1, y1, (dx * dy : F32))))

def tile.cell(+x: F32, +w: F32, +n: U32) -> U32:
  U32.mod(F32.to_u32(F32.floor((tile.wrap(x, w) * U32.to_f32(n) / w : F32))), n)

# Nearest tile pixel under a pattern-space point.
def tile.read(+pixels: Img.Pixels, +side: U32, +wd: U32, +ht: U32, +w: F32, +h: F32, q: Point) -> Img.Color:
  Point{x, y} = q
  Img.pixels.get(pixels, side, tile.cell(x, w, wd), tile.cell(y, h, ht))

# Sum of grid by grid nearest reads spread over the pixel footprint (u, v).
@unsafe
def tile.grid(+pixels: Img.Pixels, +side: U32, +wd: U32, +ht: U32, +w: F32, +h: F32, +q: Point, +u: Point, +v: Point, +grid: U32, n: Nat, +i: U32, acc: Img.Color) -> Img.Color:
  match n:
    case 0n: acc
    case 1n+d:
      +gx = ((U32.to_f32(U32.mod(i, grid)) + 0.5) / U32.to_f32(grid) - 0.5 : F32)
      +gy = ((U32.to_f32(U32.div(i, grid)) + 0.5) / U32.to_f32(grid) - 0.5 : F32)
      tile.grid(pixels, side, wd, ht, w, h, q, u, v, grid, d, (i + 1 : U32), color.add(acc, tile.read(pixels, side, wd, ht, w, h, point.add(q, point.add(point.scale(u, gx), point.scale(v, gy))))))

# A grid of one reads the tile bilinearly at the point (aligned tiles at device
# density); a larger grid averages nearest reads of a denser tile over the
# device pixel's footprint, the pattern-space vectors u and v.
def tile.sample(+r: Raster, +q: Point, +w: F32, +h: F32, +opacity: F32, +u: Point, +v: Point, +grid: U32) -> Img.Color:
  Raster{origin, step, width, height, depth, linear, pixels} = r
  Point{x, y} = q
  +wd = width
  +ht = height
  +px = pixels
  +side = U32.shln(1, depth)
  U.branch(Img.Color, U32.is_eq(wd, 0) || U32.is_eq(ht, 0), _ => Img.clear(),
    _ => color.fade(U.branch(Img.Color, U32.is_le(grid, 1),
      _ => tile.blend(px, side, wd, ht, (tile.wrap(x, w) * U32.to_f32(wd) / w - 0.5 : F32), (tile.wrap(y, h) * U32.to_f32(ht) / h - 0.5 : F32)),
      _ => color.fade(tile.grid(px, side, wd, ht, w, h, Point{x, y}, u, v, grid, U32.to_nat((grid * grid : U32)), 0, Img.clear()), (1.0 / U32.to_f32((grid * grid : U32)) : F32))), opacity))

def brush.sample(brush: Brush, +p: Point, +paintPoint: Point, next: List<&2, Scene<Brush>> -> Point -> Point -> Img.Color) -> Img.Color:
  match brush:
    case Solid{c, source}: c
    case Bitmap{raster, inv, nearest}:
      +mat = inv
      bitmap.sample(raster, matrix.point(mat, p), matrix.point(mat, paintPoint), nearest)
    case PendingContext{stroke, opacity}: Img.clear()
    case ContextPaint{source, matrix, opacity}:
      +mat = matrix
      color.fade(brush.sample(source, matrix.point(mat, p), matrix.point(mat, paintPoint), next), opacity)
    case Pattern{inv, w, h, opacity, nodes}:
      +matrix = inv
      pattern.at(matrix.point(matrix, p), matrix.point(matrix, paintPoint), w, h, opacity, nodes, next)
    case Tile{raster, inv, w, h, opacity, u, v, grid}: tile.sample(raster, matrix.point(inv, p), w, h, opacity, u, v, grid)
    case Gradient{inv, radial, start, end, radius, fr, stops, spread, opacity, linear}:
      +q = matrix.point(inv, paintPoint)
      +a = start
      +b = end
      gradient.at(U.choose(Parameter, radial, radial.parameter(q, a, b, radius, fr), linear.parameter(q, a, b)),
        stops, spread, opacity, linear)

def gradient.box(b: Bounds) -> Matrix:
  Bounds{x0, y0, x1, y1} = b
  +x = x0
  +y = y0
  matrix.mul(translate(x, y), scale((x1 - x : F32), (y1 - y : F32)))

def gradient.build(e: XML.Element, +box: Bounds, +w: F32, +h: F32, opacity: F32) -> Brush:
  XML.Element{n, attrs, kids, txt} = e
  +as = CSS.properties(attrs)
  +user = String.eq(XML.attr.get(as, "gradientUnits", "objectBoundingBox"), "userSpaceOnUse")
  +vw = U.choose(F32, user, w, 1.0)
  +vh = U.choose(F32, user, h, 1.0)
  +linear = String.eq(XML.attr.get(as, "color-interpolation", "sRGB"), "linearRGB")
  +radial = String.eq(n, "radialGradient")
  +cx = dimension(as, "cx", vw, "50%")
  +cy = dimension(as, "cy", vh, "50%")
  +radiusRef = F32.sqrt(((vw * vw + vh * vh) / 2.0 : F32))
  Gradient{matrix.inverse(matrix.mul(U.choose(Matrix, user, identity(), gradient.box(box)),
    transform(XML.attr.get(as, "gradientTransform", ""), identity()))), radial,
    U.choose(Point, radial, Point{dimension(as, "fx", vw, F32.show(cx)), dimension(as, "fy", vh, F32.show(cy))},
      Point{dimension(as, "x1", vw, "0%"), dimension(as, "y1", vh, "0%")}),
    U.choose(Point, radial, Point{cx, cy}, Point{dimension(as, "x2", vw, "100%"), dimension(as, "y2", vh, "0%")}),
    dimension(as, "r", radiusRef, "50%"), dimension(as, "fr", radiusRef, "0%"),
    gradient.stops(kids, as, 0.0, linear),
    U.choose(U32, String.eq(XML.attr.get(as, "spreadMethod", "pad"), "repeat"), 1,
      U.choose(U32, String.eq(XML.attr.get(as, "spreadMethod", "pad"), "reflect"), 2, 0)), opacity, linear}

def gradient.is.valid(e: XML.Element) -> Bool:
  XML.Element{n, as, kids, txt} = e
  +tag = n
  String.eq(tag, "linearGradient") || String.eq(tag, "radialGradient")

def brush.resource(result: Maybe<&2, XML.Element>, +all: List<&2, XML.Element>, +box: Bounds, +w: F32, +h: F32,
  +opacity: F32, fallback: String, patterns: XML.Element -> Bounds -> F32 -> F32 -> F32 -> Brush) -> Brush:
  match result:
    case None{}: brush.solid(color(fallback), opacity)
    case Some{XML.Element{tagname, as, kids, txt}}:
      +tag = tagname
      +node = {XML.Element{tag, as, kids, txt} : XML.Element}
      U.branch(Brush, gradient.is.valid(node), _ => gradient.build(gradient.resolve(32n, node, all), box, w, h, opacity),
        _ => U.branch(Brush, String.eq(tag, "pattern"), _ => patterns(node)(box)(w)(h)(opacity),
          _ => brush.solid(color(fallback), opacity)))

def brush.url(+scan: U.Scan, +all: List<&2, XML.Element>, box: Bounds, w: F32, h: F32, opacity: F32, patterns: XML.Element -> Bounds -> F32 -> F32 -> F32 -> Brush) -> Brush:
  U.Scan{url, fallback} = scan
  brush.resource(XML.element.find(all, U.drop(U.unquote(U.trim.both(url)), "#")), all, box, w, h, opacity,
    U.choose(String, String.eq(U.trim(fallback), ""), "none", U.trim(fallback)), patterns)

def brush(+s: String, current: String, +opacity: F32, +all: List<&2, XML.Element>, box: Bounds, w: F32, h: F32, patterns: XML.Element -> Bounds -> F32 -> F32 -> F32 -> Brush) -> Brush:
  U.branch(Brush, U.prefix(s, "url("), _ => brush.url(U.until(U.drop(s, "url("), 41, ""), all, box, w, h, opacity, patterns),
    _ => U.branch(Brush, String.eq(CSS.css.lower(U.trim.both(s)), "context-fill") || String.eq(CSS.css.lower(U.trim.both(s)), "context-stroke"), _ => PendingContext{String.eq(CSS.css.lower(U.trim.both(s)), "context-stroke"), opacity},
      _ => brush.solid(color(U.choose(String, String.eq(CSS.css.lower(U.trim.both(s)), "currentcolor"), current, s)), opacity)))

def style.colors(+s: Style, +all: List<&2, XML.Element>, +box: Bounds, +w: F32, +h: F32, fills: XML.Element -> Bounds -> F32 -> F32 -> F32 -> Brush, strokes: XML.Element -> Bounds -> F32 -> F32 -> F32 -> Brush) -> Paint<Brush>:
  Style{fill, stroke, col, fo, so, width, even, visible, ss, ms, rendering, order} = s
  Paint{brush(fill, col, fo, all, box, w, h, fills), brush(stroke, col, so, all, box, w, h, strokes)}

# Clip paths combine geometry by union; nested clip paths intersect coverage.
def clip.inside(c: Clip, +p: Point) -> Bool:
  match c:
    case ClipAll{}: True{}
    case ClipShape{es, inv, even, cover}: edge.tree.inside(es, matrix.point(inv, p), even)
    case ClipUnion{a, b}: clip.inside(a, p) || clip.inside(b, p)
    case ClipIntersect{a, b}: clip.inside(a, p) && clip.inside(b, p)

# Clip coverage: unions add as independent areas, intersections multiply.
def clip.cover(c: Clip, +p: Point) -> F32:
  match c:
    case ClipAll{}: 1.0
    case ClipShape{es, inv, even, cover}:
      +cov = cover
      U.branch(F32, cover.present(cov), _ => cover.at(cov, p), _ => U.choose(F32, edge.tree.inside(es, matrix.point(inv, p), even), 1.0, 0.0))
    case ClipUnion{a, b}:
      +u = clip.cover(a, p)
      +v = clip.cover(b, p)
      (u + v - u * v : F32)
    case ClipIntersect{a, b}: (clip.cover(a, p) * clip.cover(b, p) : F32)

def clip.fade(+cov: F32, render: Unit -> Img.Color) -> Img.Color:
  U.branch(Img.Color, F32.is_gt(cov, 0.0), _ => color.fade(render(Unit{}), cov), _ => Img.clear())

def clip.empty() -> Clip:
  ClipShape{EdgeEmpty{}, identity(), False{}, cover.none()}

def clip.reference(result: Maybe<&2, XML.Element>, +box: Bounds, +m: Matrix,
  build: List<&2, XML.Element> -> Matrix -> Clip) -> Clip:
  match result:
    case None{}: ClipAll{}
    case Some{XML.Element{n, as, kids, txt}}:
      +tag = n
      +attrs = as
      U.branch(Clip, String.eq(tag, "clipPath"),
        _ => build(Con{XML.Element{tag, attrs, kids, txt}, Nil{}})(matrix.mul(m,
          U.choose(Matrix, String.eq(XML.attr.get(attrs, "clipPathUnits", "userSpaceOnUse"), "objectBoundingBox"),
            gradient.box(box), identity()))), _ => ClipAll{})

def clip.attach(+as: List<&2, XML.Attr>, +all: List<&2, XML.Element>, box: Bounds, m: Matrix,
  build: List<&2, XML.Element> -> Matrix -> Clip) -> Clip:
  +value = XML.attr.get(as, "clip-path", "none")
  U.branch(Clip, U.prefix(value, "url("),
    _ => clip.reference(XML.element.find(all, U.drop(U.unquote(U.trim.both(U.scan.head(U.until(U.drop(value, "url("), 41, "")))), "#")),
      box, m, build), _ => ClipAll{})

@unsafe
def clip.build(fuel: Nat, +xs: List<&2, XML.Element>, +all: List<&2, XML.Element>, +m: Matrix,
  +w: F32, +h: F32, +even: Bool) -> Clip:
  match fuel:
    case 0n: clip.empty()
    case 1n+d:
      match xs:
        case Nil{}: clip.empty()
        case Con{XML.Element{n, attrs, kids, txt}, rest}:
          +dd = d
          +as = CSS.properties(attrs)
          +matrix = matrix.mul(matrix.mul(m, transform(XML.attr.get(as, "transform", ""), identity())),
            U.choose(Matrix, String.eq(n, "use"), translate(dimension(as, "x", w, "0"), dimension(as, "y", h, "0")), identity()))
          +rule = String.eq(XML.attr.get(as, "clip-rule", U.choose(String, even, "evenodd", "nonzero")), "evenodd")
          +es = shape.children(n, as, kids, w, h)
          +box = bounds(es, Bounds{1000000000.0, 1000000000.0, F32.neg(1000000000.0), F32.neg(1000000000.0)})
          U.branch(Clip, String.eq(XML.attr.get(as, "display", "inline"), "none"),
            _ => clip.build(1n+dd, rest, all, m, w, h, even),
            _ => ClipUnion{ClipIntersect{
              ClipUnion{ClipShape{edge.tree(es), matrix.inverse(matrix), rule, cover.none()}, clip.build(1n+dd, kids, all, matrix, w, h, rule)},
              clip.attach(as, all, box, matrix, nodes => mat => clip.build(dd, nodes, all, mat, w, h, False{}))},
              clip.build(1n+dd, rest, all, m, w, h, even)})

def clip.compile(as: List<&2, XML.Attr>, +all: List<&2, XML.Element>, box: Bounds, m: Matrix, +w: F32, +h: F32) -> Clip:
  clip.attach(as, all, box, m, nodes => mat => clip.build(128n, nodes, all, mat, w, h, False{}))

def style.nonScaling(s: Style) -> Bool:
  Style{fill, stroke, col, fo, so, width, even, visible, ss, ms, rendering, order} = s
  StrokeSettings{cap, join, limit, dash, offset, vector} = ss
  String.eq(vector, "non-scaling-stroke")

def style.outline(+s: Style, +es: List<&2, Edge>, +m: Matrix, ref: F32, declared: F32) -> StrokeMesh:
  Style{fill, stroke, col, fo, so, width, even, visible, ss, ms, rendering, order} = s
  +screen = style.nonScaling(s)
  stroke.mesh(U.branch(List<&2, StrokePart>, String.eq(stroke, "none") || F32.is_le(width, 0.0), _ => Nil{},
    _ => stroke.compile(U.choose(List<&2, Edge>, screen, edges.transform(es, m), es), (width / 2.0 : F32), ss, ref, declared)),
    U.choose(Matrix, screen, identity(), matrix.inverse(m)))

def bounds.transformed(es: List<&2, Edge>, +m: Matrix, box: Bounds) -> Bounds:
  match es:
    case Nil{}: box
    case Con{Edge{a, b, stroked, closed}, rest}:
      bounds.transformed(rest, m, bounds.point(bounds.point(box, matrix.point(m, a)), matrix.point(m, b)))

def scene.bounds(xs: List<&2, Scene<Brush>>, +parentInverse: Matrix, box: Bounds) -> Bounds:
  match xs:
    case Nil{}: box
    case Con{Scene{es, childbox, inv, style, opacity, kids, id, ink, mask, outline, fillTree, maskNodes, maskMode, markerNodes, coverage, effect}, rest}:
      scene.bounds(rest, parentInverse, scene.bounds(kids, parentInverse,
        bounds.transformed(es, matrix.mul(parentInverse, matrix.inverse(inv)), box)))

def bounds.spec(+as: List<&2, XML.Attr>, box: Bounds) -> Bounds:
  +value = XML.attr.get(as, "#paint-box", "")
  +vs = U.numbers(value)
  U.choose(Bounds, String.eq(value, ""), box, Bounds{U.nth(vs, 0n, 0.0), U.nth(vs, 1n, 0.0), U.nth(vs, 2n, 0.0), U.nth(vs, 3n, 0.0)})

def filter.dimension(+as: List<&2, XML.Attr>, +key: String, +ref: F32, +fallback: String, user: Bool) -> F32:
  U.branch(F32, user, _ => dimension(as, key, ref, fallback), _ => (dimension(as, key, 1.0, fallback) * ref : F32))

def filter.region(+as: List<&2, XML.Attr>, box: Bounds, +w: F32, +h: F32, +primitiveBox: Bool) -> Bounds:
  Bounds{x0, y0, x1, y1} = box
  +bx = x0
  +by = y0
  +bw = (x1 - bx : F32)
  +bh = (y1 - by : F32)
  +user = String.eq(XML.attr.get(as, "filterUnits", "objectBoundingBox"), "userSpaceOnUse")
  +fw = U.choose(F32, user, w, bw)
  +fh = U.choose(F32, user, h, bh)
  +x = (U.choose(F32, user, 0.0, bx) + filter.dimension(as, "x", fw, "-10%", user) : F32)
  +y = (U.choose(F32, user, 0.0, by) + filter.dimension(as, "y", fh, "-10%", user) : F32)
  +width = filter.dimension(as, "width", fw, "120%", user)
  +height = filter.dimension(as, "height", fh, "120%", user)
  U.branch(Bounds, (user || (F32.is_gt(bw, 0.0) && F32.is_gt(bh, 0.0))) && (Bool.not(primitiveBox) || (F32.is_gt(bw, 0.0) && F32.is_gt(bh, 0.0))),
    _ => U.branch(Bounds, primitiveBox, _ => Bounds{((x - bx) / bw : F32), ((y - by) / bh : F32), ((x + width - bx) / bw : F32), ((y + height - by) / bh : F32)},
      _ => Bounds{x, y, (x + width : F32), (y + height : F32)}), _ => bounds.empty())

def filter.resource(result: Maybe<&2, XML.Element>, +box: Bounds, m: Matrix, +w: F32, +h: F32) -> FilterEffect:
  match result:
    case None{}: NoFilter{}
    case Some{XML.Element{name, attrs, kids, txt}}:
      +as = CSS.properties(attrs)
      +object = String.eq(XML.attr.get(as, "primitiveUnits", "userSpaceOnUse"), "objectBoundingBox")
      U.branch(FilterEffect, String.eq(name, "filter"), _ => FilterSpec{filter.region(as, box, w, h, object), matrix.mul(m, U.choose(Matrix, object, gradient.box(box), identity())), Point{U.choose(F32, object, 1.0, w), U.choose(F32, object, 1.0, h)}, as, kids}, _ => NoFilter{})

def filter.spec(+as: List<&2, XML.Attr>, all: List<&2, XML.Element>, box: Bounds, m: Matrix, w: F32, h: F32) -> FilterEffect:
  +value = U.trim.both(XML.attr.get(as, "filter", "none"))
  +id = U.drop(U.unquote(U.trim.both(U.scan.head(U.until(U.drop(value, "url("), 41, "")))), "#")
  U.branch(FilterEffect, U.prefix(value, "url("), _ => filter.resource(XML.element.find(all, id), box, m, w, h), _ => NoFilter{})

def scene.make(+es: List<&2, Edge>, +m: Matrix, +s: Style, opacity: F32, +children: List<&2, Scene<Brush>>, id: String,
  +all: List<&2, XML.Element>, +w: F32, +h: F32, +as: List<&2, XML.Attr>, fills: XML.Element -> Bounds -> F32 -> F32 -> F32 -> Brush, strokes: XML.Element -> Bounds -> F32 -> F32 -> F32 -> Brush) -> Scene<Brush>:
  +box = bounds.spec(as, scene.bounds(children, matrix.inverse(m), bounds(es, Bounds{1000000000.0, 1000000000.0, F32.neg(1000000000.0), F32.neg(1000000000.0)})))
  Scene{es, box, matrix.inverse(m), s, opacity, children, id, style.colors(s, all, box, w, h, fills, strokes), clip.compile(as, all, box, m, w, h), style.outline(s, es, m, F32.sqrt(((w * w + h * h) / 2.0 : F32)), U.scalar(XML.attr.get(as, "pathLength", "0"), 0.0)), fill.new(es), Nil{}, 0, Nil{}, bounds.empty(), filter.spec(as, all, box, m, w, h)}

# SVG viewports establish local units and intersect their children with overflow clips.
def viewbox.matrix(+v: List<&2, F32>, +w: F32, +h: F32, +aspect: String) -> Matrix:
  +x = U.nth(v, 0n, 0.0)
  +y = U.nth(v, 1n, 0.0)
  +vw = U.nth(v, 2n, w)
  +vh = U.nth(v, 3n, h)
  +sx = (w / U.max(0.000001, vw) : F32)
  +sy = (h / U.max(0.000001, vh) : F32)
  +s = U.choose(F32, U.prefix(U.through(aspect, " "), "slice"), U.max(sx, sy), U.min(sx, sy))
  +tx = U.choose(F32, U.prefix(aspect, "xMin"), 0.0, U.choose(F32, U.prefix(aspect, "xMax"), 1.0, 0.5))
  +ty = U.choose(F32, U.prefix(U.drop(aspect, "xxxx"), "YMin"), 0.0,
    U.choose(F32, U.prefix(U.drop(aspect, "xxxx"), "YMax"), 1.0, 0.5))
  U.branch(Matrix, String.eq(aspect, "none"), _ => matrix.mul(scale(sx, sy), translate(F32.neg(x), F32.neg(y))),
    _ => matrix.mul(translate(((w - vw * s) * tx : F32), ((h - vh * s) * ty : F32)),
      matrix.mul(scale(s, s), translate(F32.neg(x), F32.neg(y)))))

type EmbeddedImage is Data:
  NoImage{}
  EmbeddedImage{raster: Raster, attrs: List<&2, XML.Attr>, inverse: Matrix, nearest: Bool}

def bitmap.layout(+raster: Raster, +as: List<&2, XML.Attr>, +vw: F32, +vh: F32) -> EmbeddedImage:
  Raster{origin, step, width, height, depth, linear, pixels} = raster
  +iw = U32.to_f32(width)
  +ih = U32.to_f32(height)
  +aw = XML.attr.get(as, "width", "auto")
  +ah = XML.attr.get(as, "height", "auto")
  +autoW = String.eq(aw, "auto")
  +autoH = String.eq(ah, "auto")
  +rw = dimension(as, "width", vw, "0")
  +rh = dimension(as, "height", vh, "0")
  +w = U.choose(F32, autoW, U.choose(F32, autoH, iw, (rh * iw / U.max(ih, 0.000001) : F32)), rw)
  +h = U.choose(F32, autoH, U.choose(F32, autoW, ih, (rw * ih / U.max(iw, 0.000001) : F32)), rh)
  +attrs = {Con{XML.Attr{"width", F32.show(w)}, Con{XML.Attr{"height", F32.show(h)}, as}} : List<&2, XML.Attr>}
  +inv = matrix.inverse(matrix.mul(translate(dimension(as, "x", vw, "0"), dimension(as, "y", vh, "0")), viewbox.matrix(Con{0.0, Con{0.0, Con{iw, Con{ih, Nil{}}}}}, w, h, U.trim.both(XML.attr.get(as, "preserveAspectRatio", "xMidYMid meet")))))
  +rendering = XML.attr.get(as, "image-rendering", "auto")
  EmbeddedImage{raster, attrs, inv, String.eq(rendering, "pixelated") || String.eq(rendering, "crisp-edges") || String.eq(rendering, "optimizeSpeed")}

def style.image.rendering(s: Style) -> String:
  Style{fill, stroke, col, fo, so, width, even, visible, ss, ms, rendering, order} = s
  rendering

def bitmap.element(+name: String, +as: List<&2, XML.Attr>, w: F32, h: F32) -> EmbeddedImage:
  U.branch(EmbeddedImage, String.eq(name, "image"), _ => bitmap.layout(bitmap.decode(XML.attr.get(as, "href", XML.attr.get(as, "xlink:href", ""))), as, w, h), _ => NoImage{})

def bitmap.attrs(image: EmbeddedImage, fallback: List<&2, XML.Attr>) -> List<&2, XML.Attr>:
  match image:
    case NoImage{}: fallback
    case EmbeddedImage{raster, attrs, inv, nearest}: attrs

def style.image(s: Style) -> Style:
  Style{fill, stroke, col, fo, so, width, even, visible, ss, ms, rendering, order} = s
  Style{"white", "none", col, 1.0, 1.0, 0.0, False{}, visible, ss, MarkerStyle{"none", "none", "none"}, rendering, order}

def bitmap.style(image: EmbeddedImage, style: Style) -> Style:
  match image:
    case NoImage{}: style
    case EmbeddedImage{raster, attrs, inv, nearest}: style.image(style)

def style.is.visible(s: Style) -> Bool:
  Style{fill, stroke, col, fo, so, width, even, visible, ss, ms, rendering, order} = s
  visible

def style.embedded(s: Style) -> Style:
  Style{fill, stroke, col, fo, so, width, even, visible, ss, ms, rendering, order} = s
  Style{"none", "none", col, 1.0, 1.0, 0.0, False{}, visible, ss, MarkerStyle{"none", "none", "none"}, rendering, order}

def bitmap.paint(image: EmbeddedImage, ink: Paint<Brush>) -> Paint<Brush>:
  match image:
    case NoImage{}: ink
    case EmbeddedImage{raster, attrs, inv, nearest}: Paint{Bitmap{raster, inv, nearest}, brush.solid(Img.clear(), 1.0)}

def scene.bitmap(scene: Scene<Brush>, image: EmbeddedImage) -> Scene<Brush>:
  Scene{es, box, inv, style, opacity, kids, id, ink, clip, outline, fillTree, masks, maskMode, markers, coverage, effect} = scene
  Scene{es, box, inv, style, opacity, kids, id, bitmap.paint(image, ink), clip, outline, fillTree, masks, maskMode, markers, coverage, effect}

type Viewport is Data:
  Viewport{matrix: Matrix, width: F32, height: F32, clip: Clip, valid: Bool}

def viewport.clip(+w: F32, +h: F32, m: Matrix) -> Clip:
  ClipShape{edge.tree(path(shape.rect.path(0.0, 0.0, w, h, 0.0, 0.0))), matrix.inverse(m), False{}, cover.none()}

def viewport.dimension(+as: List<&2, XML.Attr>, key: String, +ref: F32) -> F32:
  +value = XML.attr.get(as, key, "auto")
  U.branch(F32, String.eq(value, "auto"), _ => ref, _ => U.unit(U.number(value), ref))

def image.layout.sized(+as: List<&2, XML.Attr>, +values: List<&2, F32>, +vw: F32, +vh: F32) -> List<&2, XML.Attr>:
  +iw = U.nth(values, 0n, 300.0)
  +ih = U.nth(values, 1n, 150.0)
  +ratio = U.nth(values, 2n, 0.0)
  +aw = String.eq(XML.attr.get(as, "width", "auto"), "auto")
  +ah = String.eq(XML.attr.get(as, "height", "auto"), "auto")
  +rw = dimension(as, "width", vw, "0")
  +rh = dimension(as, "height", vh, "0")
  +w = U.choose(F32, aw, U.choose(F32, ah, iw, U.choose(F32, F32.is_gt(ratio, 0.0), (rh * ratio : F32), iw)), rw)
  +h = U.choose(F32, ah, U.choose(F32, aw, ih, U.choose(F32, F32.is_gt(ratio, 0.0), (rw / U.max(ratio, 0.000001) : F32), ih)), rh)
  Con{XML.Attr{"width", F32.show(w)}, Con{XML.Attr{"height", F32.show(h)}, as}}

def image.layout.attrs(+as: List<&2, XML.Attr>, +w: F32, +h: F32) -> List<&2, XML.Attr>:
  +size = XML.attr.get(as, "#image-size", "")
  U.branch(List<&2, XML.Attr>, String.eq(size, ""), _ => as, _ => image.layout.sized(as, U.numbers(size), w, h))

def element.viewport(+name: String, raw: List<&2, XML.Attr>, +m: Matrix, +w: F32, +h: F32, +root: Bool) -> Viewport:
  +as = image.layout.attrs(raw, w, h)
  +base = matrix.mul(m, transform(XML.attr.get(as, "transform", ""), identity()))
  +svg = String.eq(name, "svg")
  +width = U.choose(F32, root, w, viewport.dimension(as, "width", w))
  +height = U.choose(F32, root, h, viewport.dimension(as, "height", h))
  +origin = matrix.mul(base, U.choose(Matrix, root, identity(),
    translate(dimension(as, "x", w, "0"), dimension(as, "y", h, "0"))))
  +view = U.numbers(XML.attr.get(as, "viewBox", ""))
  +vw = U.nth(view, 2n, width)
  +vh = U.nth(view, 3n, height)
  U.branch(Viewport, svg, _ => Viewport{
      matrix.mul(origin, viewbox.matrix(view, width, height, U.trim.both(XML.attr.get(as, "preserveAspectRatio", "xMidYMid meet")))), vw, vh,
      U.branch(Clip, String.eq(XML.attr.get(as, "overflow", "hidden"), "visible"), _ => ClipAll{}, _ => viewport.clip(width, height, origin)),
      F32.is_gt(width, 0.0) && F32.is_gt(height, 0.0) && F32.is_gt(vw, 0.0) && F32.is_gt(vh, 0.0)},
    _ => Viewport{U.branch(Matrix, String.eq(name, "use"),
      _ => matrix.mul(base, translate(dimension(as, "x", w, "0"), dimension(as, "y", h, "0"))), _ => base), w, h, ClipAll{}, True{}})

def scene.clipped(scene: Scene<Brush>, viewportClip: Clip) -> Scene<Brush>:
  Scene{es, box, inv, style, opacity, kids, id, ink, mask, outline, fillTree, maskNodes, maskMode, markerNodes, coverage, effect} = scene
  Scene{es, box, inv, style, opacity, kids, id, ink, ClipIntersect{mask, viewportClip}, outline, fillTree, maskNodes, maskMode, markerNodes, coverage, effect}

def element.hidden(+name: String, as: List<&2, XML.Attr>) -> Bool:
  String.eq(name, "#text") || String.eq(name, "defs") || String.eq(name, "title") || String.eq(name, "desc")
    || String.eq(name, "metadata") || String.eq(name, "clipPath") || String.eq(name, "mask")
    || String.eq(name, "symbol") || String.eq(name, "linearGradient") || String.eq(name, "radialGradient")
    || String.eq(name, "marker") || String.eq(name, "pattern") || String.eq(name, "filter") || String.eq(name, "style")
    || String.eq(XML.attr.get(as, "display", "inline"), "none")

def instance.anonymous(xs: List<&2, XML.Element>) -> List<&2, XML.Element>:
  match xs:
    case Nil{}: Nil{}
    case Con{XML.Element{n, as, kids, txt}, rest}:
      Con{XML.Element{n, Con{XML.Attr{"#editor-id", ""}, as}, instance.anonymous(kids), txt}, instance.anonymous(rest)}

def instance.root(result: Maybe<&2, XML.Element>, +useAttrs: List<&2, XML.Attr>) -> List<&2, XML.Element>:
  match result:
    case None{}: Nil{}
    case Some{XML.Element{n, attrs, kids, txt}}:
      +tagname = n
      +as = CSS.properties(attrs)
      +width = XML.attr.get(useAttrs, "width", "auto")
      +height = XML.attr.get(useAttrs, "height", "auto")
      +viewport = String.eq(tagname, "svg") || String.eq(tagname, "symbol")
      Con{XML.Element{U.choose(String, String.eq(tagname, "symbol"), "svg", tagname),
        U.choose(List<&2, XML.Attr>, viewport,
          Con{XML.Attr{"style", ""}, Con{XML.Attr{"width", U.choose(String, String.eq(width, "auto"), XML.attr.get(as, "width", "auto"), width)},
            Con{XML.Attr{"height", U.choose(String, String.eq(height, "auto"), XML.attr.get(as, "height", "auto"), height)}, as}}}, as), kids, txt}, Nil{}}

def use.children(+as: List<&2, XML.Attr>, all: List<&2, XML.Element>, ancestors: List<&2, String>,
  expand: List<&2, XML.Element> -> List<&2, XML.Element>) -> List<&2, XML.Element>:
  +href = XML.attr.get(as, "href", XML.attr.get(as, "xlink:href", ""))
  +id = U.drop(href, "#")
  U.branch(List<&2, XML.Element>, U.prefix(href, "#") && Bool.not(String.eq(id, "")) && Bool.not(U.strings.has(ancestors, id)),
    _ => instance.anonymous(expand(instance.root(XML.element.find(all, id), as))), _ => Nil{})

@unsafe
def use.expand(+fuel: Nat, +xs: List<&2, XML.Element>, +all: List<&2, XML.Element>, +ancestors: List<&2, String>) -> List<&2, XML.Element>:
  match fuel xs:
    case 0n _: Nil{}
    case 1n+d Nil{}: Nil{}
    case 1n+d Con{XML.Element{n, attrs, kids, txt}, rest}:
      +as = attrs
      +tagname = n
      +parents = {Con{XML.attr.get(as, "id", ""), ancestors} : List<&2, String>}
      Con{XML.Element{tagname, as, U.branch(List<&2, XML.Element>, String.eq(tagname, "use"),
        _ => use.children(CSS.properties(as), all, parents, nodes => use.expand(d, nodes, all, parents)),
        _ => use.expand(fuel, kids, U.choose(List<&2, XML.Element>, String.eq(tagname, "#svg-image"), kids, all), U.choose(List<&2, String>, String.eq(tagname, "#svg-image"), Nil{}, parents))), txt}, use.expand(fuel, rest, all, ancestors)}

def scenes.append(xs: List<&2, Scene<Brush>>, ys: List<&2, Scene<Brush>>) -> List<&2, Scene<Brush>>:
  match xs:
    case Nil{}: ys
    case Con{h, t}: Con{h, scenes.append(t, ys)}

# A mask is rendered as a transparent subscene before its alpha/luminance is used.
type MaskData is Data:
  MaskData{nodes: List<&2, Scene<Brush>>, mode: U32}

def mask.scene(scene: Scene<Brush>, data: MaskData) -> Scene<Brush>:
  Scene{es, box, inv, style, opacity, kids, id, ink, clip, outline, fillTree, oldNodes, oldMode, markerNodes, coverage, effect} = scene
  MaskData{nodes, mode} = data
  Scene{es, box, inv, style, opacity, kids, id, ink, clip, outline, fillTree, nodes, mode, markerNodes, coverage, effect}

def mask.clip(nodes: List<&2, Scene<Brush>>, +region: Clip) -> List<&2, Scene<Brush>>:
  match nodes:
    case Nil{}: Nil{}
    case Con{h, t}: Con{scene.clipped(h, region), mask.clip(t, region)}

def mask.region(+as: List<&2, XML.Attr>, +box: Bounds, +m: Matrix, +w: F32, +h: F32) -> Clip:
  +user = String.eq(XML.attr.get(as, "maskUnits", "objectBoundingBox"), "userSpaceOnUse")
  +vw = U.choose(F32, user, w, 1.0)
  +vh = U.choose(F32, user, h, 1.0)
  +width = dimension(as, "width", vw, "120%")
  +height = dimension(as, "height", vh, "120%")
  U.branch(Clip, F32.is_gt(width, 0.0) && F32.is_gt(height, 0.0),
    _ => ClipShape{edge.tree(path(shape.rect.path(dimension(as, "x", vw, "-10%"), dimension(as, "y", vh, "-10%"), width, height, 0.0, 0.0))),
      matrix.inverse(matrix.mul(m, U.choose(Matrix, user, identity(), gradient.box(box)))), False{}, cover.none()}, _ => clip.empty())

def mask.resource(result: Maybe<&2, XML.Element>, +id: String, +mode: String, +box: Bounds, +m: Matrix, +w: F32, +h: F32,
  build: String -> List<&2, XML.Element> -> Matrix -> F32 -> F32 -> List<&2, Scene<Brush>>) -> MaskData:
  match result:
    case None{}: MaskData{Nil{}, 2}
    case Some{XML.Element{n, attrs, kids, txt}}:
      +as = CSS.properties(attrs)
      +bbox = String.eq(XML.attr.get(as, "maskContentUnits", "userSpaceOnUse"), "objectBoundingBox")
      +kind = U.choose(String, String.eq(mode, "alpha") || String.eq(mode, "luminance"), mode, XML.attr.get(as, "mask-type", "luminance"))
      U.branch(MaskData, String.eq(n, "mask"),
        _ => MaskData{mask.clip(build(id)(Con{XML.Element{"g", as, kids, txt}, Nil{}})(matrix.mul(m, U.choose(Matrix, bbox, gradient.box(box), identity())))(U.choose(F32, bbox, 1.0, w))(U.choose(F32, bbox, 1.0, h)), mask.region(as, box, m, w, h)),
          U.choose(U32, String.eq(kind, "alpha"), 1, U.choose(U32, String.eq(XML.attr.get(as, "color-interpolation", "sRGB"), "linearRGB"), 3, 2))},
        _ => MaskData{Nil{}, 2})

def mask.attach(+as: List<&2, XML.Attr>, all: List<&2, XML.Element>, active: List<&2, String>, box: Bounds, m: Matrix, w: F32, h: F32,
  build: String -> List<&2, XML.Element> -> Matrix -> F32 -> F32 -> List<&2, Scene<Brush>>) -> MaskData:
  +value = XML.attr.get(as, "mask-image", XML.attr.get(as, "mask", "none"))
  +id = U.drop(U.unquote(U.trim.both(U.scan.head(U.until(U.drop(value, "url("), 41, "")))), "#")
  U.branch(MaskData, U.prefix(value, "url("),
    _ => U.branch(MaskData, U.strings.has(active, id), _ => MaskData{Nil{}, 2},
      _ => mask.resource(XML.element.find(all, id), id, XML.attr.get(as, "mask-mode", "match-source"), box, m, w, h, build)),
    _ => MaskData{Nil{}, 0})

def scene.masked(+scene: Scene<Brush>, as: List<&2, XML.Attr>, all: List<&2, XML.Element>, active: List<&2, String>, w: F32, h: F32,
  build: String -> List<&2, XML.Element> -> Matrix -> F32 -> F32 -> List<&2, Scene<Brush>>) -> Scene<Brush>:
  Scene{es, box, inv, style, opacity, kids, id, ink, clip, outline, fillTree, maskNodes, maskMode, markerNodes, coverage, effect} = scene
  mask.scene(scene, mask.attach(as, all, active, box, matrix.inverse(inv), w, h, build))

def mask.value(c: Img.Color, mode: U32) -> F32:
  Img.Color{r, g, b, a} = c
  U.choose(F32, U32.is_eq(mode, 1), a, (r * 0.2126 + g * 0.7152 + b * 0.0722 : F32))

def mask.factor(+mode: U32, render: Unit -> Img.Color) -> F32:
  U.branch(F32, U32.is_eq(mode, 0), _ => 1.0, _ => mask.value(render(Unit{}), mode))

# Transparent source pixels cannot contribute, so avoid rendering their masks.
def mask.apply(+c: Img.Color, +opacity: F32, mode: U32, render: Unit -> Img.Color) -> Img.Color:
  Img.Color{r, g, b, a} = c
  U.branch(Img.Color, F32.is_gt(a, 0.0) && F32.is_gt(opacity, 0.0),
    _ => color.fade(c, (opacity * mask.factor(mode, render) : F32)), _ => Img.clear())

def style.paint(s: String, +current: String, opacity: F32) -> Img.Color:
  +paint = s
  color.fade(color(U.choose(String, String.eq(CSS.css.lower(U.trim.both(paint)), "currentcolor"), current, paint)), opacity)

def filter.sample(effect: FilterEffect, p: Point, linear: Bool, original: Unit -> Img.Color) -> Img.Color:
  match effect:
    case NoFilter{}: original(Unit{})
    case FilterSpec{region, units, viewport, attrs, primitives}: original(Unit{})
    case FilterImage{raster}: raster.color(raster, p, linear)

def paint.order.composite(+order: U32, +fill: Img.Color, +stroke: Img.Color, +markers: Img.Color) -> Img.Color:
  U.choose(Img.Color, U32.is_eq(order, 1), color.over(stroke, color.over(markers, fill)),
    U.choose(Img.Color, U32.is_eq(order, 2), color.over(markers, color.over(fill, stroke)),
      U.choose(Img.Color, U32.is_eq(order, 3), color.over(fill, color.over(markers, stroke)),
        U.choose(Img.Color, U32.is_eq(order, 4), color.over(stroke, color.over(fill, markers)),
          U.choose(Img.Color, U32.is_eq(order, 5), color.over(fill, color.over(stroke, markers)), color.over(markers, color.over(stroke, fill)))))))

# `limit` is the coverage the enclosing clips leave at this pixel; taking the
# minimum with the shape's own coverage keeps an edge that coincides with a clip
# edge (marker and image viewports) at its true coverage instead of squaring it.
def scene.shape(es: Fill, +s: Style, ink: Paint<Brush>, outline: StrokeMesh, +p: Point, +paintPoint: Point, +worldPoint: Point, +linear: Bool, markers: Img.Color, fills: List<&2, Scene<Brush>> -> Point -> Point -> Img.Color, strokes: List<&2, Scene<Brush>> -> Point -> Point -> Img.Color, +limit: F32) -> Img.Color:
  Style{fill, stroke, col, fo, so, width, even, visible, ss, ms, rendering, order} = s
  Paint{fc, sc} = ink
  +fillCover = U.choose(F32, visible && Bool.not(String.eq(fill, "none")), U.min(fill.coverage(es, p, worldPoint, even), limit), 0.0)
  +strokeCover = U.choose(F32, visible && Bool.not(String.eq(stroke, "none")) && F32.is_gt(width, 0.0), U.min(stroke.coverage(outline, worldPoint), limit), 0.0)
  paint.order.composite(order,
    U.branch(Img.Color, F32.is_gt(fillCover, 0.0), _ => color.fade(color.space(brush.sample(fc, p, paintPoint, fills), linear), fillCover), _ => Img.clear()),
    U.branch(Img.Color, F32.is_gt(strokeCover, 0.0), _ => color.fade(color.space(brush.sample(sc, p, paintPoint, strokes), linear), strokeCover), _ => Img.clear()), markers)

def style.margin(s: Style) -> F32:
  Style{fill, stroke, col, fo, so, w, even, visible, ss, ms, rendering, order} = s
  StrokeSettings{cap, join, limit, dash, offset, vector} = ss
  (w * U.max(1.41421356237, limit) / 2.0 : F32)

def scene.local(+scene: Scene<Brush>, +p: Point, paintPoint: Point, linear: Bool, +markers: Img.Color, fills: List<&2, Scene<Brush>> -> Point -> Point -> Img.Color, strokes: List<&2, Scene<Brush>> -> Point -> Point -> Img.Color, +limit: F32) -> Img.Color:
  Scene{es, box, inv, style, opacity, kids, id, ink, mask, outline, fillTree, maskNodes, maskMode, markerNodes, coverage, effect} = scene
  +q = matrix.point(inv, p)
  U.branch(Img.Color, bounds.inside(box, q, style.margin(style)) || style.nonScaling(style), _ => scene.shape(fillTree, style, ink, outline, q, matrix.point(inv, paintPoint), p, linear, markers, fills, strokes, limit), _ => markers)

# A rendered filter carries its clip as a plain factor; otherwise the clip
# coverage travels down as the limit.
def filter.rendered(effect: FilterEffect) -> Bool:
  match effect:
    case NoFilter{}: False{}
    case FilterSpec{region, units, viewport, attrs, primitives}: False{}
    case FilterImage{raster}: True{}

# Pattern scenes are finite compiled subtrees; the callback obscures structural descent.
@unsafe
def sample(+scenes: List<&2, Scene<Brush>>, +p: Point, +paintPoint: Point, +back: Img.Color, +linear: Bool, +limit: F32) -> Img.Color:
  match scenes:
    case Nil{}: back
    case Con{Scene{es, box, inv, style, opacity, kids, id, ink, mask, outline, fillTree, maskNodes, maskMode, markerNodes, coverage, effect}, rest}:
      +cc = clip.cover(mask, p)
      +inner = U.min(limit, cc)
      +gate = U.choose(F32, filter.rendered(effect), cc, U.choose(F32, F32.is_gt(inner, 0.0), 1.0, 0.0))
      sample(rest, p, paintPoint, U.branch(Img.Color, bounds.inside(coverage, p, 0.01), _ => color.over(mask.apply(clip.fade(gate, _ => filter.sample(effect, paintPoint, linear, _ => sample(kids, p, paintPoint,
        scene.local(Scene{es, box, inv, style, opacity, kids, id, ink, mask, outline, fillTree, maskNodes, maskMode, markerNodes, coverage, effect}, p, paintPoint, linear, sample(markerNodes, p, paintPoint, Img.clear(), linear, inner),
          nodes => q => center => sample(nodes, q, center, Img.clear(), False{}, 1.0),
          nodes => q => center => sample(nodes, q, center, Img.clear(), False{}, 1.0), inner), linear, inner))),
        opacity, maskMode, _ => sample(maskNodes, p, paintPoint, Img.clear(), U32.is_eq(maskMode, 3), 1.0)), back), _ => back), linear, limit)

# Patterns compile their content once and reuse it for every tile sample.
def pattern.has.content(xs: List<&2, XML.Element>) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{XML.Element{n, as, kids, txt}, rest}:
      +tagname = n
      Bool.not(String.eq(tagname, "title") || String.eq(tagname, "desc") || String.eq(tagname, "metadata") || String.eq(tagname, "#text")) || pattern.has.content(rest)

def pattern.attributes(+xs: List<&2, XML.Attr>) -> List<&2, XML.Attr>:
  match xs:
    case Nil{}: Nil{}
    case Con{XML.Attr{k, v}, rest}:
      +key = k
      U.branch(List<&2, XML.Attr>, String.eq(key, "x") || String.eq(key, "y") || String.eq(key, "width") || String.eq(key, "height")
        || String.eq(key, "viewBox") || String.eq(key, "preserveAspectRatio") || String.eq(key, "patternTransform")
        || String.eq(key, "patternUnits") || String.eq(key, "patternContentUnits"),
        _ => Con{XML.Attr{key, v}, pattern.attributes(rest)}, _ => pattern.attributes(rest))

def pattern.merge(local: XML.Element, template: XML.Element) -> XML.Element:
  XML.Element{n, as, kids, txt} = local
  XML.Element{tn, tas, tkids, ttxt} = template
  +children = kids
  XML.Element{n, XML.attrs.append(as, pattern.attributes(tas)), U.choose(List<&2, XML.Element>, pattern.has.content(children), children, tkids), txt}

def pattern.reference(+node: XML.Element, result: Maybe<&2, XML.Element>, next: XML.Element -> XML.Element) -> XML.Element:
  match result:
    case None{}: node
    case Some{XML.Element{n, as, kids, txt}}:
      +tagname = n
      U.branch(XML.Element, String.eq(tagname, "pattern"), _ => pattern.merge(node, next(XML.Element{tagname, as, kids, txt})), _ => node)

def pattern.resolve(depth: Nat, +node: XML.Element, +all: List<&2, XML.Element>) -> XML.Element:
  match depth:
    case 0n: node
    case 1n+d:
      XML.Element{n, as, kids, txt} = node
      +href = XML.attr.get(as, "href", XML.attr.get(as, "xlink:href", ""))
      U.branch(XML.Element, U.prefix(href, "#"),
        _ => pattern.reference(node, XML.element.find(all, U.drop(href, "#")), e => pattern.resolve(d, e, all)), _ => node)

def pattern.paint(+nodes: List<&2, Scene<Brush>>, inv: Matrix, width: F32, height: F32, opacity: F32) -> Brush:
  Pattern{inv, width, height, opacity, nodes}

def pattern.tile(e: XML.Element, box: Bounds, +w: F32, +h: F32, opacity: F32,
  build: String -> List<&2, XML.Element> -> Matrix -> F32 -> F32 -> List<&2, Scene<Brush>>) -> Brush:
  XML.Element{n, attrs, kids, txt} = e
  Bounds{x0, y0, x1, y1} = box
  +as = CSS.properties(attrs)
  +bx = x0
  +by = y0
  +bw = (x1 - bx : F32)
  +bh = (y1 - by : F32)
  +user = String.eq(XML.attr.get(as, "patternUnits", "objectBoundingBox"), "userSpaceOnUse")
  +contentUser = String.eq(XML.attr.get(as, "patternContentUnits", "userSpaceOnUse"), "userSpaceOnUse")
  +uw = U.choose(F32, user, w, 1.0)
  +uh = U.choose(F32, user, h, 1.0)
  +width = dimension(as, "width", uw, "0")
  +height = dimension(as, "height", uh, "0")
  +view = U.numbers(XML.attr.get(as, "viewBox", ""))
  +hasView = Bool.not(String.eq(XML.attr.get(as, "viewBox", ""), ""))
  +vw = U.choose(F32, hasView, U.nth(view, 2n, 0.0), U.choose(F32, contentUser, w, 1.0))
  +vh = U.choose(F32, hasView, U.nth(view, 3n, 0.0), U.choose(F32, contentUser, h, 1.0))
  +units = U.choose(Matrix, user, identity(), matrix.mul(translate(bx, by), scale(bw, bh)))
  +content = U.choose(Matrix, hasView,
    viewbox.matrix(view, width, height, XML.attr.get(as, "preserveAspectRatio", "xMidYMid meet")),
    scale((U.choose(F32, contentUser, 1.0, bw) / U.choose(F32, user, 1.0, U.max(bw, 0.0000001)) : F32),
      (U.choose(F32, contentUser, 1.0, bh) / U.choose(F32, user, 1.0, U.max(bh, 0.0000001)) : F32)))
  U.branch(Brush, F32.is_gt(width, 0.0) && F32.is_gt(height, 0.0) && F32.is_gt(vw, 0.0) && F32.is_gt(vh, 0.0)
      && (user || (F32.is_gt(bw, 0.0) && F32.is_gt(bh, 0.0))),
    _ => pattern.paint(build(XML.attr.get(as, "id", ""))(Con{XML.Element{"g", Con{XML.Attr{"display", "inline"}, as}, kids, txt}, Nil{}})(content)(vw)(vh),
      matrix.inverse(matrix.mul(transform(XML.attr.get(as, "patternTransform", ""), identity()), matrix.mul(units,
        translate(dimension(as, "x", uw, "0"), dimension(as, "y", uh, "0"))))), width, height, opacity),
    _ => Solid{Img.clear(), Img.clear()})

def pattern.build(+node: XML.Element, +all: List<&2, XML.Element>, active: List<&2, String>, box: Bounds, w: F32, h: F32, opacity: F32,
  build: String -> List<&2, XML.Element> -> Matrix -> F32 -> F32 -> List<&2, Scene<Brush>>) -> Brush:
  XML.Element{n, as, kids, txt} = node
  U.branch(Brush, U.strings.has(active, XML.attr.get(as, "id", "")), _ => Solid{Img.clear(), Img.clear()},
    _ => pattern.tile(pattern.resolve(32n, node, all), box, w, h, opacity, build))

def matrix.show(m: Matrix) -> String:
  Matrix{a, b, c, d, e, f} = m
  "matrix(" ++ xy(a, b) ++ xy(c, d) ++ xy(e, f) ++ ")"

# Marker instances have independent styles and viewports. Their geometry does not
# enlarge the referring shape's object bounding box.
def scene.marked(scene: Scene<Brush>, nodes: List<&2, Scene<Brush>>) -> Scene<Brush>:
  Scene{es, box, inv, style, opacity, kids, id, ink, clip, outline, fillTree, maskNodes, maskMode, oldMarkers, coverage, effect} = scene
  Scene{es, box, inv, style, opacity, kids, id, ink, clip, outline, fillTree, maskNodes, maskMode, nodes, coverage, effect}

def marker.angle.number(n: U.Number) -> F32:
  U.Number{x, t, ok} = n
  +suffix = U.trim.both(t)
  (x * U.choose(F32, String.eq(suffix, "rad"), 57.29577951308232, U.choose(F32, String.eq(suffix, "grad"), 0.9, U.choose(F32, String.eq(suffix, "turn"), 360.0, 1.0))) : F32)

def marker.orient(+s: String, angle: F32, start: Bool) -> F32:
  +auto = String.eq(s, "auto") || String.eq(s, "auto-start-reverse")
  U.choose(F32, auto, (angle + U.choose(F32, start && String.eq(s, "auto-start-reverse"), 180.0, 0.0) : F32), marker.angle.number(U.number(s)))

def marker.reference.point(p: Point, +width: F32, +height: F32) -> List<&2, XML.Attr>:
  Point{x, y} = p
  Con{XML.Attr{"x", F32.show(F32.neg(x))}, Con{XML.Attr{"y", F32.show(F32.neg(y))}, Con{XML.Attr{"width", F32.show(width)}, Con{XML.Attr{"height", F32.show(height)}, Nil{}}}}}

def marker.resource(+result: Maybe<&2, XML.Element>, id: String, vertex: MarkerVertex, start: Bool, strokeWidth: F32, +w: F32, +h: F32) -> List<&2, XML.Element>:
  match result:
    case None{}: Nil{}
    case Some{XML.Element{n, as, kids, txt}}:
      MarkerVertex{Point{x, y}, angle} = vertex
      +width = dimension(as, "markerWidth", w, "3")
      +height = dimension(as, "markerHeight", h, "3")
      +view = U.numbers(XML.attr.get(as, "viewBox", ""))
      +vw = U.nth(view, 2n, width)
      +vh = U.nth(view, 3n, height)
      +unitScale = U.choose(F32, String.eq(XML.attr.get(as, "markerUnits", "strokeWidth"), "userSpaceOnUse"), 1.0, strokeWidth)
      +mat = matrix.mul(translate(x, y), matrix.mul(rotate(marker.orient(XML.attr.get(as, "orient", "0"), angle, start)), scale(unitScale, unitScale)))
      +ref = matrix.point(viewbox.matrix(view, width, height, XML.attr.get(as, "preserveAspectRatio", "xMidYMid meet")), Point{dimension(as, "refX", vw, "0"), dimension(as, "refY", vh, "0")})
      U.branch(List<&2, XML.Element>, String.eq(n, "marker") && F32.is_gt(width, 0.0) && F32.is_gt(height, 0.0) && F32.is_gt(vw, 0.0) && F32.is_gt(vh, 0.0) && F32.is_gt(unitScale, 0.0),
        _ => Con{XML.Element{"g", Con{XML.Attr{"transform", matrix.show(mat)}, Nil{}}, Con{XML.Element{"svg", Con{XML.Attr{"#marker-source", id}, Con{XML.Attr{"#editor-id", ""}, Con{XML.Attr{"transform", ""}, XML.attrs.append(marker.reference.point(ref, width, height), as)}}}, instance.anonymous(kids), txt}, Nil{}}, ""}, Nil{}}, _ => Nil{})

def marker.instance(+value: String, vertex: MarkerVertex, start: Bool, +all: List<&2, XML.Element>, active: List<&2, String>, width: F32, w: F32, h: F32) -> List<&2, XML.Element>:
  +id = U.drop(U.unquote(U.trim.both(U.scan.head(U.until(U.drop(value, "url("), 41, "")))), "#")
  U.branch(List<&2, XML.Element>, U.prefix(value, "url(") && Bool.not(U.strings.has(active, id)),
    _ => marker.resource(XML.element.find(all, id), id, vertex, start, width, w, h), _ => Nil{})

def marker.elements.append(xs: List<&2, XML.Element>, ys: List<&2, XML.Element>) -> List<&2, XML.Element>:
  match xs:
    case Nil{}: ys
    case Con{a, rest}: Con{a, marker.elements.append(rest, ys)}

@unsafe
def marker.instances.loop(xs: List<&2, MarkerVertex>, +first: Bool, +ms: MarkerStyle, +all: List<&2, XML.Element>, +active: List<&2, String>, +width: F32, +w: F32, +h: F32) -> List<&2, XML.Element>:
  match xs:
    case Nil{}: Nil{}
    case Con{vertex, Nil{}}:
      MarkerStyle{start, middle, end} = ms
      +v = vertex
      marker.elements.append(U.branch(List<&2, XML.Element>, first, _ => marker.instance(start, v, True{}, all, active, width, w, h), _ => Nil{}), marker.instance(end, v, False{}, all, active, width, w, h))
    case Con{vertex, Con{head, tail}}:
      MarkerStyle{start, middle, end} = ms
      marker.elements.append(marker.instance(U.choose(String, first, start, middle), vertex, first, all, active, width, w, h), marker.instances.loop(Con{head, tail}, False{}, ms, all, active, width, w, h))

def marker.enabled(ms: MarkerStyle) -> Bool:
  MarkerStyle{start, middle, end} = ms
  U.prefix(start, "url(") || U.prefix(middle, "url(") || U.prefix(end, "url(")

def marker.instances(+name: String, as: List<&2, XML.Attr>, +s: Style, all: List<&2, XML.Element>, active: List<&2, String>, +w: F32, +h: F32) -> List<&2, XML.Element>:
  Style{fill, stroke, col, fo, so, width, even, visible, ss, ms, rendering, order} = s
  U.branch(List<&2, XML.Element>, marker.enabled(ms) && (String.eq(name, "path") || String.eq(name, "line") || String.eq(name, "polyline") || String.eq(name, "polygon")),
    _ => marker.instances.loop(marker.trace(shape.data(name, as, w, h)), True{}, ms, all, active, width, w, h), _ => Nil{})

def compile.node(+n: String, +as: List<&2, XML.Attr>, +glyphs: List<&2, XML.Element>, +vp: Viewport, inherited: Style, +all: List<&2, XML.Element>, +active: List<&2, String>,
  masks: String -> List<&2, XML.Element> -> Matrix -> F32 -> F32 -> List<&2, Scene<Brush>>, fills: String -> List<&2, XML.Element> -> Matrix -> F32 -> F32 -> List<&2, Scene<Brush>>, strokes: String -> List<&2, XML.Element> -> Matrix -> F32 -> F32 -> List<&2, Scene<Brush>>,
  markers: List<&2, XML.Element> -> Matrix -> F32 -> F32 -> List<&2, Scene<Brush>>,
  children: Style -> Matrix -> F32 -> F32 -> List<&2, Scene<Brush>>) -> List<&2, Scene<Brush>>:
  Viewport{matrix, vw, vh, viewportClip, valid} = vp
  +baseStyle = style.inherit(inherited, as, F32.sqrt(((vw * vw + vh * vh) / 2.0 : F32)))
  +embedded = bitmap.element(n, Con{XML.Attr{"image-rendering", style.image.rendering(baseStyle)}, as}, vw, vh)
  +attrs = bitmap.attrs(embedded, as)
  +style = U.choose(Style, String.eq(n, "#svg-image"), style.embedded(baseStyle), bitmap.style(embedded, baseStyle))
  U.branch(List<&2, Scene<Brush>>, element.hidden(n, as) || Bool.not(valid) || (String.eq(n, "#svg-image") && Bool.not(style.is.visible(baseStyle))), _ => Nil{},
    _ => Con{scene.marked(scene.masked(scene.clipped(scene.bitmap(scene.make(shape.children(n, attrs, glyphs, vw, vh), matrix, style,
      color.opacity(XML.attr.get(attrs, "opacity", "1"), 1.0), U.branch(List<&2, Scene<Brush>>, String.eq(n, "#glyph-run"), _ => Nil{}, _ => children(style)(matrix)(vw)(vh)),
      XML.attr.get(attrs, "#editor-id", ""), all, vw, vh, attrs,
        node => box => pw => ph => alpha => pattern.build(node, all, active, box, pw, ph, alpha, fills),
        node => box => pw => ph => alpha => pattern.build(node, all, active, box, pw, ph, alpha, strokes)), embedded), viewportClip), attrs, all, active, vw, vh, masks), markers(marker.instances(n, attrs, style, all, active, vw, vh))(matrix)(vw)(vh)), Nil{}})

@unsafe
def compile(+fuel: Nat, +xs: List<&2, XML.Element>, +inherited: Style, +m: Matrix, +w: F32, +h: F32,
  +all: List<&2, XML.Element>, +root: Bool, +active: List<&2, String>) -> List<&2, Scene<Brush>>:
  match fuel xs:
    case 0n _: Nil{}
    case 1n+d Nil{}: Nil{}
    case 1n+d Con{XML.Element{tagname, attrs, kids, txt}, rest}:
      +as = image.layout.attrs(CSS.properties(attrs), w, h)
      +n = tagname
      scenes.append(compile.node(n, as, kids, element.viewport(n, as, m, w, h, root), inherited, all, active,
        used => nodes => mat => vw => vh => compile(d, nodes, style.default(), mat, vw, vh, all, False{}, Con{used, active}),
        used => nodes => mat => vw => vh => compile(d, nodes, style.default(), mat, vw, vh, all, False{}, Con{used, active}),
        used => nodes => mat => vw => vh => compile(d, nodes, style.default(), mat, vw, vh, all, False{}, Con{used, active}),
        nodes => mat => vw => vh => compile(d, nodes, style.default(), mat, vw, vh, all, False{}, active),
        style => mat => vw => vh => compile(U.choose(Nat, String.eq(XML.attr.get(as, "#marker-source", ""), ""), fuel, d), kids, U.choose(Style, String.eq(n, "#svg-image"), style.default(), style), mat, vw, vh, U.choose(List<&2, XML.Element>, String.eq(n, "#svg-image"), resources(kids, Nil{}), all), False{}, U.choose(List<&2, String>, String.eq(n, "#svg-image"), Nil{}, U.choose(List<&2, String>, String.eq(XML.attr.get(as, "#marker-source", ""), ""), active, Con{XML.attr.get(as, "#marker-source", ""), active})))),
        compile(fuel, rest, inherited, m, w, h, all, root, active))

# XML.Text layout produces internal glyph geometry while preserving text/tspan groups.
type TextFont is Data:
  TextFont{size: F32, face: U32, weight: String, slant: String, anchor: String,
    letter: F32, word: F32, shift: F32, baseline: String, kern: Bool, preserve: Bool, book: Font.FontBook}

def text.font.em(font: TextFont) -> F32:
  TextFont{size, face, weight, slant, anchor, letter, word, shift, baseline, kern, preserve, book} = font
  size

def text.font.default(book: Font.FontBook) -> TextFont:
  TextFont{16.0, 0, "normal", "normal", "start", 0.0, 0.0, 0.0, "alphabetic", True{}, False{}, book}

def text.measure(+num: U.Number, ref: F32, +size: F32) -> F32:
  U.Number{x, tail, ok} = num
  +t = tail
  U.choose(F32, U.prefix(t, "em"), (x * size : F32), U.choose(F32, U.prefix(t, "ex"), (x * size * 0.536 : F32),
    U.choose(F32, U.prefix(t, "rem"), (x * 16.0 : F32), U.unit(num, ref))))

def text.font.size(+s: String, +parent: F32) -> F32:
  U.choose(F32, String.eq(s, "smaller"), (parent / 1.2 : F32), U.choose(F32, String.eq(s, "larger"), (parent * 1.2 : F32),
    U.choose(F32, String.eq(s, "medium"), 16.0, U.choose(F32, String.eq(s, "small"), 13.0,
      U.choose(F32, String.eq(s, "large"), 18.0, U.max(0.0, text.measure(U.number(s), parent, parent)))))))

def text.font.inherit(+font: TextFont, +as: List<&2, XML.Attr>) -> TextFont:
  TextFont{size, face, weight, slant, anchor, letter, word, shift, baseline, kern, preserve, book} = font
  +sz = text.font.size(style.value(as, "font-size", F32.show(size), "16", True{}), size)
  +wt = style.value(as, "font-weight", weight, "normal", True{})
  +it = style.value(as, "font-style", slant, "normal", True{})
  +bold = String.eq(wt, "bold") || String.eq(wt, "bolder") || F32.is_ge(U.scalar(wt, 400.0), 600.0)
  +italic = String.eq(it, "italic") || U.prefix(it, "oblique")
  +selectedFace = (U.choose(U32, bold, 1, 0) + U.choose(U32, italic, 2, 0) : U32)
  +bs = XML.attr.get(as, "baseline-shift", "0")
  +ws = style.value(as, "white-space", U.choose(String, preserve, "pre", "normal"), "normal", True{})
  +xml = XML.attr.get(as, "xml:space", "")
  TextFont{sz, selectedFace, wt, it,
    style.value(as, "text-anchor", anchor, "start", True{}),
    text.measure(U.number(style.value(as, "letter-spacing", F32.show(letter), "0", True{})), sz, sz),
    text.measure(U.number(style.value(as, "word-spacing", F32.show(word), "0", True{})), sz, sz),
    (shift + U.choose(F32, String.eq(bs, "super"), (Font.font.metric(book, selectedFace, "superscript", 0.4) * sz : F32), U.choose(F32, String.eq(bs, "sub"), (F32.neg(Font.font.metric(book, selectedFace, "subscript", 0.2)) * sz : F32), text.measure(U.number(bs), sz, sz))) : F32),
    style.value(as, "dominant-baseline", baseline, "alphabetic", True{}),
    Bool.not(String.eq(style.value(as, "font-kerning", U.choose(String, kern, "auto", "none"), "auto", True{}), "none")),
    U.choose(Bool, String.eq(xml, "preserve"), True{}, U.choose(Bool, String.eq(xml, "default"), False{}, U.prefix(ws, "pre") || String.eq(ws, "break-spaces"))), book}

def text.length.value(+num: U.Number, +ref: F32, +size: F32, next: String -> List<&2, F32>) -> List<&2, F32>:
  U.Number{x, tail, ok} = num
  U.branch(List<&2, F32>, ok, _ => Con{text.measure(num, ref, size), next(dash.skip.units(tail))}, _ => Nil{})

@unsafe
def text.lengths(s: String, +ref: F32, +size: F32) -> List<&2, F32>:
  text.length.value(U.number(s), ref, size, rest => text.lengths(U.separators(rest), ref, size))

type TextFrame is Data:
  TextFrame{start: U32, xs: List<&2, F32>, ys: List<&2, F32>, dxs: List<&2, F32>, dys: List<&2, F32>, angles: List<&2, F32>}

def text.frame(+as: List<&2, XML.Attr>, start: U32, +w: F32, +h: F32, +size: F32) -> TextFrame:
  TextFrame{start, text.lengths(XML.attr.get(as, "x", ""), w, size), text.lengths(XML.attr.get(as, "y", ""), h, size),
    text.lengths(XML.attr.get(as, "dx", ""), w, size), text.lengths(XML.attr.get(as, "dy", ""), h, size), U.numbers(XML.attr.get(as, "rotate", ""))}

type TextValue is Data:
  TextValue{value: F32, set: Bool}

def text.at(xs: List<&2, F32>, +index: U32, +repeat: Bool, previous: TextValue) -> TextValue:
  match xs:
    case Nil{}: U.choose(TextValue, repeat, previous, TextValue{0.0, False{}})
    case Con{head, tail}:
      +h = head
      U.branch(TextValue, U32.is_eq(index, 0), _ => TextValue{h, True{}}, _ => text.at(tail, (index - 1 : U32), repeat, TextValue{h, True{}}))

def text.axis.first(+value: TextValue, fallback: Unit -> TextValue) -> TextValue:
  TextValue{x, set} = value
  U.branch(TextValue, set, _ => value, _ => fallback(Unit{}))

def text.axis(xs: List<&2, TextFrame>, +index: U32, +axis: U32) -> TextValue:
  match xs:
    case Nil{}: TextValue{0.0, False{}}
    case Con{TextFrame{start, xx, yy, dx, dy, angles}, rest}:
      text.axis.first(text.at(U.choose(List<&2, F32>, U32.is_eq(axis, 0), xx, U.choose(List<&2, F32>, U32.is_eq(axis, 1), yy,
        U.choose(List<&2, F32>, U32.is_eq(axis, 2), dx, U.choose(List<&2, F32>, U32.is_eq(axis, 3), dy, angles)))),
        (index - start : U32), U32.is_eq(axis, 4), TextValue{0.0, False{}}), _ => text.axis(rest, index, axis))

type TextPosition is Data:
  TextPosition{x: TextValue, y: TextValue, dx: TextValue, dy: TextValue, angle: TextValue}

def text.position(+frames: List<&2, TextFrame>, +index: U32) -> TextPosition:
  TextPosition{text.axis(frames, index, 0), text.axis(frames, index, 1), text.axis(frames, index, 2), text.axis(frames, index, 3), text.axis(frames, index, 4)}

type TextChunk is Data:
  TextChunk{key: U32, delta: F32}

type TextCursor is Data:
  TextCursor{x: F32, y: F32, index: U32, chunk: U32, start: F32, anchor: String,
    previous: U32, previousClass: U32, previousFace: U32, previousSize: F32,
    seen: Bool, space: Bool, trailing: F32, spacing: F32, chunks: List<&2, TextChunk>}

def text.cursor() -> TextCursor:
  TextCursor{0.0, 0.0, 0, 0, 0.0, "start", 0, 0, 99, 0.0, False{}, True{}, 0.0, 0.0, Nil{}}

def text.chunk(+cursor: TextCursor) -> List<&2, TextChunk>:
  TextCursor{x, y, index, chunk, start, anchor, prev, pc, pf, ps, seen, blankState, trailing, spacing, chunks} = cursor
  +width = (x - start - trailing - spacing : F32)
  Con{TextChunk{chunk, U.choose(F32, String.eq(anchor, "middle"), (width / 2.0 : F32), U.choose(F32, String.eq(anchor, "end"), width, 0.0))}, chunks}

def text.index(cursor: TextCursor) -> U32:
  TextCursor{x, y, index, chunk, start, anchor, prev, pc, pf, ps, seen, blankState, trailing, spacing, chunks} = cursor
  index

# XML.Text paths use the same flattened geometry as fills and strokes.
def text.path.target(target: Maybe<&2, XML.Element>, +w: F32, +h: F32) -> List<&2, XML.Attr>:
  match target:
    case None{}: Nil{}
    case Some{XML.Element{n, as, kids, txt}}:
      +attrs = CSS.properties(as)
      Con{XML.Attr{"#text-path-data", shape.data(n, attrs, w, h)}, Con{XML.Attr{"#text-path-transform", XML.attr.get(attrs, "transform", "")}, Con{XML.Attr{"#text-path-length", XML.attr.get(attrs, "pathLength", "0")}, Nil{}}}}

def text.path.attrs(+as: List<&2, XML.Attr>, all: List<&2, XML.Element>, +w: F32, +h: F32) -> List<&2, XML.Attr>:
  +direct = XML.attr.get(as, "path", "")
  +href = XML.attr.get(as, "href", XML.attr.get(as, "xlink:href", ""))
  +found = text.path.target(U.branch(Maybe<&2, XML.Element>, U.prefix(href, "#"), _ => XML.element.find(all, U.drop(href, "#")), _ => None{}), w, h)
  XML.attrs.append(U.choose(List<&2, XML.Attr>, String.eq(direct, ""), found, Con{XML.Attr{"#text-path-data", direct}, Nil{}}), as)

def text.path.resolve.node(+n: String, +as: List<&2, XML.Attr>, +kids: List<&2, XML.Element>, txt: String, +all: List<&2, XML.Element>, w: F32, h: F32, vp: Viewport,
  expand: List<&2, XML.Element> -> List<&2, XML.Element> -> F32 -> F32 -> List<&2, XML.Element>) -> XML.Element:
  Viewport{mat, vw, vh, clip, valid} = vp
  XML.Element{n, U.choose(List<&2, XML.Attr>, String.eq(n, "textPath"), text.path.attrs(as, all, w, h), as), expand(kids)(U.choose(List<&2, XML.Element>, String.eq(n, "#svg-image"), kids, all))(vw)(vh), txt}

@unsafe
def text.path.resolve(xs: List<&2, XML.Element>, +all: List<&2, XML.Element>, +w: F32, +h: F32, +root: Bool) -> List<&2, XML.Element>:
  match xs:
    case Nil{}: Nil{}
    case Con{XML.Element{n, attrs, kids, txt}, rest}:
      +as = CSS.properties(attrs)
      +tagname = n
      Con{text.path.resolve.node(tagname, as, kids, txt, all, w, h, element.viewport(tagname, as, identity(), w, h, root), nodes => scope => vw => vh => text.path.resolve(nodes, scope, vw, vh, False{})), text.path.resolve(rest, all, w, h, root)}

def text.path.edges(+xs: List<&2, Edge>, +acc: List<&2, Edge>) -> List<&2, Edge>:
  match xs:
    case Nil{}: acc
    case Con{Edge{p, q, stroked, closed}, rest}: text.path.edges(rest, U.choose(List<&2, Edge>, stroked && F32.is_gt(point.distance(p, q), 0.000001), Con{Edge{p, q, stroked, closed}, acc}, acc))

def text.path.geometry(+as: List<&2, XML.Attr>) -> List<&2, Edge>:
  text.path.edges(edges.transform(path(XML.attr.get(as, "#text-path-data", "")), transform(XML.attr.get(as, "#text-path-transform", ""), identity())), Nil{})

def text.path.total(xs: List<&2, Edge>) -> F32:
  match xs:
    case Nil{}: 0.0
    case Con{Edge{p, q, stroked, closed}, rest}: (point.distance(p, q) + text.path.total(rest) : F32)

def text.path.at(+xs: List<&2, Edge>, +distance: F32, fallback: Matrix) -> Matrix:
  match xs:
    case Nil{}: fallback
    case Con{Edge{Point{x, y}, Point{u, v}, stroked, closed}, rest}:
      +dx = (u - x : F32)
      +dy = (v - y : F32)
      +len = F32.sqrt((dx * dx + dy * dy : F32))
      +tx = (dx / len : F32)
      +ty = (dy / len : F32)
      U.branch(Matrix, F32.is_le(distance, len), _ => Matrix{tx, ty, F32.neg(ty), tx, (x + tx * distance : F32), (y + ty * distance : F32)},
        _ => text.path.at(rest, (distance - len : F32), Matrix{tx, ty, F32.neg(ty), tx, u, v}))

def text.path.offset(+num: U.Number, +total: F32, +calibration: F32, em: F32) -> F32:
  U.Number{x, suffix, valid} = num
  (text.measure(num, total, em) * U.choose(F32, U.prefix(suffix, "%") || F32.is_le(calibration, 0.0), 1.0, (total / calibration : F32)) : F32)

def text.path.begin(+cursor: TextCursor) -> TextCursor:
  TextCursor{x, y, index, chunk, start, anchor, prev, pc, pf, ps, seen, blankState, trailing, spacing, chunks} = cursor
  TextCursor{0.0, 0.0, index, chunk, 0.0, anchor, 0, 0, 99, 0.0, False{}, blankState, 0.0, 0.0, text.chunk(cursor)}

def text.path.end(+cursor: TextCursor, +matrix: Matrix) -> TextCursor:
  TextCursor{x, y, index, chunk, start, anchor, prev, pc, pf, ps, seen, blankState, trailing, spacing, chunks} = cursor
  Matrix{a, b, c, d, e, f} = matrix
  TextCursor{e, f, index, U32.inc(chunk), e, "start", 0, 0, 99, 0.0, True{}, blankState, 0.0, 0.0, text.chunk(cursor)}

def text.path.frames(xs: List<&2, TextFrame>) -> List<&2, TextFrame>:
  match xs:
    case Nil{}: Nil{}
    case Con{TextFrame{start, xx, yy, dx, dy, angles}, rest}: Con{TextFrame{start, xx, Nil{}, dx, dy, angles}, text.path.frames(rest)}

type TextLayout is Data:
  TextLayout{nodes: List<&2, XML.Element>, cursor: TextCursor}

def text.nodes.append(xs: List<&2, XML.Element>, ys: List<&2, XML.Element>) -> List<&2, XML.Element>:
  match xs:
    case Nil{}: ys
    case Con{h, t}: Con{h, text.nodes.append(t, ys)}

def text.layout.combine(left: List<&2, XML.Element>, result: TextLayout) -> TextLayout:
  TextLayout{right, cursor} = result
  TextLayout{text.nodes.append(left, right), cursor}

def text.layout.then(result: TextLayout, next: TextCursor -> TextLayout) -> TextLayout:
  TextLayout{nodes, cursor} = result
  text.layout.combine(nodes, next(cursor))

def text.baseline(+font: TextFont) -> F32:
  TextFont{size, face, weight, slant, anchor, letter, word, shift, baseline, kern, preserve, book} = font
  +base = baseline
  +ascender = Font.font.metric(book, face, "ascender", 1.069)
  +descender = Font.font.metric(book, face, "descender", F32.neg(0.293))
  (U.choose(F32, String.eq(base, "middle"), (size * Font.font.metric(book, face, "xheight", 0.536) / 2.0 : F32),
    U.choose(F32, String.eq(base, "central"), (size * (ascender + descender) / 2.0 : F32),
      U.choose(F32, String.eq(base, "text-before-edge") || String.eq(base, "before-edge"), (size * ascender : F32),
        U.choose(F32, String.eq(base, "text-after-edge") || String.eq(base, "after-edge"), (size * descender : F32), 0.0)))) - shift : F32)

def text.glyph.node(outline: String, advance: F32, width: F32, extra: F32, x: F32, +matrix: Matrix, chunk: U32, index: U32) -> XML.Element:
  XML.Element{"#glyph", Con{XML.Attr{"#length-x", F32.show(x)}, Con{XML.Attr{"#length-width", F32.show(width)}, Con{XML.Attr{"#length-extra", F32.show(extra)}, Con{XML.Attr{"d", outline}, Con{XML.Attr{"#glyph-transform", matrix.show(matrix)}, Con{XML.Attr{"#glyph-advance", F32.show(advance)},
    Con{XML.Attr{"#text-chunk", U32.show(chunk)}, Con{XML.Attr{"#text-index", U32.show(index)}, Nil{}}}}}}}}}, Nil{}, ""}

def text.place(+cursor: TextCursor, +font: TextFont, +glyph: Font.FontGlyph, +pos: TextPosition, +ch: U32) -> TextLayout:
  TextCursor{oldx, oldy, index, oldchunk, start, oldanchor, prev, pc, pf, ps, seen, wasSpace, trailing, spacing, chunks} = cursor
  TextFont{size, face, weight, slant, anchor, letter, word, shift, baseline, kern, preserve, book} = font
  Font.FontGlyph{advance, outline, gid, leftClass, rightClass} = glyph
  TextPosition{TextValue{xx, setx}, TextValue{yy, sety}, TextValue{dx, setdx}, TextValue{dy, setdy}, TextValue{angle, seta}} = pos
  +fresh = setx || sety || Bool.not(seen)
  +factor = (size / 1000.0 : F32)
  +kerning = U.choose(F32, kern && Bool.not(fresh) && U32.is_eq(face, pf) && F32.is_eq(size, ps),
    (Font.font.kern(book, face, prev, pc, gid, rightClass) * factor : F32), 0.0)
  +x = (U.choose(F32, setx, xx, oldx) + dx + kerning : F32)
  +y = (U.choose(F32, sety, yy, oldy) + dy : F32)
  +chunk = U.choose(U32, fresh, U32.inc(oldchunk), oldchunk)
  +blank = U32.is_eq(ch, 32)
  +width = (advance * factor + letter + U.choose(F32, blank, word, 0.0) : F32)
  TextLayout{Con{text.glyph.node(outline, advance, width, (letter + U.choose(F32, blank, word, 0.0) : F32), x, matrix.mul(translate(x, (y + text.baseline(font) : F32)),
    matrix.mul(rotate(angle), scale(factor, F32.neg(factor)))), chunk, index), Nil{}},
    TextCursor{(x + width : F32), y, U32.inc(index), chunk, U.choose(F32, fresh, x, start), U.choose(String, fresh, anchor, oldanchor),
      gid, leftClass, face, size, True{}, blank, U.choose(F32, blank && Bool.not(preserve), width, 0.0), U.choose(F32, blank && Bool.not(preserve), spacing, letter),
      U.choose(List<&2, TextChunk>, fresh, text.chunk(cursor), chunks)}}

def text.character(+cursor: TextCursor, +font: TextFont, frames: List<&2, TextFrame>, +ch: U32) -> TextLayout:
  TextCursor{x, y, index, chunk, start, anchor, prev, pc, pf, ps, seen, previousSpace, trailing, spacing, chunks} = cursor
  TextFont{size, face, weight, slant, fa, letter, word, shift, baseline, kern, preserve, book} = font
  +blank = U.space(ch)
  +value = U.choose(U32, blank, 32, ch)
  U.branch(TextLayout, blank && previousSpace && Bool.not(preserve), _ => TextLayout{Nil{}, cursor},
    _ => text.place(cursor, font, Font.font.glyph(book, face, value), text.position(frames, index), value))

@unsafe
def text.characters(s: String, +font: TextFont, +frames: List<&2, TextFrame>, cursor: TextCursor) -> TextLayout:
  match s:
    case SNil{}: TextLayout{Nil{}, cursor}
    case SCon{Chr{ch}, rest}: text.layout.then(text.character(cursor, font, frames, ch), next => text.characters(rest, font, frames, next))

# Length fitting is applied inside-out; an explicitly fitted child is one fixed unit.
type TextMeasure is Data:
  TextMeasure{count: U32, lo: F32, hi: F32, extra: F32, fixed: F32}

def text.measure.empty() -> TextMeasure:
  TextMeasure{0, 1000000000.0, F32.neg(1000000000.0), 0.0, 0.0}

def text.measure.add(m: TextMeasure, +x: F32, +width: F32, extra: F32, fixed: Bool) -> TextMeasure:
  TextMeasure{count, lo, hi, oldExtra, oldFixed} = m
  TextMeasure{U32.inc(count), U.min(lo, x), U.max(hi, (x + width : F32)), extra, (oldFixed + U.choose(F32, fixed, width, 0.0) : F32)}

def text.measure.nodes(xs: List<&2, XML.Element>, +skip: String, +acc: TextMeasure) -> TextMeasure:
  match xs:
    case Nil{}: acc
    case Con{XML.Element{n, as, kids, txt}, rest}:
      +attrs = as
      +glyph = String.eq(n, "#glyph")
      +fixed = String.eq(XML.attr.get(attrs, "#length-fixed", ""), "yes")
      text.measure.nodes(rest, skip, U.branch(TextMeasure, (glyph && Bool.not(String.eq(XML.attr.get(attrs, "#text-index", ""), skip))) || fixed,
        _ => text.measure.add(acc, U.scalar(XML.attr.get(attrs, "#length-x", "0"), 0.0), U.scalar(XML.attr.get(attrs, "#length-width", "0"), 0.0), U.scalar(XML.attr.get(attrs, "#length-extra", "0"), 0.0), fixed),
        _ => text.measure.nodes(kids, skip, acc)))

def text.length.matrix(m: Matrix, +ratio: F32, delta: F32) -> Matrix:
  Matrix{a, b, c, d, e, f} = m
  Matrix{(a * ratio : F32), (b * ratio : F32), c, d, (e + delta : F32), f}

def text.length.attrs(+as: List<&2, XML.Attr>, +ratio: F32, +delta: F32) -> List<&2, XML.Attr>:
  Con{XML.Attr{"#glyph-transform", matrix.show(text.length.matrix(transform(XML.attr.get(as, "#glyph-transform", ""), identity()), ratio, delta))},
    Con{XML.Attr{"#length-x", F32.show((U.scalar(XML.attr.get(as, "#length-x", "0"), 0.0) + delta : F32))},
      Con{XML.Attr{"#length-width", F32.show((U.scalar(XML.attr.get(as, "#length-width", "0"), 0.0) * ratio : F32))},
        Con{XML.Attr{"#length-extra", F32.show((U.scalar(XML.attr.get(as, "#length-extra", "0"), 0.0) * ratio : F32))}, as}}}}

def text.length.translate(xs: List<&2, XML.Element>, +delta: F32) -> List<&2, XML.Element>:
  match xs:
    case Nil{}: Nil{}
    case Con{XML.Element{n, as, kids, txt}, rest}:
      +attrs = as
      +tagname = n
      Con{XML.Element{tagname, U.choose(List<&2, XML.Attr>, String.eq(tagname, "#glyph") || String.eq(XML.attr.get(attrs, "#length-fixed", ""), "yes"), text.length.attrs(attrs, 1.0, delta), attrs),
        text.length.translate(kids, delta), txt}, text.length.translate(rest, delta)}

type TextFit is Data:
  TextFit{nodes: List<&2, XML.Element>, count: U32, fixed: F32}

def text.fit.append(nodes: List<&2, XML.Element>, result: TextFit) -> TextFit:
  TextFit{rest, endCount, endFixed} = result
  TextFit{text.nodes.append(nodes, rest), endCount, endFixed}

def text.fit.then(result: TextFit, next: U32 -> F32 -> TextFit) -> TextFit:
  TextFit{nodes, count, fixed} = result
  text.fit.append(nodes, next(count)(fixed))

def text.fit.group(n: String, as: List<&2, XML.Attr>, txt: String, result: TextFit) -> TextFit:
  TextFit{nodes, count, fixed} = result
  TextFit{Con{XML.Element{n, as, nodes, txt}, Nil{}}, count, fixed}

@unsafe
def text.fit.nodes(+xs: List<&2, XML.Element>, +origin: F32, +ratio: F32, +step: F32, +skip: String, +count: U32, +fixed: F32) -> TextFit:
  match xs:
    case Nil{}: TextFit{Nil{}, count, fixed}
    case Con{XML.Element{n, as, kids, txt}, rest}:
      +attrs = as
      +tagname = n
      +locked = String.eq(XML.attr.get(attrs, "#length-fixed", ""), "yes")
      +glyph = String.eq(tagname, "#glyph")
      +x = U.scalar(XML.attr.get(attrs, "#length-x", "0"), 0.0)
      +delta = ((x - origin - fixed) * (ratio - 1.0) + U32.to_f32(count) * step : F32)
      text.fit.then(U.branch(TextFit, locked || (glyph && Bool.not(String.eq(XML.attr.get(attrs, "#text-index", ""), skip))),
        _ => TextFit{Con{XML.Element{tagname, text.length.attrs(attrs, U.choose(F32, locked, 1.0, ratio), delta),
          text.length.translate(kids, delta), txt}, Nil{}}, U32.inc(count), (fixed + U.choose(F32, locked, U.scalar(XML.attr.get(attrs, "#length-width", "0"), 0.0), 0.0) : F32)},
        _ => text.fit.group(tagname, attrs, txt, text.fit.nodes(kids, origin, ratio, step, skip, count, fixed))),
        nextCount => nextFixed => text.fit.nodes(rest, origin, ratio, step, skip, nextCount, nextFixed))

def text.length.finish(fit: TextFit, cursor: TextCursor, delta: F32) -> TextLayout:
  TextFit{nodes, count, fixed} = fit
  TextCursor{x, y, index, chunk, start, anchor, prev, pc, pf, ps, seen, blankState, trailing, spacing, chunks} = cursor
  TextLayout{nodes, TextCursor{(x + delta : F32), y, index, chunk, start, anchor, prev, pc, pf, ps, seen, blankState, trailing, spacing, chunks}}

def text.length.fit(+result: TextLayout, +m: TextMeasure, +target: F32, +stretch: Bool, +skip: String) -> TextLayout:
  TextLayout{nodes, cursor} = result
  TextMeasure{count, lo, hi, extra, fixed} = m
  +natural = (hi - lo - extra : F32)
  +free = (natural - fixed : F32)
  +ratio = U.choose(F32, stretch && F32.is_gt(free, 0.0), (U.max(0.0, (target - fixed : F32)) / U.max(free, 0.000001) : F32), 1.0)
  +step = U.choose(F32, Bool.not(stretch) && U32.is_gt(count, 1), ((target - natural) / U.max(1.0, (U32.to_f32(count) - 1.0 : F32)) : F32), 0.0)
  +delta = U.choose(F32, stretch, (free * (ratio - 1.0) - extra : F32), U.choose(F32, U32.is_gt(count, 1), (target - natural - extra : F32), 0.0))
  U.branch(TextLayout, U32.is_gt(count, 0) && F32.is_gt(natural, 0.0),
    _ => text.length.finish(text.fit.nodes(nodes, lo, ratio, step, skip, 0, 0.0), cursor, delta), _ => result)

def text.length.valid(num: U.Number) -> Bool:
  U.Number{x, tail, ok} = num
  ok && F32.is_ge(x, 0.0)

def text.length(+result: TextLayout, +as: List<&2, XML.Attr>, w: F32, size: F32, trimEnd: Bool) -> TextLayout:
  TextLayout{nodes, cursor} = result
  TextCursor{x, y, index, chunk, start, anchor, prev, pc, pf, ps, seen, blankState, trailing, spacing, chunks} = cursor
  +target = text.measure(U.number(XML.attr.get(as, "textLength", "-1")), w, size)
  +skip = U.choose(String, trimEnd && F32.is_gt(trailing, 0.0), U32.show((index - 1 : U32)), "#none")
  U.branch(TextLayout, text.length.valid(U.number(XML.attr.get(as, "textLength", "-1"))) && F32.is_ge(target, 0.0),
    _ => text.length.fit(result, text.measure.nodes(nodes, skip, text.measure.empty()), target, String.eq(XML.attr.get(as, "lengthAdjust", "spacing"), "spacingAndGlyphs"), skip), _ => result)

def text.length.group.attrs(+as: List<&2, XML.Attr>, +m: TextMeasure) -> List<&2, XML.Attr>:
  TextMeasure{count, lo, hi, extra, fixed} = m
  U.branch(List<&2, XML.Attr>, U32.is_gt(count, 0) && F32.is_ge(U.scalar(XML.attr.get(as, "textLength", "-1"), F32.neg(1.0)), 0.0),
    _ => Con{XML.Attr{"#length-fixed", "yes"}, Con{XML.Attr{"#length-x", F32.show(lo)}, Con{XML.Attr{"#length-width", F32.show((hi - lo - extra : F32))}, as}}}, _ => as)

def text.layout.group(+as: List<&2, XML.Attr>, +result: TextLayout) -> TextLayout:
  TextLayout{nodes, cursor} = result
  TextLayout{Con{XML.Element{"g", text.length.group.attrs(as, text.measure.nodes(nodes, "#none", text.measure.empty())), nodes, ""}, Nil{}}, cursor}

def text.path.layout(+as: List<&2, XML.Attr>, result: TextLayout, em: F32) -> TextLayout:
  TextLayout{nodes, cursor} = result
  +edges = text.path.geometry(as)
  TextLayout{instance.anonymous(Con{XML.Element{"g", Con{XML.Attr{"#text-path", "1"}, Con{XML.Attr{"#text-path-em", F32.show(em)}, as}}, nodes, ""}, Nil{}}), text.path.end(cursor, text.path.at(edges, text.path.total(edges), identity()))}

@unsafe
def text.layout(+xs: List<&2, XML.Element>, +font: TextFont, +frames: List<&2, TextFrame>, +cursor: TextCursor, +w: F32, +h: F32, +onPath: Bool) -> TextLayout:
  match xs:
    case Nil{}: TextLayout{Nil{}, cursor}
    case Con{XML.Element{n, attrs, kids, txt}, rest}:
      +as = CSS.properties(attrs)
      +childFont = text.font.inherit(font, as)
      text.layout.then(U.branch(TextLayout, String.eq(n, "#text"), _ => text.characters(txt, font, U.choose(List<&2, TextFrame>, onPath, text.path.frames(frames), frames), cursor),
        _ => U.branch(TextLayout, String.eq(n, "textPath") && Bool.not(String.eq(XML.attr.get(as, "display", ""), "none")),
          _ => text.path.layout(as, text.length(text.layout(kids, childFont, frames, text.path.begin(cursor), w, h, True{}), as, w, text.font.em(childFont), False{}), text.font.em(childFont)),
        _ => U.branch(TextLayout, (String.eq(n, "tspan") || String.eq(n, "a")) && Bool.not(String.eq(XML.attr.get(as, "display", ""), "none")),
          _ => text.layout.group(as, text.length(text.layout(kids, childFont, Con{text.frame(as, text.index(cursor), w, h, text.font.em(childFont)), frames}, cursor, w, h, onPath), as, w, text.font.em(childFont), False{})),
          _ => TextLayout{Nil{}, cursor}))),
        next => text.layout(rest, font, frames, next, w, h, onPath))

def text.chunk.shift(xs: List<&2, TextChunk>, +key: U32) -> F32:
  match xs:
    case Nil{}: 0.0
    case Con{TextChunk{id, shift}, rest}: U.branch(F32, U32.is_eq(id, key), _ => shift, _ => text.chunk.shift(rest, key))

def text.anchor.nodes(+xs: List<&2, XML.Element>, +chunks: List<&2, TextChunk>, +skip: String) -> List<&2, XML.Element>:
  match xs:
    case Nil{}: Nil{}
    case Con{XML.Element{n, attrs, kids, txt}, rest}:
      +tagname = n
      +as = attrs
      +glyph = String.eq(tagname, "#glyph")
      +shift = text.chunk.shift(chunks, F32.to_u32(U.scalar(XML.attr.get(as, "#text-chunk", "0"), 0.0)))
      +mat = matrix.mul(translate(F32.neg(shift), 0.0), transform(XML.attr.get(as, "#glyph-transform", ""), identity()))
      U.branch(List<&2, XML.Element>, glyph && String.eq(XML.attr.get(as, "#text-index", ""), skip),
        _ => text.anchor.nodes(rest, chunks, skip),
        _ => Con{XML.Element{tagname, U.choose(List<&2, XML.Attr>, glyph, Con{XML.Attr{"#glyph-transform", matrix.show(mat)}, as}, as),
          text.anchor.nodes(kids, chunks, skip), txt}, text.anchor.nodes(rest, chunks, skip)})

def text.path.glyph.matrix(+mat: Matrix, +position: Matrix, +advance: F32) -> Matrix:
  Matrix{a, b, c, d, e, f} = mat
  Matrix{tx, ty, nx, ny, px, py} = position
  +aa = (tx * a + nx * b : F32)
  +bb = (ty * a + ny * b : F32)
  Matrix{aa, bb, (tx * c + nx * d : F32), (ty * c + ny * d : F32), (px + nx * f - aa * advance / 2.0 : F32), (py + ny * f - bb * advance / 2.0 : F32)}

def text.path.glyph(+as: List<&2, XML.Attr>, +edges: List<&2, Edge>, +total: F32, offset: F32, +mat: Matrix) -> List<&2, XML.Element>:
  Matrix{a, b, c, d, e, f} = mat
  +advance = U.scalar(XML.attr.get(as, "#glyph-advance", "0"), 0.0)
  +mid = (e + advance * F32.sqrt((a * a + b * b : F32)) / 2.0 + offset : F32)
  U.branch(List<&2, XML.Element>, F32.is_lt(mid, 0.0) || F32.is_gt(mid, total) || F32.is_le(total, 0.0), _ => Nil{},
    _ => Con{XML.Element{"#glyph", Con{XML.Attr{"#glyph-transform", matrix.show(text.path.glyph.matrix(mat, text.path.at(edges, mid, identity()), advance))}, as}, Nil{}, ""}, Nil{}})

def text.path.map(+xs: List<&2, XML.Element>, +edges: List<&2, Edge>, +total: F32, +offset: F32) -> List<&2, XML.Element>:
  match xs:
    case Nil{}: Nil{}
    case Con{XML.Element{n, as, kids, txt}, rest}:
      text.nodes.append(U.branch(List<&2, XML.Element>, String.eq(n, "#glyph"), _ => text.path.glyph(as, edges, total, offset, transform(XML.attr.get(as, "#glyph-transform", ""), identity())),
        _ => Con{XML.Element{n, as, text.path.map(kids, edges, total, offset), txt}, Nil{}}), text.path.map(rest, edges, total, offset))

def text.path.mapped(kids: List<&2, XML.Element>, +as: List<&2, XML.Attr>) -> List<&2, XML.Element>:
  +edges = text.path.geometry(as)
  +total = text.path.total(edges)
  text.path.map(kids, edges, total, text.path.offset(U.number(XML.attr.get(as, "startOffset", "0")), total, U.scalar(XML.attr.get(as, "#text-path-length", "0"), 0.0), U.scalar(XML.attr.get(as, "#text-path-em", "16"), 16.0)))

def text.path.finish(+xs: List<&2, XML.Element>) -> List<&2, XML.Element>:
  match xs:
    case Nil{}: Nil{}
    case Con{XML.Element{n, as, kids, txt}, rest}:
      Con{XML.Element{n, as, U.branch(List<&2, XML.Element>, String.eq(XML.attr.get(as, "#text-path", ""), "1"), _ => text.path.mapped(kids, as), _ => text.path.finish(kids)), txt}, text.path.finish(rest)}

def text.cell(+mat: Matrix, +width: F32, box: Bounds) -> Bounds:
  bounds.point(bounds.point(bounds.point(bounds.point(box, matrix.point(mat, Point{0.0, F32.neg(293.0)})),
    matrix.point(mat, Point{width, F32.neg(293.0)})), matrix.point(mat, Point{width, 1069.0})), matrix.point(mat, Point{0.0, 1069.0}))

def text.bounds(xs: List<&2, XML.Element>, +matrix: Matrix, +box: Bounds) -> Bounds:
  match xs:
    case Nil{}: box
    case Con{XML.Element{n, as, kids, txt}, rest}:
      +attrs = as
      +mat = matrix.mul(matrix, transform(XML.attr.get(attrs, "transform", ""), identity()))
      text.bounds(rest, matrix, text.bounds(kids, mat,
        U.branch(Bounds, String.eq(n, "#glyph"), _ => text.cell(matrix.mul(mat, transform(XML.attr.get(attrs, "#glyph-transform", ""), identity())),
          U.scalar(XML.attr.get(attrs, "#glyph-advance", "0"), 0.0), box), _ => box)))

def text.bounds.show(box: Bounds) -> String:
  Bounds{x0, y0, x1, y1} = box
  xy(x0, y0) ++ xy(x1, y1)

def text.paint.bounds(xs: List<&2, XML.Element>, +box: String) -> List<&2, XML.Element>:
  match xs:
    case Nil{}: Nil{}
    case Con{XML.Element{n, as, kids, txt}, rest}: Con{XML.Element{n, Con{XML.Attr{"#paint-box", box}, as}, text.paint.bounds(kids, box), txt}, text.paint.bounds(rest, box)}

def text.finished.nodes(+nodes: List<&2, XML.Element>, as: List<&2, XML.Attr>) -> XML.Element:
  +box = text.bounds.show(text.bounds(nodes, identity(), Bounds{1000000000.0, 1000000000.0, F32.neg(1000000000.0), F32.neg(1000000000.0)}))
  XML.Element{"g", Con{XML.Attr{"#paint-box", box}, as}, text.paint.bounds(nodes, box), ""}

def text.finish(+result: TextLayout, as: List<&2, XML.Attr>) -> XML.Element:
  TextLayout{nodes, cursor} = result
  TextCursor{x, y, index, chunk, start, anchor, prev, pc, pf, ps, seen, blankState, trailing, spacing, chunks} = cursor
  text.finished.nodes(text.path.finish(text.anchor.nodes(nodes, text.chunk(cursor), U.choose(String, F32.is_gt(trailing, 0.0), U32.show((index - 1 : U32)), "#none"))), as)

def text.font.reset(font: TextFont) -> TextFont:
  TextFont{size, face, weight, slant, anchor, letter, word, shift, baseline, kern, preserve, book} = font
  text.font.default(book)

def text.expand.node(+n: String, +as: List<&2, XML.Attr>, +kids: List<&2, XML.Element>, txt: String, +font: TextFont, +vp: Viewport,
  expand: List<&2, XML.Element> -> TextFont -> F32 -> F32 -> List<&2, XML.Element>) -> XML.Element:
  Viewport{matrix, w, h, clip, valid} = vp
  +f = U.choose(TextFont, String.eq(n, "#svg-image"), text.font.reset(font), text.font.inherit(font, as))
  U.branch(XML.Element, String.eq(n, "text"),
    _ => text.finish(text.length(text.layout(kids, f, Con{text.frame(as, 0, w, h, text.font.em(f)), Nil{}}, text.cursor(), w, h, False{}), as, w, text.font.em(f), True{}), as),
    _ => XML.Element{n, as, expand(kids)(f)(w)(h), txt})

@unsafe
def text.expand(xs: List<&2, XML.Element>, +font: TextFont, +w: F32, +h: F32, +root: Bool) -> List<&2, XML.Element>:
  match xs:
    case Nil{}: Nil{}
    case Con{XML.Element{n, as, kids, txt}, rest}:
      +tagname = n
      +attrs = as
      Con{text.expand.node(tagname, attrs, kids, txt, font, element.viewport(tagname, attrs, identity(), w, h, root),
        nodes => f => vw => vh => text.expand(nodes, f, vw, vh, False{})), text.expand(rest, font, w, h, root)}

type TextPaintRun is Data:
  TextPaintRun{nodes: List<&2, XML.Element>, rest: List<&2, XML.Element>}

def text.paint.reverse(xs: List<&2, XML.Element>, acc: List<&2, XML.Element>) -> List<&2, XML.Element>:
  match xs:
    case Nil{}: acc
    case Con{h, t}: text.paint.reverse(t, Con{h, acc})

@unsafe
def text.paint.take(+xs: List<&2, XML.Element>, +acc: List<&2, XML.Element>) -> TextPaintRun:
  match xs:
    case Nil{}: TextPaintRun{text.paint.reverse(acc, Nil{}), Nil{}}
    case Con{XML.Element{n, as, kids, txt}, rest}:
      +name = n
      U.branch(TextPaintRun, String.eq(name, "#glyph"),
        _ => text.paint.take(rest, Con{XML.Element{name, as, kids, txt}, acc}), _ => TextPaintRun{text.paint.reverse(acc, Nil{}), xs})

def text.paint.attrs(xs: List<&2, XML.Element>) -> List<&2, XML.Attr>:
  match xs:
    case Nil{}: Nil{}
    case Con{XML.Element{n, as, kids, txt}, rest}: Con{XML.Attr{"fill-rule", "nonzero"}, as}

def text.paint.run(run: TextPaintRun, next: List<&2, XML.Element> -> List<&2, XML.Element>) -> List<&2, XML.Element>:
  TextPaintRun{nodes, rest} = run
  +glyphs = nodes
  Con{XML.Element{"#glyph-run", text.paint.attrs(glyphs), glyphs, ""}, next(rest)}

@unsafe
def text.paint.group(+xs: List<&2, XML.Element>) -> List<&2, XML.Element>:
  match xs:
    case Nil{}: Nil{}
    case Con{XML.Element{n, as, kids, txt}, rest}:
      +name = n
      U.branch(List<&2, XML.Element>, String.eq(name, "#glyph"), _ => text.paint.run(text.paint.take(xs, Nil{}), remaining => text.paint.group(remaining)),
        _ => Con{XML.Element{name, as, text.paint.group(kids), txt}, text.paint.group(rest)})

# Resolve context paints after compiling the finite scene tree. Paint server
# coordinates stay in the referencing shape's space, including bounding boxes.
def context.unfaded(+brush: Brush) -> Brush:
  match brush:
    case Bitmap{raster, inv, nearest}: Bitmap{raster, inv, nearest}
    case Solid{col, source}: Solid{source, source}
    case PendingContext{stroke, opacity}: PendingContext{stroke, 1.0}
    case ContextPaint{source, matrix, opacity}: ContextPaint{source, matrix, 1.0}
    case Pattern{inverse, width, height, opacity, nodes}: Pattern{inverse, width, height, 1.0, nodes}
    case Tile{raster, inverse, width, height, opacity, u, v, grid}: Tile{raster, inverse, width, height, 1.0, u, v, grid}
    case Gradient{inv, radial, start, end, radius, fr, stops, spread, opacity, linear}: Gradient{inv, radial, start, end, radius, fr, stops, spread, 1.0, linear}

def context.select(paint: Paint<Brush>, stroke: Bool) -> Brush:
  Paint{f, s} = paint
  context.unfaded(U.choose(Brush, stroke, s, f))

def context.brush(brush: Brush, paint: Paint<Brush>, matrix: Matrix, patterns: List<&2, Scene<Brush>> -> List<&2, Scene<Brush>>) -> Brush:
  match brush:
    case Bitmap{raster, inv, nearest}: Bitmap{raster, inv, nearest}
    case Solid{col, source}: Solid{col, source}
    case PendingContext{stroke, opacity}: ContextPaint{context.select(paint, stroke), matrix, opacity}
    case ContextPaint{source, matrix, opacity}: ContextPaint{source, matrix, opacity}
    case Pattern{inverse, width, height, opacity, nodes}: Pattern{inverse, width, height, opacity, patterns(nodes)}
    case Tile{raster, inverse, width, height, opacity, u, v, grid}: Tile{raster, inverse, width, height, opacity, u, v, grid}
    case Gradient{inv, radial, start, end, radius, fr, stops, spread, opacity, linear}: Gradient{inv, radial, start, end, radius, fr, stops, spread, opacity, linear}

def context.empty() -> Paint<Brush>:
  Paint{Solid{Img.clear(), Img.clear()}, Solid{Img.clear(), Img.clear()}}

def context.paint(ink: Paint<Brush>, +paint: Paint<Brush>, +matrix: Matrix, fills: List<&2, Scene<Brush>> -> List<&2, Scene<Brush>>, strokes: List<&2, Scene<Brush>> -> List<&2, Scene<Brush>>) -> Paint<Brush>:
  Paint{f, s} = ink
  Paint{context.brush(f, paint, matrix, fills), context.brush(s, paint, matrix, strokes)}

# These bounds enclose rendered coverage, including descendant strokes and
# markers. They are distinct from objectBoundingBox paint coordinates.
def bounds.finite(b: Bounds) -> Bool:
  Bounds{x0, y0, x1, y1} = b
  F32.is_lt(F32.abs(x0), 1.0e25) && F32.is_lt(F32.abs(y0), 1.0e25) && F32.is_lt(F32.abs(x1), 1.0e25) && F32.is_lt(F32.abs(y1), 1.0e25)

def bounds.safe(+box: Bounds) -> Bounds:
  U.choose(Bounds, bounds.finite(box), box, Bounds{F32.neg(1.0e30), F32.neg(1.0e30), 1.0e30, 1.0e30})

def bounds.transform(box: Bounds, +mat: Matrix) -> Bounds:
  Bounds{x0, y0, x1, y1} = box
  +left = x0
  +top = y0
  +right = x1
  +bottom = y1
  # Include the local stroke tests' tolerances before transforming the corners.
  +a = (left - 0.0001 : F32)
  +b = (top - 0.0001 : F32)
  +c = (right + 0.0001 : F32)
  +d = (bottom + 0.0001 : F32)
  U.branch(Bounds, F32.is_gt(left, right) || F32.is_gt(top, bottom), _ => bounds.empty(),
    _ => bounds.safe(bounds.point(bounds.point(bounds.point(bounds.point(bounds.empty(), matrix.point(mat, Point{a, b})), matrix.point(mat, Point{c, b})), matrix.point(mat, Point{a, d})), matrix.point(mat, Point{c, d}))))

def stroke.mesh.bounds(mesh: StrokeMesh) -> Bounds:
  StrokeMesh{stree, inv, cover} = mesh
  bounds.transform(stroke.tree.bounds(stree), matrix.inverse(inv))

def scene.coverage(xs: List<&2, Scene<Brush>>, box: Bounds) -> Bounds:
  match xs:
    case Nil{}: box
    case Con{Scene{es, objectBox, inv, style, opacity, kids, id, ink, clip, outline, fillTree, maskNodes, maskMode, markerNodes, coverage, effect}, rest}:
      scene.coverage(rest, bounds.merge(box, coverage))

def scene.effect.coverage(effect: FilterEffect, cached: Bounds, computed: Bounds) -> Bounds:
  match effect:
    case FilterImage{raster}: cached
    case NoFilter{}: computed
    case FilterSpec{region, units, viewport, attrs, primitives}: computed

def scene.covered(+scene: Scene<Brush>) -> Scene<Brush>:
  Scene{es, box, inv, style, opacity, kids, id, ink, clip, outline, fillTree, maskNodes, maskMode, markerNodes, coverage, effect} = scene
  +own = bounds.merge(bounds.transform(fill.bounds(fillTree), matrix.inverse(inv)), stroke.mesh.bounds(outline))
  Scene{es, box, inv, style, opacity, kids, id, ink, clip, outline, fillTree, maskNodes, maskMode, markerNodes, scene.effect.coverage(effect, coverage, scene.coverage(markerNodes, scene.coverage(kids, own))), effect}

def context.node(scene: Scene<Brush>, +ink: Paint<Brush>, kids: List<&2, Scene<Brush>>, masks: List<&2, Scene<Brush>>, markers: Paint<Brush> -> List<&2, Scene<Brush>>) -> Scene<Brush>:
  Scene{es, box, inv, style, opacity, oldKids, id, oldInk, clip, outline, fillTree, maskNodes, maskMode, markerNodes, coverage, effect} = scene
  scene.covered(Scene{es, box, inv, style, opacity, kids, id, ink, clip, outline, fillTree, masks, maskMode, markers(ink), bounds.empty(), effect})

@unsafe
def context.scenes(+xs: List<&2, Scene<Brush>>, +paint: Paint<Brush>, +parent: Matrix) -> List<&2, Scene<Brush>>:
  match xs:
    case Nil{}: Nil{}
    case Con{Scene{es, box, inv, style, opacity, kids, id, ink, clip, outline, fillTree, maskNodes, maskMode, markerNodes, coverage, effect}, rest}:
      Con{context.node(Scene{es, box, inv, style, opacity, kids, id, ink, clip, outline, fillTree, maskNodes, maskMode, markerNodes, coverage, effect},
        context.paint(ink, paint, matrix.mul(parent, matrix.inverse(inv)),
          nodes => context.scenes(nodes, context.empty(), identity()), nodes => context.scenes(nodes, context.empty(), identity())),
        context.scenes(kids, paint, parent), context.scenes(maskNodes, context.empty(), identity()),
        source => context.scenes(markerNodes, source, inv)), context.scenes(rest, paint, parent)}

def image.svg.stack.empty(stack: List<&2, String>) -> Bool:
  match stack:
    case Nil{}: True{}
    case Con{head, tail}: False{}

@unsafe
def image.svg.wellformed(+tokens: List<&2, XML.Token>, +stack: List<&2, String>, +seen: Bool) -> Bool:
  match tokens stack:
    case Nil{} Nil{}: seen
    case Nil{} Con{head, tail}: False{}
    case Con{XML.Text{content}, rest} stack:
      (Bool.not(image.svg.stack.empty(stack)) || String.eq(U.trim.both(content), "")) && image.svg.wellformed(rest, stack, seen)
    case Con{XML.Open{name, attrs, closed}, rest} stack:
      +top = image.svg.stack.empty(stack)
      U.branch(Bool, Bool.not(top) || (Bool.not(seen) && String.eq(name, "svg")),
        _ => image.svg.wellformed(rest, U.choose(List<&2, String>, closed, stack, Con{name, stack}), seen || top), _ => False{})
    case Con{XML.Shut{name}, rest} Nil{}: False{}
    case Con{XML.Shut{name}, rest} Con{head, tail}:
      String.eq(U.trim.both(name), head) && image.svg.wellformed(rest, tail, seen)

def image.svg.read(+text: String) -> XML.Element:
  +source = U.choose(String, U.prefix(text, "﻿"), U.drop(text, "﻿"), text)
  U.branch(XML.Element, image.svg.wellformed(XML.tokenize(source), Nil{}, False{}), _ => XML.parse(source), _ => XML.Element{"#document", Nil{}, Nil{}, ""})

# Expand data-URI SVG images into isolated vector subdocuments.
type ImageCodepoint is Data:
  ImageCodepoint{point: U32, step: U32}

@unsafe
def image.svg.utf8.tail(+data: Bin.Bytes, +at: U32, left: Nat, +acc: U32, +minimum: U32, +step: U32) -> ImageCodepoint:
  match left:
    case Zero{}: U.choose(ImageCodepoint, U32.is_ge(acc, minimum) && U32.is_le(acc, 1114111) && Bool.not(U32.is_ge(acc, 55296) && U32.is_le(acc, 57343)), ImageCodepoint{acc, step}, ImageCodepoint{65533, 1})
    case Succ{rest}:
      +v = Bin.bytes.get(data, at)
      U.branch(ImageCodepoint, U32.is_ge(v, 128) && U32.is_le(v, 191), _ => image.svg.utf8.tail(data, U32.inc(at), rest, (acc * 64 + v % 64 : U32), minimum, step), _ => ImageCodepoint{65533, 1})

def image.svg.utf8(+data: Bin.Bytes, +at: U32) -> ImageCodepoint:
  +v = Bin.bytes.get(data, at)
  U.branch(ImageCodepoint, U32.is_lt(v, 128), _ => ImageCodepoint{v, 1},
    _ => U.branch(ImageCodepoint, U32.is_ge(v, 194) && U32.is_le(v, 223), _ => image.svg.utf8.tail(data, U32.inc(at), 1n, (v % 32 : U32), 128, 2),
      _ => U.branch(ImageCodepoint, U32.is_ge(v, 224) && U32.is_le(v, 239), _ => image.svg.utf8.tail(data, U32.inc(at), 2n, (v % 16 : U32), 2048, 3),
        _ => U.branch(ImageCodepoint, U32.is_ge(v, 240) && U32.is_le(v, 244), _ => image.svg.utf8.tail(data, U32.inc(at), 3n, (v % 8 : U32), 65536, 4), _ => ImageCodepoint{65533, 1}))))

def image.svg.utf8.more(decoded: ImageCodepoint, acc: String, next: U32 -> String -> String) -> String:
  ImageCodepoint{point, step} = decoded
  next(step)(SCon{Chr{point}, acc})

@unsafe
def image.svg.byte.text(+data: Bin.Bytes, +at: U32, +acc: String) -> String:
  U.branch(String, U32.is_ge(at, Bin.bytes.size(data)), _ => U.rev(acc, ""), _ => image.svg.utf8.more(image.svg.utf8(data, at), acc, step => text => image.svg.byte.text(data, (at + step : U32), text)))

def image.svg.utf8.push(+out: Bin.Bytes, +c: U32) -> Bin.Bytes:
  U.branch(Bin.Bytes, U32.is_lt(c, 128), _ => Bin.bytes.push(out, c),
    _ => U.branch(Bin.Bytes, U32.is_lt(c, 2048), _ => Bin.bytes.push(Bin.bytes.push(out, (192 + c / 64 : U32)), (128 + c % 64 : U32)),
      _ => U.branch(Bin.Bytes, U32.is_lt(c, 65536), _ => Bin.bytes.push(Bin.bytes.push(Bin.bytes.push(out, (224 + c / 4096 : U32)), (128 + (c / 64) % 64 : U32)), (128 + c % 64 : U32)),
        _ => Bin.bytes.push(Bin.bytes.push(Bin.bytes.push(Bin.bytes.push(out, (240 + c / 262144 : U32)), (128 + (c / 4096) % 64 : U32)), (128 + (c / 64) % 64 : U32)), (128 + c % 64 : U32)))))

def image.svg.uri.bytes(+s: String, +out: Bin.Bytes) -> Bin.Bytes:
  match s:
    case SNil{}: out
    case SCon{Chr{37}, SCon{Chr{a}, SCon{Chr{b}, rest}}}:
      U.branch(Bin.Bytes, Bin.uri.hex.valid(a) && Bin.uri.hex.valid(b), _ => image.svg.uri.bytes(rest, Bin.bytes.push(out, (U.hex.digit(a) * 16 + U.hex.digit(b) : U32))), _ => Bin.bytes.empty())
    case SCon{Chr{c}, rest}:
      U.branch(Bin.Bytes, Bool.not(U32.is_eq(c, 37)), _ => image.svg.uri.bytes(rest, image.svg.utf8.push(out, c)), _ => Bin.bytes.empty())

def image.svg.source(+scan: U.Scan) -> String:
  U.Scan{mime, data} = scan
  +body = U.branch(Bin.Bytes, U.string.contains(CSS.css.lower(mime), ";base64"), _ => Bin.base64(data), _ => image.svg.uri.bytes(data, Bin.bytes.empty()))
  image.svg.byte.text(body, 0, "")

def image.svg.root(+xs: List<&2, XML.Element>) -> XML.Element:
  match xs:
    case Nil{}: XML.Element{"#empty", Nil{}, Nil{}, ""}
    case Con{XML.Element{n, as, kids, txt}, rest}:
      U.branch(XML.Element, String.eq(n, "svg"), _ => XML.Element{n, as, kids, txt}, _ => image.svg.root(rest))

def image.svg.document(root: XML.Element) -> XML.Element:
  XML.Element{n, as, kids, txt} = root
  image.svg.root(kids)

# Intrinsic dimensions come from the root's own width/height attributes; the
# document stylesheet only styles the content once the viewport is known.
def image.svg.attrs(root: XML.Element) -> List<&2, XML.Attr>:
  XML.Element{n, as, kids, txt} = root
  as

def image.svg.absolute(+s: String) -> F32:
  U.branch(F32, String.eq(s, "auto") || U.string.contains(s, "%") || Bool.not(text.length.valid(U.number(s))), _ => F32.neg(1.0), _ => U.unit(U.number(s), 0.0))

def image.svg.ratio(+as: List<&2, XML.Attr>) -> F32:
  +w = image.svg.absolute(XML.attr.get(as, "width", "auto"))
  +h = image.svg.absolute(XML.attr.get(as, "height", "auto"))
  +vb = U.numbers(XML.attr.get(as, "viewBox", ""))
  +vw = U.nth(vb, 2n, 0.0)
  +vh = U.nth(vb, 3n, 0.0)
  U.choose(F32, F32.is_ge(w, 0.0) && F32.is_gt(h, 0.0), (w / U.max(h, 0.000001) : F32), U.choose(F32, F32.is_gt(vw, 0.0) && F32.is_gt(vh, 0.0), (vw / U.max(vh, 0.000001) : F32), 0.0))

def image.svg.size(+as: List<&2, XML.Attr>) -> Point:
  +w = image.svg.absolute(XML.attr.get(as, "width", "auto"))
  +h = image.svg.absolute(XML.attr.get(as, "height", "auto"))
  +ratio = image.svg.ratio(as)
  +hasW = F32.is_ge(w, 0.0)
  +hasH = F32.is_ge(h, 0.0)
  +hasRatio = F32.is_gt(ratio, 0.0)
  +dw = U.choose(F32, hasRatio, U.min(300.0, (150.0 * ratio : F32)), 300.0)
  +dh = U.choose(F32, hasRatio, (dw / U.max(ratio, 0.000001) : F32), 150.0)
  Point{U.choose(F32, hasW, w, U.choose(F32, hasH && hasRatio, (h * ratio : F32), dw)), U.choose(F32, hasH, h, U.choose(F32, hasW && hasRatio, (w / U.max(ratio, 0.000001) : F32), dh))}

def image.svg.normalized(root: XML.Element, size: Point) -> XML.Element:
  XML.Element{n, as, kids, txt} = root
  Point{w, h} = size
  XML.Element{n, Con{XML.Attr{"width", F32.show(w)}, Con{XML.Attr{"height", F32.show(h)}, as}}, kids, txt}

def image.svg.place(+as: List<&2, XML.Attr>, +size: Point, +root: XML.Element,
  expand: List<&2, XML.Element> -> F32 -> F32 -> List<&2, XML.Element>) -> XML.Element:
  Point{iw, ih} = size
  +ratio = image.svg.ratio(image.svg.attrs(root))
  +metadata = F32.show(iw) ++ " " ++ F32.show(ih) ++ " " ++ F32.show(ratio)
  +inside = {Con{root, Nil{}} : List<&2, XML.Element>}
  +styled = {Con{image.svg.normalized(image.svg.root(CSS.css.tree(inside, CSS.css.rules(CSS.css.sheets(inside, iw, ih), iw, ih), Nil{}, Nil{}, 1, 1)), size), Nil{}} : List<&2, XML.Element>}
  +frame = {Con{XML.Attr{"#image-size", metadata}, Con{XML.Attr{"x", XML.attr.get(as, "x", "0")}, Con{XML.Attr{"y", XML.attr.get(as, "y", "0")}, Con{XML.Attr{"width", XML.attr.get(as, "width", "auto")}, Con{XML.Attr{"height", XML.attr.get(as, "height", "auto")}, Con{XML.Attr{"viewBox", "0 0 " ++ F32.show(iw) ++ " " ++ F32.show(ih)}, Con{XML.Attr{"preserveAspectRatio", U.choose(String, F32.is_gt(ratio, 0.0), XML.attr.get(as, "preserveAspectRatio", "xMidYMid meet"), "none")}, Con{XML.Attr{"overflow", XML.attr.get(as, "overflow", "hidden")}, Nil{}}}}}}}}} : List<&2, XML.Attr>}
  XML.Element{"#svg-image", Con{XML.Attr{"#image-size", metadata}, as}, Con{XML.Element{"svg", frame, instance.anonymous(expand(styled)(iw)(ih)), ""}, Nil{}}, ""}

def image.svg.sized(as: List<&2, XML.Attr>, +root: XML.Element,
  expand: List<&2, XML.Element> -> F32 -> F32 -> List<&2, XML.Element>) -> XML.Element:
  image.svg.place(as, image.svg.size(image.svg.attrs(root)), root, expand)

def image.svg.node(as: List<&2, XML.Attr>, +root: XML.Element,
  expand: List<&2, XML.Element> -> F32 -> F32 -> List<&2, XML.Element>) -> XML.Element:
  image.svg.sized(as, root, expand)

def image.svg.mime.name(scan: U.Scan) -> Bool:
  U.Scan{name, rest} = scan
  String.eq(CSS.css.lower(U.trim.both(name)), "image/svg+xml")

def image.svg.mime(scan: U.Scan) -> Bool:
  U.Scan{name, data} = scan
  image.svg.mime.name(U.until(name, 59, ""))

def image.svg.scheme(scan: U.Scan) -> Bool:
  U.Scan{name, rest} = scan
  String.eq(CSS.css.lower(name), "data") && image.svg.mime(U.until(rest, 44, ""))

def image.svg.reference(href: String) -> Bool:
  image.svg.scheme(U.until(href, 58, ""))

@unsafe
def image.svg.expand(+fuel: Nat, +xs: List<&2, XML.Element>, +w: F32, +h: F32) -> List<&2, XML.Element>:
  match fuel xs:
    case Zero{} _: Nil{}
    case Succ{d} Nil{}: Nil{}
    case Succ{d} Con{XML.Element{n, attrs, kids, txt}, rest}:
      +as = CSS.properties(attrs)
      +href = U.trim.both(XML.attr.get(as, "href", XML.attr.get(as, "xlink:href", "")))
      Con{U.branch(XML.Element, String.eq(n, "image") && image.svg.reference(href),
        _ => image.svg.node(as, image.svg.document(image.svg.read(image.svg.source(U.until(U.drop(href, "data:"), 44, "")))), nodes => iw => ih => image.svg.expand(d, nodes, iw, ih)),
        _ => XML.Element{n, attrs, image.svg.expand(fuel, kids, w, h), txt}), image.svg.expand(fuel, rest, w, h)}

# Font loading must include text hidden inside an SVG image data URI.
def text.present(+xs: List<&2, XML.Element>) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{XML.Element{n, as, kids, txt}, rest}: String.eq(n, "text") || (String.eq(n, "image") && image.svg.reference(U.trim.both(XML.attr.get(as, "href", XML.attr.get(as, "xlink:href", ""))))) || text.present(kids) || text.present(rest)

def document.camera.fonts(+root: XML.Element, +w: F32, +h: F32, matrix: Matrix, book: Font.FontBook) -> List<&2, Scene<Brush>>:
  XML.Element{n, a, kids, txt} = root
  +styled = CSS.css.tree(kids, CSS.css.rules(CSS.css.sheets(kids, w, h), w, h), Nil{}, Nil{}, 1, CSS.css.element.count(kids))
  +embedded = image.svg.expand(16n, styled, w, h)
  +used = use.expand(64n, embedded, embedded, Nil{})
  +nodes = text.paint.group(text.expand(text.path.resolve(used, used, w, h, True{}), text.font.default(book), w, h, True{}))
  context.scenes(compile(64n, nodes, style.default(), matrix, w, h, resources(nodes, a), True{}, Nil{}), context.empty(), identity())

def document.fonts(root: XML.Element, w: F32, h: F32, book: Font.FontBook) -> List<&2, Scene<Brush>>:
  document.camera.fonts(root, w, h, identity(), book)

# The document viewport and the output matrix have independent dimensions.
def document.size(+root: XML.Element, +w: F32, +h: F32) -> Point:
  XML.Element{n, attrs, kids, txt} = root
  +styled = CSS.css.tree(kids, CSS.css.rules(CSS.css.sheets(kids, w, h), w, h), Nil{}, Nil{}, 1, CSS.css.element.count(kids))
  +as = image.svg.attrs(image.svg.root(styled))
  Point{U.max(0.0, viewport.dimension(as, "width", w)), U.max(0.0, viewport.dimension(as, "height", h))}

def document.fit.matrix(size: Point, +w: F32, +h: F32) -> Matrix:
  Point{width, height} = size
  +vw = width
  +vh = height
  +zoom = U.min((w / U.max(vw, 0.000001) : F32), (h / U.max(vh, 0.000001) : F32))
  Matrix{zoom, 0.0, 0.0, zoom, ((w - vw * zoom) * 0.5 : F32), ((h - vh * zoom) * 0.5 : F32)}

def document.natural.size(root: XML.Element, matrix: Matrix, book: Font.FontBook, size: Point) -> List<&2, Scene<Brush>>:
  Point{vw, vh} = size
  document.camera.fonts(root, vw, vh, matrix, book)

def document.natural.fonts(+root: XML.Element, +w: F32, +h: F32, matrix: Matrix, book: Font.FontBook) -> List<&2, Scene<Brush>>:
  document.natural.size(root, matrix, book, document.size(root, w, h))

def document.fitted.size(root: XML.Element, w: F32, h: F32, book: Font.FontBook, +size: Point) -> List<&2, Scene<Brush>>:
  Point{vw, vh} = size
  document.camera.fonts(root, vw, vh, document.fit.matrix(size, w, h), book)

def document.fitted.fonts(+root: XML.Element, +w: F32, +h: F32, book: Font.FontBook) -> List<&2, Scene<Brush>>:
  document.fitted.size(root, w, h, book, document.size(root, w, h))

def document(root: XML.Element, w: F32, h: F32) -> List<&2, Scene<Brush>>:
  document.fonts(root, w, h, Font.font.empty())

# Every fill, stroke and clip carries its analytic coverage (see cover.scenes), so
# one sample at the pixel center reads exact area coverage; paint is evaluated there.
def pixel.color(+scene: List<&2, Scene<Brush>>, x: U32, y: U32, +aa: U32) -> Img.Color:
  +center = {Point{(U32.to_f32(x) + 0.5 : F32), (U32.to_f32(y) + 0.5 : F32)} : Point}
  sample(scene, center, center, Img.clear(), False{}, 1.0)

def channel(x: F32) -> U32:
  F32.to_u32(F32.floor((U.clamp(x, 0.0, 1.0) * 255.0 + 0.5 : F32)))

def color.pack(c: Img.Color) -> U32:
  Img.Color{r, g, b, a} = c
  (channel(r) * 65536 + channel(g) * 256 + channel(b) : U32)

def pixel(+scene: List<&2, Scene<Brush>>, x: U32, y: U32, aa: U32) -> U32:
  color.pack(color.over(pixel.color(scene, x, y, aa), color.rgb(16777215)))

def bounds.nonempty(b: Bounds) -> Bool:
  Bounds{x0, y0, x1, y1} = b
  F32.is_gt(x1, x0) && F32.is_gt(y1, y0)

def bounds.expand(b: Bounds, +margin: F32) -> Bounds:
  Bounds{x0, y0, x1, y1} = b
  Bounds{(x0 - margin : F32), (y0 - margin : F32), (x1 + margin : F32), (y1 + margin : F32)}

def bounds.overlap(a: Bounds, b: Bounds) -> Bool:
  Bounds{x0, y0, x1, y1} = a
  Bounds{u0, v0, u1, v1} = b
  F32.is_le(x0, u1) && F32.is_le(u0, x1) && F32.is_le(y0, v1) && F32.is_le(v0, y1)

@unsafe
def raster.depth(+size: U32, +side: U32, +depth: Nat) -> Nat:
  U.branch(Nat, U32.is_ge(side, size), _ => depth, _ => raster.depth(size, (side * 2 : U32), 1n+depth))

def raster.format(box: Bounds, requested: F32) -> Raster:
  Bounds{x0, y0, x1, y1} = box
  +x = x0
  +y = y0
  +right = x1
  +bottom = y1
  +step = U.max(U.max(requested, 0.000001), (U.max((right - x : F32), (bottom - y : F32)) / 1022.0 : F32))
  +ox = (F32.floor((x / step : F32)) * step : F32)
  +oy = (F32.floor((y / step : F32)) * step : F32)
  +w = F32.to_u32(U.clamp(F32.ceil(((right - ox) / step : F32)), 0.0, 1024.0))
  +h = F32.to_u32(U.clamp(F32.ceil(((bottom - oy) / step : F32)), 0.0, 1024.0))
  Raster{Point{ox, oy}, step, w, h, raster.depth(U.choose(U32, U32.is_gt(w, h), w, h), 1, 0n), False{}, Img.Flat{Img.clear()}}

def raster.empty() -> Raster:
  Raster{Point{0.0, 0.0}, 1.0, 0, 0, 0n, False{}, Img.Flat{Img.clear()}}

def raster.store(format: Raster, pixels: Img.Pixels, linear: Bool) -> Raster:
  Raster{origin, step, width, height, depth, oldLinear, oldPixels} = format
  Raster{origin, step, width, height, depth, linear, pixels}

def raster.position(+format: Raster, x: F32, y: F32) -> Point:
  Raster{Point{ox, oy}, step, width, height, depth, pixelsLinear, pixels} = format
  Point{(ox + x * step : F32), (oy + y * step : F32)}

def raster.scale(format: Raster) -> F32:
  Raster{origin, step, width, height, depth, pixelsLinear, pixels} = format
  step

def raster.is.linear(format: Raster) -> Bool:
  Raster{origin, step, width, height, depth, pixelsLinear, pixels} = format
  pixelsLinear

def raster.tile.box(+format: Raster, +x: U32, +y: U32, size: U32) -> Bounds:
  +n = U32.to_f32(size)
  +xx = U32.to_f32(x)
  +yy = U32.to_f32(y)
  bounds.point(bounds.point(bounds.empty(), raster.position(format, xx, yy)), raster.position(format, (xx + n : F32), (yy + n : F32)))

def raster.in.frame(format: Raster, x: U32, y: U32) -> Bool:
  Raster{origin, step, width, height, depth, pixelsLinear, pixels} = format
  U32.is_lt(x, width) && U32.is_lt(y, height)

def raster.scene.pixel(+format: Raster, +x: U32, +y: U32, nodes: List<&2, Scene<Brush>>, +aa: U32) -> Img.Color:
  +center = raster.position(format, (U32.to_f32(x) + 0.5 : F32), (U32.to_f32(y) + 0.5 : F32))
  sample(nodes, center, center, Img.clear(), False{}, 1.0)

def raster.scene.tiles(depth: Nat, +x: U32, +y: U32, +format: Raster, +nodes: List<&2, Scene<Brush>>, +box: Bounds, +aa: U32) -> Img.Pixels:
  match depth:
    case 0n:
      U.branch(Img.Pixels, raster.in.frame(format, x, y) && bounds.overlap(box, raster.tile.box(format, x, y, 1)),
        _ => Img.Flat{raster.scene.pixel(format, x, y, nodes, aa)}, _ => Img.Flat{Img.clear()})
    case 1n+d:
      +dd = d
      +half = U32.shln(1, dd)
      U.branch(Img.Pixels, raster.in.frame(format, x, y) && bounds.overlap(box, raster.tile.box(format, x, y, (half * 2 : U32))),
        _ => Img.pixels.join(raster.scene.tiles(dd, x, y, format, nodes, box, aa), raster.scene.tiles(dd, (x + half : U32), y, format, nodes, box, aa), raster.scene.tiles(dd, x, (y + half : U32), format, nodes, box, aa), raster.scene.tiles(dd, (x + half : U32), (y + half : U32), format, nodes, box, aa)), _ => Img.Flat{Img.clear()})

# ---- coverage pass ----
# Before a raster is painted, every fill, stroke outline and clip shape gets a
# coverage mask on that raster's grid (cover.bend), and every pattern brush is
# rendered once into a tile raster at the grid's resolution; sampling then reads
# one value per pixel instead of testing a grid of sub-samples.

# Sub-scanlines per pixel row: the requested AA level, never below four.
def cover.sub(+aa: U32) -> U32:
  U.choose(U32, U32.is_lt(aa, 4), 4, aa)

def cover.pixel(+frame: Raster, p: Point) -> Point:
  Raster{Point{ox, oy}, step, width, height, depth, linear, pixels} = frame
  Point{x, y} = p
  +stepDup = step
  Point{((x - ox) / stepDup : F32), ((y - oy) / stepDup : F32)}

def cover.line(a: Point, b: Point) -> Cov.CovLine:
  Point{ax, ay} = a
  Point{bx, by} = b
  Cov.CovLine{ax, ay, bx, by}

def cover.lines(es: List<&2, Edge>, +frame: Raster) -> List<&2, Cov.CovLine>:
  match es:
    case Nil{}: Nil{}
    case Con{Edge{a, b, stroked, closed}, rest}: Con{cover.line(cover.pixel(frame, a), cover.pixel(frame, b)), cover.lines(rest, frame)}

def cover.build(+lines: List<&2, Cov.CovLine>, +even: Bool, +frame: Raster, +sub: U32) -> Cover:
  Raster{origin, step, width, height, depth, linear, pixels} = frame
  Cover{Cov.mask(lines, even, width, height, sub), origin, step}

# Local edges through m (local to device) onto the frame's pixel grid.
def cover.edges(es: List<&2, Edge>, +m: Matrix, +even: Bool, +frame: Raster, +sub: U32) -> Cover:
  cover.build(cover.lines(edges.transform(es, m), frame), even, frame, sub)

def cover.tree.edges(t: EdgeTree, acc: List<&2, Edge>) -> List<&2, Edge>:
  match t:
    case EdgeEmpty{}: acc
    case EdgeLeaf{box, edge}: Con{edge, acc}
    case EdgeFork{box, left, right}: cover.tree.edges(left, cover.tree.edges(right, acc))

def cover.parts(t: StrokeTree, acc: List<&2, StrokePart>) -> List<&2, StrokePart>:
  match t:
    case StrokeEmpty{}: acc
    case StrokeLeaf{box, part}: Con{part, acc}
    case StrokeFork{box, left, right}: cover.parts(left, cover.parts(right, acc))

def cover.reverse(pts: List<&2, Point>, acc: List<&2, Point>) -> List<&2, Point>:
  match pts:
    case Nil{}: acc
    case Con{p, rest}: cover.reverse(rest, Con{p, acc})

def cover.area(pts: List<&2, Point>, +first: Point, +acc: F32) -> F32:
  match pts:
    case Nil{}: acc
    case Con{p, Nil{}}: (acc + point.cross(p, first) : F32)
    case Con{p, Con{q, rest}}:
      +qq = q
      cover.area(Con{qq, rest}, first, (acc + point.cross(p, qq) : F32))

# Every part polygon is oriented the same way so nonzero winding unions them.
def cover.oriented(pts: List<&2, Point>) -> List<&2, Point>:
  match pts:
    case Nil{}: Nil{}
    case Con{p, rest}:
      +pp = p
      +ps = {Con{pp, rest} : List<&2, Point>}
      U.branch(List<&2, Point>, F32.is_lt(cover.area(ps, pp, 0.0), 0.0), _ => cover.reverse(ps, Nil{}), _ => ps)

def cover.close(pts: List<&2, Point>, +first: Point, acc: List<&2, Edge>) -> List<&2, Edge>:
  match pts:
    case Nil{}: acc
    case Con{p, Nil{}}: Con{Edge{p, first, True{}, True{}}, acc}
    case Con{p, Con{q, rest}}:
      +qq = q
      Con{Edge{p, qq, True{}, True{}}, cover.close(Con{qq, rest}, first, acc)}

def cover.polygon(pts: List<&2, Point>, acc: List<&2, Edge>) -> List<&2, Edge>:
  match pts:
    case Nil{}: acc
    case Con{p, rest}:
      +pp = p
      cover.close(Con{pp, rest}, pp, acc)

def cover.arc(n: Nat, +c: Point, +r: F32, +angle: F32, +step: F32, acc: List<&2, Point>) -> List<&2, Point>:
  match n:
    case 0n: cover.reverse(Con{point.add(c, Point{(r * F32.cos(angle) : F32), (r * F32.sin(angle) : F32)}), acc}, Nil{})
    case 1n+d: cover.arc(d, c, r, (angle + step : F32), step, Con{point.add(c, Point{(r * F32.cos(angle) : F32), (r * F32.sin(angle) : F32)}), acc})

def cover.segments(+extent: F32, +radius: F32) -> U32:
  F32.to_u32(U.clamp((F32.ceil((extent * F32.sqrt((radius * 2.5 : F32)) : F32)) + 2.0 : F32), 3.0, 64.0))

def cover.wrap(+a: F32) -> F32:
  (a - 6.283185307179586 * F32.floor((a / 6.283185307179586 : F32)) : F32)

def cover.angle(p: Point) -> F32:
  Point{x, y} = p
  F32.atan2(y, x)

# The polygon of one stroke part; `scale` is device pixels per mesh unit for arcs.
def cover.part.points(part: StrokePart, +scale: F32) -> List<&2, Point>:
  match part:
    case StrokeBand{origin, dir, len, r}:
      +dirDup = dir
      +p = origin
      +q = point.add(p, point.scale(dirDup, len))
      +n = point.scale(point.normal(dirDup), r)
      Con{point.add(p, n), Con{point.add(q, n), Con{point.sub(q, n), Con{point.sub(p, n), Nil{}}}}}
    case StrokeTriangle{a, b, c}: Con{a, Con{b, Con{c, Nil{}}}}
    case StrokeCircle{center, radius}:
      +r = radius
      +n = cover.segments(6.283185307179586, (r * scale : F32))
      cover.arc(U32.to_nat((n - 1 : U32)), center, r, 0.0, (6.283185307179586 / U32.to_f32(n) : F32), Nil{})
    case StrokeSector{center, radius, a, b, sign}:
      +bDup = b
      +r = radius
      +start = cover.angle(a)
      +sweep = U.choose(F32, F32.is_gt(sign, 0.0), cover.wrap((cover.angle(bDup) - start : F32)), F32.neg(cover.wrap((start - cover.angle(bDup) : F32))))
      +n = cover.segments(F32.abs(sweep), (r * scale : F32))
      +c = center
      Con{c, cover.arc(U32.to_nat(n), c, r, start, (sweep / U32.to_f32(n) : F32), Nil{})}

def cover.parts.edges(parts: List<&2, StrokePart>, +scale: F32, acc: List<&2, Edge>) -> List<&2, Edge>:
  match parts:
    case Nil{}: acc
    case Con{part, rest}: cover.parts.edges(rest, scale, cover.polygon(cover.oriented(cover.part.points(part, scale)), acc))

def cover.scale(+m: Matrix, +frame: Raster) -> F32:
  Matrix{a, b, c, d, e, f} = m
  Raster{origin, step, width, height, depth, linear, pixels} = frame
  (F32.sqrt(F32.abs((a * d - b * c : F32))) / step : F32)

def cover.stroke(mesh: StrokeMesh, +frame: Raster, +sub: U32) -> StrokeMesh:
  StrokeMesh{stree, inv, old} = mesh
  +tree = stree
  +iv = inv
  +m = matrix.inverse(iv)
  StrokeMesh{tree, iv, cover.build(cover.lines(edges.transform(cover.parts.edges(cover.parts(tree, Nil{}), cover.scale(m, frame), Nil{}), m), frame), False{}, frame, sub)}

def cover.clip(c: Clip, +frame: Raster, +sub: U32) -> Clip:
  match c:
    case ClipAll{}: ClipAll{}
    case ClipShape{es, inv, even, old}:
      +tree = es
      +iv = inv
      +ev = even
      ClipShape{tree, iv, ev, cover.edges(cover.tree.edges(tree, Nil{}), matrix.inverse(iv), ev, frame, sub)}
    case ClipUnion{a, b}: ClipUnion{cover.clip(a, frame, sub), cover.clip(b, frame, sub)}
    case ClipIntersect{a, b}: ClipIntersect{cover.clip(a, frame, sub), cover.clip(b, frame, sub)}

def cover.fill(f: Fill, es: List<&2, Edge>, +m: Matrix, +even: Bool, +frame: Raster, +sub: U32) -> Fill:
  Fill{tree, old} = f
  Fill{tree, cover.edges(es, m, even, frame, sub)}

def cover.rule(+s: Style) -> Bool:
  Style{fill, stroke, col, fo, so, width, even, visible, ss, ms, rendering, order} = s
  even

# ---- pattern tiles ----
# Device pixels per pattern unit along the denser tile axis; m maps pattern space to device.
def cover.density(+m: Matrix, +frame: Raster) -> F32:
  Matrix{a, b, c, d, e, f} = m
  (U.max(F32.sqrt((a * a + b * b : F32)), F32.sqrt((c * c + d * d : F32))) / raster.scale(frame) : F32)

def cover.tile.frame(+w: F32, +h: F32, +density: F32) -> Raster:
  raster.format(Bounds{0.0, 0.0, w, h}, (1.0 / U.max(density, 0.000001) : F32))

def cover.tile.wrapped(p: Point, +w: F32, +h: F32) -> Point:
  Point{x, y} = p
  Point{tile.wrap(x, w), tile.wrap(y, h)}

# Pixel centers wrap into the tile, so a partial last column or row shows the tile's start.
def cover.tile.center(+frame: Raster, +x: U32, +y: U32, +w: F32, +h: F32) -> Point:
  cover.tile.wrapped(raster.position(frame, (U32.to_f32(x) + 0.5 : F32), (U32.to_f32(y) + 0.5 : F32)), w, h)

@unsafe
def cover.tile.pixels(depth: Nat, +x: U32, +y: U32, +frame: Raster, +nodes: List<&2, Scene<Brush>>, +box: Bounds, +w: F32, +h: F32) -> Img.Pixels:
  match depth:
    case 0n:
      +center = cover.tile.center(frame, x, y, w, h)
      U.branch(Img.Pixels, raster.in.frame(frame, x, y) && bounds.inside(box, center, 0.01), _ => Img.Flat{sample(nodes, center, center, Img.clear(), False{}, 1.0)}, _ => Img.Flat{Img.clear()})
    case 1n+d:
      +dd = d
      +half = U32.shln(1, dd)
      U.branch(Img.Pixels, raster.in.frame(frame, x, y),
        _ => Img.pixels.join(cover.tile.pixels(dd, x, y, frame, nodes, box, w, h), cover.tile.pixels(dd, (x + half : U32), y, frame, nodes, box, w, h), cover.tile.pixels(dd, x, (y + half : U32), frame, nodes, box, w, h), cover.tile.pixels(dd, (x + half : U32), (y + half : U32), frame, nodes, box, w, h)),
        _ => Img.Flat{Img.clear()})

def cover.tile(+frame: Raster, nodes: List<&2, Scene<Brush>>, +w: F32, +h: F32) -> Raster:
  Raster{origin, step, width, height, depth, linear, pixels} = frame
  +ns = nodes
  raster.store(frame, cover.tile.pixels(depth, 0, 0, frame, ns, scene.coverage(ns, bounds.empty()), w, h), False{})

# ---- bitmap minification ----
# An image drawn smaller than its pixels is box-filtered down to its device
# footprint first (area weights over the source pixels each output pixel
# covers), so a bilinear read at the pixel center approximates area filtering.

# Overlap of [lo, hi) with source pixel i.
def reduce.weight(+lo: F32, +hi: F32, +i: U32) -> F32:
  U.max((U.min(hi, (U32.to_f32(i) + 1.0 : F32)) - U.max(lo, U32.to_f32(i)) : F32), 0.0)

@unsafe
def reduce.cols(+pixels: Img.Pixels, +side: U32, +x: U32, +y: U32, +lo: F32, +hi: F32, +wy: F32, n: Nat, acc: Img.Color) -> Img.Color:
  match n:
    case 0n: acc
    case 1n+d: reduce.cols(pixels, side, (x + 1 : U32), y, lo, hi, wy, d, color.add(acc, color.fade(Img.pixels.get(pixels, side, x, y), (reduce.weight(lo, hi, x) * wy : F32))))

@unsafe
def reduce.rows(+pixels: Img.Pixels, +side: U32, +x: U32, +y: U32, +x0: F32, +x1: F32, +y0: F32, +y1: F32, +nx: Nat, n: Nat, acc: Img.Color) -> Img.Color:
  match n:
    case 0n: acc
    case 1n+d: reduce.rows(pixels, side, x, (y + 1 : U32), x0, x1, y0, y1, nx, d, reduce.cols(pixels, side, x, y, x0, x1, reduce.weight(y0, y1, y), nx, acc))

# Output pixel (x, y) covers source [x fx, (x + 1) fx) by [y fy, (y + 1) fy), clipped to the image.
def reduce.cell(+pixels: Img.Pixels, +side: U32, +x: U32, +y: U32, +w: U32, +h: U32, +fx: F32, +fy: F32) -> Img.Color:
  +x0 = (U32.to_f32(x) * fx : F32)
  +y0 = (U32.to_f32(y) * fy : F32)
  +x1 = U.min((x0 + fx : F32), U32.to_f32(w))
  +y1 = U.min((y0 + fy : F32), U32.to_f32(h))
  +ix = F32.to_u32(F32.floor(x0))
  +iy = F32.to_u32(F32.floor(y0))
  +area = ((x1 - x0) * (y1 - y0) : F32)
  U.branch(Img.Color, F32.is_le(area, 0.0), _ => Img.clear(),
    _ => color.fade(reduce.rows(pixels, side, ix, iy, x0, x1, y0, y1, U32.to_nat((F32.to_u32(F32.ceil(x1)) - ix : U32)), U32.to_nat((F32.to_u32(F32.ceil(y1)) - iy : U32)), Img.clear()), (1.0 / area : F32)))

@unsafe
def reduce.pixels(depth: Nat, +x: U32, +y: U32, +pixels: Img.Pixels, +side: U32, +w: U32, +h: U32, +fx: F32, +fy: F32, +rw: U32, +rh: U32) -> Img.Pixels:
  match depth:
    case 0n: U.branch(Img.Pixels, U32.is_lt(x, rw) && U32.is_lt(y, rh), _ => Img.Flat{reduce.cell(pixels, side, x, y, w, h, fx, fy)}, _ => Img.Flat{Img.clear()})
    case 1n+d:
      +dd = d
      +half = U32.shln(1, dd)
      U.branch(Img.Pixels, U32.is_lt(x, rw) && U32.is_lt(y, rh),
        _ => Img.pixels.join(reduce.pixels(dd, x, y, pixels, side, w, h, fx, fy, rw, rh), reduce.pixels(dd, (x + half : U32), y, pixels, side, w, h, fx, fy, rw, rh), reduce.pixels(dd, x, (y + half : U32), pixels, side, w, h, fx, fy, rw, rh), reduce.pixels(dd, (x + half : U32), (y + half : U32), pixels, side, w, h, fx, fy, rw, rh)),
        _ => Img.Flat{Img.clear()})

# Resample to rw by rh pixels, each covering fx by fy source pixels.
def raster.resample(+r: Raster, +rw: U32, +rh: U32, +fx: F32, +fy: F32) -> Raster:
  Raster{origin, step, width, height, depth, linear, pixels} = r
  +rd = raster.depth(U.choose(U32, U32.is_gt(rw, rh), rw, rh), 1, 0n)
  Raster{origin, step, rw, rh, rd, linear, reduce.pixels(rd, 0, 0, pixels, U32.shln(1, depth), width, height, fx, fy, rw, rh)}

# Reduce a whole image to rw by rh pixels; the caller rescales the brush inverse to match.
def raster.reduce(+r: Raster, +rw: U32, +rh: U32) -> Raster:
  Raster{origin, step, width, height, depth, linear, pixels} = r
  raster.resample(r, rw, rh, (U32.to_f32(width) / U32.to_f32(rw) : F32), (U32.to_f32(height) / U32.to_f32(rh) : F32))

# An axis-aligned tile of at least four device pixels is rendered at device
# density and read bilinearly (nearest-neighbour images stay crisp). A rotated,
# skewed or tiny tile is rendered at `sub` times the density, or at least four
# pixels across, and read with a sub by sub grid of nearest lookups over each
# device pixel's footprint: rotated content keeps supersampled edges and a tile
# smaller than a pixel averages out.
def cover.aligned(+m: Matrix) -> Bool:
  Matrix{a, b, c, d, e, f} = m
  F32.is_le((F32.abs(b) + F32.abs(c) : F32), (0.001 * (F32.abs(a) + F32.abs(d) : F32) : F32))

# The linear part of m applied to (x, y).
def cover.vector(+m: Matrix, +x: F32, +y: F32) -> Point:
  Matrix{a, b, c, d, e, f} = m
  Point{(a * x + c * y : F32), (b * x + d * y : F32)}

# Device pixels per image pixel along each image axis; m maps image pixels to device.
def cover.axes(+m: Matrix, +frame: Raster) -> Point:
  Matrix{a, b, c, d, e, f} = m
  +st = raster.scale(frame)
  Point{(F32.sqrt((a * a + b * b : F32)) / st : F32), (F32.sqrt((c * c + d * d : F32)) / st : F32)}

def cover.reduced(+size: U32, +density: F32) -> U32:
  +n = F32.to_u32(F32.ceil((U32.to_f32(size) * U.min(density, 1.0) : F32)))
  U.choose(U32, U32.is_lt(n, 1), 1, n)

def cover.bitmap.sized(+raster: Raster, +inv: Matrix, +nearest: Bool, +w: U32, +h: U32, +rw: U32, +rh: U32) -> Brush:
  U.branch(Brush, Bool.not(nearest) && (U32.is_lt(rw, w) || U32.is_lt(rh, h)),
    _ => Bitmap{raster.reduce(raster, rw, rh), matrix.mul(scale((U32.to_f32(rw) / U32.to_f32(w) : F32), (U32.to_f32(rh) / U32.to_f32(h) : F32)), inv), nearest},
    _ => Bitmap{raster, inv, nearest})

# A minified image is box-filtered down to its device footprint (see raster.resample).
def cover.bitmap(+raster: Raster, +inv: Matrix, +nearest: Bool, axes: Point) -> Brush:
  Raster{origin, step, width, height, depth, linear, pixels} = raster
  Point{dx, dy} = axes
  cover.bitmap.sized(raster, inv, nearest, width, height, cover.reduced(width, dx), cover.reduced(height, dy))

# A pattern brush becomes a tile raster at the frame's resolution, its content
# covered on that tile grid first; m maps the brush's local space to device space.
def cover.brush(brush: Brush, +m: Matrix, +frame: Raster, +sub: U32, cover: List<&2, Scene<Brush>> -> Raster -> U32 -> List<&2, Scene<Brush>>) -> Brush:
  match brush:
    case Bitmap{raster, inv, nearest}:
      +matrix = inv
      cover.bitmap(raster, matrix, nearest, cover.axes(matrix.mul(m, matrix.inverse(matrix)), frame))
    case Solid{c, source}: Solid{c, source}
    case PendingContext{stroke, opacity}: PendingContext{stroke, opacity}
    case ContextPaint{source, mat, opacity}:
      +matrix = mat
      ContextPaint{cover.brush(source, matrix.mul(m, matrix.inverse(matrix)), frame, sub, cover), matrix, opacity}
    case Pattern{inv, w, h, opacity, nodes}:
      +matrix = inv
      +ww = w
      +hh = h
      +pm = matrix.mul(m, matrix.inverse(matrix))
      +density = cover.density(pm, frame)
      +direct = cover.aligned(pm) && F32.is_ge((U.min(ww, hh) * density : F32), 4.0)
      +tile = cover.tile.frame(ww, hh, U.choose(F32, direct, density, U.max((density * U32.to_f32(sub) : F32), (4.0 / U.max(U.min(ww, hh), 0.000001) : F32))))
      +back = matrix.inverse(pm)
      +st = raster.scale(frame)
      Tile{cover.tile(tile, cover(nodes)(tile)(sub), ww, hh), matrix, ww, hh, opacity, cover.vector(back, st, 0.0), cover.vector(back, 0.0, st), U.choose(U32, direct, 1, sub)}
    case Tile{raster, inv, w, h, opacity, u, v, grid}: Tile{raster, inv, w, h, opacity, u, v, grid}
    case Gradient{inv, radial, start, end, radius, focal, stops, spread, opacity, linear}: Gradient{inv, radial, start, end, radius, focal, stops, spread, opacity, linear}

def cover.paint(ink: Paint<Brush>, +m: Matrix, +frame: Raster, +sub: U32, fills: List<&2, Scene<Brush>> -> Raster -> U32 -> List<&2, Scene<Brush>>, strokes: List<&2, Scene<Brush>> -> Raster -> U32 -> List<&2, Scene<Brush>>) -> Paint<Brush>:
  Paint{fill, stroke} = ink
  Paint{cover.brush(fill, m, frame, sub, fills), cover.brush(stroke, m, frame, sub, strokes)}

def paint.fill(+ink: Paint<Brush>) -> Brush:
  Paint{f, st} = ink
  f

def cover.image.rect(+raster: Raster) -> List<&2, Edge>:
  Raster{origin, step, width, height, depth, linear, pixels} = raster
  path(shape.rect.path(0.0, 0.0, U32.to_f32(width), U32.to_f32(height), 0.0, 0.0))

# An image's own rectangle joins the scene clip, so its edges get coverage like
# any shape (the bitmap read clamps to its edge pixels); iv maps device to local.
def cover.image.clip(+brush: Brush, clip: Clip, +iv: Matrix, +frame: Raster, +sub: U32) -> Clip:
  match brush:
    case Bitmap{raster, inv, nearest}:
      +to = matrix.mul(inv, iv)
      +rect = cover.image.rect(raster)
      ClipIntersect{clip, ClipShape{edge.tree(rect), to, False{}, cover.edges(rect, matrix.inverse(to), False{}, frame, sub)}}
    case _: clip

# Half a device pixel in local units, so a scene whose box only reaches into part
# of a pixel is still painted there: the pixel center may lie outside the box.
def cover.reach(+inv: Matrix, +half: F32) -> F32:
  Matrix{a, b, c, d, e, f} = inv
  (half * U.max(F32.sqrt((a * a + b * b : F32)), F32.sqrt((c * c + d * d : F32))) + 0.0001 : F32)

@unsafe
def cover.scenes(xs: List<&2, Scene<Brush>>, +frame: Raster, +sub: U32) -> List<&2, Scene<Brush>>:
  match xs:
    case Nil{}: Nil{}
    case Con{Scene{es, box, inv, style, opacity, kids, id, ink, clip, outline, fill, maskNodes, maskMode, markerNodes, coverage, effect}, rest}:
      +edges = es
      +iv = inv
      +st = style
      +m = matrix.inverse(iv)
      +half = (raster.scale(frame) * 0.5 + 0.01 : F32)
      +ik = ink
      Con{Scene{edges, bounds.expand(box, cover.reach(iv, half)), iv, st, opacity, cover.scenes(kids, frame, sub), id, cover.paint(ik, m, frame, sub, nodes => f => n => cover.scenes(nodes, f, n), nodes => f => n => cover.scenes(nodes, f, n)), cover.image.clip(paint.fill(ik), cover.clip(clip, frame, sub), iv, frame, sub), cover.stroke(outline, frame, sub),
        cover.fill(fill, edges, m, cover.rule(st), frame, sub), cover.scenes(maskNodes, frame, sub), maskMode, cover.scenes(markerNodes, frame, sub), bounds.expand(coverage, half), effect}, cover.scenes(rest, frame, sub)}

def raster.scene(+format: Raster, +nodes: List<&2, Scene<Brush>>, +aa: U32) -> Raster:
  Raster{origin, step, width, height, depth, pixelsLinear, pixels} = format
  +covered = cover.scenes(nodes, format, cover.sub(aa))
  raster.store(format, raster.scene.tiles(depth, 0, 0, format, covered, scene.coverage(covered, bounds.empty()), aa), False{})

# A source alpha input shares its buffer; only the returned RGB channels change.
type FilterInput is Data:
  FilterInput{raster: Raster, region: Bounds, alpha: Bool, standard: Bool}

def color.alpha.only(c: Img.Color) -> Img.Color:
  Img.Color{r, g, b, a} = c
  Img.Color{0.0, 0.0, 0.0, a}

def filter.input.color(input: FilterInput, p: Point, linear: Bool) -> Img.Color:
  FilterInput{raster, region, alpha, standard} = input
  +c = raster.color(raster, p, linear)
  U.branch(Img.Color, alpha, _ => color.alpha.only(c), _ => c)

def filter.input.raster(input: FilterInput) -> Raster:
  FilterInput{raster, region, alpha, standard} = input
  raster

type ColorRow is Data:
  ColorRow{r: F32, g: F32, b: F32, a: F32, bias: F32}

type ColorMatrix is Data:
  ColorMatrix{r: ColorRow, g: ColorRow, b: ColorRow, a: ColorRow}

def color.straight(c: Img.Color) -> Img.Color:
  Img.Color{r, g, b, a} = c
  +alpha = a
  Img.Color{(r / U.max(alpha, 0.0000001) : F32), (g / U.max(alpha, 0.0000001) : F32), (b / U.max(alpha, 0.0000001) : F32), alpha}

def color.premultiply(c: Img.Color) -> Img.Color:
  Img.Color{r, g, b, a} = c
  +alpha = U.clamp(a, 0.0, 1.0)
  Img.Color{(U.clamp(r, 0.0, 1.0) * alpha : F32), (U.clamp(g, 0.0, 1.0) * alpha : F32), (U.clamp(b, 0.0, 1.0) * alpha : F32), alpha}

def color.premul.clamp(c: Img.Color) -> Img.Color:
  Img.Color{r, g, b, a} = c
  +alpha = U.clamp(a, 0.0, 1.0)
  Img.Color{U.clamp(r, 0.0, alpha), U.clamp(g, 0.0, alpha), U.clamp(b, 0.0, alpha), alpha}

def filter.row(row: ColorRow, c: Img.Color) -> F32:
  ColorRow{rr, rg, rb, ra, bias} = row
  Img.Color{r, g, b, a} = c
  (rr * r + rg * g + rb * b + ra * a + bias : F32)

def filter.matrix(rows: ColorMatrix, c: Img.Color) -> Img.Color:
  ColorMatrix{r, g, b, a} = rows
  +straight = color.straight(c)
  color.premultiply(Img.Color{filter.row(r, straight), filter.row(g, straight), filter.row(b, straight), filter.row(a, straight)})

def filter.matrix.row(+vs: List<&2, F32>, +start: U32, +diagonal: U32) -> ColorRow:
  ColorRow{U.nth(vs, U32.to_nat(start), U.choose(F32, U32.is_eq(diagonal, 0), 1.0, 0.0)), U.nth(vs, U32.to_nat((start + 1 : U32)), U.choose(F32, U32.is_eq(diagonal, 1), 1.0, 0.0)), U.nth(vs, U32.to_nat((start + 2 : U32)), U.choose(F32, U32.is_eq(diagonal, 2), 1.0, 0.0)), U.nth(vs, U32.to_nat((start + 3 : U32)), U.choose(F32, U32.is_eq(diagonal, 3), 1.0, 0.0)), U.nth(vs, U32.to_nat((start + 4 : U32)), 0.0)}

def filter.matrix.identity() -> ColorMatrix:
  ColorMatrix{ColorRow{1.0, 0.0, 0.0, 0.0, 0.0}, ColorRow{0.0, 1.0, 0.0, 0.0, 0.0}, ColorRow{0.0, 0.0, 1.0, 0.0, 0.0}, ColorRow{0.0, 0.0, 0.0, 1.0, 0.0}}

def filter.matrix.saturate(+s: F32) -> ColorMatrix:
  ColorMatrix{ColorRow{(0.213 + 0.787 * s : F32), (0.715 - 0.715 * s : F32), (0.072 - 0.072 * s : F32), 0.0, 0.0}, ColorRow{(0.213 - 0.213 * s : F32), (0.715 + 0.285 * s : F32), (0.072 - 0.072 * s : F32), 0.0, 0.0}, ColorRow{(0.213 - 0.213 * s : F32), (0.715 - 0.715 * s : F32), (0.072 + 0.928 * s : F32), 0.0, 0.0}, ColorRow{0.0, 0.0, 0.0, 1.0, 0.0}}

def filter.matrix.hue(angle: F32) -> ColorMatrix:
  +rad = (angle * 0.017453292519943295 : F32)
  +c = F32.cos(rad)
  +s = F32.sin(rad)
  ColorMatrix{ColorRow{(0.213 + 0.787 * c - 0.213 * s : F32), (0.715 - 0.715 * c - 0.715 * s : F32), (0.072 - 0.072 * c + 0.928 * s : F32), 0.0, 0.0}, ColorRow{(0.213 - 0.213 * c + 0.143 * s : F32), (0.715 + 0.285 * c + 0.140 * s : F32), (0.072 - 0.072 * c - 0.283 * s : F32), 0.0, 0.0}, ColorRow{(0.213 - 0.213 * c - 0.787 * s : F32), (0.715 - 0.715 * c + 0.715 * s : F32), (0.072 + 0.928 * c + 0.072 * s : F32), 0.0, 0.0}, ColorRow{0.0, 0.0, 0.0, 1.0, 0.0}}

def filter.matrix.parse(+as: List<&2, XML.Attr>) -> ColorMatrix:
  +kind = XML.attr.get(as, "type", "matrix")
  +vs = U.numbers(XML.attr.get(as, "values", ""))
  U.branch(ColorMatrix, String.eq(kind, "saturate"), _ => filter.matrix.saturate(U.nth(vs, 0n, 1.0)),
    _ => U.branch(ColorMatrix, String.eq(kind, "hueRotate"), _ => filter.matrix.hue(U.nth(vs, 0n, 0.0)),
      _ => U.branch(ColorMatrix, String.eq(kind, "luminanceToAlpha"), _ => ColorMatrix{ColorRow{0.0, 0.0, 0.0, 0.0, 0.0}, ColorRow{0.0, 0.0, 0.0, 0.0, 0.0}, ColorRow{0.0, 0.0, 0.0, 0.0, 0.0}, ColorRow{0.2125, 0.7154, 0.0721, 0.0, 0.0}},
        _ => U.choose(ColorMatrix, U32.is_eq(floats.count(vs), 20), ColorMatrix{filter.matrix.row(vs, 0, 0), filter.matrix.row(vs, 5, 1), filter.matrix.row(vs, 10, 2), filter.matrix.row(vs, 15, 3)}, filter.matrix.identity()))))

type Transfer is Data:
  Transfer{kind: U32, values: List<&2, F32>, count: U32, a: F32, b: F32, c: F32}

def transfer.identity() -> Transfer:
  Transfer{0, Nil{}, 0, 1.0, 0.0, 0.0}

def transfer.parse(+as: List<&2, XML.Attr>) -> Transfer:
  +kind = XML.attr.get(as, "type", "identity")
  +vs = U.numbers(XML.attr.get(as, "tableValues", ""))
  Transfer{U.choose(U32, String.eq(kind, "table"), 1, U.choose(U32, String.eq(kind, "discrete"), 2, U.choose(U32, String.eq(kind, "linear"), 3, U.choose(U32, String.eq(kind, "gamma"), 4, 0)))), vs, floats.count(vs), U.scalar(XML.attr.get(as, U.choose(String, String.eq(kind, "gamma"), "amplitude", "slope"), "1"), 1.0), U.scalar(XML.attr.get(as, U.choose(String, String.eq(kind, "gamma"), "exponent", "intercept"), U.choose(String, String.eq(kind, "gamma"), "1", "0")), 0.0), U.scalar(XML.attr.get(as, "offset", "0"), 0.0)}

def transfer.find(xs: List<&2, XML.Element>, +name: String) -> Transfer:
  match xs:
    case Nil{}: transfer.identity()
    case Con{XML.Element{n, as, kids, txt}, rest}:
      U.branch(Transfer, String.eq(n, name), _ => transfer.parse(as), _ => transfer.find(rest, name))

def transfer.apply(+t: Transfer, +x: F32) -> F32:
  Transfer{kind, vs, count, a, b, c} = t
  +last = U.choose(U32, U32.is_eq(count, 0), 0, (count - 1 : U32))
  +position = (U.clamp(x, 0.0, 1.0) * U32.to_f32(last) : F32)
  +index = F32.to_u32(F32.floor(position))
  +left = U.nth(vs, U32.to_nat(index), x)
  U.branch(F32, U32.is_eq(kind, 1) && U32.is_gt(count, 0), _ => (left + (U.nth(vs, U32.to_nat(U32.inc(index)), left) - left) * (position - U32.to_f32(index)) : F32),
    _ => U.branch(F32, U32.is_eq(kind, 2) && U32.is_gt(count, 0), _ => U.nth(vs, U32.to_nat(F32.to_u32(U.min(U32.to_f32(last), F32.floor((U.clamp(x, 0.0, 1.0) * U32.to_f32(count) : F32))))), x),
      _ => U.branch(F32, U32.is_eq(kind, 3), _ => (a * x + b : F32), _ => U.branch(F32, U32.is_eq(kind, 4), _ => (a * F32.pow(U.max(x, 0.0), b) + c : F32), _ => x))))

def filter.transfer(r: Transfer, g: Transfer, b: Transfer, a: Transfer, c: Img.Color) -> Img.Color:
  Img.Color{cr, cg, cb, ca} = c
  +alpha = ca
  color.premultiply(Img.Color{transfer.apply(r, (cr / U.max(alpha, 0.0000001) : F32)), transfer.apply(g, (cg / U.max(alpha, 0.0000001) : F32)), transfer.apply(b, (cb / U.max(alpha, 0.0000001) : F32)), transfer.apply(a, alpha)})

def color.alpha(c: Img.Color) -> F32:
  Img.Color{r, g, b, a} = c
  a

def filter.arithmetic(+a: F32, +b: F32, k1: F32, k2: F32, k3: F32, k4: F32) -> F32:
  (k1 * a * b + k2 * a + k3 * b + k4 : F32)

def filter.composite(+a: Img.Color, +b: Img.Color, +kind: U32, +k1: F32, +k2: F32, +k3: F32, +k4: F32) -> Img.Color:
  Img.Color{ar, ag, ab, aa} = a
  Img.Color{br, bg, bb, ba} = b
  U.branch(Img.Color, U32.is_eq(kind, 5), _ => color.premul.clamp(Img.Color{filter.arithmetic(ar, br, k1, k2, k3, k4), filter.arithmetic(ag, bg, k1, k2, k3, k4), filter.arithmetic(ab, bb, k1, k2, k3, k4), filter.arithmetic(aa, ba, k1, k2, k3, k4)}),
    _ => U.branch(Img.Color, U32.is_eq(kind, 1), _ => color.fade(a, ba),
      _ => U.branch(Img.Color, U32.is_eq(kind, 2), _ => color.fade(a, (1.0 - ba : F32)),
        _ => U.branch(Img.Color, U32.is_eq(kind, 3), _ => color.add(color.fade(a, ba), color.fade(b, (1.0 - aa : F32))),
          _ => U.branch(Img.Color, U32.is_eq(kind, 4), _ => color.add(color.fade(a, (1.0 - ba : F32)), color.fade(b, (1.0 - aa : F32))), _ => color.over(a, b))))))

def filter.blend.hard(+a: F32, +b: F32) -> F32:
  U.choose(F32, F32.is_le(a, 0.5), (2.0 * a * b : F32), (1.0 - 2.0 * (1.0 - a) * (1.0 - b) : F32))

def filter.blend.soft(+a: F32, +b: F32) -> F32:
  +curve = U.choose(F32, F32.is_le(b, 0.25), (((16.0 * b - 12.0) * b + 4.0) * b : F32), F32.sqrt(b))
  U.choose(F32, F32.is_le(a, 0.5), (b - (1.0 - 2.0 * a) * b * (1.0 - b) : F32), (b + (2.0 * a - 1.0) * (curve - b) : F32))

def filter.blend.channel(+a: F32, +b: F32, kind: U32) -> F32:
  match kind:
    case 1: (a * b : F32)
    case 2: (a + b - a * b : F32)
    case 3: U.min(a, b)
    case 4: U.max(a, b)
    case 5: filter.blend.hard(b, a)
    case 6: U.choose(F32, F32.is_le(b, 0.0), 0.0, U.choose(F32, F32.is_ge(a, 1.0), 1.0, U.min(1.0, (b / U.max(0.0000001, (1.0 - a : F32)) : F32))))
    case 7: U.choose(F32, F32.is_ge(b, 1.0), 1.0, U.choose(F32, F32.is_le(a, 0.0), 0.0, (1.0 - U.min(1.0, ((1.0 - b) / U.max(0.0000001, a) : F32)) : F32)))
    case 8: filter.blend.hard(a, b)
    case 9: filter.blend.soft(a, b)
    case 10: F32.abs((a - b : F32))
    case 11: (a + b - 2.0 * a * b : F32)
    case _: a

def filter.blend.lum(c: Img.Color) -> F32:
  Img.Color{r, g, b, a} = c
  (0.3 * r + 0.59 * g + 0.11 * b : F32)

def filter.blend.sat(+c: Img.Color) -> F32:
  Img.Color{r, g, b, a} = c
  (U.max(r, U.max(g, b)) - U.min(r, U.min(g, b)) : F32)

def filter.blend.setsat(+c: Img.Color, +s: F32) -> Img.Color:
  Img.Color{r, g, b, a} = c
  +lo = U.min(r, U.min(g, b))
  +span = (U.max(r, U.max(g, b)) - lo : F32)
  +scale = U.choose(F32, F32.is_gt(span, 0.0), (s / U.max(span, 0.0000001) : F32), 0.0)
  Img.Color{((r - lo) * scale : F32), ((g - lo) * scale : F32), ((b - lo) * scale : F32), 1.0}

def filter.blend.clip.scale(c: Img.Color, +l: F32, +scale: F32) -> Img.Color:
  Img.Color{r, g, b, a} = c
  Img.Color{(l + (r - l) * scale : F32), (l + (g - l) * scale : F32), (l + (b - l) * scale : F32), 1.0}

def filter.blend.clip(+c: Img.Color) -> Img.Color:
  Img.Color{r, g, b, a} = c
  +l = filter.blend.lum(c)
  +lo = U.min(r, U.min(g, b))
  +hi = U.max(r, U.max(g, b))
  +scaleLow = U.choose(F32, F32.is_lt(lo, 0.0), (l / U.max(0.0000001, (l - lo : F32)) : F32), 1.0)
  +scaleHigh = U.choose(F32, F32.is_gt(hi, 1.0), ((1.0 - l) / U.max(0.0000001, (hi - l : F32)) : F32), 1.0)
  filter.blend.clip.scale(c, l, (scaleLow * scaleHigh : F32))

def filter.blend.setlum(+c: Img.Color, l: F32) -> Img.Color:
  Img.Color{r, g, b, a} = c
  +delta = (l - filter.blend.lum(c) : F32)
  filter.blend.clip(Img.Color{(r + delta : F32), (g + delta : F32), (b + delta : F32), 1.0})

def filter.blend.rgb(+a: Img.Color, +b: Img.Color, +kind: U32) -> Img.Color:
  Img.Color{ar, ag, ab, aa} = a
  Img.Color{br, bg, bb, ba} = b
  U.branch(Img.Color, U32.is_eq(kind, 12), _ => filter.blend.setlum(filter.blend.setsat(a, filter.blend.sat(b)), filter.blend.lum(b)),
    _ => U.branch(Img.Color, U32.is_eq(kind, 13), _ => filter.blend.setlum(filter.blend.setsat(b, filter.blend.sat(a)), filter.blend.lum(b)),
      _ => U.branch(Img.Color, U32.is_eq(kind, 14), _ => filter.blend.setlum(a, filter.blend.lum(b)),
        _ => U.branch(Img.Color, U32.is_eq(kind, 15), _ => filter.blend.setlum(b, filter.blend.lum(a)),
          _ => Img.Color{filter.blend.channel(ar, br, kind), filter.blend.channel(ag, bg, kind), filter.blend.channel(ab, bb, kind), 1.0}))))

def filter.blend(+a: Img.Color, +b: Img.Color, +kind: U32) -> Img.Color:
  Img.Color{ar, ag, ab, aa} = a
  Img.Color{br, bg, bb, ba} = b
  +alpha = (aa * ba : F32)
  color.add(color.add(color.fade(a, (1.0 - ba : F32)), color.fade(b, (1.0 - aa : F32))), color.fade(filter.blend.rgb(Img.Color{(ar / U.max(aa, 0.0000001) : F32), (ag / U.max(aa, 0.0000001) : F32), (ab / U.max(aa, 0.0000001) : F32), 1.0}, Img.Color{(br / U.max(ba, 0.0000001) : F32), (bg / U.max(ba, 0.0000001) : F32), (bb / U.max(ba, 0.0000001) : F32), 1.0}, kind), alpha))

type FilterTap is Data:
  FilterTap{delta: Point, weight: F32}

# Convolution kernels operate on a pixel grid; edge extension precedes interpolation.
type Convolution is Data:
  Convolution{kernel: List<&2, FilterTap>, divisor: F32, bias: F32, preserve: Bool, edge: U32, limits: Bounds}

type FilterOp is Data:
  FilterCopy{}
  FilterFlood{color: Img.Color}
  FilterOffset{delta: Point}
  FilterMatrix{rows: ColorMatrix}
  FilterTransfer{r: Transfer, g: Transfer, b: Transfer, a: Transfer}
  FilterComposite{kind: U32, k1: F32, k2: F32, k3: F32, k4: F32}
  FilterBlend{kind: U32}
  FilterMerge{inputs: List<&2, FilterInput>}
  FilterBlur{kernel: List<&2, FilterTap>}
  FilterMorphology{dilate: Bool, radius: U32, direction: Point}
  FilterConvolution{spec: Convolution}

def filter.merge(xs: List<&2, FilterInput>, +p: Point, +linear: Bool, back: Img.Color) -> Img.Color:
  match xs:
    case Nil{}: back
    case Con{h, t}: filter.merge(t, p, linear, color.over(filter.input.color(h, p, linear), back))

def filter.convolve(xs: List<&2, FilterTap>, +input: FilterInput, +p: Point, +linear: Bool, acc: Img.Color) -> Img.Color:
  match xs:
    case Nil{}: acc
    case Con{FilterTap{delta, weight}, rest}: filter.convolve(rest, input, p, linear, color.add(acc, color.fade(filter.input.color(input, point.add(p, delta), linear), weight)))

# Morphology takes component-wise extrema of premultiplied channels.
def filter.morphology.join(+a: Img.Color, +b: Img.Color, +dilate: Bool) -> Img.Color:
  Img.Color{ar, ag, ab, aa} = a
  Img.Color{br, bg, bb, ba} = b
  Img.Color{U.choose(F32, dilate, U.max(ar, br), U.min(ar, br)), U.choose(F32, dilate, U.max(ag, bg), U.min(ag, bg)), U.choose(F32, dilate, U.max(ab, bb), U.min(ab, bb)), U.choose(F32, dilate, U.max(aa, ba), U.min(aa, ba))}

def filter.morphology.sample(left: Nat, +index: F32, +direction: Point, +dilate: Bool, +input: FilterInput, +p: Point, +linear: Bool, acc: Img.Color) -> Img.Color:
  match left:
    case 0n: acc
    case 1n+rest:
      filter.morphology.sample(rest, (index + 1.0 : F32), direction, dilate, input, p, linear,
        filter.morphology.join(acc, filter.input.color(input, point.add(p, point.scale(direction, index)), linear), dilate))

def filter.convolution.index(+n: F32, +low: F32, +high: F32, edge: U32) -> F32:
  +length = U.max((high - low : F32), 1.0)
  U.choose(F32, U32.is_eq(edge, 1), (low + (n - low) - F32.floor(((n - low) / length : F32)) * length : F32), U.clamp(n, low, (high - 1.0 : F32)))

def filter.convolution.raw(+input: FilterInput, x: F32, y: F32, +linear: Bool) -> Img.Color:
  FilterInput{raster, region, alpha, standard} = input
  +stored = raster.is.linear(raster)
  +c = raster.pixel(raster, x, y)
  +converted = U.branch(Img.Color, U.choose(Bool, stored, linear, Bool.not(linear)), _ => c,
    _ => U.branch(Img.Color, stored, _ => color.from.linear(c), _ => color.space(c, True{})))
  U.choose(Img.Color, alpha, color.alpha.only(converted), converted)

def filter.convolution.pixel(+input: FilterInput, +limits: Bounds, +edge: U32, +x: F32, +y: F32, linear: Bool) -> Img.Color:
  Bounds{x0, y0, x1, y1} = limits
  U.branch(Img.Color, bounds.nonempty(limits) && (Bool.not(U32.is_eq(edge, 2)) || (F32.is_ge(x, x0) && F32.is_lt(x, x1) && F32.is_ge(y, y0) && F32.is_lt(y, y1))),
    _ => filter.convolution.raw(input, filter.convolution.index(x, x0, x1, edge), filter.convolution.index(y, y0, y1, edge), linear), _ => Img.clear())

def filter.convolution.horizontal(+input: FilterInput, +limits: Bounds, +edge: U32, +x: F32, +y: F32, +dx: F32, +linear: Bool) -> Img.Color:
  U.branch(Img.Color, F32.is_eq(dx, 0.0), _ => filter.convolution.pixel(input, limits, edge, x, y, linear),
    _ => color.mix(filter.convolution.pixel(input, limits, edge, x, y, linear), filter.convolution.pixel(input, limits, edge, (x + 1.0 : F32), y, linear), dx))

def filter.convolution.at(+input: FilterInput, +limits: Bounds, +edge: U32, +raster: Raster, p: Point, +linear: Bool) -> Img.Color:
  Raster{Point{ox, oy}, step, width, height, depth, stored, pixels} = raster
  Point{x, y} = p
  +fx = ((x - ox) / step - 0.5 : F32)
  +fy = ((y - oy) / step - 0.5 : F32)
  +ix = F32.floor(fx)
  +iy = F32.floor(fy)
  +dx = (fx - ix : F32)
  +dy = (fy - iy : F32)
  U.branch(Img.Color, F32.is_eq(dy, 0.0), _ => filter.convolution.horizontal(input, limits, edge, ix, iy, dx, linear),
    _ => color.mix(filter.convolution.horizontal(input, limits, edge, ix, iy, dx, linear), filter.convolution.horizontal(input, limits, edge, ix, (iy + 1.0 : F32), dx, linear), dy))

def filter.convolution.color(+input: FilterInput, limits: Bounds, edge: U32, p: Point, linear: Bool) -> Img.Color:
  filter.convolution.at(input, limits, edge, filter.input.raster(input), p, linear)

def filter.convolution.sum(xs: List<&2, FilterTap>, +input: FilterInput, +limits: Bounds, +edge: U32, +preserve: Bool, +p: Point, +linear: Bool, acc: Img.Color) -> Img.Color:
  match xs:
    case Nil{}: acc
    case Con{FilterTap{delta, weight}, rest}:
      +sample = filter.convolution.color(input, limits, edge, point.add(p, delta), linear)
      filter.convolution.sum(rest, input, limits, edge, preserve, p, linear, color.add(acc, color.fade(U.choose(Img.Color, preserve, color.straight(sample), sample), weight)))

def filter.convolution.finish(+c: Img.Color, +divisor: F32, +bias: F32, +preserve: Bool, original: Img.Color) -> Img.Color:
  Img.Color{r, g, b, a} = c
  Img.Color{rr, gg, bb, aa} = original
  +alpha = U.choose(F32, preserve, aa, (a / divisor + bias : F32))
  U.branch(Img.Color, preserve,
    _ => color.premultiply(Img.Color{(r / divisor + bias : F32), (g / divisor + bias : F32), (b / divisor + bias : F32), alpha}),
    _ => color.premul.clamp(Img.Color{(r / divisor + bias * alpha : F32), (g / divisor + bias * alpha : F32), (b / divisor + bias * alpha : F32), alpha}))

def filter.convolution.sample(+spec: Convolution, +input: FilterInput, +p: Point, +linear: Bool) -> Img.Color:
  Convolution{kernel, divisor, bias, preserve, edge, limits} = spec
  filter.convolution.finish(filter.convolution.sum(kernel, input, limits, edge, preserve, p, linear, Img.clear()), divisor, bias, preserve, filter.input.color(input, p, linear))

def filter.op.sample(op: FilterOp, +a: FilterInput, +b: FilterInput, +p: Point, +linear: Bool) -> Img.Color:
  match op:
    case FilterCopy{}: filter.input.color(a, p, linear)
    case FilterFlood{c}: c
    case FilterOffset{delta}: filter.input.color(a, point.sub(p, delta), linear)
    case FilterMatrix{rows}: filter.matrix(rows, filter.input.color(a, p, linear))
    case FilterTransfer{r, g, b, alpha}: filter.transfer(r, g, b, alpha, filter.input.color(a, p, linear))
    case FilterComposite{kind, k1, k2, k3, k4}: filter.composite(filter.input.color(a, p, linear), filter.input.color(b, p, linear), kind, k1, k2, k3, k4)
    case FilterBlend{kind}: filter.blend(filter.input.color(a, p, linear), filter.input.color(b, p, linear), kind)
    case FilterMerge{inputs}: filter.merge(inputs, p, linear, Img.clear())
    case FilterBlur{kernel}: filter.convolve(kernel, a, p, linear, Img.clear())
    case FilterConvolution{spec}: filter.convolution.sample(spec, a, p, linear)
    case FilterMorphology{dilate, radius, direction}:
      +n = radius
      +expand = dilate
      filter.morphology.sample(U32.to_nat((n * 2 + 1 : U32)), F32.neg(U32.to_f32(n)), direction, expand, a, p, linear, U.choose(Img.Color, expand, Img.clear(), Img.Color{1.0, 1.0, 1.0, 1.0}))

type FilterWindow is Data:
  FilterWindow{region: Bounds, inverse: Matrix, exact: Bool}

def filter.region.inside(b: Bounds, p: Point) -> Bool:
  Bounds{x0, y0, x1, y1} = b
  Point{x, y} = p
  +xx = x
  +yy = y
  F32.is_ge(xx, x0) && F32.is_ge(yy, y0) && F32.is_lt(xx, x1) && F32.is_lt(yy, y1)

def filter.window.contains(region: Bounds, tile: Bounds) -> U32:
  Bounds{x0, y0, x1, y1} = region
  Bounds{a, b, c, d} = tile
  U.choose(U32, F32.is_ge(a, x0) && F32.is_ge(b, y0) && F32.is_le(c, x1) && F32.is_le(d, y1), 1, 2)

def filter.window.span(window: FilterWindow, tile: Bounds) -> U32:
  FilterWindow{region, inverse, exact} = window
  +local = bounds.transform(tile, inverse)
  +box = region
  U.choose(U32, bounds.overlap(box, local), filter.window.contains(box, local), 0)

def filter.window.inside(window: FilterWindow, p: Point) -> Bool:
  FilterWindow{region, inverse, exact} = window
  filter.region.inside(region, matrix.point(inverse, p))

def filter.window.exact(window: FilterWindow) -> Bool:
  FilterWindow{region, inverse, exact} = window
  exact

# An axis-aligned window clips a buffer pixel by its exact overlap with the region.
def filter.window.aligned(window: FilterWindow) -> Bool:
  FilterWindow{region, inverse, exact} = window
  Matrix{a, b, c, d, e, f} = inverse
  F32.is_eq(b, 0.0) && F32.is_eq(c, 0.0)

def filter.window.overlap(region: Bounds, local: Bounds) -> F32:
  Bounds{x0, y0, x1, y1} = region
  Bounds{u0, v0, u1, v1} = local
  +a0 = u0
  +b0 = v0
  +a1 = u1
  +b1 = v1
  +w = U.max(0.0, (U.min(x1, a1) - U.max(x0, a0) : F32))
  +h = U.max(0.0, (U.min(y1, b1) - U.max(y0, b0) : F32))
  (w * h / U.max(((a1 - a0) * (b1 - b0) : F32), 0.000000001) : F32)

def filter.window.area(window: FilterWindow, tile: Bounds) -> F32:
  FilterWindow{region, inverse, exact} = window
  Bounds{x0, y0, x1, y1} = tile
  +m = inverse
  filter.window.overlap(region, bounds.point(bounds.point(bounds.empty(), matrix.point(m, Point{x0, y0})), matrix.point(m, Point{x1, y1})))

def filter.window.samples(n: Nat, +i: U32, +aa: U32, +window: FilterWindow, +point: Point, +step: F32, acc: F32) -> F32:
  match n:
    case 0n: acc
    case 1n+d:
      filter.window.samples(d, U32.inc(i), aa, window, point, step,
        (acc + U.choose(F32, filter.window.inside(window, point.add(point, Point{((U32.to_f32(U32.mod(i, aa)) + 0.5) * step : F32), ((U32.to_f32(U32.div(i, aa)) + 0.5) * step : F32)})), 1.0, 0.0) : F32))

def filter.draw.pixel(+format: Raster, +x: U32, +y: U32, op: FilterOp, a: FilterInput, b: FilterInput, +window: FilterWindow, linear: Bool, +aa: U32, span: U32) -> Img.Pixels:
  +c = filter.op.sample(op, a, b, raster.position(format, (U32.to_f32(x) + 0.5 : F32), (U32.to_f32(y) + 0.5 : F32)), linear)
  # Intermediate offscreens include each pixel intersecting the hard clipping
  # region; the final filter region clips by the pixel's covered fraction.
  +covered = U.branch(F32, filter.window.exact(window) && filter.window.aligned(window), _ => filter.window.area(window, raster.tile.box(format, x, y, 1)),
    _ => (filter.window.samples(U32.to_nat((aa * aa : U32)), 0, aa, window, raster.position(format, U32.to_f32(x), U32.to_f32(y)), (raster.scale(format) / U32.to_f32(aa) : F32), 0.0) / U32.to_f32((aa * aa : U32)) : F32))
  Img.Flat{U.branch(Img.Color, U32.is_eq(span, 1), _ => c,
    _ => U.choose(Img.Color, filter.window.exact(window), color.fade(c, covered), U.choose(Img.Color, F32.is_gt(covered, 0.0), c, Img.clear())))}

def filter.draw.tiles(depth: Nat, +x: U32, +y: U32, +format: Raster, +op: FilterOp, +a: FilterInput, +b: FilterInput, +window: FilterWindow, +linear: Bool, +aa: U32) -> Img.Pixels:
  match depth:
    case 0n:
      +span = filter.window.span(window, raster.tile.box(format, x, y, 1))
      U.branch(Img.Pixels, raster.in.frame(format, x, y) && Bool.not(U32.is_eq(span, 0)),
        _ => filter.draw.pixel(format, x, y, op, a, b, window, linear, aa, span), _ => Img.Flat{Img.clear()})
    case 1n+d:
      +dd = d
      +half = U32.shln(1, dd)
      +span = filter.window.span(window, raster.tile.box(format, x, y, (half * 2 : U32)))
      U.branch(Img.Pixels, raster.in.frame(format, x, y) && Bool.not(U32.is_eq(span, 0)),
        _ => Img.pixels.join(filter.draw.tiles(dd, x, y, format, op, a, b, window, linear, aa), filter.draw.tiles(dd, (x + half : U32), y, format, op, a, b, window, linear, aa), filter.draw.tiles(dd, x, (y + half : U32), format, op, a, b, window, linear, aa), filter.draw.tiles(dd, (x + half : U32), (y + half : U32), format, op, a, b, window, linear, aa)), _ => Img.Flat{Img.clear()})

def filter.draw(+format: Raster, op: FilterOp, a: FilterInput, b: FilterInput, window: FilterWindow, +linear: Bool, aa: U32) -> Raster:
  Raster{origin, step, width, height, depth, pixelsLinear, pixels} = format
  raster.store(format, filter.draw.tiles(depth, 0, 0, format, op, a, b, window, linear, aa), linear)

def filter.kernel.raw(n: Nat, +i: F32, +radius: F32, +sigma: F32, +direction: Point) -> List<&2, FilterTap>:
  match n:
    case 0n: Nil{}
    case 1n+d:
      +x = (i - radius : F32)
      Con{FilterTap{point.scale(direction, x), F32.exp((F32.neg(0.5) * x * x / (sigma * sigma) : F32))}, filter.kernel.raw(d, (i + 1.0 : F32), radius, sigma, direction)}

def filter.kernel.sum(xs: List<&2, FilterTap>) -> F32:
  match xs:
    case Nil{}: 0.0
    case Con{FilterTap{delta, weight}, rest}: (weight + filter.kernel.sum(rest) : F32)

def filter.kernel.normalize(xs: List<&2, FilterTap>, +total: F32) -> List<&2, FilterTap>:
  match xs:
    case Nil{}: Nil{}
    case Con{FilterTap{delta, weight}, rest}: Con{FilterTap{delta, (weight / total : F32)}, filter.kernel.normalize(rest, total)}

def filter.kernel(+vector: Point, +step: F32) -> List<&2, FilterTap>:
  +sigma = point.distance(vector, Point{0.0, 0.0})
  +radius = U.min(512.0, F32.ceil((3.0 * sigma / step : F32)))
  +spacing = U.max(step, (3.0 * sigma / U.max(radius, 1.0) : F32))
  +kernel = filter.kernel.raw(U32.to_nat(F32.to_u32((radius * 2.0 + 1.0 : F32))), 0.0, radius, (U.max(sigma, 0.000001) / spacing : F32), point.scale(vector, (spacing / U.max(sigma, 0.000001) : F32)))
  U.branch(List<&2, FilterTap>, F32.is_lt(sigma, 0.000001), _ => Con{FilterTap{Point{0.0, 0.0}, 1.0}, Nil{}}, _ => filter.kernel.normalize(kernel, filter.kernel.sum(kernel)))

# Filter inputs form an ordered graph. Results only see preceding primitives.
type FilterResult is Data:
  FilterResult{name: String, input: FilterInput}

def filter.result(xs: List<&2, FilterResult>, +name: String, +fallback: FilterInput) -> FilterInput:
  match xs:
    case Nil{}: fallback
    case Con{FilterResult{key, input}, rest}:
      U.branch(FilterInput, String.eq(key, name), _ => input, _ => filter.result(rest, name, fallback))

def filter.input.alpha(input: FilterInput) -> FilterInput:
  FilterInput{raster, region, alpha, standard} = input
  FilterInput{raster, region, True{}, standard}

def filter.resolve(+name: String, +source: FilterInput, previous: FilterInput, results: List<&2, FilterResult>) -> FilterInput:
  U.branch(FilterInput, String.eq(name, "SourceGraphic"), _ => source,
    _ => U.branch(FilterInput, String.eq(name, "SourceAlpha"), _ => filter.input.alpha(source), _ => filter.result(results, name, previous)))

def filter.input.region(input: FilterInput) -> Bounds:
  FilterInput{raster, region, alpha, standard} = input
  region

def filter.merge.inputs(+xs: List<&2, XML.Element>, +source: FilterInput, +previous: FilterInput, +results: List<&2, FilterResult>) -> List<&2, FilterInput>:
  match xs:
    case Nil{}: Nil{}
    case Con{XML.Element{name, as, kids, txt}, rest}:
      U.branch(List<&2, FilterInput>, String.eq(name, "feMergeNode"), _ => Con{filter.resolve(XML.attr.get(as, "in", ""), source, previous, results), filter.merge.inputs(rest, source, previous, results)}, _ => filter.merge.inputs(rest, source, previous, results))

def filter.inputs.region(xs: List<&2, FilterInput>, box: Bounds) -> Bounds:
  match xs:
    case Nil{}: box
    case Con{h, t}: filter.inputs.region(t, bounds.merge(box, filter.input.region(h)))

def bounds.intersection(a: Bounds, b: Bounds) -> Bounds:
  Bounds{x0, y0, x1, y1} = a
  Bounds{u0, v0, u1, v1} = b
  Bounds{U.max(x0, u0), U.max(y0, v0), U.min(x1, u1), U.min(y1, v1)}

def filter.subregion(+as: List<&2, XML.Attr>, box: Bounds, viewport: Point) -> Bounds:
  Bounds{x0, y0, x1, y1} = box
  Point{vw, vh} = viewport
  +w = vw
  +h = vh
  +left = x0
  +top = y0
  +x = U.branch(F32, Bool.not(String.eq(XML.attr.get(as, "x", ""), "")), _ => dimension(as, "x", w, "0"), _ => left)
  +y = U.branch(F32, Bool.not(String.eq(XML.attr.get(as, "y", ""), "")), _ => dimension(as, "y", h, "0"), _ => top)
  Bounds{x, y, (x + U.branch(F32, Bool.not(String.eq(XML.attr.get(as, "width", ""), "")), _ => dimension(as, "width", w, "0"), _ => (x1 - left : F32)) : F32), (y + U.branch(F32, Bool.not(String.eq(XML.attr.get(as, "height", ""), "")), _ => dimension(as, "height", h, "0"), _ => (y1 - top : F32)) : F32)}

def matrix.vector(+m: Matrix, p: Point) -> Point:
  point.sub(matrix.point(m, p), matrix.point(m, Point{0.0, 0.0}))

def filter.offset(+as: List<&2, XML.Attr>, viewport: Point) -> Point:
  Point{w, h} = viewport
  Point{dimension(as, "dx", w, "0"), dimension(as, "dy", h, "0")}

def filter.operator(+name: String) -> U32:
  U.choose(U32, String.eq(name, "in"), 1, U.choose(U32, String.eq(name, "out"), 2, U.choose(U32, String.eq(name, "atop"), 3, U.choose(U32, String.eq(name, "xor"), 4, U.choose(U32, String.eq(name, "arithmetic"), 5, 0)))))

def filter.blend.mode(+name: String) -> U32:
  U.choose(U32, String.eq(name, "multiply"), 1, U.choose(U32, String.eq(name, "screen"), 2, U.choose(U32, String.eq(name, "darken"), 3, U.choose(U32, String.eq(name, "lighten"), 4, U.choose(U32, String.eq(name, "overlay"), 5, U.choose(U32, String.eq(name, "color-dodge"), 6, U.choose(U32, String.eq(name, "color-burn"), 7, U.choose(U32, String.eq(name, "hard-light"), 8, U.choose(U32, String.eq(name, "soft-light"), 9, U.choose(U32, String.eq(name, "difference"), 10, U.choose(U32, String.eq(name, "exclusion"), 11, U.choose(U32, String.eq(name, "hue"), 12, U.choose(U32, String.eq(name, "saturation"), 13, U.choose(U32, String.eq(name, "color"), 14, U.choose(U32, String.eq(name, "luminosity"), 15, 0)))))))))))))))

def filter.flood(+as: List<&2, XML.Attr>) -> Img.Color:
  +ink = XML.attr.get(as, "flood-color", "black")
  color.fade(color(U.choose(String, String.eq(CSS.css.lower(ink), "currentcolor"), XML.attr.get(as, "color", "black"), ink)), color.opacity(XML.attr.get(as, "flood-opacity", "1"), 1.0))

def filter.op.parse(+name: String, +as: List<&2, XML.Attr>, +kids: List<&2, XML.Element>, units: Matrix, viewport: Point, merges: List<&2, FilterInput>) -> FilterOp:
  U.branch(FilterOp, String.eq(name, "feFlood"), _ => FilterFlood{filter.flood(as)},
    _ => U.branch(FilterOp, String.eq(name, "feOffset"), _ => FilterOffset{matrix.vector(units, filter.offset(as, viewport))},
      _ => U.branch(FilterOp, String.eq(name, "feColorMatrix"), _ => FilterMatrix{filter.matrix.parse(as)},
        _ => U.branch(FilterOp, String.eq(name, "feComponentTransfer"), _ => FilterTransfer{transfer.find(kids, "feFuncR"), transfer.find(kids, "feFuncG"), transfer.find(kids, "feFuncB"), transfer.find(kids, "feFuncA")},
          _ => U.branch(FilterOp, String.eq(name, "feComposite"), _ => FilterComposite{filter.operator(XML.attr.get(as, "operator", "over")), U.scalar(XML.attr.get(as, "k1", "0"), 0.0), U.scalar(XML.attr.get(as, "k2", "0"), 0.0), U.scalar(XML.attr.get(as, "k3", "0"), 0.0), U.scalar(XML.attr.get(as, "k4", "0"), 0.0)},
            _ => U.branch(FilterOp, String.eq(name, "feBlend"), _ => FilterBlend{filter.blend.mode(XML.attr.get(as, "mode", "normal"))},
              _ => U.branch(FilterOp, String.eq(name, "feMerge"), _ => FilterMerge{merges}, _ => FilterCopy{})))))))

def filter.blur(+as: List<&2, XML.Attr>, +format: Raster, +input: FilterInput, +units: Matrix, window: FilterWindow, +linear: Bool, +aa: U32) -> Raster:
  +vs = U.numbers(XML.attr.get(as, "stdDeviation", "0"))
  +sx = U.nth(vs, 0n, 0.0)
  +sy = U.nth(vs, 1n, sx)
  +region = filter.input.region(input)
  +first = {FilterInput{filter.draw(format, FilterBlur{filter.kernel(matrix.vector(units, Point{U.max(sx, 0.0), 0.0}), raster.scale(format))}, input, input, FilterWindow{Bounds{F32.neg(1.0e30), F32.neg(1.0e30), 1.0e30, 1.0e30}, identity(), False{}}, linear, aa), region, False{}, False{}} : FilterInput}
  U.branch(Raster, F32.is_lt(sx, 0.0) || F32.is_lt(sy, 0.0), _ => raster.store(format, Img.Flat{Img.clear()}, linear),
    _ => filter.draw(format, FilterBlur{filter.kernel(matrix.vector(units, Point{0.0, sy}), raster.scale(format))}, first, first, window, linear, aa))

# Rectangular min/max is separable along the transformed primitive axes.
# A radius beyond the finite buffer diagonal only visits transparent samples.
def filter.morphology.axis(+vector: Point, +step: F32, dilate: Bool) -> FilterOp:
  +length = point.distance(vector, Point{0.0, 0.0})
  +radius = F32.to_u32(U.clamp(F32.floor((length / step + 0.5 : F32)), 0.0, 2048.0))
  FilterMorphology{dilate, radius, point.scale(vector, (step / U.max(length, 0.000001) : F32))}

def filter.morphology(+as: List<&2, XML.Attr>, +format: Raster, +input: FilterInput, +units: Matrix, window: FilterWindow, +linear: Bool, +aa: U32) -> Raster:
  +values = U.numbers(XML.attr.get(as, "radius", "0"))
  +rx = U.max(U.nth(values, 0n, 0.0), 0.0)
  +ry = U.max(U.nth(values, 1n, U.nth(values, 0n, 0.0)), 0.0)
  +dilate = String.eq(XML.attr.get(as, "operator", "erode"), "dilate")
  +region = filter.input.region(input)
  +first = {FilterInput{filter.draw(format, filter.morphology.axis(matrix.vector(units, Point{rx, 0.0}), raster.scale(format), dilate), input, input, FilterWindow{Bounds{F32.neg(1.0e30), F32.neg(1.0e30), 1.0e30, 1.0e30}, identity(), False{}}, linear, aa), region, False{}, False{}} : FilterInput}
  filter.draw(format, filter.morphology.axis(matrix.vector(units, Point{0.0, ry}), raster.scale(format), dilate), first, first, window, linear, aa)

def filter.shadow(+attrs: List<&2, XML.Attr>, +format: Raster, +input: FilterInput, +units: Matrix, +viewport: Point, +window: FilterWindow, +linear: Bool, +aa: U32) -> Raster:
  +as = {Con{XML.Attr{"stdDeviation", XML.attr.get(attrs, "stdDeviation", "2")}, Con{XML.Attr{"dx", XML.attr.get(attrs, "dx", "2")}, Con{XML.Attr{"dy", XML.attr.get(attrs, "dy", "2")}, attrs}}} : List<&2, XML.Attr>}
  +region = filter.input.region(input)
  +blur = {FilterInput{filter.blur(as, format, filter.input.alpha(input), units, window, linear, aa), region, False{}, False{}} : FilterInput}
  +offset = {FilterInput{filter.draw(format, FilterOffset{matrix.vector(units, filter.offset(as, viewport))}, blur, blur, window, linear, aa), region, False{}, False{}} : FilterInput}
  +flood = {FilterInput{filter.draw(format, FilterFlood{color.space(filter.flood(as), linear)}, input, input, window, linear, aa), region, False{}, False{}} : FilterInput}
  +shade = {FilterInput{filter.draw(format, FilterComposite{1, 0.0, 0.0, 0.0, 0.0}, flood, offset, window, linear, aa), region, False{}, False{}} : FilterInput}
  filter.draw(format, FilterMerge{Con{shade, Con{input, Nil{}}}}, input, input, window, linear, aa)

# The row-major kernel is rotated 180 degrees; target offsets refer to input cells.
def filter.convolution.taps(+xs: List<&2, F32>, +index: U32, +width: U32, +height: U32, +tx: F32, +ty: F32, +dx: Point, +dy: Point) -> List<&2, FilterTap>:
  match xs:
    case Nil{}: Nil{}
    case Con{weight, rest}:
      +x = (U32.to_f32((width - 1 - U32.mod(index, width) : U32)) - tx : F32)
      +y = (U32.to_f32((height - 1 - U32.div(index, width) : U32)) - ty : F32)
      U.branch(List<&2, FilterTap>, F32.is_eq(weight, 0.0), _ => filter.convolution.taps(rest, U32.inc(index), width, height, tx, ty, dx, dy),
        _ => Con{FilterTap{point.add(point.scale(dx, x), point.scale(dy, y)), weight}, filter.convolution.taps(rest, U32.inc(index), width, height, tx, ty, dx, dy)})

def filter.convolution.limits.box(+raster: Raster, box: Bounds) -> Bounds:
  Raster{Point{ox, oy}, step, width, height, depth, stored, pixels} = raster
  Bounds{x0, y0, x1, y1} = box
  Bounds{U.max(0.0, F32.floor(((x0 - ox) / step : F32))), U.max(0.0, F32.floor(((y0 - oy) / step : F32))), U.min(U32.to_f32(width), F32.ceil(((x1 - ox) / step : F32))), U.min(U32.to_f32(height), F32.ceil(((y1 - oy) / step : F32)))}

# Resource domains need exact edges; geometric coverage bounds include a tolerance.
def filter.convolution.bounds(box: Bounds, +units: Matrix) -> Bounds:
  Bounds{x0, y0, x1, y1} = box
  +left = x0
  +top = y0
  +right = x1
  +bottom = y1
  bounds.point(bounds.point(bounds.point(bounds.point(bounds.empty(), matrix.point(units, Point{left, top})), matrix.point(units, Point{right, top})), matrix.point(units, Point{left, bottom})), matrix.point(units, Point{right, bottom}))

def filter.convolution.limits(input: FilterInput, units: Matrix) -> Bounds:
  FilterInput{raster, region, alpha, standard} = input
  filter.convolution.limits.box(raster, filter.convolution.bounds(region, units))

def filter.convolution.parse(+as: List<&2, XML.Attr>, +units: Matrix, +input: FilterInput, +format: Raster) -> FilterOp:
  +order = U.numbers(XML.attr.get(as, "order", "3"))
  +ox = F32.floor(U.nth(order, 0n, 3.0))
  +oy = F32.floor(U.nth(order, 1n, U.nth(order, 0n, 3.0)))
  +width = F32.to_u32(U.clamp(ox, 1.0, 4096.0))
  +height = F32.to_u32(U.clamp(oy, 1.0, 4096.0))
  +tx = F32.floor(U.scalar(XML.attr.get(as, "targetX", ""), F32.floor((ox * 0.5 : F32))))
  +ty = F32.floor(U.scalar(XML.attr.get(as, "targetY", ""), F32.floor((oy * 0.5 : F32))))
  +vs = U.numbers(XML.attr.get(as, "kernelMatrix", ""))
  +sum = floats.sum(vs)
  +defaultDivisor = U.choose(F32, F32.is_eq(sum, 0.0), 1.0, sum)
  +divisor = U.scalar(XML.attr.get(as, "divisor", ""), defaultDivisor)
  +lengths = U.numbers(XML.attr.get(as, "kernelUnitLength", ""))
  +ux = U.nth(lengths, 0n, 0.0)
  +uy = U.nth(lengths, 1n, ux)
  +explicit = F32.is_gt(ux, 0.0) && F32.is_gt(uy, 0.0)
  +step = raster.scale(format)
  +dx = U.choose(Point, explicit, matrix.vector(units, Point{ux, 0.0}), Point{step, 0.0})
  +dy = U.choose(Point, explicit, matrix.vector(units, Point{0.0, uy}), Point{0.0, step})
  +edge = XML.attr.get(as, "edgeMode", "duplicate")
  +valid = F32.is_ge(ox, 1.0) && F32.is_ge(oy, 1.0) && F32.is_le(ox, 4096.0) && F32.is_le(oy, 4096.0) && F32.is_le((ox * oy : F32), 4096.0) && U32.is_eq(floats.count(vs), (width * height : U32)) && F32.is_ge(tx, 0.0) && F32.is_lt(tx, ox) && F32.is_ge(ty, 0.0) && F32.is_lt(ty, oy)
  U.branch(FilterOp, valid, _ => FilterConvolution{Convolution{filter.convolution.taps(vs, 0, width, height, tx, ty, dx, dy), U.choose(F32, F32.is_eq(divisor, 0.0), defaultDivisor, divisor), U.scalar(XML.attr.get(as, "bias", "0"), 0.0), String.eq(XML.attr.get(as, "preserveAlpha", "false"), "true"), U.choose(U32, String.eq(edge, "wrap"), 1, U.choose(U32, String.eq(edge, "none"), 2, 0)), filter.convolution.limits(input, units)}}, _ => FilterCopy{})

def filter.primitive(+name: String, +as: List<&2, XML.Attr>, +kids: List<&2, XML.Element>, +format: Raster, +source: FilterInput, +previous: FilterInput, +results: List<&2, FilterResult>, +region: Bounds, +units: Matrix, +viewport: Point, +aa: U32) -> FilterInput:
  +a = filter.resolve(XML.attr.get(as, "in", ""), source, previous, results)
  +b = filter.resolve(XML.attr.get(as, "in2", ""), source, previous, results)
  +merges = filter.merge.inputs(kids, source, previous, results)
  +two = String.eq(name, "feComposite") || String.eq(name, "feBlend")
  +defaultBox = U.branch(Bounds, String.eq(name, "feFlood"), _ => region,
    _ => U.branch(Bounds, String.eq(name, "feMerge"), _ => filter.inputs.region(merges, bounds.empty()), _ => U.choose(Bounds, two, bounds.merge(filter.input.region(a), filter.input.region(b)), filter.input.region(a))))
  +box = bounds.intersection(region, filter.subregion(as, defaultBox, viewport))
  +window = {FilterWindow{box, matrix.inverse(units), False{}} : FilterWindow}
  +linear = U.branch(Bool, String.eq(name, "feFlood"), _ => False{}, _ => U.branch(Bool, String.eq(name, "feOffset"), _ => raster.is.linear(filter.input.raster(a)), _ => Bool.not(String.eq(XML.attr.get(as, "color-interpolation-filters", "linearRGB"), "sRGB"))))
  FilterInput{U.branch(Raster, String.eq(name, "feGaussianBlur"), _ => filter.blur(as, format, a, units, window, linear, aa), _ => U.branch(Raster, String.eq(name, "feDropShadow"), _ => filter.shadow(as, format, a, units, viewport, window, linear, aa), _ => U.branch(Raster, String.eq(name, "feMorphology"), _ => filter.morphology(as, format, a, units, window, linear, aa), _ => filter.draw(format, U.branch(FilterOp, String.eq(name, "feConvolveMatrix"), _ => filter.convolution.parse(as, units, a, format), _ => filter.op.parse(name, as, kids, units, viewport, merges)), a, b, window, linear, aa)))), box, False{}, False{}}

@unsafe
def filter.chain(+xs: List<&2, XML.Element>, +format: Raster, +source: FilterInput, +previous: FilterInput, +results: List<&2, FilterResult>, +region: Bounds, +units: Matrix, +viewport: Point, +aa: U32) -> FilterInput:
  match xs:
    case Nil{}: previous
    case Con{XML.Element{name, attrs, kids, txt}, rest}:
      +as = CSS.properties(attrs)
      +next = filter.primitive(name, as, kids, format, source, previous, results, region, units, viewport, aa)
      U.branch(FilterInput, U.prefix(name, "fe"), _ => filter.chain(rest, format, source, next, Con{FilterResult{XML.attr.get(as, "result", ""), next}, results}, region, units, viewport, aa), _ => filter.chain(rest, format, source, previous, results, region, units, viewport, aa))

def filter.padding(+xs: List<&2, XML.Element>, +units: Matrix, +margin: F32) -> F32:
  match xs:
    case Nil{}: margin
    case Con{XML.Element{name, as, kids, txt}, rest}:
      +vs = U.numbers(XML.attr.get(as, "stdDeviation", U.choose(String, String.eq(name, "feDropShadow"), "2", "0")))
      +sx = U.nth(vs, 0n, 0.0)
      +sy = U.nth(vs, 1n, sx)
      +pad = (3.0 * (point.distance(matrix.vector(units, Point{sx, 0.0}), Point{0.0, 0.0}) + point.distance(matrix.vector(units, Point{0.0, sy}), Point{0.0, 0.0})) : F32)
      +radii = U.numbers(XML.attr.get(as, "radius", "0"))
      +rx = U.max(U.nth(radii, 0n, 0.0), 0.0)
      +ry = U.max(U.nth(radii, 1n, U.nth(radii, 0n, 0.0)), 0.0)
      +morphPad = (point.distance(matrix.vector(units, Point{rx, 0.0}), Point{0.0, 0.0}) + point.distance(matrix.vector(units, Point{0.0, ry}), Point{0.0, 0.0}) + 2.0 : F32)
      filter.padding(rest, units, U.choose(F32, String.eq(name, "feGaussianBlur") || String.eq(name, "feDropShadow"), U.max(margin, pad), U.choose(F32, String.eq(name, "feMorphology"), U.max(margin, morphPad), margin)))

def filter.present(xs: List<&2, XML.Element>) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{XML.Element{name, as, kids, txt}, rest}: U.prefix(name, "fe") || filter.present(rest)

def filter.density(+m: Matrix) -> F32:
  Matrix{a, b, c, d, e, f} = m
  +x = (a * a + b * b : F32)
  +y = (c * c + d * d : F32)
  +dot = (a * c + b * d : F32)
  # Largest singular value keeps transformed pattern buffers at device density.
  F32.sqrt(((x + y + F32.sqrt(((x - y) * (x - y) + 4.0 * dot * dot : F32))) * 0.5 : F32))

def filter.source(scene: Scene<Brush>) -> Scene<Brush>:
  Scene{es, box, inv, style, opacity, kids, id, ink, clip, outline, fillTree, masks, maskMode, markers, coverage, effect} = scene
  Scene{es, box, inv, style, 1.0, kids, id, ink, ClipAll{}, outline, fillTree, Nil{}, 0, markers, coverage, NoFilter{}}

def filter.render(+scene: Scene<Brush>, +region: Bounds, +units: Matrix, +viewport: Point, +primitives: List<&2, XML.Element>, space: Matrix, +aa: U32) -> Raster:
  +world = bounds.transform(region, units)
  +area = bounds.expand(bounds.merge(world, scene.coverage(Con{scene, Nil{}}, bounds.empty())), filter.padding(primitives, units, 0.0))
  +format = raster.format(area, (1.0 / U.max(filter.density(space), 0.000001) : F32))
  +raw = {FilterInput{raster.scene(format, Con{filter.source(scene), Nil{}}, aa), region, False{}, True{}} : FilterInput}
  +source = {FilterInput{filter.draw(format, FilterCopy{}, raw, raw, FilterWindow{region, matrix.inverse(units), False{}}, False{}, aa), region, False{}, True{}} : FilterInput}
  +result = filter.chain(primitives, format, source, source, Nil{}, region, units, viewport, aa)
  U.branch(Raster, bounds.nonempty(region) && filter.present(primitives),
    _ => filter.draw(format, FilterCopy{}, result, result, FilterWindow{region, matrix.inverse(units), True{}}, raster.is.linear(filter.input.raster(result)), aa), _ => raster.empty())

def filter.cache(scene: Scene<Brush>, raster: Raster, area: Bounds) -> Scene<Brush>:
  Scene{es, box, inv, style, opacity, kids, id, ink, clip, outline, fillTree, masks, maskMode, markers, coverage, effect} = scene
  Scene{es, box, inv, style, opacity, kids, id, ink, clip, outline, fillTree, masks, maskMode, markers, area, FilterImage{raster}}

def prepare.effect(effect: FilterEffect, +scene: Scene<Brush>, space: Matrix, aa: U32) -> Scene<Brush>:
  match effect:
    case NoFilter{}: scene
    case FilterImage{raster}: scene
    case FilterSpec{region, units, viewport, attrs, primitives}:
      +box = region
      +mat = units
      +buffer = filter.render(scene, box, mat, viewport, primitives, space, aa)
      filter.cache(scene, buffer, bounds.expand(bounds.transform(box, mat), raster.scale(buffer)))

def prepare.brush(brush: Brush, +space: Matrix, next: List<&2, Scene<Brush>> -> Matrix -> List<&2, Scene<Brush>>) -> Brush:
  match brush:
    case Bitmap{raster, inv, nearest}: Bitmap{raster, inv, nearest}
    case Solid{c, source}: Solid{c, source}
    case PendingContext{stroke, opacity}: PendingContext{stroke, opacity}
    case ContextPaint{source, mat, opacity}:
      +matrix = mat
      ContextPaint{prepare.brush(source, matrix.mul(space, matrix.inverse(matrix)), next), matrix, opacity}
    case Pattern{inv, width, height, opacity, nodes}:
      +matrix = inv
      Pattern{matrix, width, height, opacity, next(nodes)(matrix.mul(space, matrix.inverse(matrix)))}
    case Tile{raster, inv, width, height, opacity, u, v, grid}: Tile{raster, inv, width, height, opacity, u, v, grid}
    case Gradient{inv, radial, start, end, radius, focal, stops, spread, opacity, linear}: Gradient{inv, radial, start, end, radius, focal, stops, spread, opacity, linear}

def prepare.paint(ink: Paint<Brush>, +space: Matrix, fills: List<&2, Scene<Brush>> -> Matrix -> List<&2, Scene<Brush>>, strokes: List<&2, Scene<Brush>> -> Matrix -> List<&2, Scene<Brush>>) -> Paint<Brush>:
  Paint{fill, stroke} = ink
  Paint{prepare.brush(fill, space, fills), prepare.brush(stroke, space, strokes)}

@unsafe
def prepare.scenes(+xs: List<&2, Scene<Brush>>, +space: Matrix, +aa: U32) -> List<&2, Scene<Brush>>:
  match xs:
    case Nil{}: Nil{}
    case Con{Scene{es, box, inv, style, opacity, kids, id, ink, clip, outline, fillTree, masks, maskMode, markers, coverage, effect}, rest}:
      +node = scene.covered(Scene{es, box, inv, style, opacity, prepare.scenes(kids, space, aa), id, prepare.paint(ink, matrix.mul(space, matrix.inverse(inv)), nodes => mat => prepare.scenes(nodes, mat, aa), nodes => mat => prepare.scenes(nodes, mat, aa)), clip, outline, fillTree, prepare.scenes(masks, space, aa), maskMode, prepare.scenes(markers, space, aa), coverage, effect})
      Con{prepare.effect(effect, node, space, aa), prepare.scenes(rest, space, aa)}

# Portable image export for headless rendering and reference comparisons.
def pixel.ppm(c: U32) -> String:
  +rgb = c
  U32.show((rgb / 65536 % 256 : U32)) ++ " " ++ U32.show((rgb / 256 % 256 : U32))
    ++ " " ++ U32.show((rgb % 256 : U32)) ++ "\n"

# ---- painter ----
# Nodes are painted back to front into a flat RGBA layer (four F32 lanes per
# pixel) straight from their coverage masks: a mask leaf that spans a block
# paints that block with one coverage value, so a uniform interior costs one
# blend per pixel and nothing else, and a solid brush is sampled once per shape.
# Nodes with opacity, a mask or a rendered filter are painted into a layer of
# their own and composited; enclosing clips travel down as the coverage limit
# the per-pixel sampler also uses, so both paths agree.

def frame(+w: U32, +h: U32) -> Raster:
  Raster{Point{0.0, 0.0}, 1.0, w, h, raster.depth(U.choose(U32, U32.is_gt(w, h), w, h), 1, 0n), False{}, Img.Flat{Img.clear()}}

def layer.new(+w: U32, +h: U32) -> Array<F32>:
  Array.new(F32, raster.depth((w * h * 4 : U32), 1, 0n), 0.0)

def layer.color.a(got: Array<F32> & F32, +r: F32, +g: F32, +b: F32) -> Array<F32> & Img.Color:
  (a, al) = got
  (a, Img.Color{r, g, b, al})

def layer.color.b(got: Array<F32> & F32, +i: U32, +r: F32, +g: F32) -> Array<F32> & Img.Color:
  (a, bl) = got
  layer.color.a(Array.get(F32, a, (i + 3 : U32)), r, g, bl)

def layer.color.g(got: Array<F32> & F32, +i: U32, +r: F32) -> Array<F32> & Img.Color:
  (a, gr) = got
  layer.color.b(Array.get(F32, a, (i + 2 : U32)), i, r, gr)

def layer.color.r(got: Array<F32> & F32, +i: U32) -> Array<F32> & Img.Color:
  (a, r) = got
  layer.color.g(Array.get(F32, a, (i + 1 : U32)), i, r)

# The premultiplied color whose lanes start at i.
def layer.color(a: Array<F32>, +i: U32) -> Array<F32> & Img.Color:
  layer.color.r(Array.get(F32, a, i), i)

def layer.put(a: Array<F32>, +i: U32, c: Img.Color) -> Array<F32>:
  Img.Color{r, g, b, al} = c
  Array.set(F32, Array.set(F32, Array.set(F32, Array.set(F32, a, i, r), (i + 1 : U32), g), (i + 2 : U32), b), (i + 3 : U32), al)

def layer.over.got(got: Array<F32> & Img.Color, +i: U32, front: Img.Color) -> Array<F32>:
  (a, back) = got
  layer.put(a, i, color.over(front, back))

# Composite front over the pixel whose lanes start at i.
def layer.over(a: Array<F32>, +i: U32, front: Img.Color) -> Array<F32>:
  layer.over.got(layer.color(a, i), i, front)

def paint.with(cond: Bool, a: Array<F32>, yes: Array<F32> -> Array<F32>, no: Array<F32> -> Array<F32>) -> Array<F32>:
  match cond:
    case True{}: yes(a)
    case False{}: no(a)

# What one shape's pixels need: the brush (a solid color is sampled once), the
# device-to-local matrix, the color space and the enclosing clips.
type PaintCtx is Data:
  PaintCtx{brush: Brush, inverse: Matrix, linear: Bool, clips: List<&2, Clip>, solid: Bool, color: Img.Color}

def paint.solid(+brush: Brush) -> Bool:
  match brush:
    case Solid{c, source}: True{}
    case _: False{}

def paint.solid.color(+brush: Brush, +linear: Bool) -> Img.Color:
  match brush:
    case Solid{c, source}: color.space(c, linear)
    case _: Img.clear()

def paint.context(+brush: Brush, +inv: Matrix, +linear: Bool, +clips: List<&2, Clip>) -> PaintCtx:
  PaintCtx{brush, inv, linear, clips, paint.solid(brush), paint.solid.color(brush, linear)}

def paint.clips.of(+ctx: PaintCtx) -> List<&2, Clip>:
  PaintCtx{br, inv, linear, clips, solid, tint} = ctx
  clips

# The least coverage the enclosing clips leave at p.
def paint.limit(clips: List<&2, Clip>, +p: Point, +acc: F32) -> F32:
  match clips:
    case Nil{}: acc
    case Con{c, rest}: paint.limit(rest, p, U.min(acc, clip.cover(c, p)))

def paint.sample(+ctx: PaintCtx, +p: Point) -> Img.Color:
  PaintCtx{br, inv, linear, clips, solid, tint} = ctx
  U.branch(Img.Color, solid, _ => tint, _ => color.space(brush.sample(br, matrix.point(inv, p), matrix.point(inv, p), nodes => q => center => Img.clear()), linear))

def paint.pixel(fb: Array<F32>, +x: U32, +y: U32, +v: F32, +w: U32, +ctx: PaintCtx) -> Array<F32>:
  +p = {Point{(U32.to_f32(x) + 0.5 : F32), (U32.to_f32(y) + 0.5 : F32)} : Point}
  +c = U.min(v, paint.limit(paint.clips.of(ctx), p, 1.0))
  layer.over(fb, ((y * w + x) * 4 : U32), color.fade(paint.sample(ctx, p), c))

@unsafe
def paint.row(fb: Array<F32>, n: Nat, +x: U32, +y: U32, +v: F32, +w: U32, +ctx: PaintCtx) -> Array<F32>:
  match n:
    case 0n: fb
    case 1n+d: paint.row(paint.pixel(fb, x, y, v, w, ctx), d, (x + 1 : U32), y, v, w, ctx)

@unsafe
def paint.rows(fb: Array<F32>, n: Nat, +x0: U32, +y: U32, +cols: Nat, +v: F32, +w: U32, +ctx: PaintCtx) -> Array<F32>:
  match n:
    case 0n: fb
    case 1n+d: paint.rows(paint.row(fb, cols, x0, y, v, w, ctx), d, x0, (y + 1 : U32), cols, v, w, ctx)

def paint.span(+at: U32, +size: U32, +limit: U32) -> U32:
  U.choose(U32, U32.is_ge(at, limit), 0, U.choose(U32, U32.is_le((at + size : U32), limit), size, (limit - at : U32)))

# One uniform block of a mask, clipped to the frame.
def paint.block(fb: Array<F32>, +x0: U32, +y0: U32, +size: U32, +v: F32, +w: U32, +h: U32, +ctx: PaintCtx) -> Array<F32>:
  paint.rows(fb, U32.to_nat(paint.span(y0, size, h)), x0, y0, U32.to_nat(paint.span(x0, size, w)), v, w, ctx)

def paint.block.if(cond: Bool, fb: Array<F32>, +x0: U32, +y0: U32, +size: U32, +v: F32, +w: U32, +h: U32, +ctx: PaintCtx) -> Array<F32>:
  match cond:
    case True{}: paint.block(fb, x0, y0, size, v, w, h, ctx)
    case False{}: fb

@unsafe
def paint.tree(fb: Array<F32>, t: Cov.CovTree, +x0: U32, +y0: U32, +size: U32, +w: U32, +h: U32, +ctx: PaintCtx) -> Array<F32>:
  match t:
    case Cov.CovFlat{v}:
      +vv = v
      paint.block.if(F32.is_gt(vv, 0.0), fb, x0, y0, size, vv, w, h, ctx)
    case Cov.CovQuad{a, b, c, d}:
      +half = U32.div(size, 2)
      paint.tree(paint.tree(paint.tree(paint.tree(fb, a, x0, y0, half, w, h, ctx), b, (x0 + half : U32), y0, half, w, h, ctx), c, x0, (y0 + half : U32), half, w, h, ctx), d, (x0 + half : U32), (y0 + half : U32), half, w, h, ctx)

def paint.tree.if(cond: Bool, fb: Array<F32>, t: Cov.CovTree, +x0: U32, +y0: U32, +size: U32, +w: U32, +h: U32, +ctx: PaintCtx) -> Array<F32>:
  match cond:
    case True{}: paint.tree(fb, t, x0, y0, size, w, h, ctx)
    case False{}: fb

# A shape's coverage mask on the frame grid, painted with its brush.
def paint.cover(fb: Array<F32>, +cov: Cover, +w: U32, +h: U32, +ctx: PaintCtx) -> Array<F32>:
  Cover{Cov.CovMask{gx, gy, size, depth, tree, present}, origin, step} = cov
  paint.tree.if(present, fb, tree, gx, gy, size, w, h, ctx)

def paint.fill.if(cond: Bool, fb: Array<F32>, +f: Fill, +brush: Brush, +inv: Matrix, +linear: Bool, +clips: List<&2, Clip>, +w: U32, +h: U32) -> Array<F32>:
  match cond:
    case True{}:
      Fill{tree, cover} = f
      paint.cover(fb, cover, w, h, paint.context(brush, inv, linear, clips))
    case False{}: fb

def paint.stroke.if(cond: Bool, fb: Array<F32>, +mesh: StrokeMesh, +brush: Brush, +inv: Matrix, +linear: Bool, +clips: List<&2, Clip>, +w: U32, +h: U32) -> Array<F32>:
  match cond:
    case True{}:
      StrokeMesh{tree, meshInverse, cover} = mesh
      paint.cover(fb, cover, w, h, paint.context(brush, inv, linear, clips))
    case False{}: fb

# Fill (which = 0) or stroke (1) of a shape; markers (2) are painted by the caller.
def paint.piece(fb: Array<F32>, +which: U32, +s: Style, +ink: Paint<Brush>, +inv: Matrix, +outline: StrokeMesh, +f: Fill, +linear: Bool, +clips: List<&2, Clip>, +w: U32, +h: U32) -> Array<F32>:
  Style{fill, stroke, col, fo, so, width, even, visible, ss, ms, rendering, order} = s
  Paint{fc, sc} = ink
  paint.stroke.if(U32.is_eq(which, 1) && visible && Bool.not(String.eq(stroke, "none")) && F32.is_gt(width, 0.0),
    paint.fill.if(U32.is_eq(which, 0) && visible && Bool.not(String.eq(fill, "none")), fb, f, fc, inv, linear, clips, w, h),
    outline, sc, inv, linear, clips, w, h)

# paint-order as three steps: the first piece is order / 2, the other two in
# ascending order for an even value and descending for an odd one.
def paint.order.first(+order: U32) -> U32:
  U32.div(order, 2)

def paint.order.second(+order: U32) -> U32:
  +first = U32.div(order, 2)
  +lo = U.choose(U32, U32.is_eq(first, 0), 1, 0)
  +hi = U.choose(U32, U32.is_eq(first, 2), 1, 2)
  U.choose(U32, U32.is_eq(U32.mod(order, 2), 0), lo, hi)

def paint.order.third(+order: U32) -> U32:
  +first = U32.div(order, 2)
  +lo = U.choose(U32, U32.is_eq(first, 0), 1, 0)
  +hi = U.choose(U32, U32.is_eq(first, 2), 1, 2)
  U.choose(U32, U32.is_eq(U32.mod(order, 2), 0), hi, lo)

def paint.order.of(+s: Style) -> U32:
  Style{fill, stroke, col, fo, so, width, even, visible, ss, ms, rendering, order} = s
  order

def paint.markers.at(+which: U32, +nodes: List<&2, Scene<Brush>>) -> List<&2, Scene<Brush>>:
  U.choose(List<&2, Scene<Brush>>, U32.is_eq(which, 2), nodes, Nil{})

def paint.clips(clip: Clip, +clips: List<&2, Clip>) -> List<&2, Clip>:
  match clip:
    case ClipAll{}: clips
    case _: Con{clip, clips}

# ---- layer compositing ----

def comp.factor.got(got: Array<F32> & Img.Color, +mode: U32) -> Array<F32> & F32:
  (a, c) = got
  (a, mask.value(c, mode))

# The mask factor at lane index i: one without a mask, else the mask layer's luminance or alpha.
def comp.factor.if(read: Bool, mask: Array<F32>, +i: U32, +mode: U32) -> Array<F32> & F32:
  match read:
    case True{}: comp.factor.got(layer.color(mask, i), mode)
    case False{}: (mask, 1.0)

def comp.factor(mask: Array<F32>, +i: U32, +mode: U32) -> Array<F32> & F32:
  comp.factor.if(U32.is_ne(mode, 0), mask, i, mode)

def comp.pixel.mask(got: Array<F32> & F32, fb: Array<F32>, layer: Array<F32>, +i: U32, +opacity: F32, c: Img.Color) -> Array<F32> & (Array<F32> & Array<F32>):
  (mask, f) = got
  (layer.over(fb, i, color.fade(c, (opacity * f : F32))), (layer, mask))

def comp.pixel.layer(got: Array<F32> & Img.Color, fb: Array<F32>, mask: Array<F32>, +i: U32, +opacity: F32, +mode: U32) -> Array<F32> & (Array<F32> & Array<F32>):
  (layer, c) = got
  comp.pixel.mask(comp.factor(mask, i, mode), fb, layer, i, opacity, c)

def comp.step2(rest: Array<F32> & Array<F32>, fb: Array<F32>, +i: U32, +opacity: F32, +mode: U32) -> Array<F32> & (Array<F32> & Array<F32>):
  (layer, mask) = rest
  comp.pixel.layer(layer.color(layer, i), fb, mask, i, opacity, mode)

# One pixel: the layer's color, faded by opacity and the mask, over the frame.
def comp.step(state: Array<F32> & (Array<F32> & Array<F32>), +i: U32, +opacity: F32, +mode: U32) -> Array<F32> & (Array<F32> & Array<F32>):
  (fb, rest) = state
  comp.step2(rest, fb, i, opacity, mode)

@unsafe
def comp.row(state: Array<F32> & (Array<F32> & Array<F32>), n: Nat, +i: U32, +opacity: F32, +mode: U32) -> Array<F32> & (Array<F32> & Array<F32>):
  match n:
    case 0n: state
    case 1n+d: comp.row(comp.step(state, i, opacity, mode), d, (i + 4 : U32), opacity, mode)

@unsafe
def comp.rows(state: Array<F32> & (Array<F32> & Array<F32>), n: Nat, +y: U32, +x0: U32, +cols: Nat, +w: U32, +opacity: F32, +mode: U32) -> Array<F32> & (Array<F32> & Array<F32>):
  match n:
    case 0n: state
    case 1n+d: comp.rows(comp.row(state, cols, ((y * w + x0) * 4 : U32), opacity, mode), d, (y + 1 : U32), x0, cols, w, opacity, mode)

def comp.finish(state: Array<F32> & (Array<F32> & Array<F32>)) -> Array<F32>:
  (fb, rest) = state
  fb

# The pixel range of a device box within the frame: start and count per axis.
def comp.start(+lo: F32, +limit: U32) -> U32:
  F32.to_u32(U.clamp(F32.floor(lo), 0.0, U32.to_f32(limit)))

def comp.count(+lo: F32, +hi: F32, +limit: U32) -> U32:
  +a = comp.start(lo, limit)
  +b = F32.to_u32(U.clamp(F32.ceil(hi), 0.0, U32.to_f32(limit)))
  U.choose(U32, U32.is_gt(b, a), (b - a : U32), 0)

# A finished layer, faded by opacity and its mask layer, over the frame within box.
def comp.layer(fb: Array<F32>, layer: Array<F32>, mask: Array<F32>, +box: Bounds, +w: U32, +h: U32, +opacity: F32, +mode: U32) -> Array<F32>:
  Bounds{x0, y0, x1, y1} = box
  comp.finish(comp.rows((fb, (layer, mask)), U32.to_nat(comp.count(y0, y1, h)), comp.start(y0, h), comp.start(x0, w), U32.to_nat(comp.count(x0, x1, w)), w, opacity, mode))

# A rendered filter raster, faded by the node's clip, opacity and mask, over the frame.
def rcomp.pixel.mask(got: Array<F32> & F32, fb: Array<F32>, +i: U32, +opacity: F32, c: Img.Color) -> Array<F32> & Array<F32>:
  (mask, f) = got
  (layer.over(fb, i, color.fade(c, (opacity * f : F32))), mask)

def rcomp.step(state: Array<F32> & Array<F32>, +x: U32, +y: U32, +w: U32, +raster: Raster, +clip: Clip, +linear: Bool, +opacity: F32, +mode: U32) -> Array<F32> & Array<F32>:
  (fb, mask) = state
  +p = {Point{(U32.to_f32(x) + 0.5 : F32), (U32.to_f32(y) + 0.5 : F32)} : Point}
  +i = ((y * w + x) * 4 : U32)
  rcomp.pixel.mask(comp.factor(mask, i, mode), fb, i, opacity, color.fade(raster.color(raster, p, linear), clip.cover(clip, p)))

@unsafe
def rcomp.row(state: Array<F32> & Array<F32>, n: Nat, +x: U32, +y: U32, +w: U32, +raster: Raster, +clip: Clip, +linear: Bool, +opacity: F32, +mode: U32) -> Array<F32> & Array<F32>:
  match n:
    case 0n: state
    case 1n+d: rcomp.row(rcomp.step(state, x, y, w, raster, clip, linear, opacity, mode), d, (x + 1 : U32), y, w, raster, clip, linear, opacity, mode)

@unsafe
def rcomp.rows(state: Array<F32> & Array<F32>, n: Nat, +y: U32, +x0: U32, +cols: Nat, +w: U32, +raster: Raster, +clip: Clip, +linear: Bool, +opacity: F32, +mode: U32) -> Array<F32> & Array<F32>:
  match n:
    case 0n: state
    case 1n+d: rcomp.rows(rcomp.row(state, cols, x0, y, w, raster, clip, linear, opacity, mode), d, (y + 1 : U32), x0, cols, w, raster, clip, linear, opacity, mode)

def rcomp.finish(state: Array<F32> & Array<F32>) -> Array<F32>:
  (fb, mask) = state
  fb

def comp.raster(fb: Array<F32>, mask: Array<F32>, +raster: Raster, +clip: Clip, +box: Bounds, +w: U32, +h: U32, +linear: Bool, +opacity: F32, +mode: U32) -> Array<F32>:
  Bounds{x0, y0, x1, y1} = box
  rcomp.finish(rcomp.rows((fb, mask), U32.to_nat(comp.count(y0, y1, h)), comp.start(y0, h), comp.start(x0, w), U32.to_nat(comp.count(x0, x1, w)), w, raster, clip, linear, opacity, mode))

def filter.raster(effect: FilterEffect) -> Raster:
  match effect:
    case NoFilter{}: raster.empty()
    case FilterSpec{region, units, viewport, attrs, primitives}: raster.empty()
    case FilterImage{raster}: raster

# ---- nodes ----

# Paint a list of scenes onto fb, back to front. A node is direct when it has
# no opacity, mask or rendered filter: fill, stroke and markers in paint order,
# then its children, all limited by the enclosing clips plus its own. Otherwise
# the same content goes into a fresh layer (a copy of the node without those
# three) and the layer, or the filter raster, is composited within the node's
# coverage box; a mask is a layer painted from the mask nodes.
@unsafe
def paint.scenes(fb: Array<F32>, +xs: List<&2, Scene<Brush>>, +w: U32, +h: U32, +linear: Bool, +clips: List<&2, Clip>) -> Array<F32>:
  match xs:
    case Nil{}: fb
    case Con{Scene{es, box, inv, style, opacity, kids, id, ink, clip, outline, fill, maskNodes, maskMode, markerNodes, coverage, effect}, rest}:
      +inner = paint.clips(clip, clips)
      +direct = F32.is_ge(opacity, 1.0) && U32.is_eq(maskMode, 0) && Bool.not(filter.rendered(effect))
      +order = paint.order.of(style)
      +first = paint.order.first(order)
      +second = paint.order.second(order)
      +third = paint.order.third(order)
      paint.scenes(paint.with(direct, fb,
        fb1 => paint.scenes(
          paint.scenes(paint.piece(
            paint.scenes(paint.piece(
              paint.scenes(paint.piece(fb1, first, style, ink, inv, outline, fill, linear, inner, w, h), paint.markers.at(first, markerNodes), w, h, linear, inner),
              second, style, ink, inv, outline, fill, linear, inner, w, h), paint.markers.at(second, markerNodes), w, h, linear, inner),
            third, style, ink, inv, outline, fill, linear, inner, w, h), paint.markers.at(third, markerNodes), w, h, linear, inner),
          kids, w, h, linear, inner),
        fb1 => paint.with(filter.rendered(effect), fb1,
          fb2 => comp.raster(fb2, paint.scenes(layer.new(w, h), paint.markers.at(U.choose(U32, U32.is_ne(maskMode, 0), 2, 0), maskNodes), w, h, U32.is_eq(maskMode, 3), Nil{}), filter.raster(effect), clip, coverage, w, h, linear, opacity, maskMode),
          fb2 => comp.layer(fb2,
            paint.scenes(layer.new(w, h), Con{Scene{es, box, inv, style, 1.0, kids, id, ink, clip, outline, fill, Nil{}, 0, markerNodes, coverage, NoFilter{}}, Nil{}}, w, h, linear, clips),
            paint.scenes(layer.new(w, h), paint.markers.at(U.choose(U32, U32.is_ne(maskMode, 0), 2, 0), maskNodes), w, h, U32.is_eq(maskMode, 3), Nil{}),
            coverage, w, h, opacity, maskMode))),
        rest, w, h, linear, clips)

# The whole document at w by h device pixels.
def paint.frame(scene: List<&2, Scene<Brush>>, +w: U32, +h: U32, +aa: U32) -> Array<F32>:
  paint.scenes(layer.new(w, h), cover.scenes(prepare.scenes(scene, identity(), aa), frame(w, h), cover.sub(aa)), w, h, False{}, Nil{})

# ---- packed output ----

def pack.got(got: Array<F32> & Img.Color, out: Array<U32>, +j: U32) -> Array<F32> & Array<U32>:
  (fb, c) = got
  (fb, Array.set(U32, out, j, color.pack(color.over(c, color.rgb(16777215)))))

def pack.step(state: Array<F32> & Array<U32>, +j: U32) -> Array<F32> & Array<U32>:
  (fb, out) = state
  pack.got(layer.color(fb, (j * 4 : U32)), out, j)

@unsafe
def pack.loop(state: Array<F32> & Array<U32>, n: Nat, +j: U32) -> Array<F32> & Array<U32>:
  match n:
    case 0n: state
    case 1n+d: pack.loop(pack.step(state, j), d, (j + 1 : U32))

def pack.finish(state: Array<F32> & Array<U32>) -> Array<U32>:
  (fb, out) = state
  out

# The document as packed 0xRRGGBB pixels over white, row-major, w * h entries.
def paint.packed(scene: List<&2, Scene<Brush>>, +w: U32, +h: U32, +aa: U32) -> Array<U32>:
  pack.finish(pack.loop((paint.frame(scene, w, h, aa), Array.new(U32, raster.depth((w * h : U32), 1, 0n), 0)), U32.to_nat((w * h : U32)), 0))

# Threads an array through a continuation after one read.
def packed.then(-R: Type, got: Array<U32> & U32, next: Array<U32> -> U32 -> R) -> R:
  (a, v) = got
  next(a)(v)

# The window image: a quadtree over a 2^depth square, read from the packed pixels.
@unsafe
def image.of(a: Array<U32>, depth: Nat, +x: U32, +y: U32, +side: U32, next: Array<U32> -> Image -> Image) -> Image:
  match depth:
    case 0n: packed.then(Image, Array.get(U32, a, (y * side + x : U32)), a1 => v => next(a1)(Pix{v}))
    case 1n+d:
      +dd = d
      +half = U32.shln(1, dd)
      image.of(a, dd, x, y, side, a1 => ia => image.of(a1, dd, (x + half : U32), y, side, a2 => ib => image.of(a2, dd, x, (y + half : U32), side,
        a3 => ic => image.of(a3, dd, (x + half : U32), (y + half : U32), side, a4 => id => next(a4)(Qua{ia, ib, ic, id})))))

def image(+depth: Nat, x: U32, y: U32, scene: List<&2, Scene<Brush>>, +aa: U32) -> Image:
  +side = U32.shln(1, depth)
  image.of(paint.packed(scene, side, side, aa), depth, 0, 0, side, a => im => im)

@unsafe
def ppm.cols(a: Array<U32>, n: Nat, +j: U32, next: Array<U32> -> String -> String) -> String:
  match n:
    case 0n: next(a)("")
    case 1n+d: packed.then(String, Array.get(U32, a, j), a1 => v => ppm.cols(a1, d, (j + 1 : U32), a2 => rest => next(a2)(pixel.ppm(v) ++ rest)))

@unsafe
def ppm.rows(a: Array<U32>, n: Nat, +y: U32, +w: U32, next: Array<U32> -> String -> String) -> String:
  match n:
    case 0n: next(a)("")
    case 1n+d: ppm.cols(a, U32.to_nat(w), (y * w : U32), a1 => row => ppm.rows(a1, d, (y + 1 : U32), w, a2 => rest => next(a2)(row ++ rest)))

def ppm(+w: U32, +h: U32, scene: List<&2, Scene<Brush>>, +aa: U32) -> String:
  "P3\n" ++ U32.show(w) ++ " " ++ U32.show(h) ++ "\n255\n" ++ ppm.rows(paint.packed(scene, w, h, aa), U32.to_nat(h), 0, w, a => text => text)

type Pick is Data:
  Pick{found: Bool, id: String, inverse: Matrix}

def pick.prefer(+a: Pick, b: Pick) -> Pick:
  Pick{found, id, inv} = a
  U.choose(Pick, found, a, b)

def pick.alpha(c: Img.Color) -> Bool:
  Img.Color{r, g, b, a} = c
  F32.is_gt(a, 0.0)

def pick.node(c: Img.Color, id: String, inv: Matrix) -> Pick:
  U.choose(Pick, pick.alpha(c), Pick{True{}, id, inv}, Pick{False{}, "", identity()})

def pick.instance(+hit: Pick, id: String, inv: Matrix) -> Pick:
  Pick{found, target, local} = hit
  U.choose(Pick, found && String.eq(target, ""), Pick{found, id, inv}, hit)

def pick(+scenes: List<&2, Scene<Brush>>, +p: Point) -> Pick:
  match scenes:
    case Nil{}: Pick{False{}, "", identity()}
    case Con{Scene{es, box, inv, style, opacity, kids, id, ink, mask, outline, fillTree, maskNodes, maskMode, markerNodes, coverage, effect}, rest}:
      node = {Scene{es, box, inv, style, opacity, kids, id, ink, mask, outline, fillTree, maskNodes, maskMode, markerNodes, coverage, effect} : Scene<Brush>}
      pick.prefer(pick(rest, p), U.branch(Pick, bounds.inside(coverage, p, 0.01) && clip.inside(mask, p) && F32.is_gt(mask.factor(maskMode, _ => sample(maskNodes, p, p, Img.clear(), U32.is_eq(maskMode, 3), 1.0)), 0.0), _ => pick.prefer(pick.instance(pick(kids, p), id, inv),
        pick.node(scene.local(node, p, p, False{}, sample(markerNodes, p, p, Img.clear(), False{}, 1.0), nodes => q => center => sample(nodes, q, center, Img.clear(), False{}, 1.0), nodes => q => center => sample(nodes, q, center, Img.clear(), False{}, 1.0), 1.0), id, inv)), _ => Pick{False{}, "", identity()}))
