import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let controller: AppController

    init(controller: AppController) {
        self.controller = controller
    }

    func show(section: MainSection? = nil) {
        if let section { controller.selectedSection = section }
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 860, height: 580),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "FaceMacOS"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 760, height: 500)
            window.delegate = self
            window.contentView = NSHostingView(rootView: MainView(
                controller: controller,
                auth: controller.authenticator,
                settings: controller.settings,
                unlocker: controller.unlocker
            ))
            window.center()
            window.setFrameAutosaveName("FaceMacOSMain")
            self.window = window
        }
        NSApp.bringToFront()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        controller.authenticator.stopMonitor()
    }
}

enum MainSection: String, CaseIterable, Identifiable {
    case overview, camera, gestures, unlock, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .camera: return "Live Camera"
        case .gestures: return "Gestures"
        case .unlock: return "Mac Unlock"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "faceid"
        case .camera: return "video"
        case .gestures: return "hand.wave"
        case .unlock: return "lock.open"
        case .settings: return "gearshape"
        }
    }
}

struct MainView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var auth: FaceAuthenticator
    @ObservedObject var settings: AppSettings
    @ObservedObject var unlocker: LockScreenUnlocker

    var body: some View {
        NavigationSplitView {
            List(MainSection.allCases, selection: $controller.selectedSection) { section in
                Label(section.title, systemImage: section.symbol).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch controller.selectedSection ?? .overview {
            case .overview: OverviewView(controller: controller, auth: auth, settings: settings, unlocker: unlocker)
            case .camera: LiveCameraView(auth: auth, settings: settings)
            case .gestures: GesturesView(controller: controller, settings: settings)
            case .unlock: UnlockView(controller: controller, auth: auth, settings: settings, unlocker: unlocker)
            case .settings: SettingsView(controller: controller, settings: settings)
            }
        }
        .tint(settings.accentColor)
    }
}

struct OverviewView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var auth: FaceAuthenticator
    @ObservedObject var settings: AppSettings
    @ObservedObject var unlocker: LockScreenUnlocker

    var body: some View {
        Form {
            Section {
                HStack(spacing: 20) {
                    FaceIDGlyph()
                        .stroke(auth.isEnrolled ? settings.accentColor : Color.secondary, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        .frame(width: 60, height: 60)
                        .padding(10)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(auth.isEnrolled ? "Face ID is set up" : "Set up Face ID")
                            .font(.title2.bold())
                        Text(auth.isEnrolled
                             ? "Press ⌥⌘F to open your vault or ⌥⌘G for a gesture command."
                             : "Look at your camera and slowly move your head in a circle. It takes about 15 seconds.")
                            .foregroundStyle(.secondary)
                        HStack {
                            if auth.isEnrolled {
                                Button("Test Face ID") { controller.testFaceID() }
                                Button("Set Up Again") { controller.enroll() }
                            } else {
                                Button("Set Up Face ID") { controller.enroll() }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(.top, 4)
                        .disabled(auth.isBusy)
                    }
                }
                .padding(.vertical, 8)
            }

            Section("Getting Started") {
                StepRow(done: auth.isEnrolled, title: "Set up your face", detail: "Required for everything else.")
                StepRow(done: auth.lastScore != nil, title: "Try it", detail: "Press ⌥⌘F. Blink once when you see the Face ID animation.")
                StepRow(done: settings.gesturesEnabled && !settings.actions.isEmpty, title: "Add gestures", detail: "Blink twice or look left to open apps.") {
                    Button("Gestures…") { controller.selectedSection = .gestures }
                }
                StepRow(done: unlocker.isReady, title: "Unlock your Mac (optional)", detail: unlocker.state.description) {
                    Button("Set Up…") { controller.selectedSection = .unlock }
                }
            }

            Section("Recognition") {
                LabeledContent("Face model", value: auth.embedder.displayName)
                if auth.embedder.isDevelopmentFallback {
                    Label("No face model is bundled. Recognition is not reliable.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                LabeledContent("Anti-spoof model", value: auth.spoofClassifier == nil ? "Built-in checks (blink, motion)" : "Loaded")
                if let threshold = auth.threshold {
                    LabeledContent("Match threshold", value: String(format: "%.3f", threshold))
                }
                if let score = auth.lastScore {
                    LabeledContent("Last match score", value: String(format: "%.3f", score))
                }
            }

            if let error = auth.cameraError {
                Section {
                    Label(error, systemImage: "video.slash").foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Overview")
    }
}

struct StepRow<Accessory: View>: View {
    let done: Bool
    let title: String
    let detail: String
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(done ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            accessory()
        }
    }
}

extension StepRow where Accessory == EmptyView {
    init(done: Bool, title: String, detail: String) {
        self.init(done: done, title: title, detail: detail) { EmptyView() }
    }
}
