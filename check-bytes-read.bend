import Base
import ./util.bend as U
import ./bin.bend as Bin

# The PNG signature and size of a binary fixture read through bytes.read.
def describe(+b: Bin.Bytes) -> String:
  U32.show(Bin.bytes.size(b)) ++ " " ++ U32.show(Bin.bytes.be(b, 0, 4n, 0)) ++ " " ++ U32.show(Bin.bytes.get(b, 4))

def show(got: Result<&1, &1, U32 & String, Bin.Bytes>) -> String:
  match got:
    case Fail{err}: "fail"
    case Done{b}: describe(b)

def main() -> IO(Unit):
  do IO<Unit>:
    got : Result<&1, &1, U32 & String, Bin.Bytes> <- Bin.bytes.read("validation/fonts/NotoSans-Regular.ttf")
    missing : Result<&1, &1, U32 & String, Bin.Bytes> <- Bin.bytes.read("validation/fonts/none.ttf")
    Unit <- IO.print(show(got))
    IO.print(show(missing))

#|569208 65536 0
#|fail
