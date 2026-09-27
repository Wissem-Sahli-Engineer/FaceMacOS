import AppKit
import ApplicationServices
import Carbon.HIToolbox
import IOKit.pwr_mgt
import OpenDirectory

enum SystemControl {
    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static var isScreenLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (session["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue ?? false
    }

    static func wakeDisplay() {
        var assertion: IOPMAssertionID = 0
        IOPMAssertionDeclareUserActivity("FaceMacOS unlock" as CFString, kIOPMUserActiveLocal, &assertion)
    }

    /// Locks via ⌃⌘Q (needs Accessibility); falls back to sleeping the display.
    static func lockScreen() {
        if isAccessibilityTrusted {
            press(CGKeyCode(kVK_ANSI_Q), flags: [.maskCommand, .maskControl])
        } else {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["displaysleepnow"]
            try? process.run()
        }
    }

    /// Types the login password into the lock screen and presses Return.
    static func unlock(password: String) async {
        wakeDisplay()
        try? await Task.sleep(for: .milliseconds(700))
        // A bare Shift tap dismisses the screen saver and focuses the password field without typing anything.
        press(CGKeyCode(kVK_Shift))
        try? await Task.sleep(for: .milliseconds(600))
        type(password)
        try? await Task.sleep(for: .milliseconds(100))
        press(CGKeyCode(kVK_Return))
    }

    private static func type(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        for character in text {
            var units = Array(String(character).utf16)
            for keyDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown)
                event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
                event?.post(tap: .cghidEventTap)
            }
            usleep(12_000)
        }
    }

    private static func press(_ key: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: keyDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }
}

enum LoginPassword {
    private static let account = "login-password"

    static var isStored: Bool { Keychain.exists(account) }

    static func load(allowPrompt: Bool = true) -> String? {
        Keychain.read(account, allowPrompt: allowPrompt).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func save(_ password: String) -> OSStatus {
        Keychain.write(Data(password.utf8), account: account)
    }

    static func delete() {
        Keychain.delete(account)
    }

    /// Checks the password against the current user's account via Open Directory.
    static func verify(_ password: String) -> Bool {
        guard let node = try? ODNode(session: ODSession.default(), type: ODNodeType(kODNodeTypeAuthentication)),
              let record = try? node.record(withRecordType: kODRecordTypeUsers, name: NSUserName(), attributes: nil)
        else { return false }
        return (try? record.verifyPassword(password)) != nil
    }
}
