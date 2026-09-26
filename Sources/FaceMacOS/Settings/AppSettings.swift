import AppKit
import ServiceManagement

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Key {
        static let showInDock = "showInDock"
        static let requireBlink = "requireBlink"
        static let gesturesEnabled = "gesturesEnabled"
        static let unlockLockScreen = "unlockLockScreen"
        static let actions = "faceActions"
    }

    private let defaults = UserDefaults.standard

    @Published var showInDock: Bool {
        didSet { defaults.set(showInDock, forKey: Key.showInDock); applyDockPolicy() }
    }
    @Published var requireBlink: Bool {
        didSet { defaults.set(requireBlink, forKey: Key.requireBlink) }
    }
    @Published var gesturesEnabled: Bool {
        didSet { defaults.set(gesturesEnabled, forKey: Key.gesturesEnabled) }
    }
    @Published var unlockLockScreen: Bool {
        didSet { defaults.set(unlockLockScreen, forKey: Key.unlockLockScreen) }
    }
    @Published var actions: [FaceAction] {
        didSet { defaults.set(try? JSONEncoder().encode(actions), forKey: Key.actions) }
    }
    @Published private(set) var launchAtLoginError: String?

    private init() {
        showInDock = defaults.object(forKey: Key.showInDock) as? Bool ?? true
        requireBlink = defaults.object(forKey: Key.requireBlink) as? Bool ?? true
        gesturesEnabled = defaults.object(forKey: Key.gesturesEnabled) as? Bool ?? true
        unlockLockScreen = defaults.bool(forKey: Key.unlockLockScreen)
        actions = defaults.data(forKey: Key.actions).flatMap { try? JSONDecoder().decode([FaceAction].self, from: $0) }
            ?? FaceAction.defaults
    }

    func applyDockPolicy() {
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
    }

    var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        objectWillChange.send()
    }
}
