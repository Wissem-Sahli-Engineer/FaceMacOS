import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("General") {
                Toggle("Show icon in Dock", isOn: $settings.showInDock)
                Toggle("Launch at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                ))
                if let error = settings.launchAtLoginError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
                Toggle("Require a blink to unlock", isOn: $settings.requireBlink)
            } header: {
                Text("Security")
            } footer: {
                Text("Blinking proves a live person is in front of the camera, not a photo. Lock-screen unlock always requires it.")
            }

            Section("Keyboard Shortcuts") {
                LabeledContent("Open vault with Face ID", value: "⌥⌘F")
                LabeledContent("Gesture command", value: "⌥⌘G")
            }

            Section("Animations") {
                Button("Preview Notch Animations") { controller.runDemo() }
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
