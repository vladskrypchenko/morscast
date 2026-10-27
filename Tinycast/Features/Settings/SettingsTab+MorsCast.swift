/// MorsCast keeps every feature but lists only the everyday panes; the rest sit under Show More.
extension SettingsTab {
    static let tucked: [SettingsTab] = [
        .systemSettings, .systemActions, .commands, .quicklinks, .appleShortcuts, .fallbacks,
        .fileSearch, .windowManagement, .navigation, .notes, .calendar, .emoji, .ai,
        .quickActions, .extensions
    ]

    var isTucked: Bool { Self.tucked.contains(self) }
}
