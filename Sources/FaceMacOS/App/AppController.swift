import AppKit
import Carbon.HIToolbox
import LocalAuthentication

@MainActor
final class AppController: ObservableObject {
    @Published var selectedSection: MainSection? = .overview

    let settings = AppSettings.shared
    let authenticator = FaceAuthenticator()
    let updater = Updater()
    private(set) lazy var unlocker = LockScreenUnlocker(authenticator: authenticator, settings: settings)
    private lazy var mainWindow = MainWindowController(controller: self)
    private let vault = VaultWindowController()
    private var notch: NotchController?
    private var hotKeys: [HotKey] = []

    func start() {
        settings.applyDockPolicy()
        settings.configureLaunchAtLogin()
        notch = NotchController(authenticator: authenticator)
        _ = unlocker
        hotKeys = [
            HotKey(keyCode: kVK_ANSI_F, modifiers: cmdKey | optionKey) { [weak self] in self?.openVault() },
            HotKey(keyCode: kVK_ANSI_G, modifiers: cmdKey | optionKey) { [weak self] in self?.faceCommand() },
        ]
        if CommandLine.arguments.contains("--demo") {
            runDemo()
        } else if !authenticator.isEnrolled {
            showMainWindow()
        }
    }

    func showMainWindow(section: MainSection? = nil) {
        mainWindow.show(section: section)
    }

    func enroll() {
        Task { await authenticator.enroll() }
    }

    func testFaceID() {
        Task { await authenticator.authenticate() }
    }

    func runDemo() {
        Task { await authenticator.runDemo() }
    }

    func faceCommand() {
        guard settings.gesturesEnabled else { return }
        Task {
            await authenticator.faceCommand(settings.actions) { [weak self] action in
                ActionRunner.run(action) { self?.vault.show() }
            }
        }
    }

    func openVault() {
        guard !authenticator.isBusy else { return }
        Task {
            if await verifyOwner(reason: "unlock your FaceMacOS vault") { vault.show() }
        }
    }

    /// Face ID first, then Touch ID or the Mac password.
    func verifyOwner(reason: String) async -> Bool {
        if authenticator.isEnrolled, !authenticator.isBusy, await authenticator.authenticate() { return true }
        return await passwordFallback(reason: reason)
    }

    func deleteAllData() {
        NSApp.bringToFront()
        let alert = NSAlert()
        alert.messageText = "Delete all FaceMacOS data?"
        alert.informativeText = "Your face data, vault note and saved login password will be removed. You'll need to set up Face ID again."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        authenticator.deleteEnrollment()
        Secrets.deleteAll()
        unlocker.refresh()
    }

    /// Like Face ID falling back to the passcode: Touch ID or the Mac login password.
    private func passwordFallback(reason: String) async -> Bool {
        let context = LAContext()
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }
}
