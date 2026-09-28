import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Show icon in Dock", isOn: $settings.showInDock)
                Toggle("Open at login and keep running", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                ))
                if settings.launchAtLoginNeedsApproval {
                    HStack {
                        Label("Allow FaceMacOS in Login Items to finish turning this on.", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Open Login Items…") { settings.openLoginItemsSettings() }
                    }
                    .font(.callout)
                }
                if let error = settings.launchAtLoginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("General")
            } footer: {
                Text("FaceMacOS starts when you log in and restarts itself if it stops unexpectedly. Closing the window keeps it running in the menu bar; choose Quit from the menu bar icon to stop it until your next login.")
            }

            Section("Appearance") {
                LabeledContent("Accent color") {
                    HStack(spacing: 8) {
                        ForEach(AccentChoice.allCases.filter { $0 != .custom }) { choice in
                            AccentSwatch(color: choice.color, selected: settings.accent == choice) {
                                settings.accent = choice
                            }
                            .help(choice.title)
                        }
                        ColorPicker("Custom", selection: Binding(
                            get: { settings.customAccent },
                            set: { settings.customAccent = $0; settings.accent = .custom }
                        ), supportsOpacity: false)
                        .labelsHidden()
                        .help("Custom color")
                        .overlay {
                            if settings.accent == .custom {
                                Circle().stroke(Color.primary, lineWidth: 2).frame(width: 30, height: 30).allowsHitTesting(false)
                            }
                        }
                    }
                }
                LabeledContent("Preview") {
                    Button("Play Notch Animations") { controller.runDemo() }
                }
            }

            Section {
                Toggle("Require a blink to unlock", isOn: $settings.requireBlink)
            } header: {
                Text("Security")
            } footer: {
                Text("Blinking proves a live person is in front of the camera, not a photo. Lock-screen unlock always requires it.")
            }

            UpdatesSection(updater: controller.updater)

            Section("Keyboard Shortcuts") {
                LabeledContent("Open vault with Face ID", value: "⌥⌘F")
                LabeledContent("Gesture command", value: "⌥⌘G")
            }

            Section {
                Button("Delete All Data…", role: .destructive) { controller.deleteAllData() }
            } footer: {
                Text("Removes your face data, vault note and saved login password from the Keychain.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}

private struct UpdatesSection: View {
    @ObservedObject var updater: Updater

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        Section {
            Toggle("Check for updates automatically", isOn: Binding(
                get: { updater.automaticallyChecks },
                set: { updater.automaticallyChecks = $0 }
            ))
            LabeledContent("Version \(version)") {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
        } header: {
            Text("Updates")
        } footer: {
            if let lastCheck = updater.lastCheck {
                Text("Last checked \(lastCheck.formatted(.relative(presentation: .named))). Updates are verified before they're installed.")
            } else {
                Text("FaceMacOS checks about once a day when you're online. Updates are verified before they're installed.")
            }
        }
    }
}

private struct AccentSwatch: View {
    let color: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 20, height: 20)
                .overlay { Circle().stroke(Color.primary.opacity(selected ? 1 : 0), lineWidth: 2).padding(-4) }
                .padding(4)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
