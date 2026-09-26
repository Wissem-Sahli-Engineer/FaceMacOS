import AppKit

/// Polls permissions that macOS grants outside the app, so the UI updates as soon as they change.
@MainActor
final class Permissions: ObservableObject {
    static let shared = Permissions()

    @Published private(set) var accessibility = SystemControl.isAccessibilityTrusted
    @Published private(set) var passwordStored = LoginPassword.isStored

    private var timer: Timer?
    private var activationObserver: NSObjectProtocol?

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAccessibility() }
        }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        refreshAccessibility()
        let stored = LoginPassword.isStored
        if stored != passwordStored { passwordStored = stored }
    }

    private func refreshAccessibility() {
        let trusted = SystemControl.isAccessibilityTrusted
        if trusted != accessibility {
            Log.app.info("Accessibility permission changed: \(trusted, privacy: .public)")
            accessibility = trusted
        }
    }
}
