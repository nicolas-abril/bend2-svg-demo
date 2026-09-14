# Reproduction for a runtime fault after the byte-read effect: this file
# faults with "memory fault (machine stack overflow?)" in a native build,
# while repro-bytes-read-fault-ok.bend, the same scan over a hand-built array,
# prints. Build with `bun <bend2>/main.ts <file> -o out` from this
# directory (beside bin.bend, whose effect names the constructors) and
# run with V=0.
import Base
import ./util.bend as U
import ./bin.bend as Bin

@unsafe
def array.depth(+size: U32, +side: U32, +depth: Nat) -> Nat:
  U.branch(Nat, U32.is_ge(side, size), _ => depth, _ => array.depth(size, (side * 2 : U32), 1n+depth))

def array.word(a: Array<U32>, +base: U32, +w: U32) -> Array<U32>:
  Array.set(U32, Array.set(U32, Array.set(U32, Array.set(U32, a, base, U32.mod(w, 256)), (base + 1 : U32), U32.mod(U32.div(w, 256), 256)), (base + 2 : U32), U32.mod(U32.div(w, 65536), 256)), (base + 3 : U32), U32.mod(U32.div(w, 16777216), 256))

@unsafe
def array.run(a: Array<U32>, +base: U32, +n: U32, +v: U32) -> Array<U32>:
  match n:
    case 0: a
    case _: array.run(Array.set(U32, a, base, v), (base + 1 : U32), (n - 1 : U32), v)

def array.flat(v: U32, a: Array<U32>, +base: U32, +n: U32) -> Array<U32>:
  match v:
    case 0: a
    case _: array.run(a, base, n, v)

@unsafe
def array.fill(t: Bin.ByteTree, +cap: U32, +base: U32, a: Array<U32>) -> Array<U32>:
  match t:
    case Bin.ByteFlat{v}: array.flat(v, a, base, cap)
    case Bin.ByteWord{w}: array.word(a, base, w)
    case Bin.ByteNode{l, r}:
      +half = (cap / 2 : U32)
      array.fill(r, half, (base + half : U32), array.fill(l, half, base, a))

# The bytes as an array with at least two zero slots past the end.
def array.of.bytes(b: Bin.Bytes) -> Array<U32>:
  Bin.Bytes{bt, size, cap} = b
  +c = cap
  array.fill(bt, c, 0, Array.new(U32, array.depth((c + 2 : U32), 1, 0n), 0))

def sizeof(got: Array<U32> & U32) -> U32:
  (a, n) = got
  n

type Keyed is Data:
  Keyed{key: U32, c: U32, mode: U32, i: U32}

def key.of(got: Array<U32> & U32, +i: U32, +mode: U32) -> Array<U32> & Keyed:
  (a, c) = got
  +cc = {c : U32}
  (a, Keyed{U.choose(U32, U32.is_eq(mode, 0), cc, (mode * 256 : U32)), cc, mode, i})

def key.at(a: Array<U32>, +i: U32, +mode: U32) -> Array<U32> & Keyed:
  key.of(Array.get(U32, a, i), i, mode)

def key.next(a: Array<U32>, +i: U32, +mode: U32) -> Array<U32> & Keyed:
  key.of(Array.get(U32, a, (i + 1 : U32)), (i + 1 : U32), mode)

# The text loop, reduced: bytes up to a '<' or the end, reversed.
@unsafe
def text.read(st: Array<U32> & Keyed, acc: String) -> Array<U32> & (String & U32):
  (a, w) = st
  match w:
    case Keyed{key, c, mode, i}:
      match key:
        case 60: (a, (acc, i))
        case 0: (a, (acc, i))
        case _: text.read(key.next(a, i, 0), SCon{Chr{c}, acc})

def show(got: Array<U32> & (String & U32), +v: U32) -> String:
  (a, (s, j)) = got
  U32.show((v + j + sizeof(Array.size(U32, a)) : U32))

def run(got: Result<&1, &1, U32 & String, Bin.Bytes>, +v: U32) -> String:
  match got:
    case Fail{err}: "fail"
    case Done{b}: show(text.read(key.at(array.of.bytes(b), 0, 0), ""), v)

def main() -> IO(Unit):
  do IO<Unit>:
    v : String <- IO.try(String, IO.get_env("V"))
    got : Result<&1, &1, U32 & String, Bin.Bytes> <- Bin.bytes.read("/private/tmp/claude-501/-Users-macolas-Software-bend2-core/cfc0abc6-25af-4bd4-98fd-e896077241fc/scratchpad/iso/t2.svg")
    IO.print(run(got, F32.to_u32(U.scalar(v, 0.0))))
