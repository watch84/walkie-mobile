import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var name: String = ""
    @State private var error: DisplayName.ValidationError?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            CapsLabel(text: Copy.appName, size: 15, color: Theme.amber)

            Text(Copy.Naming.title)
                .font(Theme.mono(20, weight: .medium))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
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
                        error = nil
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(focused ? Theme.amber : Theme.faint).frame(height: 1)
                    }
                    .accessibilityIdentifier("displayNameField")

                HStack {
                    Text(errorText ?? " ")
                        .foregroundStyle(Theme.amber)
                    Spacer()
                    Text("\(name.count)/\(DisplayName.maxLength)")
                        .foregroundStyle(Theme.dim)
                }
                .font(Theme.mono(12))
            }
            .padding(.horizontal, 40)

            Button(action: submit) {
                CapsLabel(text: Copy.Naming.submit, size: 14,
                          color: canSubmit ? Theme.amber : Theme.faint)
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

    private var errorText: String? {
        switch error {
        case .empty: Copy.Naming.empty
        case .tooLong: Copy.Naming.tooLong
        case nil: nil
        }
    }

    private func submit() {
        if case .failure(let failure) = model.submitName(name) {
            error = failure
        }
    }
}
