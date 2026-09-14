# Reproduction for a runtime fault after the byte-read effect: this file
# faults with "memory fault (machine stack overflow?)" in a native build,
# while repro-bytes-read-fault-ok.bend, the same scan over a hand-built array,
# prints. Build with `bun <bend2>/main.ts <file> -o out` from this
# directory (beside bin.bend, whose effect names the constructors) and run with V=0. The anchor below only keeps the tree's
# constructors defined for the effect's C code.
import Base
import ./util.bend as U
import ./bin.bend as Bin

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
  U.rev.decode(s, "") ++ U32.show((v + j + sizeof(Array.size(U32, a)) : U32))

def main() -> IO(Unit):
  do IO<Unit>:
    v : String <- IO.try(String, IO.get_env("V"))
    IO.print(show(text.read(key.at(Array.set(U32, Array.set(U32, Array.set(U32, Array.new(U32, 3n, 0), 0, 97), 1, 98), 2, 99), 0, 0), ""), F32.to_u32(U.scalar(v, 0.0))))
