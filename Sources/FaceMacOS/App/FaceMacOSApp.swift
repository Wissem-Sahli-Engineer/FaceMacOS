import SwiftUI

@main
struct FaceMacOSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("FaceMacOS", systemImage: "faceid") {
            MenuContent(controller: appDelegate.controller, auth: appDelegate.controller.authenticator,
                        settings: appDelegate.controller.settings, unlocker: appDelegate.controller.unlocker)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let showWindowNotification = Notification.Name("com.facemacos.app.showWindow")

    let controller = AppController()
    private var showWindowObserver: NSObjectProtocol?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Only one copy may run (login agent + Finder could both start one). A second copy asks the first to show its
        // window and exits successfully, so the login agent doesn't relaunch it.
        var others = Self.otherInstances()
        if CommandLine.arguments.contains(AppSettings.takeoverArgument) {
            // Replacing a copy that is about to be stopped with the login agent: wait for it to exit.
            for _ in 0..<50 where !others.isEmpty {
                usleep(100_000)
                others = Self.otherInstances()
            }
        }
        if let running = others.first {
            DistributedNotificationCenter.default().postNotificationName(Self.showWindowNotification, object: nil, deliverImmediately: true)
            running.activate(options: [])
            exit(0)
        }
    }

    private static func otherInstances() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != getpid() && !$0.isTerminated }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        showWindowObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.showWindowNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.controller.showMainWindow() }
        }
        controller.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller.showMainWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

struct MenuContent: View {
    @ObservedObject var controller: AppController
    @ObservedObject var auth: FaceAuthenticator
    @ObservedObject var settings: AppSettings
    @ObservedObject var unlocker: LockScreenUnlocker

    var body: some View {
        Button("Open FaceMacOS…") { controller.showMainWindow() }

        Divider()

        if auth.isEnrolled {
            Button("Open Vault  (⌥⌘F)") { controller.openVault() }
            if settings.gesturesEnabled {
                Button("Gesture Command  (⌥⌘G)") { controller.faceCommand() }
            }
            Button("Test Face ID") { controller.testFaceID() }
        } else {
            Button("Set Up Face ID…") { controller.enroll() }
        }

        Divider()

        Text("Mac Unlock: \(unlocker.state.description)")
        if auth.embedder.isDevelopmentFallback {
            Text("⚠︎ No face model installed")
        }

        Divider()

        Button("Quit FaceMacOS") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
