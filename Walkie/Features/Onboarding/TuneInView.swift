import SwiftUI

struct TuneInView: View {
    @Environment(AppModel.self) private var model
    @State private var pulsing = false

    var body: some View {
        Button {
            model.tuneIn()
        } label: {
            VStack(spacing: 22) {
                Circle()
                    .fill(Theme.amber)
                    .frame(width: 10, height: 10)
                    .shadow(color: Theme.amber.opacity(0.9), radius: pulsing ? 14 : 4)
                    .opacity(pulsing ? 1 : 0.6)

                Text(Copy.TuneIn.title)
                    .font(Theme.mono(18, weight: .medium))
                    .foregroundStyle(Theme.text)

                Text(Copy.TuneIn.hint)
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.dim)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tuneInButton")
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }
}
