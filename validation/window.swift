import Foundation
import CoreGraphics
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for w in windows where (w[kCGWindowOwnerName as String] as? String) == "native" {
  print("pid", w[kCGWindowOwnerPID as String] ?? "?", "window", w[kCGWindowNumber as String] ?? "?", "bounds", w[kCGWindowBounds as String] ?? "?")
}
