// Validation only: post directly to the exact supplied SVG test process.
// This does not activate a window or post to the global input stream.
import AppKit
import ApplicationServices
func fail(_ message:String)->Never { fputs(message+"\n",stderr);exit(1) }
let args=CommandLine.arguments
if args.count < 4 { fail("usage: native-target-input PID keycode unicode | click x y | drag x y dx dy") }
guard let pid=Int32(args[1]),let app=NSRunningApplication(processIdentifier:pid),let path=app.executableURL?.path,["/private/tmp/bend-svg-work/source-undo-investigation/build/native","/private/tmp/bend-svg-work/camera-investigation/build/native","/private/tmp/bend-svg-work/convolve-investigation/build/native","/private/tmp/bend-svg-work/convolve-investigation/NativeProbe.app/Contents/MacOS/native"].contains(path) else {fail("Target is not an allowed SVG test process or key is invalid")}
if !AXIsProcessTrusted() {fail("Process-targeted input testing is unavailable")}
let windows=CGWindowListCopyWindowInfo([.optionAll],kCGNullWindowID) as? [[String:Any]] ?? []
guard let window=windows.first(where:{($0[kCGWindowOwnerPID as String] as? Int32)==pid && ($0[kCGWindowLayer as String] as? Int)==0}),let number=window[kCGWindowNumber as String] as? Int64,let dict=window[kCGWindowBounds as String] as? [String:Any],let bounds=CGRect(dictionaryRepresentation:dict as CFDictionary) else {fail("Target has no SVG window")}
func post(_ event:CGEvent) {
 guard !app.isTerminated,NSRunningApplication(processIdentifier:pid)?.executableURL?.path==path else {fail("Target process changed")}
 event.postToPid(pid)
}
func mouse(_ type:CGEventType,_ x:Double,_ y:Double) {
 guard x>=0 && x<256 && y>=0 && y<256 else {fail("Point is outside SVG canvas")}
 let point=CGPoint(x:bounds.minX+x+0.25,y:bounds.maxY-256+y+0.25)
 let types:[CGEventType:NSEvent.EventType] = [.leftMouseDown:.leftMouseDown,.leftMouseUp:.leftMouseUp,.leftMouseDragged:.leftMouseDragged,.rightMouseDown:.rightMouseDown,.rightMouseUp:.rightMouseUp]
 guard let cocoaType=types[type] else {fail("Unsupported mouse type")}
 guard bounds.contains(point),let cocoa=NSEvent.mouseEvent(with:cocoaType,location:NSPoint(x:x+0.25,y:256-y-0.25),modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:Int(number),context:nil,eventNumber:1,clickCount:1,pressure:type == .leftMouseUp ? 0:1),let event=cocoa.cgEvent else {fail("Cannot construct target mouse event")}
 event.location=point
 event.setIntegerValueField(.mouseEventWindowUnderMousePointer,value:number)
 event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent,value:number)
 post(event)
}
if args[2]=="click" || args[2]=="rightclick" || args[2]=="drag" {
 guard args.count==(args[2]=="drag" ? 7:5),let x=Double(args[3]),let y=Double(args[4]) else {fail("Invalid mouse action")}
 mouse(args[2]=="rightclick" ? .rightMouseDown:.leftMouseDown,x,y)
 if args[2]=="drag" {
  guard let dx=Double(args[5]),let dy=Double(args[6]) else {fail("Invalid drag")}
  mouse(.leftMouseDragged,x+dx,y+dy);mouse(.leftMouseUp,x+dx,y+dy)
 } else {mouse(args[2]=="rightclick" ? .rightMouseUp:.leftMouseUp,x,y)}
} else {
 guard args.count==4,let code=UInt16(args[2]),var character=UInt16(args[3]) else {fail("Invalid key")}
 for down in [true,false] {
  guard let event=CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:down) else {fail("Cannot construct key event")}
  event.keyboardSetUnicodeString(stringLength:1,unicodeString:&character)
  post(event)
 }
}
print("Posted action directly to SVG test PID",pid)
