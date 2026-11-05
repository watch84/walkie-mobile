import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var showingDebug = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            Group {
                switch model.phase {
                case .naming:
                    OnboardingView()
                case .tuneIn:
                    TuneInView()
                case .radio:
                    RadioShellView()
                }
            }
            .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.25), value: model.phase)
        #if DEBUG
        .overlay(alignment: .topTrailing) {
            Button {
                showingDebug = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Theme.dim)
                    .padding(16)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Copy.Debug.title)
            .accessibilityIdentifier("debugSettingsButton")
        }
        .sheet(isPresented: $showingDebug) {
            DebugSettingsView()
        }
        #endif
    }
}

#Preview {
    let model = AppModel(defaults: UserDefaults(suiteName: "preview")!)
    RootView()
        .environment(model)
        .environment(model.profile)
        .environment(model.debug)
        .preferredColorScheme(.dark)
}
