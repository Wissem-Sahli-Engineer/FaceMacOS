import AppKit
import SwiftUI

@MainActor
final class VaultModel: ObservableObject {
    private static let account = "vault-note"
    @Published var text = ""

    func unlock() {
        text = Keychain.read(Self.account).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    func saveAndLock() {
        Keychain.write(Data(text.utf8), account: Self.account)
        text = ""
    }

    static func deleteStoredNote() {
        Keychain.delete(account)
    }
}

struct VaultView: View {
    @ObservedObject var model: VaultModel
    @ObservedObject var settings = AppSettings.shared
    let onLock: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Unlocked with Face ID", systemImage: "lock.open.fill")
                .font(.headline)
                .foregroundStyle(settings.accentColor)
            TextEditor(text: $model.text)
                .font(.body.monospaced())
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            HStack {
                Text("Stored encrypted in your Keychain. Locks when closed or when the Mac sleeps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Lock", action: onLock).keyboardShortcut("l")
            }
        }
        .padding(16)
        .frame(minWidth: 420, minHeight: 320)
    }
}

@MainActor
final class VaultWindowController: NSObject, NSWindowDelegate {
    private let model = VaultModel()
    private var window: NSWindow?

    override init() {
        super.init()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(lock), name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(lock), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
    }

    func show() {
        model.unlock()
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "FaceMacOS Vault"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: VaultView(model: model) { [weak self] in self?.lock() })
            window.center()
            self.window = window
        }
        NSApp.bringToFront()
        window?.makeKeyAndOrderFront(nil)
    }

    @objc func lock() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        model.saveAndLock()
    }
}
