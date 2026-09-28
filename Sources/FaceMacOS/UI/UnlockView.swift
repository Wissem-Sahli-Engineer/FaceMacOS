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
    @State private var editingPassword = false
    /// The saved password while it's shown; hidden again automatically.
    @State private var revealedPassword: String?
    @State private var isRevealing = false
    @State private var hideTask: Task<Void, Never>?
    @State private var confirmRemove = false

    var body: some View {
        Form {
            Section {
                Toggle("Unlock the lock screen with Face ID", isOn: $settings.unlockLockScreen)
                LabeledContent("Status") {
                    Text(unlocker.missingRequirement.map { settings.unlockLockScreen ? "Not ready — \($0)" : $0 } ?? unlocker.state.description)
                        .foregroundStyle(unlocker.isReady ? settings.accentColor : Color.secondary)
                }
            } footer: {
                Text("Close the lid (or lock with ⌃⌘Q) and open it again. The Face ID animation appears at the top of the lock screen — look at the camera and blink. FaceMacOS checks your face, then enters your password for you. No clicks needed.")
            }

            Section("Requirements") {
                StepRow(done: auth.isEnrolled, title: "Face ID set up", detail: auth.isEnrolled ? "Your face is enrolled." : "Enroll your face first.") {
                    if !auth.isEnrolled { Button("Set Up…") { controller.enroll() } }
                }

                VStack(alignment: .leading, spacing: 8) {
                    StepRow(done: permissions.passwordStored, title: "Login password saved",
                            detail: "Checked against your account, then stored in your Keychain.")
                    if permissions.passwordStored && !editingPassword {
                        savedPasswordRow
                    } else {
                        HStack {
                            SecureField("Your Mac login password", text: $password)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(savePassword)
                            Button(isSaving ? "Checking…" : "Save", action: savePassword)
                                .disabled(password.isEmpty || isSaving)
                            if editingPassword {
                                Button("Cancel") {
                                    editingPassword = false
                                    password = ""
                                    passwordMessage = nil
                                }
                                .disabled(isSaving)
                            }
                        }
                        .buttonStyle(.bordered)
                        .accessibilityElement(children: .contain)
                    }
                    if let message = passwordMessage {
                        Label(message.text, systemImage: message.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(message.ok ? settings.accentColor : .red)
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

                StepRow(done: settings.launchAtLogin, title: "Open at login (recommended)", detail: "So unlocking works after a restart, and FaceMacOS restarts itself if it stops.") {
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
        .onDisappear(perform: hidePassword)
    }

    private var savedPasswordRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "key.fill").foregroundStyle(.secondary)
            if let revealed = revealedPassword {
                Text(revealed).font(.body.monospaced()).textSelection(.enabled)
            } else {
                Text("••••••••••").foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                revealedPassword == nil ? revealPassword() : hidePassword()
            } label: {
                Image(systemName: revealedPassword == nil ? "eye" : "eye.slash")
            }
            .disabled(isRevealing)
            .help(revealedPassword == nil ? "Show password (asks for Face ID or your Mac password)" : "Hide password")
            Button("Edit") {
                hidePassword()
                passwordMessage = nil
                editingPassword = true
            }
            Button("Remove", role: .destructive) { confirmRemove = true }
        }
        // A Form row can merge several buttons into one control that fires them all;
        // explicit styles and a containing accessibility element keep each button separate.
        .buttonStyle(.bordered)
        .accessibilityElement(children: .contain)
        .confirmationDialog("Remove the saved password?", isPresented: $confirmRemove) {
            Button("Remove Password", role: .destructive) {
                hidePassword()
                LoginPassword.delete()
                passwordMessage = nil
                permissions.refresh()
            }
        } message: {
            Text("Mac Unlock stops working until you save your password again.")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Showing the Mac login password is sensitive, so confirm it's the owner first.
    private func revealPassword() {
        isRevealing = true
        Task {
            defer { isRevealing = false }
            guard await controller.verifyOwner(reason: "show your saved Mac login password") else { return }
            guard let saved = LoginPassword.load() else {
                passwordMessage = ("Couldn't read the saved password from the Keychain.", false)
                return
            }
            revealedPassword = saved
            hideTask?.cancel()
            hideTask = Task {
                try? await Task.sleep(for: .seconds(15))
                if !Task.isCancelled { revealedPassword = nil }
            }
        }
    }

    private func hidePassword() {
        hideTask?.cancel()
        revealedPassword = nil
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
                    editingPassword = false
                } else {
                    passwordMessage = ("Couldn't save to Keychain: \(Keychain.message(for: status))", false)
                }
                permissions.refresh()
            }
        }
    }
}
