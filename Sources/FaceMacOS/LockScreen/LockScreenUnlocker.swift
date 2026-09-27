import AppKit
import Combine

/// Unlocks the macOS lock screen: scans as soon as the lid opens or the display wakes, otherwise after a short
/// grace period (or once you step away) waits for a face; verifies it with strict liveness (blink required),
/// then types the saved login password.
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
    private var lockObservers: [ImmediateDistributedObserver] = []
    private var unlockWatch: Timer?
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

        let workspace = NSWorkspace.shared.notificationCenter
        lockObservers = [
            ImmediateDistributedObserver("com.apple.screenIsLocked") { [weak self] in self?.screenLocked() },
            ImmediateDistributedObserver("com.apple.screenIsUnlocked") { [weak self] in self?.screenUnlocked() },
        ]
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
        guard task == nil else { return }
        guard let missing = missingRequirement else {
            Log.unlock.notice("Screen locked; starting face unlock")
            armed = displayAsleep
            start()
            return
        }
        Log.unlock.notice("Screen locked; face unlock not ready: \(missing, privacy: .public)")
    }

    /// Also called by the unlock watch, in case macOS's notification arrives late or not at all
    /// (e.g. the user unlocked with Touch ID or their password while a scan was running).
    private func screenUnlocked() {
        unlockWatch?.invalidate()
        unlockWatch = nil
        guard task != nil else { return }
        Log.unlock.notice("Screen unlocked")
        // After a face unlock, let the success animation finish; otherwise stop the scan and close the notch now.
        if state != .unlocking {
            task?.cancel()
            authenticator.dismissLockScreenOperation()
        }
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
        if unlockWatch == nil {
            unlockWatch = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    if !SystemControl.isScreenLocked { self?.screenUnlocked() }
                }
            }
        }
    }

    private func run() async {
        let lockedAt = ProcessInfo.processInfo.systemUptime
        // The lid was just opened or the display woke: scan right away so the Face ID animation shows immediately.
        var scanNow = armed
        while !Task.isCancelled, SystemControl.isScreenLocked {
            if displayAsleep {
                state = .armed
                scanNow = true
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
                    Log.unlock.notice("Armed")
                }
                continue
            }

            if !scanNow {
                state = .armed
                guard let present = await authenticator.waitFor(.faceAppears, timeout: .seconds(30)) else {
                    Log.unlock.error("Camera unavailable while locked: \(self.authenticator.cameraError ?? "busy", privacy: .public)")
                    try? await Task.sleep(for: .seconds(2))
                    continue
                }
                guard present, !Task.isCancelled else { continue }
            }
            scanNow = false

            state = .scanning
            Log.unlock.notice("Verifying face")
            var typedPassword = false
            let verified = await authenticator.authenticate(strict: true, timeout: .seconds(8), preempt: true) {
                guard !Task.isCancelled, SystemControl.isScreenLocked else { return }
                guard let password = LoginPassword.load(allowPrompt: false) else {
                    Log.unlock.error("Saved password could not be read from the Keychain (open FaceMacOS and allow Keychain access)")
                    return
                }
                state = .unlocking
                Log.unlock.notice("Verified; typing password")
                await SystemControl.unlock(password: password)
                typedPassword = true
            }
            guard verified else {
                Log.unlock.notice("Verification failed (score \(self.authenticator.lastScore ?? -1, privacy: .public), camera: \(self.authenticator.cameraError ?? "ok", privacy: .public))")
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            guard !Task.isCancelled, SystemControl.isScreenLocked else { return }
            guard typedPassword else {
                state = .failed("Keychain access needs approval. Open FaceMacOS and choose Always Allow.")
                return
            }
            try? await Task.sleep(for: .seconds(2))
            if SystemControl.isScreenLocked {
                Log.unlock.error("Still locked after typing password")
                state = .failed("Couldn't unlock. Check the saved password and Accessibility permission.")
                return
            }
        }
    }
}

/// Observes a distributed notification with immediate delivery. The block-based API uses NSApplication's default
/// suspension, which holds notifications while the app is inactive (a menu bar app almost always is), so lock and
/// unlock events could arrive late or not at all.
private final class ImmediateDistributedObserver: NSObject {
    private let handler: @MainActor () -> Void

    init(_ name: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(fire), name: Notification.Name(name), object: nil, suspensionBehavior: .deliverImmediately
        )
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func fire() {
        MainActor.assumeIsolated { handler() }
    }
}
