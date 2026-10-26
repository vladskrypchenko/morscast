import SwiftUI

struct SonioxSettingsSection: View {
    @AppStorage(SonioxTranscriber.enabledKey) private var enabled = false
    @State private var draftKey = ""
    @State private var hasKey = SonioxTranscriber.hasKey
    @State private var failure: String?

    var body: some View {
        Section {
            Toggle(isOn: $enabled) {
                Text("Use Soniox")
                Text("Send recordings to Soniox's cloud API instead of a local model.")
            }
            if enabled {
                LabeledContent {
                    HStack(spacing: Theme.Spacing.sm) {
                        SecureField("", text: $draftKey, prompt: Text(hasKey ? "Saved" : "API key"))
                            .labelsHidden()
                            .frame(minWidth: 180)
                        Button("Save") { save(draftKey) }
                            .disabled(draftKey.trimmingCharacters(in: .whitespaces).isEmpty)
                        if hasKey {
                            Button("Remove") { save("") }
                        }
                    }
                } label: {
                    Text("API key")
                    Text(failure ?? (hasKey ? "Stored in the Keychain." : "Required to transcribe."))
                }
            }
        } header: {
            Text("Soniox")
        }
    }

    private func save(_ key: String) {
        do {
            try SonioxTranscriber.setAPIKey(key)
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
        draftKey = ""
        hasKey = SonioxTranscriber.hasKey
    }
}
