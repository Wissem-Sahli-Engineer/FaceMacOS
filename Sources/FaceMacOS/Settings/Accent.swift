import AppKit
import SwiftUI

/// The interface accent color, used for the notch animation, progress rings and checkmarks.
enum AccentChoice: String, CaseIterable, Identifiable {
    case green, blue, purple, pink, red, orange, yellow, teal, custom

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    /// Preset color; `custom` falls back to green (callers use the stored custom color instead).
    var color: Color {
        switch self {
        case .green, .custom: return Color(red: 0.20, green: 0.84, blue: 0.40)
        case .blue: return Color(red: 0.04, green: 0.52, blue: 1.00)
        case .purple: return Color(red: 0.69, green: 0.32, blue: 0.87)
        case .pink: return Color(red: 1.00, green: 0.22, blue: 0.47)
        case .red: return Color(red: 1.00, green: 0.27, blue: 0.23)
        case .orange: return Color(red: 1.00, green: 0.62, blue: 0.04)
        case .yellow: return Color(red: 1.00, green: 0.84, blue: 0.04)
        case .teal: return Color(red: 0.19, green: 0.78, blue: 0.82)
        }
    }
}

extension Color {
    init?(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    var hex: String {
        guard let rgb = NSColor(self).usingColorSpace(.sRGB) else { return "#33D666" }
        func byte(_ component: CGFloat) -> Int { Int((min(max(component, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(rgb.redComponent), byte(rgb.greenComponent), byte(rgb.blueComponent))
    }
}
