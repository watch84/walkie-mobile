import SwiftUI

enum Theme {
    static let background = Color.black
    static let amber = Color("AccentColor")
    static let text = Color.white
    static let dim = Color.white.opacity(0.55)
    static let faint = Color.white.opacity(0.18)

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
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
