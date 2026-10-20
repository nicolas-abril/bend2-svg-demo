# A local HTTP server for the same Bend editor. Frames are lossless PNGs.
import Base
import gralha-svg-render@0.1.0.0/svg.bend as SVG
import gralha-http-core@0.1.0.0/http.bend as Http
import gralha-http-server@0.1.0.0/server.bend as Server
import ./state.bend as Editor
import ./inspect.bend as Inspect

# The server's state: the editor and the page it serves at every other path.
type Served is Data:
  Served{state: Editor.State, html: String}

def page(contentType: String, body: String) -> Http.Response:
  Http.Response{200, [Http.Header{"Connection", "close"}, Http.Header{"Cache-Control", "no-store"},
    Http.Header{"Content-Type", contentType}], body}

def response.done(got: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (socket, result) = got
  Socket.close(socket)

# Encode and send already rasterized pixels; the effect consumes the array.
def frame.send(socket: Socket, pixels: Array<U32>, +w: U32, +h: U32) -> IO(Socket & Result<&1, &1, U32 & String, Unit>):
  import "./effs/frame_send.c"
  import "./effs/frame_send.js"

def frame.reply(socket: Socket, +state: Editor.State) -> IO(Unit):
  Editor.State{doc, nodes, id, inv, down, anchor, base, history, w, h, fonts, camera} = state
  do IO<Unit>:
    sent : Socket & Result<&1, &1, U32 & String, Unit> <- frame.send(socket, SVG.paint.packed(nodes, w, h, Editor.quality(state)), w, h)
    response.done(sent)

def request.state(+request: Http.Request, +state: Editor.State) -> Editor.State:
  Http.when(Editor.State, Http.request.is(request, "POST", "/event"),
    _ => Editor.apply(state, Editor.input(Editor.wire.decode(Http.request.body(request)))), _ => state)

def request.reply(socket: Socket, +request: Http.Request, +state: Editor.State, html: String) -> IO(Unit):
  Http.when(Socket -> IO(Unit), Http.request.is(request, "GET", "/frame") || Http.request.is(request, "POST", "/event"),
    _ => s => frame.reply(s, state),
    _ => s => Server.send.text(s, Http.response.text(Http.when(Http.Response, Http.request.is(request, "GET", "/inspector"),
      _ => page("application/json; charset=utf-8", Inspect.json(state)),
      _ => Http.when(Http.Response, Http.request.is(request, "GET", "/source"),
        _ => page("text/plain; charset=utf-8", Editor.get.source(state)),
        _ => page("text/html; charset=utf-8", html))))))(socket)

def reply(socket: Socket, +request: Http.Request, app: Served) -> IO(Served):
  Served{state, html} = app
  +next = request.state(request, state)
  +page = html
  do IO<Served>:
    Unit <- request.reply(socket, request, next, page)
    return Served{next, page}

def stop(got: Listener & Served) -> IO(Unit):
  (listener, app) = got
  Listener.close(listener)

def main() -> IO(Unit):
  do IO<Unit>:
    state : Editor.State <- Editor.initial()
    html : String <- Editor.read("web.html")
    listener : Listener <- IO.try(Listener, TCP.listen("127.0.0.1", 8088))
    Unit <- IO.print("Bend SVG: http://127.0.0.1:8088")
    done : Listener & Served <- Server.serve.socket(~Served, ~(s => r => a => reply(s, r, a)), listener, Served{state, html}, 4194304)
    stop(done)
