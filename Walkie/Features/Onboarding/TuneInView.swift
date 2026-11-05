import SwiftUI

struct TuneInView: View {
    @Environment(AppModel.self) private var model
    @State private var pulsing = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Button {
                model.tuneIn()
            } label: {
                VStack(spacing: 22) {
                    Circle()
                        .fill(Theme.amber)
                        .frame(width: 10, height: 10)
                        .shadow(color: Theme.amber.opacity(0.9), radius: pulsing ? 14 : 4)
                        .opacity(pulsing ? 1 : 0.6)

                    CapsLabel(text: Copy.TuneIn.action, size: 15, color: Theme.text)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tuneInButton")

            Spacer()

            if let name = model.profile.displayName {
                VStack(spacing: 10) {
                    Text(Copy.TuneIn.greeting(name))
                        .font(Theme.mono(14))
                        .foregroundStyle(Theme.dim)
                    Button(Copy.TuneIn.changeName) { model.changeName() }
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.faint)
                        .accessibilityIdentifier("changeNameButton")
                }
                .padding(.bottom, 32)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }
}
