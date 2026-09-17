# One property catalogue and selection snapshot for the web and native editors.
import Base
import ./state.bend as Editor
import ./svg.bend as SVG
import ./xml.bend as XML
import ./css.bend as CSS
import ./util.bend as U

type Property is Data:
  Property{key: String, initial: String, example: String, inherited: Bool, options: String}

def properties() -> List<&2, Property>:
  Con{Property{"fill", "black", "#4682b4", True{}, ""},
    Con{Property{"stroke", "none", "#202b32", True{}, ""},
    Con{Property{"paint-order", "normal", "", True{}, "normal|fill stroke markers|fill markers stroke|stroke fill markers|stroke markers fill|markers fill stroke|markers stroke fill"},
    Con{Property{"stroke-width", "1", "", True{}, ""},
    Con{Property{"stroke-linecap", "butt", "", True{}, "butt|round|square"},
    Con{Property{"stroke-linejoin", "miter", "", True{}, "miter|miter-clip|round|bevel|arcs"},
    Con{Property{"stroke-miterlimit", "4", "", True{}, ""},
    Con{Property{"stroke-dasharray", "none", "4 2", True{}, ""},
    Con{Property{"stroke-dashoffset", "0", "", True{}, ""},
    Con{Property{"vector-effect", "none", "", False{}, "none|non-scaling-stroke"},
    Con{Property{"pathLength", "", "100", False{}, ""},
    Con{Property{"marker", "none", "url(#arrow)", True{}, ""},
    Con{Property{"marker-start", "none", "url(#arrow)", True{}, ""},
    Con{Property{"marker-mid", "none", "url(#arrow)", True{}, ""},
    Con{Property{"marker-end", "none", "url(#arrow)", True{}, ""},
    Con{Property{"filter", "none", "url(#shadow)", False{}, ""},
    Con{Property{"mask", "none", "url(#mask)", False{}, ""},
    Con{Property{"mask-mode", "match-source", "", False{}, "match-source|alpha|luminance"},
    Con{Property{"clip-path", "none", "url(#clip)", False{}, ""},
    Con{Property{"fill-rule", "nonzero", "", True{}, "nonzero|evenodd"},
    Con{Property{"stroke-opacity", "1", "", True{}, ""},
    Con{Property{"opacity", "1", "", False{}, ""},
    Con{Property{"fill-opacity", "1", "", True{}, ""},
    Con{Property{"transform", "none", "translate(10, 10)", False{}, ""},
    Con{Property{"x", "0", "", False{}, ""},
    Con{Property{"y", "0", "", False{}, ""},
    Con{Property{"width", "auto", "100", False{}, ""},
    Con{Property{"height", "auto", "100", False{}, ""},
    Con{Property{"preserveAspectRatio", "xMidYMid meet", "", False{}, "none|xMinYMin meet|xMinYMin slice|xMidYMin meet|xMidYMin slice|xMaxYMin meet|xMaxYMin slice|xMinYMid meet|xMinYMid slice|xMidYMid meet|xMidYMid slice|xMaxYMid meet|xMaxYMid slice|xMinYMax meet|xMinYMax slice|xMidYMax meet|xMidYMax slice|xMaxYMax meet|xMaxYMax slice"},
    Con{Property{"image-rendering", "auto", "", True{}, "auto|optimizeSpeed|optimizeQuality|crisp-edges|pixelated"},
    Con{Property{"href", "", "#symbol", False{}, ""},
    Con{Property{"textLength", "", "100", False{}, ""},
    Con{Property{"lengthAdjust", "spacing", "", False{}, "spacing|spacingAndGlyphs"},
    Con{Property{"font-size", "16", "", True{}, ""},
    Con{Property{"font-weight", "normal", "400", True{}, ""},
    Con{Property{"font-style", "normal", "", True{}, "normal|italic|oblique"},
    Con{Property{"text-anchor", "start", "", True{}, "start|middle|end"},
    Con{Property{"letter-spacing", "normal", "1", True{}, ""},
    Con{Property{"word-spacing", "normal", "2", True{}, ""},
    Con{Property{"baseline-shift", "baseline", "2", False{}, ""},
    Nil{}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}

type Selection is Data:
  Selection{tag: String, path: List<&2, List<&2, XML.Attr>>}

def found.or(+found: Selection, next: Unit -> Selection) -> Selection:
  Selection{tag, path} = found
  U.branch(Selection, U.string.equal(tag, ""), _ => next(Unit{}), _ => found)

@unsafe
def find(nodes: List<&2, XML.Element>, +id: String, +parents: List<&2, List<&2, XML.Attr>>) -> Selection:
  match nodes:
    case Nil{}: Selection{"", Nil{}}
    case Con{XML.Element{tag, attrs, kids, text}, rest}:
      +as = CSS.properties(attrs)
      U.branch(Selection, U.string.equal(XML.attr.get(as, "#editor-id", ""), id),
        _ => Selection{tag, Con{as, parents}},
        _ => found.or(find(kids, id, Con{as, parents}), _ => find(rest, id, parents)))

def selected.size(doc: XML.Element, id: String, size: SVG.Point) -> Selection:
  XML.Element{tag, attrs, kids, text} = doc
  SVG.Point{w, h} = size
  +nodes = kids
  +width = w
  +height = h
  find(CSS.css.tree(nodes, CSS.css.rules(CSS.css.sheets(nodes, width, height), width, height), Nil{}, Nil{}, 1, CSS.css.element.count(nodes)), id, Nil{})

def selected(+s: Editor.State) -> Selection:
  Editor.State{doc, scene, id, inv, down, anchor, base, history, w, h, fonts, camera} = s
  +document = doc
  +selection = id
  U.branch(Selection, U.string.equal(selection, ""), _ => Selection{"", Nil{}},
    _ => selected.size(document, selection, SVG.document.size(document, U32.to_f32(w), U32.to_f32(h))))

type Value is Data:
  Value{text: String, origin: String}

def initial(+text: String) -> Value:
  Value{text, U.choose(String, U.string.equal(text, ""), "example", "default")}

def inherited(value: Value) -> Value:
  Value{text, origin} = value
  +from = origin
  Value{text, U.choose(String, U.string.equal(from, "current"), "inherited", from)}

def value.found(found: Maybe<&2, String>, +fallback: String, +inherits: Bool, parent: Unit -> Value) -> Value:
  match found:
    case None{}: U.branch(Value, inherits, _ => inherited(parent(Unit{})), _ => initial(fallback))
    case Some{text}:
      +v = text
      +kw = SVG.style.keyword(v)
      U.branch(Value, U32.is_eq(kw, 1) || (inherits && U32.is_eq(kw, 3)),
        _ => inherited(parent(Unit{})),
        _ => U.choose(Value, U32.is_eq(kw, 2) || U32.is_eq(kw, 3), initial(fallback), Value{v, "current"}))

@unsafe
def value(path: List<&2, List<&2, XML.Attr>>, +key: String, +fallback: String, +inherits: Bool) -> Value:
  match path:
    case Nil{}: initial(fallback)
    case Con{attrs, parents}: value.found(XML.attr.find(attrs, key), fallback, inherits, _ => value(parents, key, fallback, inherits))

def hex.char(+n: U32) -> String:
  SCon{Chr{U.choose(U32, U32.is_lt(n, 10), (48 + n : U32), (87 + n : U32))}, ""}

def quote.body(s: String) -> String:
  match s:
    case SNil{}: ""
    case SCon{Chr{c}, rest}:
      +ch = c
      U.choose(String, U32.is_eq(ch, 34), "\\\"", U.choose(String, U32.is_eq(ch, 92), "\\\\",
        U.choose(String, U32.is_lt(ch, 32), "\\u00" ++ U.choose(String, U32.is_lt(ch, 16), "0", "1") ++ hex.char((ch % 16 : U32)), SCon{Chr{ch}, ""}))) ++ quote.body(rest)

def quote(s: String) -> String:
  "\"" ++ quote.body(s) ++ "\""

def property.json(p: Property, got: Value) -> String:
  Property{key, fallback, example, inh, options} = p
  Value{text, origin} = got
  "{\"key\":" ++ quote(key) ++ ",\"value\":" ++ quote(text) ++ ",\"origin\":" ++ quote(origin)
    ++ ",\"example\":" ++ quote(example) ++ ",\"options\":" ++ quote(options) ++ "}"

def properties.json(ps: List<&2, Property>, +path: List<&2, List<&2, XML.Attr>>, +sep: String) -> String:
  match ps:
    case Nil{}: ""
    case Con{Property{key, fallback, example, inh, options}, rest}:
      +k = key
      +base = fallback
      +inherit = inh
      sep ++ property.json(Property{k, base, example, inherit, options}, value(path, k, base, inherit)) ++ properties.json(rest, path, ",")

def selection.id(path: List<&2, List<&2, XML.Attr>>) -> String:
  match path:
    case Nil{}: ""
    case Con{attrs, rest}: XML.attr.get(attrs, "id", "")

def selection.json(+pick: Selection) -> String:
  Selection{tag, path} = pick
  +name = tag
  +ancestors = path
  "{\"selected\":" ++ U.choose(String, U.string.equal(name, ""), "false", "true") ++ ",\"tag\":" ++ quote(name)
    ++ ",\"id\":" ++ quote(selection.id(ancestors)) ++ ",\"properties\":[" ++ properties.json(properties(), ancestors, "") ++ "]}"

def json(s: Editor.State) -> String:
  selection.json(selected(s))
