import AppKit
import Carbon.HIToolbox
import LocalAuthentication

@MainActor
final class AppController: ObservableObject {
    @Published var selectedSection: MainSection? = .overview

    let settings = AppSettings.shared
    let authenticator = FaceAuthenticator()
    private(set) lazy var unlocker = LockScreenUnlocker(authenticator: authenticator, settings: settings)
    private lazy var mainWindow = MainWindowController(controller: self)
    private let vault = VaultWindowController()
    private var notch: NotchController?
    private var hotKeys: [HotKey] = []

    func start() {
        settings.applyDockPolicy()
        settings.configureLaunchAtLogin()
        // Ask for Keychain access now, while the user can answer, not later behind the lock screen.
        if settings.unlockLockScreen, LoginPassword.isStored { _ = LoginPassword.load() }
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
            var unlocked = await authenticator.authenticate()
            if !unlocked { unlocked = await passwordFallback() }
            if unlocked { vault.show() }
        }
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
        VaultModel.deleteStoredNote()
        LoginPassword.delete()
        unlocker.refresh()
    }

    /// Like Face ID falling back to the passcode: Touch ID or the Mac login password.
    private func passwordFallback() async -> Bool {
        let context = LAContext()
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "unlock your FaceMacOS vault")
        } catch {
            return false
        }
    }
}
