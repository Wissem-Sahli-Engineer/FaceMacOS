import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Key {
        static let showInDock = "showInDock"
        static let requireBlink = "requireBlink"
        static let gesturesEnabled = "gesturesEnabled"
        static let unlockLockScreen = "unlockLockScreen"
        static let actions = "faceActions"
        static let accent = "accent"
        static let customAccent = "customAccent"
        static let launchAtLoginWanted = "launchAtLoginWanted"
    }

    static let loginAgentLabel = "com.facemacos.app.agent"
    /// Passed to a copy started just before the login agent is removed; it waits for this copy to exit.
    static let takeoverArgument = "--takeover"

    private let defaults = UserDefaults.standard
    /// Starts the app at login and relaunches it if it crashes (see Resources/LaunchAgents).
    private let loginAgent = SMAppService.agent(plistName: "com.facemacos.app.agent.plist")

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
    @Published var accent: AccentChoice {
        didSet { defaults.set(accent.rawValue, forKey: Key.accent) }
    }
    @Published var customAccent: Color {
        didSet { defaults.set(customAccent.hex, forKey: Key.customAccent) }
    }
    @Published private(set) var launchAtLoginError: String?

    var accentColor: Color { accent == .custom ? customAccent : accent.color }

    private init() {
        showInDock = defaults.object(forKey: Key.showInDock) as? Bool ?? true
        requireBlink = defaults.object(forKey: Key.requireBlink) as? Bool ?? true
        gesturesEnabled = defaults.object(forKey: Key.gesturesEnabled) as? Bool ?? true
        unlockLockScreen = defaults.bool(forKey: Key.unlockLockScreen)
        actions = defaults.data(forKey: Key.actions).flatMap { try? JSONDecoder().decode([FaceAction].self, from: $0) }
            ?? FaceAction.defaults
        accent = defaults.string(forKey: Key.accent).flatMap(AccentChoice.init(rawValue:)) ?? .green
        customAccent = defaults.string(forKey: Key.customAccent).flatMap { Color(hex: $0) } ?? AccentChoice.green.color
    }

    func applyDockPolicy() {
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
    }

    var launchAtLogin: Bool {
        loginAgent.status == .enabled || loginAgent.status == .requiresApproval
    }

    var launchAtLoginNeedsApproval: Bool {
        loginAgent.status == .requiresApproval
    }

    private var launchedByLoginAgent: Bool {
        ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] == Self.loginAgentLabel
    }

    /// On unless the user turned it off.
    private var launchAtLoginWanted: Bool {
        defaults.object(forKey: Key.launchAtLoginWanted) as? Bool ?? true
    }

    /// Registers launch at login (on by default) and migrates the older login-item registration.
    /// When opened by hand it re-registers: macOS pins an agent to the app's location and, without a Developer ID
    /// team, to the executable's checksum, so a moved or updated app would otherwise not start at login.
    func configureLaunchAtLogin() {
        if SMAppService.mainApp.status == .enabled { try? SMAppService.mainApp.unregister() }
        Log.app.notice("Login agent status \(self.loginAgent.status.rawValue, privacy: .public), launched by agent: \(self.launchedByLoginAgent, privacy: .public)")
        guard launchAtLoginWanted, !launchedByLoginAgent else { return }
        try? loginAgent.unregister()
        setLaunchAtLogin(true)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.launchAtLoginWanted)
        do {
            if enabled {
                if loginAgent.status != .enabled { try loginAgent.register() }
            } else {
                // Unregistering stops the launchd job, which quits this copy if launchd started it.
                // Start a replacement first so the app keeps running.
                if launchedByLoginAgent {
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.createsNewApplicationInstance = true
                    configuration.arguments = [Self.takeoverArgument]
                    NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
                }
                try loginAgent.unregister()
            }
            launchAtLoginError = nil
        } catch {
            Log.app.error("Launch at login \(enabled, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            launchAtLoginError = error.localizedDescription
        }
        objectWillChange.send()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
