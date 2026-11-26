import Foundation

@main
struct DictationTest {
    static func main() {
        let locale = Locale(identifier: "en_US")
        func check(_ actual: String, _ expected: String) {
            guard actual == expected else {
                print("Expected \(expected.debugDescription), got \(actual.debugDescription)")
                exit(1)
            }
        }

        typealias Context = DictationTextFormatter.Context
        check(DictationTextFormatter.format("  Hello. \n", context: nil), "Hello.")
        check(DictationTextFormatter.format("hello", context: Context(before: "", after: "")), "Hello")
        check(DictationTextFormatter.format("World", context: Context(before: "Hello", after: "")), " world")
        check(DictationTextFormatter.format("world", context: Context(before: "Hello.", after: "")), " World")
        check(DictationTextFormatter.format("hello", context: Context(before: "Wait. ", after: "")), "Hello")
        check(
            DictationTextFormatter.format("hello", context: Context(before: "Wait\n  ", after: "")), "Hello")
        check(
            DictationTextFormatter.format("World", context: Context(before: "Hello ", after: "again")),
            "world ")
        check(DictationTextFormatter.format("hello", context: Context(before: "(", after: ")")), "hello")
        check(
            DictationTextFormatter.format("application", context: Context(before: "l’", after: "")),
            "application")
        check(
            DictationTextFormatter.format(
                "Tinycast", context: Context(before: "Use", after: "again"),
                adaptCapitalization: false), " Tinycast ")
        check(
            DictationTextFormatter.format(
                "world", context: Context(before: "Hello.", after: ""),
                adaptCapitalization: false), " world")
        check(
            DictationTextFormatter.format(
                "hello", context: Context(before: "", after: ""),
                adaptCapitalization: false), "hello")
        check(
            DictationTextFormatter.format(
                "World.", context: Context(before: "Hello ", after: ")"),
                adaptCapitalization: false), "World.")
        let document = "prefix. Text to replace suffix"
        check(
            DictationTextFormatter.format(
                "world",
                context: Context(
                    before: document.prefix(7), after: document.suffix(6))), " World ")
        check(DictationTextFormatter.stripEcho(" world peace", after: "Hello world"), " peace")
        check(DictationTextFormatter.stripEcho("theatre tickets", after: "said the"), "theatre tickets")
        check(DictationTextFormatter.stripEcho(" world", after: "Hello world"), "")
        check(DictationTextFormatter.stripEcho("good morning", after: "Hello world"), "good morning")
        check(DictationTextFormatter.stripEcho(" hello", after: ""), " hello")
        check(
            DictationTextFormatter.stripEcho("Für, Jonathan", after: "kein kuchen für"),
            " Jonathan")
        check(
            DictationTextFormatter.stripEcho("ein Kuchen für Jonathan", after: "aber kein Kuchen für"),
            " Jonathan")
        check(
            DictationTextFormatter.stripEcho("äh also weiter gehts", after: "und dann"),
            "äh also weiter gehts")
        check(DictationModel.redux.folderName, "parakeet-redux")
        check(DictationModel.ultra.folderName, "parakeet-ultra")
        check(DictationModel.redux.title, "Parakeet · Redux")
        check(DictationModel.ultra.title, "Parakeet · Ultra")
        check(DictationIdleRelease.allCases.map(\.rawValue).description, "[0, 1, 2, 5, 10, 15, 20, 30, 60]")
        check(DictationIdleRelease.never.title(locale: locale), "Never")
        check(DictationIdleRelease.oneHour.title(locale: locale), "1 hour")
        check(DictationIdleRelease.oneHour.title(locale: Locale(identifier: "fr_FR")), "1\u{00a0}heure")
        check(DictationLanguage.english.displayName(locale: locale), "English")
        check(DictationLanguage.english.displayName(locale: Locale(identifier: "de_DE")), "Englisch")
        check(DictationLanguage.english.rawValue, "English")
        check(DictationModel.qwenSmall.folderName, "qwen-0.6b")
        check(DictationModel.qwenLarge.folderName, "qwen-1.7b")
        for family in DictationModel.Family.allCases {
            guard DictationModel.allCases.contains(where: { $0.family == family }) else {
                fatalError("Every engine should expose at least one model")
            }
        }
        for model in DictationModel.allCases {
            guard !model.components.isEmpty, model.revision.count == 40,
                model.requiredFiles.isSuperset(of: model.components)
            else {
                fatalError("Model installation metadata is incomplete")
            }
            if let configuration = model.parakeetConfiguration {
                guard model.family == .parakeet, configuration.blankToken == 8192,
                    configuration.encoderUsesGPU == (model == .redux),
                    model.components.contains(configuration.joint + ".mlmodelc")
                else {
                    fatalError("Parakeet download and inference disagree")
                }
            } else if !model.isQwen {
                fatalError("Missing Parakeet decoding configuration")
            }
        }
        testTranslation(check: check)
        print("Dictation text formatting passed")
    }

    private static func testTranslation(check: (String, String) -> Void) {
        func channel(_ bundleID: String?, _ title: String?, _ fallback: DictationChannel = .chat)
            -> DictationChannel
        {
            DictationChannel.classify(bundleID: bundleID, windowTitle: title, fallback: fallback)
        }
        func expect(_ condition: Bool, _ message: String) {
            guard condition else { fatalError(message) }
        }
        expect(channel("com.apple.mail", "Slack") == .email, "A mail app is email whatever its title")
        expect(channel("com.tinyspeck.slackmacgap", nil, .email) == .chat, "Slack is a chat")
        expect(channel("com.google.Chrome", "Inbox (3) - me@example.com - Gmail") == .email, "Gmail tab")
        expect(channel("com.google.Chrome", "general | Slack", .email) == .chat, "Slack in a browser")
        expect(channel("com.google.Chrome", "Docs", .email) == .email, "Unknown pages take the fallback")
        expect(channel(nil, nil) == .chat, "Nothing known takes the fallback")
        expect(
            channel("com.microsoft.VSCode", "inbox.md — notes") == .chat,
            "A native app's document title never picks a channel")
        expect(channel("com.apple.Safari", "Gmail", .chat) == .email, "Safari reads the site title")

        let request = DictationTranslationRequest(
            transcript: "  скажи ему что я опоздаю на десять минут \n", appName: "Slack",
            bundleID: "com.tinyspeck.slackmacgap", windowTitle: "general | Acme",
            textBeforeCaret: "")
        let message = DictationTranslationPrompt.message(for: request, channel: .chat)
        expect(message.contains("<app>Slack — general | Acme</app>"), "The app and window are named")
        expect(!message.contains("<text_before_cursor>"), "An empty field sends no context block")
        expect(
            message.hasSuffix("<dictation>\nскажи ему что я опоздаю на десять минут\n</dictation>"),
            "The transcript is trimmed and closes the message")
        let long = DictationTranslationRequest(
            transcript: "ok", appName: nil, bundleID: nil, windowTitle: nil,
            textBeforeCaret: String(repeating: "a", count: 9_000) + "END")
        let bounded = DictationTranslationPrompt.message(for: long, channel: .email)
        expect(bounded.contains("END\n</text_before_cursor>"), "Context keeps the text nearest the caret")
        expect(
            bounded.count < DictationTranslationPrompt.contextLimit + 200, "Context is bounded")

        let plain = DictationTranslationPrompt.instructions(
            spokenLanguage: "Russian", language: "English", channel: .email, guide: "  ",
            channelGuide: "")
        expect(plain.contains("in English"), "The target language is named")
        expect(plain.contains("mostly in Russian"), "The spoken language is named")
        expect(
            DictationTranslationPrompt.instructions(
                spokenLanguage: nil, language: "English", channel: .chat, guide: "", channelGuide: ""
            ).contains("spoke it in any language"), "Auto names no spoken language")
        expect(plain.contains("email body"), "The channel's rules are included")
        expect(!plain.contains("style guide,"), "Blank guides add nothing")
        let guided = DictationTranslationPrompt.instructions(
            spokenLanguage: "Russian", language: "English", channel: .chat, guide: "Sign as Vlad",
            channelGuide: "No emoji")
        expect(
            guided.hasSuffix("chat messages, which wins over everything above:\n\nNo emoji"),
            "The channel guide comes last")
        expect(guided.contains("\n\nSign as Vlad\n\n"), "The general guide precedes it")

        check(DictationTranslationPrompt.clean("  \"Sounds good, thanks!\"  "), "Sounds good, thanks!")
        check(DictationTranslationPrompt.clean("```\nHi Anna,\n\nThanks!\n```"), "Hi Anna,\n\nThanks!")
        check(DictationTranslationPrompt.clean("<message>On it.</message>"), "On it.")
        check(
            DictationTranslationPrompt.clean("\"Ship it\" works, then \"merge\""),
            "\"Ship it\" works, then \"merge\"")
    }
}
