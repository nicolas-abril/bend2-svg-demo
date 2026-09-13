import AppKit
import Foundation
let path="/private/tmp/bend-svg-work/convolve-investigation/NativeProbe.app/Contents/MacOS/native"
guard let app=NSRunningApplication.runningApplications(withBundleIdentifier:"org.bend.svg.validation20260911").first(where:{$0.executableURL?.path==path}) else {exit(1)}
let activated=app.activate(options:[.activateAllWindows,.activateIgnoringOtherApps])
Thread.sleep(forTimeInterval:0.3)
let report:[String:Any]=["pid":app.processIdentifier,"activated":activated,"active":app.isActive,"frontmost":NSWorkspace.shared.frontmostApplication?.processIdentifier==app.processIdentifier,"path":path]
let bytes=try JSONSerialization.data(withJSONObject:report,options:.sortedKeys)
print(String(data:bytes,encoding:.utf8)!)
