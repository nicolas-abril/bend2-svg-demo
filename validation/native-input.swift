// Validation only: deliver input solely to the explicitly supplied SVG app PID.
import AppKit
import ApplicationServices
func fail(_ message: String) -> Never { fputs(message + "\n", stderr); exit(1) }
let args = CommandLine.arguments
if args.count < 3 { fail("usage: native-input PID click|right|undo|drag [x y [dx dy]]") }
guard let pid = Int32(args[1]), let app = NSRunningApplication(processIdentifier: pid), ["native", "Bend SVG Validation"].contains(app.localizedName ?? ""), ["/private/tmp/bend-svg-work/build/native", "/private/tmp/bend-svg-work/paint-order-investigation/build/native", "/private/tmp/bend-svg-work/paint-order-investigation/build/Bend SVG Validation.app/Contents/MacOS/native-bin"].contains(app.executableURL?.path ?? "") else { fail("Target is not the native SVG test app") }
if !AXIsProcessTrusted() { fail("Native input testing is unavailable") }
let ax = AXUIElementCreateApplication(pid)
AXUIElementSetAttributeValue(ax, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
app.activate(options: [.activateAllWindows])
RunLoop.current.run(until: Date().addingTimeInterval(0.25))
guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { fail("SVG app did not become the input target; no events sent") }
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String:Any]] ?? []
guard let window = windows.first(where: { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }), let number = window[kCGWindowNumber as String] as? Int64 else { fail("SVG app window not found") }
guard let dictionary = window[kCGWindowBounds as String] as? [String:Any], let bounds = CGRect(dictionaryRepresentation:dictionary as CFDictionary) else { fail("SVG window bounds unavailable") }
func postMouse(_ type: CGEventType, _ x: Double, _ y: Double) {
  guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid && bounds.contains(CGPoint(x:x,y:y)) else { fail("Input target changed or point is outside the SVG window") }
  guard let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x:x,y:y), mouseButton: .left) else { fail("mouse event creation failed") }
  e.setIntegerValueField(.mouseEventWindowUnderMousePointer, value:number)
  e.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value:number)
  e.post(tap: .cghidEventTap)
}
func key(_ code: CGKeyCode) {
  var character: UniChar = code == 124 ? 0xF703 : 122
  for down in [true,false] {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { fail("Keyboard target changed") }
    guard let e=CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:down) else { fail("key event creation failed") }
    e.keyboardSetUnicodeString(stringLength:1,unicodeString:&character)
    e.post(tap: .cghidEventTap)
  }
}
switch args[2] {
case "click":
  let x=Double(args[3])!, y=Double(args[4])!
  postMouse(.leftMouseDown,x,y); postMouse(.leftMouseUp,x,y)
case "drag":
  let x=Double(args[3])!, y=Double(args[4])!, dx=Double(args[5])!, dy=Double(args[6])!
  postMouse(.leftMouseDown,x,y); postMouse(.leftMouseDragged,x+dx,y+dy); postMouse(.leftMouseUp,x+dx,y+dy)
case "right": key(124)
case "undo": key(6)
default: fail("unknown input action")
}
print("Delivered",args[2],"to SVG app PID",pid)
