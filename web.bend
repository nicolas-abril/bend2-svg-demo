# A local HTTP server for the same Bend editor. Responses contain pixel matrices.
import Base
import ./svg.bend as SVG
import ./util.bend as U
import ./state.bend as Editor

def contains(+s: String, +needle: String) -> Bool:
  match s:
    case SNil{}: String.eq(needle, "")
    case SCon{c, t}: U.branch(Bool, U.prefix(s, needle), _ => True{}, _ => contains(t, needle))

def lowercase(s: String) -> String:
  match s:
    case SNil{}: ""
    case SCon{Chr{c}, t}:
      +ch = c
      SCon{Chr{U.choose(U32, U32.is_ge(ch, 65) && U32.is_le(ch, 90), (ch + 32 : U32), ch)}, lowercase(t)}

def header.line(scan: U.Scan, next: String -> U32) -> U32:
  U.Scan{line, rest} = scan
  +s = lowercase(line)
  U.choose(Unit -> U32, U.prefix(s, "content-length:"),
    _ => F32.to_u32(U.scalar(U.drop(s, "content-length:"), 0.0)), _ => next(rest))(Unit{})

@unsafe
def content.length(s: String) -> U32:
  match s:
    case SNil{}: 0
    case SCon{c, t}: header.line(U.until(SCon{c, t}, 10, ""), rest => content.length(rest))

def request.complete(+s: String) -> Bool:
  contains(s, "\r\n\r\n") && U32.is_ge(SVG.length(U.through(s, "\r\n\r\n")), content.length(s))

def request.chunk(socket: Socket, +text: String, next: Socket -> String -> IO(Socket & String)) -> IO(Socket & String):
  action = U.choose(Socket -> IO(Socket & String), request.complete(text) || U32.is_gt(SVG.length(text), 4194304),
    s => IO.pure(Socket & String, (s, text)), s => next(s)(text))
  action(socket)

def request.got(got: Socket & Result<&1, &1, U32 & String, String>, acc: String,
  next: Socket -> String -> IO(Socket & String)) -> IO(Socket & String):
  (socket, result) = got
  match result:
    case Fail{err}: IO.pure(Socket & String, (socket, ""))
    case Done{data}:
      match data:
        case SNil{}: IO.pure(Socket & String, (socket, ""))
        case SCon{c, t}: request.chunk(socket, acc ++ SCon{c, t}, next)

@unsafe
def request.read(socket: Socket, acc: String) -> IO(Socket & String):
  do IO<Socket & String>:
    got : Socket & Result<&1, &1, U32 & String, String> <- TCP.recv(socket, 65536)
    request.got(got, acc, s => text => request.read(s, text))

def utf8.count(s: String, acc: U32) -> U32:
  match s:
    case SNil{}: acc
    case SCon{Chr{c}, t}:
      +ch = c
      utf8.count(t, (acc + U.choose(U32, U32.is_lt(ch, 128), 1, U.choose(U32, U32.is_lt(ch, 2048), 2,
        U.choose(U32, U32.is_lt(ch, 65536), 3, 4))) : U32))

def utf8.length(s: String) -> U32:
  utf8.count(s, 0)

def response(contentType: String, +body: String) -> String:
  "HTTP/1.1 200 OK\r\nConnection: close\r\nCache-Control: no-store\r\nContent-Type: " ++ contentType
    ++ "\r\nContent-Length: " ++ U32.show(utf8.length(body)) ++ "\r\n\r\n" ++ body

def response.done(got: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (socket, result) = got
  Socket.close(socket)

def send(socket: Socket, body: String) -> IO(Unit):
  do IO<Unit>:
    sent : Socket & Result<&1, &1, U32 & String, Unit> <- TCP.send(socket, body)
    response.done(sent)

def request.state(+request: String, +state: Editor.State) -> Editor.State:
  U.branch(Editor.State, U.prefix(request, "POST /event "),
    _ => Editor.apply(state, Editor.input(Editor.wire.decode(U.through(request, "\r\n\r\n")))), _ => state)

def request.body(+request: String, +state: Editor.State, html: String) -> String:
  U.branch(String, U.prefix(request, "GET /source "),
    _ => response("text/plain; charset=utf-8", Editor.get.source(state)),
    _ => U.branch(String, U.prefix(request, "GET /frame ") || U.prefix(request, "POST /event "),
      _ => response("text/plain; charset=utf-8", Editor.frame(state)),
      _ => response("text/html; charset=utf-8", html)))

def request.handle(got: Socket & String, state: Editor.State, html: String) -> IO(Editor.State):
  (socket, request) = got
  +req = request
  +next = request.state(req, state)
  do IO<Editor.State>:
    Unit <- send(socket, request.body(req, next, html))
    return next

def accepted(got: Listener & Result<&1, &1, U32 & String, Socket>, state: Editor.State, html: String) -> IO(Listener & Editor.State):
  (listener, result) = got
  do IO<Listener & Editor.State>:
    socket : Socket <- IO.pass(Socket, result)
    request : Socket & String <- request.read(socket, "")
    next : Editor.State <- request.handle(request, state, html)
    return (listener, next)

def serve.next(got: Listener & Editor.State, next: Listener -> Editor.State -> IO(Unit)) -> IO(Unit):
  (listener, state) = got
  next(listener)(state)

@unsafe
def serve(listener: Listener, state: Editor.State, +html: String) -> IO(Unit):
  do IO<Unit>:
    connection : Listener & Result<&1, &1, U32 & String, Socket> <- TCP.accept(listener)
    next : Listener & Editor.State <- accepted(connection, state, html)
    serve.next(next, l => s => serve(l, s, html))

def main() -> IO(Unit):
  do IO<Unit>:
    state : Editor.State <- Editor.initial()
    html : String <- Editor.read("web.html")
    listener : Listener <- IO.try(Listener, TCP.listen(8088))
    Unit <- IO.print("Bend SVG: http://127.0.0.1:8088")
    serve(listener, state, html)
