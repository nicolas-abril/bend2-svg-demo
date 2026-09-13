# Analytic coverage: line lists in pixel space are scan-converted with a winding
# count on a few sub-scanlines per row (exact span extents in x, so the fill
# rule holds even where contours overlap), and the result is a sparse quadtree
# mask.
import Base
import ./util.bend as U

# A directed line in pixel coordinates of the target grid.
type CovLine is Data:
  CovLine{x0: F32, y0: F32, x1: F32, y1: F32}

# Coverage over a power-of-two square: uniform cells collapse to one leaf.
type CovTree is Data:
  CovFlat{value: F32}
  CovQuad{a: CovTree, b: CovTree, c: CovTree, d: CovTree}

# A mask placed at pixel (x, y) of its grid, size = 2^depth cells on a side.
type CovMask is Data:
  CovMask{x: U32, y: U32, size: U32, depth: Nat, tree: CovTree, present: Bool}

def mask.none() -> CovMask:
  CovMask{0, 0, 0, 0n, CovFlat{0.0}, False{}}

def mask.present(+m: CovMask) -> Bool:
  CovMask{x, y, size, depth, tree, present} = m
  present

def tree.at(t: CovTree, +half: U32, +x: U32, +y: U32) -> F32:
  match t:
    case CovFlat{v}: v
    case CovQuad{a, b, c, d}:
      +left = U32.is_lt(x, half)
      +top = U32.is_lt(y, half)
      +xx = U.choose(U32, left, x, (x - half : U32))
      +yy = U.choose(U32, top, y, (y - half : U32))
      +next = U32.div(half, 2)
      U.branch(F32, top, _ => U.branch(F32, left, _ => tree.at(a, next, xx, yy), _ => tree.at(b, next, xx, yy)),
        _ => U.branch(F32, left, _ => tree.at(c, next, xx, yy), _ => tree.at(d, next, xx, yy)))

# Coverage of the pixel containing (px, py), in grid pixel coordinates.
def mask.at(+m: CovMask, +px: F32, +py: F32) -> F32:
  CovMask{x, y, size, depth, tree, present} = m
  +sizeDup = size
  +yDup = y
  +xDup = x
  +fx = F32.floor(px)
  +fy = F32.floor(py)
  +ix = (F32.to_u32(U.max(fx, 0.0)) - xDup : U32)
  +iy = (F32.to_u32(U.max(fy, 0.0)) - yDup : U32)
  U.branch(F32, F32.is_lt(fx, U32.to_f32(xDup)) || F32.is_lt(fy, U32.to_f32(yDup)) || U32.is_ge(ix, sizeDup) || U32.is_ge(iy, sizeDup), _ => 0.0,
    _ => tree.at(tree, U32.div(sizeDup, 2), ix, iy))

# ---- clipping to the grid's horizontal extent ----

def line.split(l: CovLine, +at: F32) -> List<&2, CovLine>:
  CovLine{x0, y0, x1, y1} = l
  +ax = x0
  +ay = y0
  +bx = x1
  +by = y1
  +t = ((at - ax) / (bx - ax) : F32)
  +my = (ay + (by - ay) * t : F32)
  U.branch(List<&2, CovLine>, (F32.is_lt(ax, at) && F32.is_gt(bx, at)) || (F32.is_gt(ax, at) && F32.is_lt(bx, at)),
    _ => Con{CovLine{ax, ay, at, my}, Con{CovLine{at, my, bx, by}, Nil{}}},
    _ => Con{CovLine{ax, ay, bx, by}, Nil{}})

def lines.append(xs: List<&2, CovLine>, ys: List<&2, CovLine>) -> List<&2, CovLine>:
  match xs:
    case Nil{}: ys
    case Con{h, t}: Con{h, lines.append(t, ys)}

def lines.split(xs: List<&2, CovLine>, +at: F32) -> List<&2, CovLine>:
  match xs:
    case Nil{}: Nil{}
    case Con{l, rest}: lines.append(line.split(l, at), lines.split(rest, at))

# Pieces left of 0 or right of w become vertical lines on that boundary, which keeps
# the winding of every cell inside [0, w) intact.
def lines.clamp(xs: List<&2, CovLine>, +w: F32) -> List<&2, CovLine>:
  match xs:
    case Nil{}: Nil{}
    case Con{CovLine{x0, y0, x1, y1}, rest}: Con{CovLine{U.clamp(x0, 0.0, w), y0, U.clamp(x1, 0.0, w), y1}, lines.clamp(rest, w)}

def lines.clip(xs: List<&2, CovLine>, +w: F32) -> List<&2, CovLine>:
  lines.clamp(lines.split(lines.split(xs, 0.0), w), w)

# ---- accumulation helpers ----

# Linear values cannot be captured by both branch lambdas, so a branch hands the
# array (and any continuation) to exactly one side.
def with(-R: Type, cond: Bool, a: Array<F32>, yes: Array<F32> -> R, no: Array<F32> -> R) -> R:
  match cond:
    case True{}: yes(a)
    case False{}: no(a)

def with.next(-R: Type, cond: Bool, a: Array<F32>, next: Array<F32> -> CovTree -> R, yes: Array<F32> -> (Array<F32> -> CovTree -> R) -> R, no: Array<F32> -> (Array<F32> -> CovTree -> R) -> R) -> R:
  match cond:
    case True{}: yes(a)(next)
    case False{}: no(a)(next)

def acc.add.got(+i: U32, +delta: F32, got: Array<F32> & F32) -> Array<F32>:
  (a, old) = got
  Array.set(F32, a, i, (old + delta : F32))

def acc.add(a: Array<F32>, +i: U32, +delta: F32) -> Array<F32>:
  acc.add.got(i, delta, Array.get(F32, a, i))

@unsafe
def acc.span(a: Array<F32>, n: Nat, +i: U32, +delta: F32) -> Array<F32>:
  match n:
    case 0n: a
    case 1n+d: acc.span(acc.add(a, i, delta), d, (i + 1 : U32), delta)

# ---- sub-scanline winding ----
# Each pixel row is sampled on `sub` horizontal scanlines. On each one the
# crossings of every line are sorted by x and walked with a winding count, so
# overlapping contours (stroke pieces at a joint, self-intersecting paths) follow
# the fill rule exactly; every inside span adds its exact horizontal extent to
# the cells it covers, weighted by one over `sub`. Coverage is exact in x and
# quantized to 1/sub in y.

type CovCross is Data:
  CovCross{x: F32, dir: F32}

@unsafe
def cross.insert(+x: F32, +dir: F32, xs: List<&2, CovCross>) -> List<&2, CovCross>:
  match xs:
    case Nil{}: Con{CovCross{x, dir}, Nil{}}
    case Con{CovCross{hx, hd}, t}:
      +hxx = hx
      +hdd = hd
      +tt = t
      U.branch(List<&2, CovCross>, F32.is_le(x, hxx), _ => Con{CovCross{x, dir}, Con{CovCross{hxx, hdd}, tt}}, _ => Con{CovCross{hxx, hdd}, cross.insert(x, dir, tt)})

# Crossings of the lines with height sy, sorted by x. A line covers [top, bottom),
# so a vertex shared by two lines counts once; horizontal lines never cross.
def crossings(xs: List<&2, CovLine>, +sy: F32, acc: List<&2, CovCross>) -> List<&2, CovCross>:
  match xs:
    case Nil{}: acc
    case Con{CovLine{x0, y0, x1, y1}, rest}:
      +ax = x0
      +ay = y0
      +bx = x1
      +by = y1
      +ac = acc
      +hit = (F32.is_le(ay, sy) && F32.is_lt(sy, by)) || (F32.is_le(by, sy) && F32.is_lt(sy, ay))
      +cx = (ax + (sy - ay) * (bx - ax) / (by - ay) : F32)
      +dir = U.choose(F32, F32.is_lt(ay, by), 1.0, F32.neg(1.0))
      crossings(rest, sy, U.branch(List<&2, CovCross>, hit, _ => cross.insert(cx, dir, ac), _ => ac))

# Add weight over the cells of [xa, xb); both ends lie within [0, stride - 2].
def span.add(a: Array<F32>, +base: U32, +xa: F32, +xb: F32, +weight: F32) -> Array<F32>:
  +ia = F32.to_u32(F32.floor(xa))
  +ib = F32.to_u32(F32.floor(xb))
  with(Array<F32>, U32.is_ge(ia, ib), a,
    arr => acc.add(arr, (base + ia : U32), ((xb - xa) * weight : F32)),
    arr => acc.add(acc.span(acc.add(arr, (base + ia : U32), ((U32.to_f32(ia) + 1.0 - xa) * weight : F32)), U32.to_nat((ib - ia - 1 : U32)), (base + ia + 1 : U32), weight), (base + ib : U32), ((xb - U32.to_f32(ib)) * weight : F32)))

def winding.inside(+wind: F32, +even: Bool) -> Bool:
  U.choose(Bool, even, F32.is_gt(F32.abs((wind - 2.0 * F32.floor((wind / 2.0 : F32)) : F32)), 0.5), F32.is_gt(F32.abs(wind), 0.5))

# Walk sorted crossings: the span before each crossing is inside when the winding
# count so far satisfies the fill rule.
@unsafe
def walk(a: Array<F32>, cs: List<&2, CovCross>, +base: U32, +wind: F32, +last: F32, +even: Bool, +weight: F32) -> Array<F32>:
  match cs:
    case Nil{}: a
    case Con{CovCross{x, d}, rest}:
      +xx = x
      walk(with(Array<F32>, winding.inside(wind, even), a, arr => span.add(arr, base, last, xx, weight), arr => arr), rest, base, (wind + d : F32), xx, even, weight)

# The lines that reach into the row band [top, bottom).
def lines.band(xs: List<&2, CovLine>, +top: F32, +bottom: F32) -> List<&2, CovLine>:
  match xs:
    case Nil{}: Nil{}
    case Con{CovLine{x0, y0, x1, y1}, rest}:
      +ax = x0
      +ay = y0
      +bx = x1
      +by = y1
      +more = lines.band(rest, top, bottom)
      U.branch(List<&2, CovLine>, F32.is_lt(U.min(ay, by), bottom) && F32.is_gt(U.max(ay, by), top), _ => Con{CovLine{ax, ay, bx, by}, more}, _ => more)

@unsafe
def scan.subs(a: Array<F32>, n: Nat, +s: U32, +sub: U32, +y: U32, +stride: U32, +xs: List<&2, CovLine>, +even: Bool) -> Array<F32>:
  match n:
    case 0n: a
    case 1n+d:
      +sy = (U32.to_f32(y) + (U32.to_f32(s) + 0.5) / U32.to_f32(sub) : F32)
      scan.subs(walk(a, crossings(xs, sy, Nil{}), (y * stride : U32), 0.0, 0.0, even, (1.0 / U32.to_f32(sub) : F32)), d, (s + 1 : U32), sub, y, stride, xs, even)

@unsafe
def scan.rows(a: Array<F32>, n: Nat, +y: U32, +stride: U32, +sub: U32, +xs: List<&2, CovLine>, +even: Bool) -> Array<F32>:
  match n:
    case 0n: a
    case 1n+d:
      +yf = U32.to_f32(y)
      scan.rows(scan.subs(a, U32.to_nat(sub), 0, sub, y, stride, lines.band(xs, yf, (yf + 1.0 : F32)), even), d, (y + 1 : U32), stride, sub, xs, even)

# ---- quadtree build ----

def tree.same(+p: CovTree, +q: CovTree) -> Bool:
  match p q:
    case CovFlat{u} CovFlat{v}: F32.is_eq(u, v)
    case _ _: False{}

def tree.value(+p: CovTree) -> F32:
  match p:
    case CovFlat{v}: v
    case CovQuad{a, b, c, d}: 0.0

def tree.merge(+a: CovTree, +b: CovTree, +c: CovTree, +d: CovTree) -> CovTree:
  U.branch(CovTree, tree.same(a, b) && tree.same(a, c) && tree.same(a, d), _ => CovFlat{tree.value(a)}, _ => CovQuad{a, b, c, d})

def build.leaf(got: Array<F32> & F32, next: Array<F32> -> CovTree -> CovTree) -> CovTree:
  (a, v) = got
  next(a)(CovFlat{v})

def build.cell(a: Array<F32>, +x: U32, +y: U32, +w: U32, +h: U32, +stride: U32, next: Array<F32> -> CovTree -> CovTree) -> CovTree:
  with.next(CovTree, U32.is_lt(x, w) && U32.is_lt(y, h), a, next, a1 => n1 => build.leaf(Array.get(F32, a1, (y * stride + x : U32)), n1), a1 => n1 => n1(a1)(CovFlat{0.0}))

# Depth-first over the power-of-two grid, threading the accumulation array through continuations.
@unsafe
def build.tree(a: Array<F32>, depth: Nat, +x: U32, +y: U32, +w: U32, +h: U32, +stride: U32, next: Array<F32> -> CovTree -> CovTree) -> CovTree:
  match depth:
    case 0n: build.cell(a, x, y, w, h, stride, next)
    case 1n+dd:
      +d0 = dd
      +half = U32.shln(1, d0)
      with.next(CovTree, U32.is_ge(x, w) || U32.is_ge(y, h), a, next, a0 => n0 => n0(a0)(CovFlat{0.0}),
        a0 => n0 => build.tree(a0, d0, x, y, w, h, stride, a1 => ta => build.tree(a1, d0, (x + half : U32), y, w, h, stride,
          a2 => tb => build.tree(a2, d0, x, (y + half : U32), w, h, stride,
            a3 => tc => build.tree(a3, d0, (x + half : U32), (y + half : U32), w, h, stride, a4 => td => n0(a4)(tree.merge(ta, tb, tc, td)))))))

# ---- entry ----

type CovBox is Data:
  CovBox{x0: F32, y0: F32, x1: F32, y1: F32}

def lines.bounds(xs: List<&2, CovLine>, +x0: F32, +y0: F32, +x1: F32, +y1: F32) -> CovBox:
  match xs:
    case Nil{}: CovBox{x0, y0, x1, y1}
    case Con{CovLine{ax, ay, bx, by}, rest}:
      +byDup = by
      +bxDup = bx
      +ayDup = ay
      +axDup = ax
      +lx = U.min(axDup, bxDup)
      +ly = U.min(ayDup, byDup)
      +hx = U.max(axDup, bxDup)
      +hy = U.max(ayDup, byDup)
      lines.bounds(rest, U.min(x0, lx), U.min(y0, ly), U.max(x1, hx), U.max(y1, hy))

def lines.shift(xs: List<&2, CovLine>, +dx: F32, +dy: F32) -> List<&2, CovLine>:
  match xs:
    case Nil{}: Nil{}
    case Con{CovLine{ax, ay, bx, by}, rest}: Con{CovLine{(ax - dx : F32), (ay - dy : F32), (bx - dx : F32), (by - dy : F32)}, lines.shift(rest, dx, dy)}

@unsafe
def depth.for(+size: U32, +side: U32, +depth: Nat) -> Nat:
  U.branch(Nat, U32.is_ge(side, size), _ => depth, _ => depth.for(size, (side * 2 : U32), 1n+depth))

def mask.build(+xs: List<&2, CovLine>, +gx: U32, +gy: U32, +w: U32, +h: U32, +even: Bool, +sub: U32) -> CovMask:
  +stride = (w + 2 : U32)
  +cells = (stride * h : U32)
  +side = U.choose(U32, U32.is_gt(w, h), w, h)
  +depth = depth.for(side, 1, 0n)
  CovMask{gx, gy, U32.shln(1, depth), depth, build.tree(scan.rows(Array.new(F32, depth.for(cells, 1, 0n), 0.0), U32.to_nat(h), 0, stride, sub, lines.clip(xs, U32.to_f32(w)), even), depth, 0, 0, w, h, stride, a => t => t), True{}}

def mask.box(+xs: List<&2, CovLine>, +even: Bool, +width: U32, +height: U32, +sub: U32, box: CovBox) -> CovMask:
  CovBox{x0, y0, x1, y1} = box
  +gx = F32.to_u32(U.clamp(F32.floor(x0), 0.0, U32.to_f32(width)))
  +gy = F32.to_u32(U.clamp(F32.floor(y0), 0.0, U32.to_f32(height)))
  +ex = F32.to_u32(U.clamp(F32.ceil(x1), 0.0, U32.to_f32(width)))
  +ey = F32.to_u32(U.clamp(F32.ceil(y1), 0.0, U32.to_f32(height)))
  U.branch(CovMask, U32.is_ge(gx, ex) || U32.is_ge(gy, ey), _ => CovMask{0, 0, 0, 0n, CovFlat{0.0}, True{}},
    _ => mask.build(lines.shift(xs, U32.to_f32(gx), U32.to_f32(gy)), gx, gy, (ex - gx : U32), (ey - gy : U32), even, sub))

# Rasterize closed contours given as directed lines in pixel coordinates of a
# width by height grid, with `sub` scanlines per pixel row; nonzero winding, or
# even-odd when `even` holds.
def mask(+xs: List<&2, CovLine>, +even: Bool, +width: U32, +height: U32, +sub: U32) -> CovMask:
  mask.box(xs, even, width, height, sub, lines.bounds(xs, 1000000000.0, 1000000000.0, F32.neg(1000000000.0), F32.neg(1000000000.0)))
