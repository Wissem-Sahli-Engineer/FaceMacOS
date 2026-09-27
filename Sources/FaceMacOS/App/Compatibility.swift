import AppKit

extension NSApplication {
    /// `activate()` on macOS 14+, the older call on macOS 13.
    func bringToFront() {
        if #available(macOS 14, *) {
            activate()
        } else {
            activate(ignoringOtherApps: true)
        }
    }
}
