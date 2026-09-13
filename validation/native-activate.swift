// Activate only a verified visible SVG test window; never send keyboard input.
import AppKit
import ApplicationServices
func fail(_ message:String)->Never { fputs(message+"\n",stderr);exit(1) }
let args=CommandLine.arguments
guard args.count==3,let pid=Int32(args[1]),let target=Int64(args[2]),let app=NSRunningApplication(processIdentifier:pid),["native","Bend SVG Validation"].contains(app.localizedName ?? ""),["/private/tmp/bend-svg-work/paint-order-investigation/build/native", "/private/tmp/bend-svg-work/build/native", "/private/tmp/bend-svg-work/paint-order-investigation/build/Bend SVG Validation.app/Contents/MacOS/native-bin"].contains(app.executableURL?.path ?? "") else {fail("Expected the explicitly launched candidate SVG app and window IDs")}
guard AXIsProcessTrusted() else {fail("Accessibility input is unavailable")}
let ax=AXUIElementCreateApplication(pid)
var values:CFTypeRef?
if AXUIElementCopyAttributeValue(ax,kAXWindowsAttribute as CFString,&values) == .success,let windows=values as? [AXUIElement] {for window in windows {_=AXUIElementPerformAction(window,kAXRaiseAction as CFString)}}
app.activate(options:[.activateAllWindows])
RunLoop.current.run(until:Date().addingTimeInterval(0.25))
if NSWorkspace.shared.frontmostApplication?.processIdentifier==pid {print("SVG app already focused");exit(0)}
let windows=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
func rect(_ window:[String:Any])->CGRect? {guard let value=window[kCGWindowBounds as String] as? [String:Any] else {return nil};return CGRect(dictionaryRepresentation:value as CFDictionary)}
guard let targetWindow=windows.first(where:{($0[kCGWindowNumber as String] as? Int64)==target&&($0[kCGWindowOwnerPID as String] as? Int32)==pid}),let bounds=rect(targetWindow) else {fail("Target SVG window is not on screen")}
let point=CGPoint(x:bounds.midX,y:bounds.minY+16)
guard let first=windows.first(where:{($0[kCGWindowAlpha as String] as? Double ?? 1)>0.01 && (rect($0)?.contains(point) ?? false)}), (first[kCGWindowNumber as String] as? Int64)==target else {fail("Another window covers the activation point; no events sent")}
for type in [CGEventType.leftMouseDown,CGEventType.leftMouseUp] {
 guard let event=CGEvent(mouseEventSource:nil,mouseType:type,mouseCursorPosition:point,mouseButton:.left) else {fail("Mouse event creation failed")}
 event.setIntegerValueField(.mouseEventWindowUnderMousePointer,value:target)
 event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent,value:target)
 event.post(tap:.cghidEventTap)
 RunLoop.current.run(until:Date().addingTimeInterval(0.05))
}
RunLoop.current.run(until:Date().addingTimeInterval(0.5))
guard NSWorkspace.shared.frontmostApplication?.processIdentifier==pid else {fail("Activation click reached the verified SVG window but focus was not acquired; no keyboard events sent")}
print("Activated SVG app",pid,"through window",target)
