import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var name: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Text(Copy.brand)
                .font(Theme.mono(15, weight: .medium))
                .tracking(4)
                .foregroundStyle(Theme.amber)

            VStack(spacing: 14) {
                Text(Copy.Naming.title)
                    .font(Theme.mono(20, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)

                TextField("", text: $name, prompt: Text(Copy.Naming.placeholder).foregroundStyle(Theme.faint))
                    .font(Theme.mono(22))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($focused)
                    .onSubmit(submit)
                    .onChange(of: name) { _, newValue in
                        let clamped = DisplayName.clampInput(newValue)
                        if clamped != newValue { name = clamped }
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(focused ? Theme.amber : Theme.faint).frame(height: 1)
                    }
                    .accessibilityLabel(Copy.Naming.title)
                    .accessibilityIdentifier("displayNameField")

                Text(Copy.Naming.hint)
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.dim)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)

            Button(action: submit) {
                Text(Copy.Naming.submit)
                    .font(Theme.mono(14, weight: .medium))
                    .foregroundStyle(canSubmit ? Theme.amber : Theme.faint)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .overlay(Capsule().stroke(canSubmit ? Theme.amber : Theme.faint, lineWidth: 1))
            }
            .disabled(!canSubmit)
            .accessibilityIdentifier("continueButton")

            Spacer()
            Spacer()
        }
        .onAppear {
            name = model.profile.displayName ?? ""
            focused = true
        }
    }

    private var canSubmit: Bool { DisplayName.isValid(name) }

    private func submit() {
        guard canSubmit else { return }
        model.submitName(name)
    }
}
