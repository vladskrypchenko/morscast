import SwiftUI

/// A Keychain-backed key: typed once, never shown again, replaced or removed in place.
struct APIKeyRow: View {
    let title: LocalizedStringResource
    let need: LocalizedStringResource
    let hasKey: () -> Bool
    let store: (String) throws -> Void
    @State private var draftKey = ""
    @State private var saved = false
    @State private var failure: String?

    static var soniox: APIKeyRow {
        APIKeyRow(
            title: "Soniox API key", need: "Required to transcribe.",
            hasKey: { SonioxTranscriber.hasKey }, store: SonioxTranscriber.setAPIKey)
    }

    static var claude: APIKeyRow {
        APIKeyRow(
            title: "Claude API key", need: "Required to translate.",
            hasKey: { DictationTranslator.hasClaudeKey }, store: DictationTranslator.setClaudeKey)
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: Theme.Spacing.sm) {
                SecureField("", text: $draftKey, prompt: Text(saved ? "Saved" : "API key"))
                    .labelsHidden()
                    .frame(minWidth: 180)
                Button("Save") { save(draftKey) }
                    .disabled(draftKey.trimmingCharacters(in: .whitespaces).isEmpty)
                if saved {
                    Button("Remove") { save("") }
                }
            }
        } label: {
            Text(title)
            if let failure {
                Text(failure)
            } else {
                Text(saved ? "Stored in the Keychain." : need)
            }
        }
        .onAppear { saved = hasKey() }
    }

    private func save(_ key: String) {
        do {
            try store(key)
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
        draftKey = ""
        saved = hasKey()
    }
}
