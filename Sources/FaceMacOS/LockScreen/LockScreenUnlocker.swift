import AppKit
import Combine

/// Unlocks the macOS lock screen: after a short grace period (or once you step away), waits for a face,
/// verifies it with strict liveness (blink required), then types the saved login password.
@MainActor
final class LockScreenUnlocker: ObservableObject {
    static let gracePeriod: TimeInterval = 5
    static let absenceToArm: Double = 2

    enum State: Equatable {
        case off
        case idle
        case waitingToArm
        case armed
        case scanning
        case unlocking
        case failed(String)

        var description: String {
            switch self {
            case .off: return "Off"
            case .idle: return "Ready — lock your Mac to use it"
            case .waitingToArm: return "Locked — starting in a few seconds"
            case .armed: return "Locked — look at the camera and blink"
            case .scanning: return "Verifying your face…"
            case .unlocking: return "Unlocking…"
            case .failed(let reason): return reason
            }
        }
    }

    @Published private(set) var state: State = .off

    private let authenticator: FaceAuthenticator
    private let settings: AppSettings
    private let permissions = Permissions.shared
    private var task: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []
    private var displayAsleep = false
    private var armed = false

    var missingRequirement: String? {
        if !settings.unlockLockScreen { return "Turned off" }
        if !authenticator.isEnrolled { return "Set up Face ID first" }
        if !permissions.passwordStored { return "Save your login password" }
        if !permissions.accessibility { return "Grant Accessibility permission" }
        return nil
    }

    var isReady: Bool { missingRequirement == nil }

    init(authenticator: FaceAuthenticator, settings: AppSettings) {
        self.authenticator = authenticator
        self.settings = settings

        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        observe(distributed, "com.apple.screenIsLocked") { $0.screenLocked() }
        observe(distributed, "com.apple.screenIsUnlocked") { $0.screenUnlocked() }
        observe(workspace, NSWorkspace.screensDidSleepNotification.rawValue) { $0.displaySleepChanged(asleep: true) }
        observe(workspace, NSWorkspace.screensDidWakeNotification.rawValue) { $0.displaySleepChanged(asleep: false) }

        Publishers.Merge3(
            permissions.$accessibility.map { _ in () },
            permissions.$passwordStored.map { _ in () },
            settings.$unlockLockScreen.map { _ in () }
        )
        .merge(with: authenticator.$isEnrolled.map { _ in () })
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.refresh() }
        .store(in: &cancellables)
    }

    func refresh() {
        if SystemControl.isScreenLocked {
            if task == nil { screenLocked() }
            return
        }
        if case .failed = state, isReady { return }
        state = isReady ? .idle : .off
    }

    private func observe(_ center: NotificationCenter, _ name: String, _ handler: @escaping (LockScreenUnlocker) -> Void) {
        observers.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self { handler(self) }
            }
        })
    }

    private func screenLocked() {
        guard let missing = missingRequirement else {
            Log.unlock.info("Screen locked; starting face unlock")
            armed = displayAsleep
            start()
            return
        }
        Log.unlock.info("Screen locked; face unlock not ready: \(missing, privacy: .public)")
    }

    private func screenUnlocked() {
        Log.unlock.info("Screen unlocked")
        task?.cancel()
        task = nil
        armed = false
        state = isReady ? .idle : .off
    }

    private func displaySleepChanged(asleep: Bool) {
        displayAsleep = asleep
        if asleep { armed = true }
        if SystemControl.isScreenLocked, isReady { start() }
    }

    private func start() {
        task?.cancel()
        task = Task { await run() }
    }

    private func run() async {
        let lockedAt = ProcessInfo.processInfo.systemUptime
        while !Task.isCancelled, SystemControl.isScreenLocked {
            if displayAsleep {
                state = .armed
                try? await Task.sleep(for: .seconds(2))
                continue
            }

            if !armed {
                state = .waitingToArm
                let remaining = max(0.5, Self.gracePeriod - (ProcessInfo.processInfo.systemUptime - lockedAt))
                let away = await authenticator.waitFor(.faceAbsent(seconds: Self.absenceToArm), timeout: .seconds(remaining))
                if away == nil { try? await Task.sleep(for: .seconds(1)) }
                if away == true || ProcessInfo.processInfo.systemUptime - lockedAt >= Self.gracePeriod {
                    armed = true
                    Log.unlock.info("Armed")
                }
                continue
            }

            state = .armed
            guard let present = await authenticator.waitFor(.faceAppears, timeout: .seconds(30)) else {
                Log.unlock.error("Camera unavailable while locked: \(self.authenticator.cameraError ?? "busy", privacy: .public)")
                try? await Task.sleep(for: .seconds(2))
                continue
            }
            guard present, !Task.isCancelled else { continue }

            state = .scanning
            Log.unlock.info("Face present; verifying")
            guard await authenticator.authenticate(strict: true, timeout: .seconds(6)) else {
                Log.unlock.info("Verification failed (score \(self.authenticator.lastScore ?? -1, privacy: .public))")
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            guard !Task.isCancelled, SystemControl.isScreenLocked else { return }
            guard let password = LoginPassword.load() else {
                state = .failed("Saved password could not be read from the Keychain.")
                return
            }

            state = .unlocking
            Log.unlock.info("Verified; typing password")
            await SystemControl.unlock(password: password)
            try? await Task.sleep(for: .seconds(3))
            if SystemControl.isScreenLocked {
                Log.unlock.error("Still locked after typing password")
                state = .failed("Couldn't unlock. Check the saved password and Accessibility permission.")
                return
            }
        }
    }
}
