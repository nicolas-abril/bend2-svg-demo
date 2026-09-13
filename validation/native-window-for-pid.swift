// Read-only inspection of the explicitly launched validation app's window.
import Foundation
import CoreGraphics
guard CommandLine.arguments.count == 2, let pid=Int32(CommandLine.arguments[1]) else {exit(2)}
let windows=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
if let w=windows.first(where:{($0[kCGWindowOwnerPID as String] as? Int32)==pid&&($0[kCGWindowLayer as String] as? Int)==0}),let number=w[kCGWindowNumber as String] {
 let info:[String:Any]=["pid":pid,"window":number,"bounds":w[kCGWindowBounds as String] ?? [:]]
 if let bytes=try? JSONSerialization.data(withJSONObject:info,options:[.sortedKeys]),let json=String(data:bytes,encoding:.utf8){print(json);exit(0)}
}
exit(1)
