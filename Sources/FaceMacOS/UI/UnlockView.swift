import SwiftUI

struct UnlockView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var auth: FaceAuthenticator
    @ObservedObject var settings: AppSettings
    @ObservedObject var unlocker: LockScreenUnlocker
    @ObservedObject private var permissions = Permissions.shared

    @State private var password = ""
    @State private var passwordMessage: (text: String, ok: Bool)?
    @State private var isSaving = false

    var body: some View {
        Form {
            Section {
                Toggle("Unlock the lock screen with Face ID", isOn: $settings.unlockLockScreen)
                LabeledContent("Status") {
                    Text(unlocker.missingRequirement.map { settings.unlockLockScreen ? "Not ready — \($0)" : $0 } ?? unlocker.state.description)
                        .foregroundStyle(unlocker.isReady ? Color.green : Color.secondary)
                }
            } footer: {
                Text("Lock your Mac (⌃⌘Q). After a few seconds, look at the camera and blink. FaceMacOS checks your face, then enters your password for you.")
            }

            Section("Requirements") {
                StepRow(done: auth.isEnrolled, title: "Face ID set up", detail: "Enroll your face first.") {
                    if !auth.isEnrolled { Button("Set Up…") { controller.enroll() } }
                }

                VStack(alignment: .leading, spacing: 8) {
                    StepRow(done: permissions.passwordStored, title: "Login password saved",
                            detail: "Checked against your account, then stored in your Keychain.") {
                        if permissions.passwordStored {
                            Button("Remove") {
                                LoginPassword.delete()
                                passwordMessage = nil
                                permissions.refresh()
                            }
                        }
                    }
                    HStack {
                        SecureField(permissions.passwordStored ? "Replace saved password" : "Your Mac login password", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(savePassword)
                        Button(isSaving ? "Checking…" : "Save", action: savePassword)
                            .disabled(password.isEmpty || isSaving)
                    }
                    if let message = passwordMessage {
                        Label(message.text, systemImage: message.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(message.ok ? .green : .red)
                    }
                }

                StepRow(done: permissions.accessibility, title: "Accessibility permission",
                        detail: permissions.accessibility
                            ? "Granted."
                            : "Turn on FaceMacOS in the list. If it's already on, remove it with − and add it again.") {
                    if !permissions.accessibility {
                        Button("Open Settings…") {
                            SystemControl.requestAccessibility()
                            SystemControl.openAccessibilitySettings()
                        }
                    }
                }

                StepRow(done: settings.launchAtLogin, title: "Launch at login (recommended)", detail: "So unlocking works after a restart.") {
                    if !settings.launchAtLogin { Button("Enable") { settings.setLaunchAtLogin(true) } }
                }
            }

            Section("Good to know") {
                Label("Works on the lock screen and screen saver, not at startup, FileVault login or after logging out.", systemImage: "info.circle")
                Label("A blink is always required here, so a still photo can't unlock your Mac.", systemImage: "eye")
                Label("A regular webcam is less secure than Apple's Face ID. Don't use this on a Mac with sensitive data.", systemImage: "exclamationmark.shield")
                    .foregroundStyle(.orange)
            }
            .font(.callout)
        }
        .formStyle(.grouped)
        .navigationTitle("Mac Unlock")
        .onAppear {
            permissions.refresh()
            unlocker.refresh()
        }
    }

    private func savePassword() {
        let candidate = password
        guard !candidate.isEmpty, !isSaving else { return }
        isSaving = true
        passwordMessage = nil
        Task.detached(priority: .userInitiated) {
            let valid = LoginPassword.verify(candidate)
            await MainActor.run {
                defer {
                    isSaving = false
                    password = ""
                }
                guard valid else {
                    passwordMessage = ("That isn't the login password for \(NSUserName()).", false)
                    return
                }
                let status = LoginPassword.save(candidate)
                if status == errSecSuccess {
                    passwordMessage = ("Password verified and saved.", true)
                } else {
                    passwordMessage = ("Couldn't save to Keychain: \(Keychain.message(for: status))", false)
                }
                permissions.refresh()
            }
        }
    }
}
