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

# A run of cells [x0, x1) of one nonzero coverage value in a row.
type Run is Data:
  Run{x0: U32, x1: U32, value: F32}

# A mask's coverage: rows of runs (top first, ascending runs), which a fill is
# painted from directly, or the tree, which clip masks and sampled tiles need
# for block and pixel queries.
type CovData is Data:
  CovRows{rows: List<&2, List<&2, Run>>}
  CovTreed{tree: CovTree}

# A mask placed at pixel (x, y) of its grid, size = 2^depth cells on a side.
type CovMask is Data:
  CovMask{x: U32, y: U32, size: U32, depth: Nat, data: CovData, present: Bool}

def mask.none() -> CovMask:
  CovMask{0, 0, 0, 0n, CovTreed{CovFlat{0.0}}, False{}}

# Coverage of a cell from rows of runs; a slow path for masks built without a tree.
def runs.at(rs: List<&2, Run>, +x: U32) -> F32:
  match rs:
    case Nil{}: 0.0
    case Con{Run{a, b, v}, rest}:
      +aa = a
      +bb = b
      +vv = v
      U.choose(F32, U32.is_ge(x, aa) && U32.is_lt(x, bb), vv, runs.at(rest, x))

def rows.at(rows: List<&2, List<&2, Run>>, +y: U32, +x: U32) -> F32:
  match rows:
    case Nil{}: 0.0
    case Con{r, rest}: U.choose(F32, U32.is_eq(y, 0), runs.at(r, x), rows.at(rest, (y - 1 : U32), x))

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

def data.at(d: CovData, +half: U32, +x: U32, +y: U32) -> F32:
  match d:
    case CovTreed{t}: tree.at(t, half, x, y)
    case CovRows{rows}: rows.at(rows, y, x)

def mask.at.in(outside: Bool, d: CovData, +half: U32, +x: U32, +y: U32) -> F32:
  match outside:
    case True{}: 0.0
    case False{}: data.at(d, half, x, y)

# Coverage of the pixel containing (px, py), in grid pixel coordinates; the
# reads branch through matches, not lambdas, since they run once per pixel.
def mask.at(+m: CovMask, +px: F32, +py: F32) -> F32:
  CovMask{x, y, size, depth, data, present} = m
  +sizeDup = size
  +yDup = y
  +xDup = x
  +fx = F32.floor(px)
  +fy = F32.floor(py)
  +ix = (F32.to_u32(U.max(fx, 0.0)) - xDup : U32)
  +iy = (F32.to_u32(U.max(fy, 0.0)) - yDup : U32)
  mask.at.in(F32.is_lt(fx, U32.to_f32(xDup)) || F32.is_lt(fy, U32.to_f32(yDup)) || U32.is_ge(ix, sizeDup) || U32.is_ge(iy, sizeDup), data, U32.div(sizeDup, 2), ix, iy)

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
# The uniform value of runs over the columns [x0, x1): a run covering them
# all gives its value, none touching them gives 0, anything else -1.
def runs.over(rs: List<&2, Run>, +x0: U32, +x1: U32, +acc: F32) -> F32:
  match rs:
    case Nil{}: U.choose(F32, F32.is_gt(acc, 1.5), 0.0, acc)
    case Con{Run{a, b, v}, rest}:
      +aa = a
      +bb = b
      +vv = v
      +overlaps = U32.is_lt(aa, x1) && U32.is_lt(x0, bb)
      +covers = U32.is_le(aa, x0) && U32.is_ge(bb, x1)
      runs.over(rest, x0, x1, U.choose(F32, Bool.not(overlaps), acc, U.choose(F32, covers && F32.is_gt(acc, 1.5), vv, F32.neg(1.0))))

# The uniform value of rows over the cell rectangle [x0, x1) by [y0, y1) in
# grid cells relative to the mask; rows past the list are empty.
@unsafe
def rows.over(rows: List<&2, List<&2, Run>>, +y: U32, +x0: U32, +y0: U32, +x1: U32, +y1: U32, +acc: F32) -> F32:
  match rows:
    case Nil{}: U.choose(F32, U32.is_lt(y, y1), tree.same.as(acc, 0.0), acc)
    case Con{r, rest}:
      U.choose(F32, U32.is_ge(y, y1) || F32.is_lt(acc, F32.neg(0.5)), acc,
        rows.over(rest, (y + 1 : U32), x0, y0, x1, y1, U.choose(F32, U32.is_lt(y, y0), acc, tree.same.as(acc, runs.over(r, x0, x1, 2.0)))))

def data.uniform(d: CovData, +mx: U32, +my: U32, +sz: U32, +x0: U32, +y0: U32, +x1: U32, +y1: U32) -> F32:
  match d:
    case CovTreed{t}: tree.uniform(t, mx, my, sz, x0, y0, x1, y1, 2.0)
    case CovRows{rows}: rows.over(rows, 0, (x0 - mx : U32), (y0 - my : U32), (x1 - mx : U32), (y1 - my : U32), 2.0)

def mask.uniform.in(+m: CovMask, +x0: U32, +y0: U32, +x1: U32, +y1: U32) -> F32:
  CovMask{x, y, size, depth, data, present} = m
  +mx = x
  +my = y
  +sz = size
  +outside = U32.is_lt(x0, mx) || U32.is_lt(y0, my) || U32.is_gt(x1, (mx + sz : U32)) || U32.is_gt(y1, (my + sz : U32))
  +inside = data.uniform(data, mx, my, sz, U.max.u32(x0, mx), U.max.u32(y0, my), U.min.u32(x1, (mx + sz : U32)), U.min.u32(y1, (my + sz : U32)))
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

# ---- sub-scanline winding ----
# Each pixel row is sampled on `sub` horizontal scanlines. The lines reaching
# a scanline are kept in a list sorted by their x on it: one pass per
# scanline walks that list with a winding count, emitting the inside spans as
# events, and at the same time places every line that still reaches the next
# scanline into the next list at its x there (lines keep their order almost
# everywhere, so the insertion is a prepend). Lines start when the sorted
# pending list reaches their top and end when the next scanline passes their
# bottom. Coverage is exact in x and quantized to 1/sub in y, overlapping
# contours follow the fill rule exactly, and nothing is sorted from scratch.

def line.top(+l: CovLine) -> F32:
  CovLine{x0, y0, x1, y1} = l
  U.min(y0, y1)

# A line on the scanlines: x at the current one is cur; slope is dx/dy.
type Act is Data:
  Act{cur: F32, x0: F32, y0: F32, slope: F32, bottom: F32, dir: F32}

# Insert into a list descending by cur, after the elements not below it.
type Ins is Data:
  Placed{list: List<&2, Act>}
  Passed{h: Act, t: List<&2, Act>, a: Act}

def act.ins.pick(hit: Bool, a: Act, h: Act, t: List<&2, Act>) -> Ins:
  match hit:
    case True{}: Placed{Con{a, Con{h, t}}}
    case False{}: Passed{h, t, a}

@unsafe
def act.insert.go(i: Ins) -> List<&2, Act>:
  match i:
    case Placed{list}: list
    case Passed{h, t, a}:
      match t:
        case Nil{}: Con{h, Con{a, Nil{}}}
        case Con{Act{c2, x2, y2, s2, b2, d2}, t2}:
          Act{ac, ax, ay, as, ab, ad} = a
          +cc = c2
          +acc = ac
          Con{h, act.insert.go(act.ins.pick(F32.is_ge(acc, cc), Act{acc, ax, ay, as, ab, ad}, Act{cc, x2, y2, s2, b2, d2}, t2))}

def act.insert(a: Act, xs: List<&2, Act>) -> List<&2, Act>:
  Act{ac, ax, ay, as, ab, ad} = a
  match xs:
    case Nil{}: Con{Act{ac, ax, ay, as, ab, ad}, Nil{}}
    case Con{Act{c2, x2, y2, s2, b2, d2}, t2}:
      +cc = c2
      +acc = ac
      act.insert.go(act.ins.pick(F32.is_ge(acc, cc), Act{acc, ax, ay, as, ab, ad}, Act{cc, x2, y2, s2, b2, d2}, t2))

def act.reverse(xs: List<&2, Act>, acc: List<&2, Act>) -> List<&2, Act>:
  match xs:
    case Nil{}: acc
    case Con{a, rest}: act.reverse(rest, Con{a, acc})

# The line as it will stand on scanline sy, placed into the descending list.
def act.keep(keep: Bool, +x0: F32, +y0: F32, +slope: F32, +bottom: F32, +dir: F32, +sy: F32, acc: List<&2, Act>) -> List<&2, Act>:
  match keep:
    case False{}: acc
    case True{}: act.insert(Act{(x0 + (sy - y0) * slope : F32), x0, y0, slope, bottom, dir}, acc)

# A line covers [top, bottom) so a shared vertex counts once; a horizontal line
# never crosses. Lines whose bottom the scanline has passed are dropped.
def act.add(l: CovLine, +sy: F32, acc: List<&2, Act>) -> List<&2, Act>:
  CovLine{x0, y0, x1, y1} = l
  +ax = x0
  +ay = y0
  +bx = x1
  +by = y1
  +up = F32.is_lt(ay, by)
  +bottom = U.max(ay, by)
  act.keep(F32.is_lt(sy, bottom) && Bool.not(F32.is_eq(ay, by)), ax, ay, ((bx - ax) / (by - ay) : F32), bottom, U.choose(F32, up, 1.0, F32.neg(1.0)), sy, acc)

# Lines from the sorted pending list whose top the scanline sy has reached.
type Take is Data:
  Take{done: Bool, pending: List<&2, CovLine>, acc: List<&2, Act>}

def take.pick(hit: Bool, l: CovLine, rest: List<&2, CovLine>, +sy: F32, acc: List<&2, Act>) -> Take:
  match hit:
    case True{}: Take{False{}, rest, act.add(l, sy, acc)}
    case False{}: Take{True{}, Con{l, rest}, acc}

@unsafe
def take.go(t: Take, +sy: F32) -> Take:
  match t:
    case Take{done, pending, acc}:
      match done:
        case True{}: Take{True{}, pending, acc}
        case False{}:
          match pending:
            case Nil{}: Take{True{}, Nil{}, acc}
            case Con{l, rest}:
              +ll = l
              take.go(take.pick(F32.is_le(line.top(ll), sy), ll, rest, sy, acc), sy)

# ---- span events ----
# A span [xa, xb) of weight w touches its two end cells directly (their partial
# overlap) and every cell between them in full. An event carries a direct
# contribution to one cell and a delta that applies to that cell and all cells
# to its right: +w at the first interior cell and -w at the last cell, so a
# span costs three events however wide it is. Events are kept in descending
# cell order (a walk goes left to right and prepends).

type CovEv is Data:
  CovEv{cell: U32, direct: F32, delta: F32}

def ev.push.if(skip: Bool, +cell: U32, +direct: F32, +delta: F32, acc: List<&2, CovEv>) -> List<&2, CovEv>:
  match skip:
    case True{}: acc
    case False{}: Con{CovEv{cell, direct, delta}, acc}

def ev.push(+cell: U32, +direct: F32, +delta: F32, acc: List<&2, CovEv>) -> List<&2, CovEv>:
  ev.push.if(F32.is_eq(direct, 0.0) && F32.is_eq(delta, 0.0), cell, direct, delta, acc)

def span.events.cells(one: Bool, +ia: U32, +ib: U32, +xa: F32, +xb: F32, +w: F32, acc: List<&2, CovEv>) -> List<&2, CovEv>:
  match one:
    case True{}: ev.push(ia, ((xb - xa) * w : F32), 0.0, acc)
    case False{}: ev.push(ib, ((xb - U32.to_f32(ib)) * w : F32), F32.neg(w), ev.push((ia + 1 : U32), 0.0, w, ev.push(ia, ((U32.to_f32(ia) + 1.0 - xa) * w : F32), 0.0, acc)))

# Events of the span [xa, xb) when it is inside; both ends lie within [0, width].
def span.events(inside: Bool, +xa: F32, +xb: F32, +w: F32, acc: List<&2, CovEv>) -> List<&2, CovEv>:
  match inside:
    case False{}: acc
    case True{}:
      +ia = F32.to_u32(F32.floor(xa))
      +ib = F32.to_u32(F32.floor(xb))
      span.events.cells(U32.is_ge(ia, ib), ia, ib, xa, xb, w, acc)

def winding.inside(+wind: F32, +even: Bool) -> Bool:
  U.choose(Bool, even, F32.is_gt(F32.abs((wind - 2.0 * F32.floor((wind / 2.0 : F32)) : F32)), 0.5), F32.is_gt(F32.abs(wind), 0.5))

# One scanline: walk the ascending list, emit the inside spans' events, and
# build the descending list for the next scanline sy2.
type Step is Data:
  Step{events: List<&2, CovEv>, next: List<&2, Act>}

@unsafe
def step(xs: List<&2, Act>, +sy2: F32, +wind: F32, +last: F32, +even: Bool, +weight: F32, evs: List<&2, CovEv>, acc: List<&2, Act>) -> Step:
  match xs:
    case Nil{}: Step{evs, acc}
    case Con{Act{cur, x0, y0, slope, bottom, dir}, rest}:
      +c = cur
      +d = dir
      +b = bottom
      step(rest, sy2, (wind + d : F32), c, even, weight, span.events(winding.inside(wind, even), last, c, weight, evs),
        act.keep(F32.is_lt(sy2, b), x0, y0, slope, b, d, sy2, acc))

# Merge two descending event lists, larger cells first.
type EvOrder is Data:
  EvOrder{first: CovEv, rest: List<&2, CovEv>, other: List<&2, CovEv>}

def ev.cell(+e: CovEv) -> U32:
  CovEv{cell, direct, delta} = e
  cell

def ev.order.pick(hit: Bool, x: CovEv, xt: List<&2, CovEv>, y: CovEv, yt: List<&2, CovEv>) -> EvOrder:
  match hit:
    case True{}: EvOrder{x, xt, Con{y, yt}}
    case False{}: EvOrder{y, yt, Con{x, xt}}

def ev.order(x: CovEv, xt: List<&2, CovEv>, y: CovEv, yt: List<&2, CovEv>) -> EvOrder:
  +xx = x
  +yy = y
  ev.order.pick(U32.is_ge(ev.cell(xx), ev.cell(yy)), xx, xt, yy, yt)

@unsafe
def ev.merge.go(o: EvOrder) -> List<&2, CovEv>:
  match o:
    case EvOrder{first, rest, other}:
      match rest:
        case Nil{}: Con{first, other}
        case Con{x, xt}:
          match other:
            case Nil{}: Con{first, Con{x, xt}}
            case Con{y, yt}: Con{first, ev.merge.go(ev.order(x, xt, y, yt))}

def ev.merge(xs: List<&2, CovEv>, ys: List<&2, CovEv>) -> List<&2, CovEv>:
  match xs:
    case Nil{}: ys
    case Con{x, xt}:
      match ys:
        case Nil{}: Con{x, xt}
        case Con{y, yt}: ev.merge.go(ev.order(x, xt, y, yt))

# ---- rows of runs ----
# A row's events, swept from the right, become runs [x0, x1) of one nonzero
# coverage value in ascending order; cells in no run are zero. Sweeping from
# the right, the coverage of a cell is the negated sum of the deltas to its
# right (all deltas of a row sum to zero) plus its direct contributions.

# Sums of a weight's multiples cancel exactly for power-of-two sub counts and
# to within rounding otherwise; noise below a millionth reads as empty.
def run.snap(+v: F32) -> F32:
  U.choose(F32, F32.is_lt(F32.abs(v), 0.000001), 0.0, v)

def runs.emit.join(join: Bool, +x0: U32, +x1: U32, +v: F32, +b: U32, head: Run, rest: List<&2, Run>) -> List<&2, Run>:
  match join:
    case True{}: Con{Run{x0, b, v}, rest}
    case False{}: Con{Run{x0, x1, v}, Con{head, rest}}

def runs.emit.some(skip: Bool, +x0: U32, +x1: U32, +v: F32, acc: List<&2, Run>) -> List<&2, Run>:
  match skip:
    case True{}: acc
    case False{}:
      match acc:
        case Nil{}: Con{Run{x0, x1, v}, Nil{}}
        case Con{Run{a, b, u}, rest}:
          +aa = a
          +bb = b
          +uu = u
          runs.emit.join(U32.is_eq(aa, x1) && F32.is_eq(uu, v), x0, x1, v, bb, Run{aa, bb, uu}, rest)

# Prepend the run [x0, x1) of value v, extending the head when they meet with one value.
def runs.emit(+x0: U32, +x1: U32, +v: F32, acc: List<&2, Run>) -> List<&2, Run>:
  runs.emit.some(U32.is_ge(x0, x1) || F32.is_eq(v, 0.0), x0, x1, v, acc)

# Sweep state: sum is the total delta at cells >= upper, the runs so far cover
# cells >= upper, and the open group collects the events of cell c.
type Sweep is Data:
  Sweep{sum: F32, upper: U32, c: U32, direct: F32, delta: F32, acc: List<&2, Run>}

# Close the group at c: the gap (c, upper) holds -sum, cell c adds its directs.
def sweep.flush(+sum: F32, +upper: U32, +c: U32, +direct: F32, acc: List<&2, Run>) -> List<&2, Run>:
  runs.emit(c, (c + 1 : U32), run.snap((direct - sum : F32)), runs.emit((c + 1 : U32), upper, run.snap(F32.neg(sum)), acc))

def sweep.step(same: Bool, +cell: U32, +direct: F32, +delta: F32, +sum: F32, +upper: U32, +c: U32, +dsum: F32, +dlsum: F32, acc: List<&2, Run>) -> Sweep:
  match same:
    case True{}: Sweep{sum, upper, c, (dsum + direct : F32), (dlsum + delta : F32), acc}
    case False{}: Sweep{(sum + dlsum : F32), c, cell, direct, delta, sweep.flush(sum, upper, c, dsum, acc)}

@unsafe
def sweep(st: Sweep, evs: List<&2, CovEv>) -> List<&2, Run>:
  Sweep{sum, upper, c, dsum, dlsum, acc} = st
  match evs:
    case Nil{}: sweep.flush(sum, upper, c, dsum, acc)
    case Con{CovEv{cell, direct, delta}, rest}:
      +cc = c
      +ce = cell
      sweep(sweep.step(U32.is_eq(ce, cc), ce, direct, delta, sum, upper, cc, dsum, dlsum, acc), rest)

# The runs of a row of width w from its descending events.
def row.runs(evs: List<&2, CovEv>, +w: U32) -> List<&2, Run>:
  sweep(Sweep{0.0, w, w, 0.0, 0.0, Nil{}}, evs)

# ---- sorting lines by top ----

type LineOrder is Data:
  LineOrder{first: CovLine, rest: List<&2, CovLine>, other: List<&2, CovLine>}

def lines.order.pick(hit: Bool, x: CovLine, xt: List<&2, CovLine>, y: CovLine, yt: List<&2, CovLine>) -> LineOrder:
  match hit:
    case True{}: LineOrder{x, xt, Con{y, yt}}
    case False{}: LineOrder{y, yt, Con{x, xt}}

def lines.order(x: CovLine, xt: List<&2, CovLine>, y: CovLine, yt: List<&2, CovLine>) -> LineOrder:
  +xx = x
  +yy = y
  lines.order.pick(F32.is_le(line.top(xx), line.top(yy)), xx, xt, yy, yt)

@unsafe
def lines.merge.go(o: LineOrder) -> List<&2, CovLine>:
  match o:
    case LineOrder{first, rest, other}:
      match rest:
        case Nil{}: Con{first, other}
        case Con{x, xt}:
          match other:
            case Nil{}: Con{first, Con{x, xt}}
            case Con{y, yt}: Con{first, lines.merge.go(lines.order(x, xt, y, yt))}

def lines.merge(xs: List<&2, CovLine>, ys: List<&2, CovLine>) -> List<&2, CovLine>:
  match xs:
    case Nil{}: ys
    case Con{x, xt}:
      match ys:
        case Nil{}: Con{x, xt}
        case Con{y, yt}: lines.merge.go(lines.order(x, xt, y, yt))

type LineSplit is Data:
  LineSplit{left: List<&2, CovLine>, right: List<&2, CovLine>}

def lines.deal(xs: List<&2, CovLine>, left: List<&2, CovLine>, right: List<&2, CovLine>) -> LineSplit:
  match xs:
    case Nil{}: LineSplit{left, right}
    case Con{x, Nil{}}: LineSplit{Con{x, left}, right}
    case Con{x, Con{y, rest}}: lines.deal(rest, Con{x, left}, Con{y, right})

# Merge sort by top.
@unsafe
def lines.sort.go(s: LineSplit) -> List<&2, CovLine>:
  match s:
    case LineSplit{left, right}:
      match right:
        case Nil{}: left
        case Con{y, yt}: lines.merge(lines.sort.go(lines.deal(left, Nil{}, Nil{})), lines.sort.go(lines.deal(Con{y, yt}, Nil{}, Nil{})))

def lines.sort(xs: List<&2, CovLine>) -> List<&2, CovLine>:
  lines.sort.go(lines.deal(xs, Nil{}, Nil{}))

# ---- the scan ----
# The active list stands at the current scanline; each step walks it, merges
# the scanline's events into the row's, and readies the list for the next
# scanline, taking the lines that start before it. The rows list is built top
# row last (prepended) and reversed at the end.

type Subs is Data:
  Subs{active: List<&2, Act>, pending: List<&2, CovLine>, events: List<&2, CovEv>}

def subs.done(t: Take, events: List<&2, CovEv>) -> Subs:
  Take{done, pending, acc} = t
  Subs{act.reverse(acc, Nil{}), pending, events}

def subs.after(s: Step, pending: List<&2, CovLine>, +sy2: F32, events: List<&2, CovEv>) -> Subs:
  Step{evs, acc} = s
  subs.done(take.go(Take{False{}, pending, acc}, sy2), ev.merge(evs, events))

def subs.step(st: Subs, +sy: F32, +dy: F32, +even: Bool, +weight: F32) -> Subs:
  Subs{active, pending, events} = st
  +sy2 = (sy + dy : F32)
  subs.after(step(active, sy2, 0.0, 0.0, even, weight, Nil{}, Nil{}), pending, sy2, events)

@unsafe
def scan.subs(st: Subs, n: Nat, +sy: F32, +dy: F32, +even: Bool, +weight: F32) -> Subs:
  match n:
    case 0n: st
    case 1n+d: scan.subs(subs.step(st, sy, dy, even, weight), d, (sy + dy : F32), dy, even, weight)

type Scan is Data:
  Scan{rows: List<&2, List<&2, Run>>, active: List<&2, Act>, pending: List<&2, CovLine>}

def scan.row.done(st: Subs, rows: List<&2, List<&2, Run>>, +w: U32) -> Scan:
  Subs{active, pending, events} = st
  Scan{Con{row.runs(events, w), rows}, active, pending}

def scan.row(st: Scan, +y: U32, +sub: U32, +even: Bool, +w: U32) -> Scan:
  Scan{rows, active, pending} = st
  +dy = (1.0 / U32.to_f32(sub) : F32)
  scan.row.done(scan.subs(Subs{active, pending, Nil{}}, U32.to_nat(sub), (U32.to_f32(y) + dy * 0.5 : F32), dy, even, dy), rows, w)

@unsafe
def scan.rows.go(st: Scan, n: Nat, +y: U32, +sub: U32, +even: Bool, +w: U32) -> Scan:
  match n:
    case 0n: st
    case 1n+d: scan.rows.go(scan.row(st, y, sub, even, w), d, (y + 1 : U32), sub, even, w)

def rows.reverse(rows: List<&2, List<&2, Run>>, acc: List<&2, List<&2, Run>>) -> List<&2, List<&2, Run>>:
  match rows:
    case Nil{}: acc
    case Con{r, rest}: rows.reverse(rest, Con{r, acc})

def scan.done(st: Scan) -> List<&2, List<&2, Run>>:
  Scan{rows, active, pending} = st
  rows.reverse(rows, Nil{})

def scan.start(t: Take) -> Scan:
  Take{done, pending, acc} = t
  Scan{Nil{}, act.reverse(acc, Nil{}), pending}

# The rows of runs (top first) of the lines over a width by height grid.
def scan.rows(+h: U32, +sub: U32, +xs: List<&2, CovLine>, +even: Bool, +w: U32) -> List<&2, List<&2, Run>>:
  scan.done(scan.rows.go(scan.start(take.go(Take{False{}, lines.sort(xs), Nil{}}, (0.5 / U32.to_f32(sub) : F32))), U32.to_nat(h), 0, sub, even, w))

# ---- the tree ----
# A node is built top-down from the rows of runs that lie inside it, clipped
# to its columns. One pass over a node's rows tells whether it is uniform (no
# runs, or in every row one run spanning the node with the same value) and at
# the same time splits the rows into the four quarters, each row's runs cut at
# the middle column, so no list is shared between the node and its children
# and a uniform node's rows are never looked at again.

# A row's runs cut at mid into the left and right halves, with the row's
# uniform value over [x0, x1): 0 for no runs, the value of a single run that
# spans the columns, -1 otherwise.
type Halves is Data:
  Halves{value: F32, left: List<&2, Run>, right: List<&2, Run>}

def halves.place(onLeft: Bool, onRight: Bool, +v: F32, +a: U32, +b: U32, +u: F32, +mid: U32, left: List<&2, Run>, right: List<&2, Run>) -> Halves:
  match onLeft onRight:
    case True{} _: Halves{v, Con{Run{a, b, u}, left}, right}
    case False{} True{}: Halves{v, left, Con{Run{a, b, u}, right}}
    case False{} False{}: Halves{v, Con{Run{a, mid, u}, left}, Con{Run{mid, b, u}, right}}

def halves.push(h: Halves, +a: U32, +b: U32, +u: F32, +mid: U32, +x0: U32, +x1: U32) -> Halves:
  match h:
    case Halves{value, left, right}:
      +vv = value
      +full = F32.is_eq(vv, 0.0) && U32.is_eq(a, x0) && U32.is_eq(b, x1)
      halves.place(U32.is_le(b, mid), U32.is_ge(a, mid), U.choose(F32, full, u, F32.neg(1.0)), a, b, u, mid, left, right)

def runs.halves(rs: List<&2, Run>, +mid: U32, +x0: U32, +x1: U32) -> Halves:
  match rs:
    case Nil{}: Halves{0.0, Nil{}, Nil{}}
    case Con{Run{a, b, u}, rest}: halves.push(runs.halves(rest, mid, x0, x1), a, b, u, mid, x0, x1)

# A node's uniform value (2 before any row, -1 once rows disagree) and its
# quarters' rows; flat holds when the node is uniform (no rows means empty).
type Node is Data:
  Node{flat: Bool, value: F32, tl: List<&2, List<&2, Run>>, tr: List<&2, List<&2, Run>>, bl: List<&2, List<&2, Run>>, br: List<&2, List<&2, Run>>}

def node.push(n: Node, h: Halves, top: Bool) -> Node:
  Node{flat, value, tl, tr, bl, br} = n
  Halves{v, left, right} = h
  match top:
    case True{}: Node{flat, tree.same.as(value, v), Con{left, tl}, Con{right, tr}, bl, br}
    case False{}: Node{flat, tree.same.as(value, v), tl, tr, Con{left, bl}, Con{right, br}}

# Rows past the end of the list are empty; row i of size is a top row when i < half.
def node.rows(rows: List<&2, List<&2, Run>>, +i: U32, +size: U32, +half: U32, +x0: U32) -> Node:
  match rows:
    case Nil{}: Node{False{}, U.choose(F32, U32.is_lt(i, size), 0.0, 2.0), Nil{}, Nil{}, Nil{}, Nil{}}
    case Con{r, rest}: node.push(node.rows(rest, (i + 1 : U32), size, half, x0), runs.halves(r, (x0 + half : U32), x0, (x0 + size : U32)), U32.is_lt(i, half))

def node.mark(n: Node) -> Node:
  Node{flat, value, tl, tr, bl, br} = n
  +vv = value
  Node{Bool.not(F32.is_lt(vv, 0.0)), vv, tl, tr, bl, br}

def node.of(rows: List<&2, List<&2, Run>>, +size: U32, +x0: U32) -> Node:
  node.mark(node.rows(rows, 0, size, U32.div(size, 2), x0))

def node.value(+v: F32) -> F32:
  U.choose(F32, F32.is_gt(v, 1.5), 0.0, v)

@unsafe
def tree.node(n: Node, depth: Nat, +x0: U32, +size: U32) -> CovTree:
  match n:
    case Node{flat, value, tl, tr, bl, br}:
      match flat:
        case True{}: CovFlat{node.value(value)}
        case False{}:
          match depth:
            case 0n: CovFlat{node.value(value)}
            case 1n+d:
              +dd = d
              +half = U32.shln(1, dd)
              +x1 = (x0 + half : U32)
              CovQuad{tree.node(node.of(tl, half, x0), dd, x0, half), tree.node(node.of(tr, half, x1), dd, x1, half),
                tree.node(node.of(bl, half, x0), dd, x0, half), tree.node(node.of(br, half, x1), dd, x1, half)}

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

def mask.data(trees: Bool, rows: List<&2, List<&2, Run>>, +size: U32, +depth: Nat) -> CovData:
  match trees:
    case True{}: CovTreed{tree.node(node.of(rows, size, 0), depth, 0, size)}
    case False{}: CovRows{rows}

def mask.build(+xs: List<&2, CovLine>, +gx: U32, +gy: U32, +w: U32, +h: U32, +even: Bool, +sub: U32, +trees: Bool) -> CovMask:
  +side = U.choose(U32, U32.is_gt(w, h), w, h)
  +depth = depth.for(side, 1, 0n)
  +size = U32.shln(1, depth)
  CovMask{gx, gy, size, depth, mask.data(trees, scan.rows(h, sub, lines.clip(xs, U32.to_f32(w)), even, w), size, depth), True{}}

def mask.box(+xs: List<&2, CovLine>, +even: Bool, +width: U32, +height: U32, +sub: U32, box: CovBox, +trees: Bool) -> CovMask:
  CovBox{x0, y0, x1, y1} = box
  +gx = F32.to_u32(U.clamp(F32.floor(x0), 0.0, U32.to_f32(width)))
  +gy = F32.to_u32(U.clamp(F32.floor(y0), 0.0, U32.to_f32(height)))
  +ex = F32.to_u32(U.clamp(F32.ceil(x1), 0.0, U32.to_f32(width)))
  +ey = F32.to_u32(U.clamp(F32.ceil(y1), 0.0, U32.to_f32(height)))
  U.branch(CovMask, U32.is_ge(gx, ex) || U32.is_ge(gy, ey), _ => CovMask{0, 0, 0, 0n, CovTreed{CovFlat{0.0}}, True{}},
    _ => mask.build(lines.shift(xs, U32.to_f32(gx), U32.to_f32(gy)), gx, gy, (ex - gx : U32), (ey - gy : U32), even, sub, trees))

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

# A full rectangle as rows: one run per row.
def rect.rows(n: Nat, +w: U32, acc: List<&2, List<&2, Run>>) -> List<&2, List<&2, Run>>:
  match n:
    case 0n: acc
    case 1n+d: rect.rows(d, w, Con{Con{Run{0, w, 1.0}, Nil{}}, acc})

def rect.data(trees: Bool, +depth: Nat, +w: U32, +h: U32) -> CovData:
  match trees:
    case True{}: CovTreed{tree.rect(depth, 0, 0, w, h)}
    case False{}: CovRows{rect.rows(U32.to_nat(h), w, Nil{})}

def mask.rect(+width: U32, +height: U32, +box: CovBox, +trees: Bool) -> CovMask:
  CovBox{x0, y0, x1, y1} = box
  +gx = F32.to_u32(U.clamp(x0, 0.0, U32.to_f32(width)))
  +gy = F32.to_u32(U.clamp(y0, 0.0, U32.to_f32(height)))
  +ex = F32.to_u32(U.clamp(x1, 0.0, U32.to_f32(width)))
  +ey = F32.to_u32(U.clamp(y1, 0.0, U32.to_f32(height)))
  +w = (ex - gx : U32)
  +h = (ey - gy : U32)
  +depth = depth.for(U.choose(U32, U32.is_gt(w, h), w, h), 1, 0n)
  U.branch(CovMask, U32.is_ge(gx, ex) || U32.is_ge(gy, ey), _ => CovMask{0, 0, 0, 0n, CovTreed{CovFlat{0.0}}, True{}},
    _ => CovMask{gx, gy, U32.shln(1, depth), depth, rect.data(trees, depth, w, h), True{}})

def mask.shape(aligned: Bool, +xs: List<&2, CovLine>, +even: Bool, +width: U32, +height: U32, +sub: U32, +box: CovBox, +trees: Bool) -> CovMask:
  match aligned:
    case True{}: mask.rect(width, height, box, trees)
    case False{}: mask.box(xs, even, width, height, sub, box, trees)

# Rasterize closed contours given as directed lines in pixel coordinates of a
# width by height grid, with `sub` scanlines per pixel row; nonzero winding, or
# even-odd when `even` holds.
# even-odd when `even` holds; with `trees` the mask carries the quadtree that
# block and pixel queries need, else only its rows of runs.
def mask(+xs: List<&2, CovLine>, +even: Bool, +width: U32, +height: U32, +sub: U32, +trees: Bool) -> CovMask:
  +box = lines.bounds(xs, 1000000000.0, 1000000000.0, F32.neg(1000000000.0), F32.neg(1000000000.0))
  mask.shape(rect.aligned(xs, box), xs, even, width, height, sub, box, trees)

def mask.scanned(+xs: List<&2, CovLine>, +even: Bool, +width: U32, +height: U32, +sub: U32, +trees: Bool) -> CovMask:
  mask.box(xs, even, width, height, sub, lines.bounds(xs, 1000000000.0, 1000000000.0, F32.neg(1000000000.0), F32.neg(1000000000.0)), trees)
