import AppKit
import SwiftUI

struct NotchGeometry {
    let screen: NSScreen
    let closedSize: CGSize

    static func current() -> NotchGeometry {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return NotchGeometry(screen: screen, closedSize: CGSize(width: screen.frame.width - left.width - right.width, height: top))
        }
        let menuBarHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
        return NotchGeometry(screen: screen, closedSize: CGSize(width: 160, height: menuBarHeight))
    }
}

final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isMovable = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Allow the panel to sit over the menu bar / notch area.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
final class NotchController {
    private static let canvasSize = CGSize(width: 400, height: 380)
    private let panel = NotchPanel()
    private let authenticator: FaceAuthenticator
    private var screenObserver: NSObjectProtocol?

    init(authenticator: FaceAuthenticator) {
        self.authenticator = authenticator
        layout()
        panel.orderFrontRegardless()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
    }

    private func layout() {
        let geometry = NotchGeometry.current()
        let frame = geometry.screen.frame
        let size = Self.canvasSize
        panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height), display: true)
        panel.contentView = NSHostingView(rootView: NotchView(auth: authenticator, closedSize: geometry.closedSize))
    }
}
