import SwiftUI

/// Colour and type tokens from the web client's `radio.css`.
enum Theme {
    static let background = Color.black
    static let amber = Color(hex: 0xFABE3E)
    static let amberDim = Color(hex: 0xBE9036)
    static let ink = Color(hex: 0xFBFAF7)
    static let muted = Color(hex: 0x8E8B87)
    static let faintInk = Color(hex: 0x4A4946)
    static let red = Color(hex: 0xFF4B33)
    /// Raised surfaces (PTT face, pills) on the black background.
    static let surface = Color(hex: 0x161514)

    static let text = ink
    static let dim = muted
    static let faint = faintInk

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// Uppercase, widely tracked monospace label used for captions on the radio UI.
struct CapsLabel: View {
    let text: String
    var size: CGFloat = 13
    var color: Color = Theme.dim

    var body: some View {
        Text(text.uppercased())
            .font(Theme.mono(size, weight: .medium))
            .tracking(size * 0.28)
            .foregroundStyle(color)
    }
}

/// Rounded status pill (`.pill` in radio.css).
struct Pill<Content: View>: View {
    var stroke: Color = Theme.faint
    var fill: Color = Theme.surface
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 8) { content }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(fill))
            .overlay(Capsule().stroke(stroke, lineWidth: 1))
    }
}
