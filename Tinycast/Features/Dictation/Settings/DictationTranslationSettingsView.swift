import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// Everything Dictate & Translate needs in one pane, Dictation's shared values included.
struct DictationTranslationSettingsView: View {
    @Environment(DictationCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings
    @Environment(HotKeyManager.self) private var hotKeys
    @State private var microphones: [AVCaptureDevice] = []
    @State private var microphoneAccess = Permissions.microphoneAccess()

    var body: some View {
        Form {
            Section {
                Toggle(isOn: enabledBinding) {
                    SettingsFeatureToggleLabel(
                        anchor: .dictationTranslationDictateTranslate,
                        title: "Enable Dictate & Translate",
                        subtitle: "Speak in Russian; Claude pastes a polished message in English.")
                }
                if settings.dictationTranslationEnabled, microphoneAccess != .authorized {
                    microphoneWarning
                }
            }
            .settingsAnchor(.dictationTranslationDictateTranslate)

            if settings.dictationTranslationEnabled {
                shortcutSection
                speechSection
                claudeSection
                messageSection
                styleSection
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.dictationTranslation)
        .onAppear { microphoneAccess = Permissions.microphoneAccess() }
        // Device discovery takes ~350 ms cold, so it never runs on the pane's first frame.
        .task(id: settings.dictationTranslationEnabled) {
            guard settings.dictationTranslationEnabled else { return }
            microphones = await DictationCapture.discoverMicrophones()
        }
        .task {
            for await _ in NotificationCenter.default.notifications(
                named: NSApplication.didBecomeActiveNotification)
            {
                microphoneAccess = Permissions.microphoneAccess()
            }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.dictationTranslationEnabled },
            set: { coordinator.setTranslationEnabled($0) })
    }

    private var microphoneWarning: some View {
        LabeledContent {
            Button(microphoneAccess == .notDetermined ? "Grant Access…" : "Open System Settings") {
                if microphoneAccess == .notDetermined {
                    Task {
                        _ = await Permissions.requestMicrophoneAccess()
                        microphoneAccess = Permissions.microphoneAccess()
                    }
                } else {
                    Permissions.openMicrophoneSettings()
                }
            }
        } label: {
            Text("Microphone access required")
                .foregroundStyle(.orange)
            Text("Needed to record your dictation.")
        }
    }

    // MARK: - Shortcut

    private var shortcutSection: some View {
        @Bindable var settings = settings
        return Section {
            HStack {
                SettingsRowTitle(.dictationTranslationShortcut, "Shortcut")
                Spacer()
                ShortcutRecorder(action: .dictationTranslate)
            }
            Picker(selection: $settings.dictationMode) {
                ForEach(DictationMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            } label: {
                SettingsRowTitle(.dictationTranslationShortcut, "Shortcut behavior")
                Text("Shared with Dictation.")
            }
        } header: {
            SettingsSectionHeader(.dictationTranslationShortcut)
        } footer: {
            Text(shortcutHint)
                .foregroundStyle(shortcutIssue ? Color.orange : Color.secondary)
        }
    }

    private var shortcutIssue: Bool {
        settings.dictationMode == .pushToTalk
            && hotKeys.binding(for: .dictationTranslate).map { $0.shortcut == nil } == true
    }

    private var shortcutHint: String {
        guard settings.dictationMode == .pushToTalk else {
            return String(localized: "Press to start, press again to translate. Escape cancels.")
        }
        return shortcutIssue
            ? String(localized: "Hold to talk needs a key combination here, not a single modifier.")
            : String(localized: "Hold to talk, release to translate. Escape cancels.")
    }

    // MARK: - Speech

    private var speechSection: some View {
        Section {
            APIKeyRow.soniox
            Picker(selection: spokenLanguageBinding) {
                Text(LocalizedStringResource("dictation-language-auto", defaultValue: "Auto")).tag("")
                Divider()
                ForEach(DictationLanguage.allCases) { language in
                    Text(language.displayName(locale: .current)).tag(language.rawValue)
                }
            } label: {
                SettingsRowTitle(.dictationTranslationSpeech, "You speak")
            }
            Picker(selection: microphoneBinding) {
                Text(microphones.isEmpty ? "No microphone available" : "System default").tag("")
                if !microphones.isEmpty { Divider() }
                ForEach(microphones, id: \.uniqueID) { microphone in
                    Text(microphone.localizedName).tag(microphone.uniqueID)
                }
            } label: {
                SettingsRowTitle(.dictationTranslationSpeech, "Microphone")
                Text("Shared with Dictation.")
            }
        } header: {
            SettingsSectionHeader(.dictationTranslationSpeech)
        } footer: {
            Text("Soniox transcribes as you speak, and the panel shows what it heard.")
        }
    }

    private var spokenLanguageBinding: Binding<String> {
        Binding(
            get: { settings.dictationTranslationSpokenLanguage ?? "" },
            set: { settings.dictationTranslationSpokenLanguage = $0.isEmpty ? nil : $0 })
    }

    private var microphoneBinding: Binding<String> {
        Binding(
            get: { settings.dictationMicrophone ?? "" },
            set: { settings.dictationMicrophone = $0.isEmpty ? nil : $0 })
    }

    // MARK: - Claude

    private var claudeSection: some View {
        @Bindable var settings = settings
        return Section {
            APIKeyRow.claude
            Picker(selection: $settings.dictationTranslationModel) {
                ForEach(DictationTranslationModel.allCases) { model in
                    Text(verbatim: model.title).tag(model)
                }
            } label: {
                SettingsRowTitle(.dictationTranslationModel, "Model")
                Text(settings.dictationTranslationModel.summary)
            }
            Toggle(isOn: $settings.dictationTranslationThinks) {
                SettingsRowTitle(.dictationTranslationModel, "Thinking")
                Text("Off answers faster. Turn it on for long, tangled notes.")
            }
            Picker(selection: $settings.dictationTranslationEffort) {
                ForEach(DictationTranslationEffort.allCases) { effort in
                    Text(effort.title).tag(effort)
                }
            } label: {
                SettingsRowTitle(.dictationTranslationModel, "Effort")
                Text("Low is fastest and is plenty for a message.")
            }
        } header: {
            SettingsSectionHeader(.dictationTranslationModel)
        } footer: {
            Text("Get a key at console.anthropic.com. It is stored in the Keychain on this Mac.")
        }
    }

    // MARK: - Message

    private var messageSection: some View {
        @Bindable var settings = settings
        return Section {
            Picker(selection: $settings.dictationTranslationLanguage) {
                ForEach(DictationLanguage.allCases) { language in
                    Text(language.displayName(locale: .current)).tag(language.rawValue)
                }
            } label: {
                SettingsRowTitle(.dictationTranslationMessage, "Translate into")
            }
            Picker(selection: $settings.dictationTranslationFallbackChannel) {
                ForEach(DictationChannel.allCases) { channel in
                    Text(channel.title).tag(channel)
                }
            } label: {
                SettingsRowTitle(.dictationTranslationMessage, "Other apps")
                Text("For apps that are neither a known mail client nor a known chat.")
            }
        } header: {
            SettingsSectionHeader(.dictationTranslationMessage)
        } footer: {
            Text(
                """
                Mail apps and webmail get an email; Slack, Telegram and other chats get a short \
                message. Text already in the field is sent along so the reply continues it.
                """)
        }
    }

    // MARK: - Style guides

    private var styleSection: some View {
        @Bindable var settings = settings
        return Section {
            StyleGuideRow(
                title: SettingsRowTitle(.dictationTranslationStyle, "General"),
                subtitle: "How you write everywhere: tone, phrases, names, terms.",
                text: $settings.dictationTranslationGuide)
            StyleGuideRow(
                title: SettingsRowTitle(.dictationTranslationStyle, "Messenger"),
                subtitle: "Extra rules for Slack, Telegram and other chats.",
                text: $settings.dictationTranslationChatGuide)
            StyleGuideRow(
                title: SettingsRowTitle(.dictationTranslationStyle, "Email"),
                subtitle: "Extra rules for emails: greeting, structure, sign-off.",
                text: $settings.dictationTranslationEmailGuide)
        } header: {
            SettingsSectionHeader(.dictationTranslationStyle)
        } footer: {
            Text("Write in any language, or add Markdown files. Your guides win over the built-in rules.")
        }
    }
}

/// One guide: a prompt editor and a button that appends a Markdown or text file to it.
private struct StyleGuideRow: View {
    let title: SettingsRowTitle
    let subtitle: LocalizedStringResource
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    title
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: Theme.Spacing.lg)
                Button("Add File…", action: addFile)
            }
            SystemPromptEditor(text: $text)
        }
    }

    private func addFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]
        panel.prompt = String(localized: "Add")
        // Tinycast is an accessory app, so the panel opens behind the frontmost app without this.
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        let added = panel.urls.compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !added.isEmpty else { return }
        let existing = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = ([existing].filter { !$0.isEmpty } + added).joined(separator: "\n\n")
    }
}
