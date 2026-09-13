import AppKit
import ApplicationServices
let apps=NSRunningApplication.runningApplications(withBundleIdentifier:"org.bend.svg.validation.paintorder")
let windows=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
for app in apps {
 print("APP",app.processIdentifier,app.localizedName ?? "",app.executableURL?.path ?? "", "active",app.isActive)
 for w in windows where (w[kCGWindowOwnerPID as String] as? Int32)==app.processIdentifier {print(w)}
}
print("FRONT",NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1)
