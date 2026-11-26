import Foundation

/// Dictate & Translate's own Claude route: its key, its model, one streamed request per press.
@MainActor
final class DictationTranslator: DictationTranslating {
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    static let keychain = KeychainSecretStore(scope: "dictation-translation")
    private static let keyAccount = UUID(uuidString: "2F6C9B1E-7A4D-4E8B-B3C5-91D0E6A47F28")!
    private static let endpoint = URL(string: "https://api.anthropic.com")!

    static var hasClaudeKey: Bool { (try? keychain.hasSecret(for: keyAccount)) ?? false }

    static func setClaudeKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try keychain.removeSecret(for: keyAccount)
        } else {
            try keychain.setSecret(trimmed, for: keyAccount)
        }
    }

    func issue() -> String? {
        guard settings.dictationTranslationEnabled else {
            return String(localized: "Turn on Dictate & Translate in Settings")
        }
        guard SonioxTranscriber.hasKey else {
            return String(localized: "Add a Soniox API key in Dictate & Translate settings")
        }
        guard Self.hasClaudeKey else {
            return String(localized: "Add a Claude API key in Dictate & Translate settings")
        }
        return nil
    }

    func translate(
        _ request: DictationTranslationRequest, onText: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        guard let key = try? Self.keychain.secret(for: Self.keyAccount), !key.isEmpty else {
            throw AIProviderError.unavailable(
                String(localized: "Add a Claude API key in Dictate & Translate settings"))
        }
        let provider = HTTPAIProvider(
            configuration: AIHTTPConfiguration(
                provider: .anthropic, baseURL: Self.endpoint,
                model: settings.dictationTranslationModel.rawValue),
            apiKey: key)
        let channel = DictationChannel.classify(
            bundleID: request.bundleID, windowTitle: request.windowTitle,
            fallback: settings.dictationTranslationFallbackChannel)
        let instructions = DictationTranslationPrompt.instructions(
            spokenLanguage: settings.dictationTranslationSpokenLanguage,
            language: settings.dictationTranslationLanguage, channel: channel,
            guide: settings.dictationTranslationGuide,
            channelGuide: channel == .email
                ? settings.dictationTranslationEmailGuide : settings.dictationTranslationChatGuide)
        let aiRequest = AIRequest(
            instructions: instructions,
            messages: [
                AIMessage(
                    role: .user, text: DictationTranslationPrompt.message(for: request, channel: channel))
            ],
            maxOutputTokens: Self.maxOutputTokens,
            reasoning: AIReasoning(
                thinks: settings.dictationTranslationThinks,
                effort: settings.dictationTranslationEffort.rawValue))
        var text = ""
        for try await event in provider.stream(aiRequest) {
            try Task.checkCancellation()
            guard case .text(let delta) = event else { continue }
            text += delta
            onText(text)
        }
        let cleaned = DictationTranslationPrompt.clean(text)
        guard !cleaned.isEmpty else {
            throw AIProviderError.responseFailed(String(localized: "The model returned nothing."))
        }
        return cleaned
    }

    /// Room for thinking as well as a long email, which a dictated note rarely outgrows.
    private static let maxOutputTokens = 8_192
}
