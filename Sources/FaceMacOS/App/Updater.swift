import AppKit
import Sparkle

/// In-app updates via Sparkle. Checks the appcast (SUFeedURL in Info.plist) about once a day while online,
/// and only installs updates signed with the release key (SUPublicEDKey) and the same code-signing certificate.
@MainActor
final class Updater: NSObject, ObservableObject, SPUStandardUserDriverDelegate {
    @Published private(set) var canCheckForUpdates = false
    private var controller: SPUStandardUpdaterController!

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
    }

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            controller.updater.automaticallyChecksForUpdates = newValue
        }
    }

    var lastCheck: Date? { controller.updater.lastUpdateCheckDate }

    func checkForUpdates() {
        NSApp.bringToFront()
        controller.checkForUpdates(nil)
    }

    // A menu bar app is usually in the background, so bring it forward when a scheduled check finds an update;
    // otherwise the update window would open behind other apps.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        guard handleShowingUpdate, !state.userInitiated else { return }
        Task { @MainActor in NSApp.bringToFront() }
    }
}
