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
    let controller = AppController()

    func applicationDidFinishLaunching(_ notification: Notification) {
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
