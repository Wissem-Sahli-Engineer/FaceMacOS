import AppKit

enum FaceGesture: String, Codable, CaseIterable, Identifiable {
    case doubleBlink, tripleBlink, lookLeft, lookRight, lookUp, lookDown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .doubleBlink: return "Blink twice"
        case .tripleBlink: return "Blink 3 times"
        case .lookLeft: return "Look left"
        case .lookRight: return "Look right"
        case .lookUp: return "Look up"
        case .lookDown: return "Look down"
        }
    }

    var symbol: String {
        switch self {
        case .doubleBlink, .tripleBlink: return "eye"
        case .lookLeft: return "arrow.left"
        case .lookRight: return "arrow.right"
        case .lookUp: return "arrow.up"
        case .lookDown: return "arrow.down"
        }
    }
}

enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case openVault, openApp, openURL, runShortcut, lockScreen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openVault: return "Open Vault"
        case .openApp: return "Open App"
        case .openURL: return "Open Website / File"
        case .runShortcut: return "Run Shortcut"
        case .lockScreen: return "Lock Screen"
        }
    }
}

struct FaceAction: Codable, Identifiable, Equatable {
    var id = UUID()
    var gesture: FaceGesture
    var kind: ActionKind
    var target: String = ""

    var summary: String {
        switch kind {
        case .openVault: return "Opening Vault"
        case .openApp: return "Opening \(URL(fileURLWithPath: target).deletingPathExtension().lastPathComponent)"
        case .openURL: return "Opening \(target)"
        case .runShortcut: return "Running \(target)"
        case .lockScreen: return "Locking"
        }
    }

    static let defaults: [FaceAction] = [
        FaceAction(gesture: .doubleBlink, kind: .openVault),
        FaceAction(gesture: .lookLeft, kind: .openApp, target: "/Applications/Safari.app"),
        FaceAction(gesture: .lookRight, kind: .lockScreen),
    ]
}

@MainActor
enum ActionRunner {
    static func run(_ action: FaceAction, openVault: () -> Void) {
        let target = action.target.trimmingCharacters(in: .whitespaces)
        switch action.kind {
        case .openVault:
            openVault()
        case .openApp:
            guard !target.isEmpty else { return }
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: target), configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        case .openURL:
            guard !target.isEmpty else { return }
            if let url = URL(string: target), url.scheme != nil {
                NSWorkspace.shared.open(url)
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath: (target as NSString).expandingTildeInPath))
            }
        case .runShortcut:
            guard !target.isEmpty else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", target]
            try? process.run()
        case .lockScreen:
            SystemControl.lockScreen()
        }
    }
}
