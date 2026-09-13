# Text scanning, number parsing and small list helpers shared by the SVG libraries.
import Base

def choose(-A: Type, yes: Bool, a: A, b: A) -> A:
  match yes:
    case True{}: a
    case False{}: b

def min(+a: F32, +b: F32) -> F32:
  choose(F32, F32.is_lt(a, b), a, b)

def max(+a: F32, +b: F32) -> F32:
  choose(F32, F32.is_gt(a, b), a, b)

def clamp(x: F32, lo: F32, hi: F32) -> F32:
  max(lo, min(hi, x))

def code(c: Char) -> U32:
  Chr{x} = c
  x

def space(+c: U32) -> Bool:
  U32.is_eq(c, 32) || U32.is_eq(c, 9) || U32.is_eq(c, 10) || U32.is_eq(c, 13)

def digit(+c: U32) -> Bool:
  U32.is_ge(c, 48) && U32.is_le(c, 57)

def rev(s: String, acc: String) -> String:
  match s:
    case SNil{}: acc
    case SCon{c, t}: rev(t, SCon{c, acc})

# Consume equality inputs without rebuilding borrowed strings on the host stack.
@unsafe
def string.equal.go(same: Bool, a: String, b: String) -> Bool:
  match same a b:
    case False{} _ _: False{}
    case True{} SNil{} SNil{}: True{}
    case True{} SCon{Chr{x}, xs} SCon{Chr{y}, ys}: string.equal.go(U32.is_eq(x, y), xs, ys)
    case True{} _ _: False{}

def string.equal(a: String, b: String) -> Bool:
  string.equal.go(True{}, a, b)

def branch(-A: Type, yes: Bool, a: Unit -> A, b: Unit -> A) -> A:
  match yes:
    case True{}: a(Unit{})
    case False{}: b(Unit{})

def trim(+s: String) -> String:
  match s:
    case SNil{}: ""
    case SCon{Chr{c}, t}:
      branch(String, space(c), _ => trim(t), _ => SCon{Chr{c}, t})

type Scan is Data:
  Scan{head: String, tail: String}

def until(+s: String, +end: U32, +acc: String) -> Scan:
  match s:
    case SNil{}: Scan{rev(acc, ""), ""}
    case SCon{Chr{c}, t}:
      branch(Scan, U32.is_eq(c, end),
        _ => Scan{rev(acc, ""), t},
        _ => until(t, end, SCon{Chr{c}, acc}))

# XML tokenizer and document tree. Attribute values remain available to the editor.
def prefix(s: String, p: String) -> Bool:
  match s p:
    case _ SNil{}: True{}
    case SNil{} SCon{pc, pt}: False{}
    case SCon{sc, st} SCon{pc, pt}:
      U32.is_eq(code(sc), code(pc)) && prefix(st, pt)

def drop(s: String, p: String) -> String:
  match s p:
    case s SNil{}: s
    case SNil{} SCon{pc, pt}: ""
    case SCon{sc, st} SCon{pc, pt}: drop(st, pt)

def through(+s: String, +p: String) -> String:
  match s:
    case SNil{}: ""
    case SCon{sc, st}:
      branch(String, prefix(s, p), _ => drop(s, p), _ => through(st, p))

def until.sequence(+s: String, +end: String, +acc: String) -> Scan:
  match s:
    case SNil{}: Scan{rev(acc, ""), ""}
    case SCon{c, t}: branch(Scan, prefix(s, end), _ => Scan{rev(acc, ""), drop(s, end)}, _ => until.sequence(t, end, SCon{c, acc}))

# SVG number grammar, including adjacent signs and scientific notation.
def separators(+s: String) -> String:
  match s:
    case SNil{}: ""
    case SCon{Chr{c}, t}:
      branch(String, space(c) || U32.is_eq(c, 44), _ => separators(t), _ => s)

def number.exponent(+s: String) -> Bool:
  match s:
    case SNil{}: False{}
    case SCon{Chr{c}, t}:
      match t:
        case SNil{}: digit(c)
        case SCon{Chr{d}, rest}: digit(c) || ((U32.is_eq(c, 43) || U32.is_eq(c, 45)) && digit(d))

def number.scan(+s: String, +acc: String, +sign: Bool, +dot: Bool, +exp: Bool, +digits: Bool) -> Scan:
  match s:
    case SNil{}: Scan{rev(acc, ""), ""}
    case SCon{Chr{c}, t}:
      +isDot = U32.is_eq(c, 46)
      +isExp = U32.is_eq(c, 101) || U32.is_eq(c, 69)
      branch(Scan, digit(c) || (isDot && Bool.not(dot || exp))
        || (isExp && digits && Bool.not(exp) && number.exponent(t))
        || (sign && (U32.is_eq(c, 43) || U32.is_eq(c, 45))),
        _ => number.scan(t, SCon{Chr{c}, acc}, isExp, dot || isDot, exp || isExp, digits || digit(c)),
        _ => Scan{rev(acc, ""), s})

type Number is Data:
  Number{value: F32, tail: String, valid: Bool}

def number.value(t: String, v: Maybe<&2, F32>) -> Number:
  match v:
    case None{}: Number{0.0, t, False{}}
    case Some{x}: Number{x, t, True{}}

def number.read(scan: Scan) -> Number:
  Scan{h, t} = scan
  number.value(t, F32.read(h))

def number(s: String) -> Number:
  number.read(number.scan(separators(s), "", True{}, False{}, False{}, False{}))

def number.default(num: Number, fallback: F32) -> F32:
  Number{x, t, valid} = num
  choose(F32, valid, x, fallback)

def scalar(s: String, fallback: F32) -> F32:
  number.default(number(s), fallback)

def numbers.next(num: Number, next: String -> List<&2, F32>) -> List<&2, F32>:
  Number{x, t, valid} = num
  choose(Unit -> List<&2, F32>, valid, _ => Con{x, next(t)}, _ => Nil{})(Unit{})

@unsafe
def numbers(s: String) -> List<&2, F32>:
  numbers.next(number(s), t => numbers(t))

def nth(xs: List<&2, F32>, i: Nat, fallback: F32) -> F32:
  match xs i:
    case Nil{} _: fallback
    case Con{h, t} 0n: h
    case Con{h, t} 1n+p: nth(t, p, fallback)

def uints.nth(xs: List<&2, U32>, n: Nat, +fallback: U32) -> U32:
  match xs n:
    case Nil{} _: fallback
    case Con{h, t} 0n: h
    case Con{h, t} 1n+d: uints.nth(t, d, fallback)

def hex.digit(+c: U32) -> U32:
  choose(U32, digit(c), (c - 48 : U32),
    choose(U32, U32.is_ge(c, 65) && U32.is_le(c, 70), (c - 55 : U32),
      choose(U32, U32.is_ge(c, 97) && U32.is_le(c, 102), (c - 87 : U32), 0)))

def hex(s: String, acc: U32) -> U32:
  match s:
    case SNil{}: acc
    case SCon{Chr{c}, t}: hex(t, (acc * 16 + hex.digit(c) : U32))

def trim.both(s: String) -> String:
  rev(trim(rev(trim(s), "")), "")

def unit(num: Number, reference: F32) -> F32:
  Number{x, t, ok} = num
  +v = x
  +u = t
  (v * choose(F32, prefix(u, "%"), (reference / 100.0 : F32),
    choose(F32, prefix(u, "in"), 96.0,
      choose(F32, prefix(u, "cm"), 37.7952755906,
        choose(F32, prefix(u, "mm"), 3.77952755906,
          choose(F32, prefix(u, "pt"), 1.333333333333,
            choose(F32, prefix(u, "pc"), 16.0, 1.0)))))) : F32)

def string.contains(+s: String, +part: String) -> Bool:
  match s:
    case SNil{}: string.equal(part, "")
    case SCon{c, rest}: prefix(s, part) || string.contains(rest, part)

def scan.head(s: Scan) -> String:
  Scan{h, t} = s
  h

def unquote(+s: String) -> String:
  branch(String, prefix(s, "'"), _ => scan.head(until(drop(s, "'"), 39, "")),
    _ => branch(String, prefix(s, "\""), _ => scan.head(until(drop(s, "\""), 34, "")), _ => s))

# Expand local use shadow trees for rendering, while retaining source separately.
def strings.has(xs: List<&2, String>, +s: String) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{h, t}: branch(Bool, string.equal(h, s), _ => True{}, _ => strings.has(t, s))
