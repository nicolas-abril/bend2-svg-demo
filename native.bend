# Native pixel window. All SVG and editing behavior lives in the shared modules.
import Base
import ./state.bend as Editor

type Session is Data:
  Session{state: Editor.State, image: Image}

def session(+state: Editor.State) -> Session:
  Session{state, Editor.canvas(state)}

def view(+s: Session) -> Session & Image:
  Session{state, image} = s
  (s, image)

def save.key(save: Bool, state: Editor.State) -> IO(Unit):
  match save:
    case False{}: IO.pure(Unit, Unit{})
    case True{}: Editor.save(state)

def event.changed(s: Session, +action: Editor.Action) -> Session:
  Session{state, image} = s
  Session{Editor.apply(state, action), image}

def refresh(s: Session, dirty: Bool) -> Session:
  Session{state, image} = s
  match dirty:
    case False{}: Session{state, image}
    case True{}: session(state)

def session.state(s: Session) -> Editor.State:
  Session{state, image} = s
  state

def tick.loop(events: List<Event>, +s: Session, +dirty: Bool) -> IO(Maybe<Session>):
  match events:
    case Nil{}: IO.pure(Maybe<Session>, Some{refresh(s, dirty)})
    case Con{Close{}, rest}: IO.pure(Maybe<Session>, None{})
    case Con{Key{code, down}, rest}:
      +k = code
      +pressed = down
      +action = Editor.event(Key{k, pressed})
      do IO<Maybe<Session>>:
        Unit <- save.key(U32.is_eq(k, 115) && pressed, session.state(s))
        tick.loop(rest, event.changed(s, action), dirty || Editor.changed(action, session.state(s)))
    case Con{ev, rest}:
      +action = Editor.event(ev)
      tick.loop(rest, event.changed(s, action), dirty || Editor.changed(action, session.state(s)))

def tick(events: List<Event>, s: Session) -> IO(Maybe<Session>):
  tick.loop(events, s, False{})

def main() -> IO(Unit):
  do IO<Unit>:
    state : Editor.State <- Editor.initial()
    App.run(~Session, ~App{s => view(s), tick}, "Bend SVG - F fit / +/- zoom / HJKL pan / Z undo", 256, 256, session(state))
