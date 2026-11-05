import SwiftUI

/// Placeholder for the radio screen. The dial, channel readout and push-to-talk
/// arrive in later milestones; this only reserves the layout.
struct RadioShellView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 18) {
                Text("—.—")
                    .font(Theme.mono(44, weight: .regular))
                    .foregroundStyle(Theme.text)
                TickRow()
                    .frame(height: 34)
                    .padding(.horizontal, 28)
                CapsLabel(text: Copy.Radio.placeholder, size: 13)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("radioPlaceholder")

            Spacer()

            if let name = model.profile.displayName {
                Button(Copy.Radio.you(name)) { model.editName() }
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.dim)
                    .padding(.bottom, 32)
                    .accessibilityIdentifier("editNameButton")
            }
        }
    }
}

/// Static, inert stand-in for the dial's tick marks.
private struct TickRow: View {
    var body: some View {
        GeometryReader { geo in
            let count = 17
            let spacing = geo.size.width / CGFloat(count - 1)
            ZStack(alignment: .leading) {
                ForEach(0..<count, id: \.self) { i in
                    let distance = abs(CGFloat(i) - CGFloat(count - 1) / 2) / (CGFloat(count - 1) / 2)
                    Capsule()
                        .fill(Theme.text.opacity(0.65 - 0.4 * distance))
                        .frame(width: 2, height: geo.size.height * (1 - 0.35 * distance))
                        .position(x: CGFloat(i) * spacing, y: geo.size.height / 2)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
