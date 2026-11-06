import SwiftUI

struct DebugSettingsView: View {
    @Environment(DebugSettings.self) private var debug
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var debug = debug

        NavigationStack {
            Form {
                Section {
                    urlField(DebugSettings.Defaults.builtInAPIBaseURL, text: $debug.apiBaseURL)
                        .accessibilityIdentifier("apiBaseURLField")
                    if !debug.isAPIBaseURLValid {
                        Text(Copy.Debug.invalidHTTP).foregroundStyle(.red)
                    }
                } header: {
                    Text(Copy.Debug.apiSection)
                } footer: {
                    Text(Copy.Debug.apiFooter)
                }

                Section {
                    urlField(DebugSettings.Defaults.builtInLiveKitURL, text: $debug.liveKitURL)
                        .accessibilityIdentifier("liveKitURLField")
                    if !debug.isLiveKitURLValid {
                        Text(Copy.Debug.invalidWS).foregroundStyle(.red)
                    }
                } header: {
                    Text(Copy.Debug.liveKitSection)
                } footer: {
                    Text(Copy.Debug.liveKitFooter)
                }

                Section {
                    Button(Copy.Debug.reset) { debug.resetToDefaults() }
                    Button(Copy.Debug.resetName, role: .destructive) {
                        model.forgetName()
                        dismiss()
                    }
                } footer: {
                    Text(Copy.Debug.nothingConnects)
                }

                Section {
                    LabeledContent("Bundle ID", value: Bundle.main.bundleIdentifier ?? "—")
                    LabeledContent("Version", value: Self.versionString)
                    LabeledContent("Display name", value: model.profile.displayName ?? "—")
                }
            }
            .font(Theme.mono(14))
            .navigationTitle(Copy.Debug.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Copy.Debug.done) { dismiss() }
                }
            }
        }
    }

    private func urlField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(.URL)
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
