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

@unsafe
def tree.at(t: CovTree, +half: U32, +x: U32, +y: U32) -> F32:
  match t:
    case CovFlat{v}: v
    case CovQuad{a, b, c, d}:
      +left = U32.is_lt(x, half)
      +top = U32.is_lt(y, half)
      +xx = U.choose(U32, left, x, (x - half : U32))
      +yy = U.choose(U32, top, y, (y - half : U32))
      +next = U32.div(half, 2)
      tree.at(U.choose(CovTree, top, U.choose(CovTree, left, a, b), U.choose(CovTree, left, c, d)), next, xx, yy)

def mask.at.in(outside: Bool, t: CovTree, +half: U32, +x: U32, +y: U32) -> F32:
  match outside:
    case True{}: 0.0
    case False{}: tree.at(t, half, x, y)

# Coverage of the pixel containing (px, py), in grid pixel coordinates; the
# reads branch through matches, not lambdas, since they run once per pixel.
def mask.at(+m: CovMask, +px: F32, +py: F32) -> F32:
  CovMask{x, y, size, depth, tree, present} = m
  +sizeDup = size
  +yDup = y
  +xDup = x
  +fx = F32.floor(px)
  +fy = F32.floor(py)
  +ix = (F32.to_u32(U.max(fx, 0.0)) - xDup : U32)
  +iy = (F32.to_u32(U.max(fy, 0.0)) - yDup : U32)
  mask.at.in(F32.is_lt(fx, U32.to_f32(xDup)) || F32.is_lt(fy, U32.to_f32(yDup)) || U32.is_ge(ix, sizeDup) || U32.is_ge(iy, sizeDup), tree, U32.div(sizeDup, 2), ix, iy)

# Coverage over the cell rectangle [x0, x1) by [y0, y1) of a node's square at
# (nx, ny) of side size, when every cell in it holds the same value; -1 otherwise.
# acc is 2 before any cell is seen, -1 once cells disagree, else the value so far.
def tree.same.as(+v: F32, +u: F32) -> F32:
  U.choose(F32, F32.is_gt(v, 1.5), u, U.choose(F32, F32.is_lt(v, 0.0) || F32.is_lt(u, 0.0) || Bool.not(F32.is_eq(v, u)), F32.neg(1.0), v))

def tree.overlaps(+nx: U32, +ny: U32, +size: U32, +x0: U32, +y0: U32, +x1: U32, +y1: U32) -> Bool:
  U32.is_lt(nx, x1) && U32.is_lt(x0, (nx + size : U32)) && U32.is_lt(ny, y1) && U32.is_lt(y0, (ny + size : U32))

@unsafe
def tree.uniform(t: CovTree, +nx: U32, +ny: U32, +size: U32, +x0: U32, +y0: U32, +x1: U32, +y1: U32, +acc: F32) -> F32:
  match t:
    case CovFlat{v}: U.choose(F32, tree.overlaps(nx, ny, size, x0, y0, x1, y1), tree.same.as(acc, v), acc)
    case CovQuad{a, b, c, d}:
      +half = U32.div(size, 2)
      U.branch(F32, Bool.not(tree.overlaps(nx, ny, size, x0, y0, x1, y1)) || F32.is_lt(acc, F32.neg(0.5)), _ => acc,
        _ => tree.uniform(d, (nx + half : U32), (ny + half : U32), half, x0, y0, x1, y1,
          tree.uniform(c, nx, (ny + half : U32), half, x0, y0, x1, y1,
            tree.uniform(b, (nx + half : U32), ny, half, x0, y0, x1, y1,
              tree.uniform(a, nx, ny, half, x0, y0, x1, y1, acc)))))

# The mask's coverage over the grid rectangle [x0, x1) by [y0, y1) when it is
# uniform (2 means "unvisited", so an empty rectangle reads as uniform 0), else -1.
def mask.uniform.in(+m: CovMask, +x0: U32, +y0: U32, +x1: U32, +y1: U32) -> F32:
  CovMask{x, y, size, depth, tree, present} = m
  +mx = x
  +my = y
  +sz = size
  +outside = U32.is_lt(x0, mx) || U32.is_lt(y0, my) || U32.is_gt(x1, (mx + sz : U32)) || U32.is_gt(y1, (my + sz : U32))
  +inside = tree.uniform(tree, mx, my, sz, x0, y0, x1, y1, 2.0)
  +v = U.choose(F32, F32.is_gt(inside, 1.5), 0.0, inside)
  U.choose(F32, outside && F32.is_gt(v, 0.0), F32.neg(1.0), v)

def mask.uniform(+m: CovMask, +x0: U32, +y0: U32, +x1: U32, +y1: U32) -> F32:
  U.choose(F32, U32.is_ge(x0, x1) || U32.is_ge(y0, y1), 0.0, mask.uniform.in(m, x0, y0, x1, y1))

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

# The loops below run once per line per scanline, so they branch through
# matches on parameters rather than lambdas (a match cannot scrutinize a local).
def cross.place(before: Bool, +x: F32, +dir: F32, +hx: F32, +hd: F32, tt: List<&2, CovCross>, rest: List<&2, CovCross>) -> List<&2, CovCross>:
  match before:
    case True{}: Con{CovCross{x, dir}, Con{CovCross{hx, hd}, tt}}
    case False{}: Con{CovCross{hx, hd}, rest}

@unsafe
def cross.insert(+x: F32, +dir: F32, xs: List<&2, CovCross>) -> List<&2, CovCross>:
  match xs:
    case Nil{}: Con{CovCross{x, dir}, Nil{}}
    case Con{CovCross{hx, hd}, t}:
      +hxx = hx
      +tt = t
      cross.place(F32.is_le(x, hxx), x, dir, hxx, hd, tt, cross.insert(x, dir, tt))

def crossings.add(hit: Bool, +cx: F32, +dir: F32, acc: List<&2, CovCross>) -> List<&2, CovCross>:
  match hit:
    case True{}: Con{CovCross{cx, dir}, acc}
    case False{}: acc

# Crossings are collected unsorted and merge sorted by x: a scanline along a
# stroked curve meets every band and join it runs through, hundreds of
# crossings, where an insertion sort was quadratic.
def cross.x(+c: CovCross) -> F32:
  CovCross{x, dir} = c
  x

@unsafe
def cross.merge(xs: List<&2, CovCross>, ys: List<&2, CovCross>) -> List<&2, CovCross>:
  match xs:
    case Nil{}: ys
    case Con{x, xt}:
      match ys:
        case Nil{}: Con{x, xt}
        case Con{y, yt}:
          +xx = x
          +yy = y
          +xs2 = xt
          +ys2 = yt
          U.branch(List<&2, CovCross>, F32.is_le(cross.x(xx), cross.x(yy)), _ => Con{xx, cross.merge(xs2, Con{yy, ys2})}, _ => Con{yy, cross.merge(Con{xx, xs2}, ys2)})

def cross.deal(xs: List<&2, CovCross>, left: List<&2, CovCross>, right: List<&2, CovCross>) -> List<&2, CovCross> & List<&2, CovCross>:
  match xs:
    case Nil{}: (left, right)
    case Con{x, Nil{}}: (Con{x, left}, right)
    case Con{x, Con{y, rest}}: cross.deal(rest, Con{x, left}, Con{y, right})

def cross.halves(halves: List<&2, CovCross> & List<&2, CovCross>, next: List<&2, CovCross> -> List<&2, CovCross> -> List<&2, CovCross>) -> List<&2, CovCross>:
  (left, right) = halves
  next(left)(right)

@unsafe
def cross.sort(xs: List<&2, CovCross>) -> List<&2, CovCross>:
  match xs:
    case Nil{}: Nil{}
    case Con{x, rest}:
      match rest:
        case Nil{}: Con{x, Nil{}}
        case Con{y, more}: cross.halves(cross.deal(Con{x, Con{y, more}}, Nil{}, Nil{}), left => right => cross.merge(cross.sort(left), cross.sort(right)))

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
      crossings(rest, sy, crossings.add((F32.is_le(ay, sy) && F32.is_lt(sy, by)) || (F32.is_le(by, sy) && F32.is_lt(sy, ay)),
        (ax + (sy - ay) * (bx - ax) / (by - ay) : F32), U.choose(F32, F32.is_lt(ay, by), 1.0, F32.neg(1.0)), acc))

# Add weight over the cells of [xa, xb); both ends lie within [0, w]. A row
# has two slots per cell: the even slot takes the partial coverage of the two
# end cells directly, the odd slot takes a run delta (+weight at the first
# interior cell, -weight past the last), so a span costs four writes however
# wide it is; prefix.rows sums the deltas back into coverage.
def span.add(a: Array<F32>, +base: U32, +xa: F32, +xb: F32, +weight: F32) -> Array<F32>:
  +ia = F32.to_u32(F32.floor(xa))
  +ib = F32.to_u32(F32.floor(xb))
  with(Array<F32>, U32.is_ge(ia, ib), a,
    arr => acc.add(arr, (base + ia * 2 : U32), ((xb - xa) * weight : F32)),
    arr => acc.add(acc.add(acc.add(acc.add(arr, (base + ia * 2 : U32), ((U32.to_f32(ia) + 1.0 - xa) * weight : F32)), (base + ia * 2 + 3 : U32), weight), (base + ib * 2 + 1 : U32), F32.neg(weight)), (base + ib * 2 : U32), ((xb - U32.to_f32(ib)) * weight : F32)))

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

# ---- active lines ----
# Lines are sorted by their top once; each row takes the lines whose top lies
# above its bottom from the sorted list and drops those whose bottom lies
# above its top, so a row only looks at the lines that reach into it.

def line.top(+l: CovLine) -> F32:
  CovLine{x0, y0, x1, y1} = l
  U.min(y0, y1)

def line.bottom(+l: CovLine) -> F32:
  CovLine{x0, y0, x1, y1} = l
  U.max(y0, y1)

@unsafe
def lines.merge(xs: List<&2, CovLine>, ys: List<&2, CovLine>) -> List<&2, CovLine>:
  match xs:
    case Nil{}: ys
    case Con{x, xt}:
      match ys:
        case Nil{}: Con{x, xt}
        case Con{y, yt}:
          +xx = x
          +yy = y
          +xs2 = xt
          +ys2 = yt
          U.branch(List<&2, CovLine>, F32.is_le(line.top(xx), line.top(yy)), _ => Con{xx, lines.merge(xs2, Con{yy, ys2})}, _ => Con{yy, lines.merge(Con{xx, xs2}, ys2)})

def lines.deal(xs: List<&2, CovLine>, left: List<&2, CovLine>, right: List<&2, CovLine>) -> List<&2, CovLine> & List<&2, CovLine>:
  match xs:
    case Nil{}: (left, right)
    case Con{x, Nil{}}: (Con{x, left}, right)
    case Con{x, Con{y, rest}}: lines.deal(rest, Con{x, left}, Con{y, right})

def lines.halves(halves: List<&2, CovLine> & List<&2, CovLine>, next: List<&2, CovLine> -> List<&2, CovLine> -> List<&2, CovLine>) -> List<&2, CovLine>:
  (left, right) = halves
  next(left)(right)

# Merge sort by top; a single line or none is already sorted.
@unsafe
def lines.sort(xs: List<&2, CovLine>) -> List<&2, CovLine>:
  match xs:
    case Nil{}: Nil{}
    case Con{x, rest}:
      match rest:
        case Nil{}: Con{x, Nil{}}
        case Con{y, more}: lines.halves(lines.deal(Con{x, Con{y, more}}, Nil{}, Nil{}), left => right => lines.merge(lines.sort(left), lines.sort(right)))

def lines.keep(keep: Bool, +l: CovLine, more: List<&2, CovLine>) -> List<&2, CovLine>:
  match keep:
    case True{}: Con{l, more}
    case False{}: more

# The active lines still reaching below top.
def lines.retire(xs: List<&2, CovLine>, +top: F32) -> List<&2, CovLine>:
  match xs:
    case Nil{}: Nil{}
    case Con{l, rest}:
      +ll = l
      lines.keep(F32.is_gt(line.bottom(ll), top), ll, lines.retire(rest, top))

# Lines from the sorted pending list whose top lies above bottom move to the
# active list; the list is sorted, so the first line that does not ends the take.
@unsafe
def lines.take(pending: List<&2, CovLine>, +bottom: F32, +active: List<&2, CovLine>) -> List<&2, CovLine> & List<&2, CovLine>:
  match pending:
    case Nil{}: (active, Nil{})
    case Con{l, rest}:
      +ll = l
      +rs = rest
      U.branch(List<&2, CovLine> & List<&2, CovLine>, F32.is_lt(line.top(ll), bottom), _ => lines.take(rs, bottom, Con{ll, active}), _ => (active, Con{ll, rs}))

@unsafe
def scan.subs(a: Array<F32>, n: Nat, +s: U32, +sub: U32, +y: U32, +stride: U32, +xs: List<&2, CovLine>, +even: Bool) -> Array<F32>:
  match n:
    case 0n: a
    case 1n+d:
      +sy = (U32.to_f32(y) + (U32.to_f32(s) + 0.5) / U32.to_f32(sub) : F32)
      scan.subs(walk(a, cross.sort(crossings(xs, sy, Nil{})), (y * stride * 2 : U32), 0.0, 0.0, even, (1.0 / U32.to_f32(sub) : F32)), d, (s + 1 : U32), sub, y, stride, xs, even)

def scan.row(taken: List<&2, CovLine> & List<&2, CovLine>, a: Array<F32>, +sub: U32, +y: U32, +stride: U32, +even: Bool) -> Array<F32> & (List<&2, CovLine> & List<&2, CovLine>):
  (active, pending) = taken
  +live = active
  (scan.subs(a, U32.to_nat(sub), 0, sub, y, stride, live, even), (live, pending))

def scan.rows.lists(lists: List<&2, CovLine> & List<&2, CovLine>, a: Array<F32>, +y: U32, +stride: U32, +sub: U32, +even: Bool) -> Array<F32> & (List<&2, CovLine> & List<&2, CovLine>):
  (active, pending) = lists
  +yf = U32.to_f32(y)
  scan.row(lines.take(pending, (yf + 1.0 : F32), lines.retire(active, yf)), a, sub, y, stride, even)

def scan.rows.step(state: Array<F32> & (List<&2, CovLine> & List<&2, CovLine>), +y: U32, +stride: U32, +sub: U32, +even: Bool) -> Array<F32> & (List<&2, CovLine> & List<&2, CovLine>):
  (a, lists) = state
  scan.rows.lists(lists, a, y, stride, sub, even)

@unsafe
def scan.rows.go(state: Array<F32> & (List<&2, CovLine> & List<&2, CovLine>), n: Nat, +y: U32, +stride: U32, +sub: U32, +even: Bool) -> Array<F32> & (List<&2, CovLine> & List<&2, CovLine>):
  match n:
    case 0n: state
    case 1n+d: scan.rows.go(scan.rows.step(state, y, stride, sub, even), d, (y + 1 : U32), stride, sub, even)

def scan.done(state: Array<F32> & (List<&2, CovLine> & List<&2, CovLine>)) -> Array<F32>:
  (a, lists) = state
  a

def scan.rows(a: Array<F32>, n: Nat, +y: U32, +stride: U32, +sub: U32, +xs: List<&2, CovLine>, +even: Bool) -> Array<F32>:
  scan.done(scan.rows.go((a, (Nil{}, lines.sort(xs))), n, y, stride, sub, even))

# ---- run deltas into coverage ----

def prefix.put(got: Array<F32> & F32, +i: U32, +running: F32) -> Array<F32>:
  (a, direct) = got
  Array.set(F32, a, i, (direct + running : F32))

def prefix.delta(got: Array<F32> & F32, +i: U32, +running: F32) -> Array<F32> & F32:
  (a, delta) = got
  +total = (running + delta : F32)
  (prefix.put(Array.get(F32, a, i), i, total), total)

def prefix.next(state: Array<F32> & F32, +i: U32) -> Array<F32> & F32:
  (a, running) = state
  prefix.delta(Array.get(F32, a, (i + 1 : U32)), i, running)

# Along one row: the running sum of deltas plus the direct partials, written into the even slots.
@unsafe
def prefix.cells(state: Array<F32> & F32, n: Nat, +i: U32) -> Array<F32> & F32:
  match n:
    case 0n: state
    case 1n+d: prefix.cells(prefix.next(state, i), d, (i + 2 : U32))

def prefix.done(state: Array<F32> & F32) -> Array<F32>:
  (a, running) = state
  a

@unsafe
def prefix.rows(a: Array<F32>, n: Nat, +y: U32, +stride: U32) -> Array<F32>:
  match n:
    case 0n: a
    case 1n+d: prefix.rows(prefix.done(prefix.cells((a, 0.0), U32.to_nat(stride), (y * stride * 2 : U32))), d, (y + 1 : U32), stride)

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
  with.next(CovTree, U32.is_lt(x, w) && U32.is_lt(y, h), a, next, a1 => n1 => build.leaf(Array.get(F32, a1, ((y * stride + x) * 2 : U32)), n1), a1 => n1 => n1(a1)(CovFlat{0.0}))

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
  +cells = (stride * h * 2 : U32)
  +side = U.choose(U32, U32.is_gt(w, h), w, h)
  +depth = depth.for(side, 1, 0n)
  CovMask{gx, gy, U32.shln(1, depth), depth, build.tree(prefix.rows(scan.rows(Array.new(F32, depth.for(cells, 1, 0n), 0.0), U32.to_nat(h), 0, stride, sub, lines.clip(xs, U32.to_f32(w)), even), U32.to_nat(h), 0, stride), depth, 0, 0, w, h, stride, a => t => t), True{}}

def mask.box(+xs: List<&2, CovLine>, +even: Bool, +width: U32, +height: U32, +sub: U32, box: CovBox) -> CovMask:
  CovBox{x0, y0, x1, y1} = box
  +gx = F32.to_u32(U.clamp(F32.floor(x0), 0.0, U32.to_f32(width)))
  +gy = F32.to_u32(U.clamp(F32.floor(y0), 0.0, U32.to_f32(height)))
  +ex = F32.to_u32(U.clamp(F32.ceil(x1), 0.0, U32.to_f32(width)))
  +ey = F32.to_u32(U.clamp(F32.ceil(y1), 0.0, U32.to_f32(height)))
  U.branch(CovMask, U32.is_ge(gx, ex) || U32.is_ge(gy, ey), _ => CovMask{0, 0, 0, 0n, CovFlat{0.0}, True{}},
    _ => mask.build(lines.shift(xs, U32.to_f32(gx), U32.to_f32(gy)), gx, gy, (ex - gx : U32), (ey - gy : U32), even, sub))

# A closed rectangle on whole pixels: four axis-aligned lines on the box edges
# with integer coordinates (the usual viewport clip and the common rect), whose
# mask is a tree of full and empty leaves with no scan at all.
def line.on.box(+ax: F32, +ay: F32, +bx: F32, +by: F32, +x0: F32, +y0: F32, +x1: F32, +y1: F32) -> Bool:
  (F32.is_eq(ax, bx) && (F32.is_eq(ax, x0) || F32.is_eq(ax, x1))) || (F32.is_eq(ay, by) && (F32.is_eq(ay, y0) || F32.is_eq(ay, y1)))

# Zero-length lines (a path's move and close) are ignored; the four real ones must lie on the box.
def lines.on.box(xs: List<&2, CovLine>, +x0: F32, +y0: F32, +x1: F32, +y1: F32, +count: U32) -> Bool:
  match xs:
    case Nil{}: U32.is_eq(count, 4)
    case Con{CovLine{ax, ay, bx, by}, rest}:
      +axx = ax
      +ayy = ay
      +bxx = bx
      +byy = by
      +empty = F32.is_eq(axx, bxx) && F32.is_eq(ayy, byy)
      (empty || line.on.box(axx, ayy, bxx, byy, x0, y0, x1, y1)) && lines.on.box(rest, x0, y0, x1, y1, U.choose(U32, empty, count, (count + 1 : U32)))

def whole(+v: F32) -> Bool:
  F32.is_eq(v, F32.floor(v))

def rect.aligned(+xs: List<&2, CovLine>, +box: CovBox) -> Bool:
  CovBox{x0, y0, x1, y1} = box
  whole(x0) && whole(y0) && whole(x1) && whole(y1) && F32.is_lt(x0, x1) && F32.is_lt(y0, y1) && lines.on.box(xs, x0, y0, x1, y1, 0)

@unsafe
def tree.rect(depth: Nat, +x: U32, +y: U32, +w: U32, +h: U32) -> CovTree:
  match depth:
    case 0n: CovFlat{U.choose(F32, U32.is_lt(x, w) && U32.is_lt(y, h), 1.0, 0.0)}
    case 1n+d:
      +dd = d
      +half = U32.shln(1, dd)
      +size = (half * 2 : U32)
      U.branch(CovTree, U32.is_ge(x, w) || U32.is_ge(y, h), _ => CovFlat{0.0},
        _ => U.branch(CovTree, U32.is_le((x + size : U32), w) && U32.is_le((y + size : U32), h), _ => CovFlat{1.0},
          _ => CovQuad{tree.rect(dd, x, y, w, h), tree.rect(dd, (x + half : U32), y, w, h), tree.rect(dd, x, (y + half : U32), w, h), tree.rect(dd, (x + half : U32), (y + half : U32), w, h)}))

def mask.rect(+width: U32, +height: U32, +box: CovBox) -> CovMask:
  CovBox{x0, y0, x1, y1} = box
  +gx = F32.to_u32(U.clamp(x0, 0.0, U32.to_f32(width)))
  +gy = F32.to_u32(U.clamp(y0, 0.0, U32.to_f32(height)))
  +ex = F32.to_u32(U.clamp(x1, 0.0, U32.to_f32(width)))
  +ey = F32.to_u32(U.clamp(y1, 0.0, U32.to_f32(height)))
  +w = (ex - gx : U32)
  +h = (ey - gy : U32)
  +depth = depth.for(U.choose(U32, U32.is_gt(w, h), w, h), 1, 0n)
  U.branch(CovMask, U32.is_ge(gx, ex) || U32.is_ge(gy, ey), _ => CovMask{0, 0, 0, 0n, CovFlat{0.0}, True{}},
    _ => CovMask{gx, gy, U32.shln(1, depth), depth, tree.rect(depth, 0, 0, w, h), True{}})

def mask.shape(aligned: Bool, +xs: List<&2, CovLine>, +even: Bool, +width: U32, +height: U32, +sub: U32, +box: CovBox) -> CovMask:
  match aligned:
    case True{}: mask.rect(width, height, box)
    case False{}: mask.box(xs, even, width, height, sub, box)

# Rasterize closed contours given as directed lines in pixel coordinates of a
# width by height grid, with `sub` scanlines per pixel row; nonzero winding, or
# even-odd when `even` holds.
def mask(+xs: List<&2, CovLine>, +even: Bool, +width: U32, +height: U32, +sub: U32) -> CovMask:
  +box = lines.bounds(xs, 1000000000.0, 1000000000.0, F32.neg(1000000000.0), F32.neg(1000000000.0))
  mask.shape(rect.aligned(xs, box), xs, even, width, height, sub, box)

def mask.scanned(+xs: List<&2, CovLine>, +even: Bool, +width: U32, +height: U32, +sub: U32) -> CovMask:
  mask.box(xs, even, width, height, sub, lines.bounds(xs, 1000000000.0, 1000000000.0, F32.neg(1000000000.0), F32.neg(1000000000.0)))
