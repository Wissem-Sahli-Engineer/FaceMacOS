import SwiftUI
import UniformTypeIdentifiers

struct GesturesView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Enable gesture commands", isOn: $settings.gesturesEnabled)
                Text("Press ⌥⌘G and look at the camera. Once you're recognized, do a gesture to run its action.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Gestures") {
                if settings.actions.isEmpty {
                    Text("No gestures yet.").foregroundStyle(.secondary)
                }
                ForEach($settings.actions) { $action in
                    ActionRow(action: $action) {
                        settings.actions.removeAll { $0.id == action.id }
                    }
                }
                Button {
                    let used = Set(settings.actions.map(\.gesture))
                    let gesture = FaceGesture.allCases.first { !used.contains($0) } ?? .doubleBlink
                    settings.actions.append(FaceAction(gesture: gesture, kind: .openApp))
                } label: {
                    Label("Add Gesture", systemImage: "plus")
                }
            }

            Section {
                Button("Try It Now") { controller.faceCommand() }
                    .disabled(!settings.gesturesEnabled || controller.authenticator.isBusy)
            } footer: {
                Text("Tip: open Live Camera to see which gestures are detected.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Gestures")
    }
}

private struct ActionRow: View {
    @Binding var action: FaceAction
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Picker("Gesture", selection: $action.gesture) {
                ForEach(FaceGesture.allCases) { gesture in
                    Label(gesture.title, systemImage: gesture.symbol).tag(gesture)
                }
            }
            .labelsHidden()
            .frame(width: 140)

            Image(systemName: "arrow.right").foregroundStyle(.secondary)

            Picker("Action", selection: $action.kind) {
                ForEach(ActionKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .labelsHidden()
            .frame(width: 170)

            targetEditor

            Spacer(minLength: 0)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var targetEditor: some View {
        switch action.kind {
        case .openApp:
            Button(action.target.isEmpty ? "Choose App…" : FileManager.default.displayName(atPath: action.target)) {
                chooseApp()
            }
        case .openURL:
            TextField("https://… or ~/Documents/file", text: $action.target)
        case .runShortcut:
            TextField("Shortcut name", text: $action.target)
        case .openVault, .lockScreen:
            EmptyView()
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            action.target = url.path
        }
    }
}
