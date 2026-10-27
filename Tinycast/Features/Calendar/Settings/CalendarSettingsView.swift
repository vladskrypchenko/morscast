import SwiftUI

struct CalendarSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @Environment(CalendarStore.self) private var store

    var body: some View {
        @Bindable var settings = settings
        Form {
            CalendarPermissionSection()

            FeatureSwitchSection(
                anchor: .calendarCalendar,
                enableTitle: "Join meetings from Tinycast",
                enableSubtitle: enableSubtitle,
                isEnabled: enabledBinding,
                showsInLauncher: $settings.calendarShowInLauncher,
                showsIcon: true,
                showsHeader: false)

            Section {
                Picker(selection: $settings.calendarLauncherLimit) {
                    ForEach(CalendarLauncherLimit.allCases) { limit in
                        Text(limit.title).tag(limit)
                    }
                } label: {
                    SettingsRowTitle(.calendarCalendar, "Upcoming meetings in launcher")
                }
            }
            .settingsEnabled(settings.calendarEnabled && settings.calendarShowInLauncher)

            Section {
                Picker(selection: $settings.joinWindowMinutes) {
                    ForEach(JoinWindow.allCases) { window in
                        Text(window.title).tag(window)
                    }
                } label: {
                    SettingsRowTitle(.calendarJoining, "Show the meeting card")
                    Text("Before and after a meeting starts.")
                }
                Toggle(isOn: $settings.autoJoinMeetings) {
                    SettingsRowTitle(.calendarJoining, "Auto Join Meetings")
                    Text("As they start.")
                }
                Toggle(isOn: $settings.autoJoinNamedProvidersOnly) {
                    SettingsRowTitle(.calendarJoining, "Only join known meeting services")
                }
                .toggleStyle(.checkbox)
                .settingsEnabled(settings.autoJoinMeetings)
                Toggle(isOn: $settings.autoJoinConfirms) {
                    SettingsRowTitle(.calendarJoining, "Confirm before joining")
                }
                .toggleStyle(.checkbox)
                .settingsEnabled(settings.autoJoinMeetings)
                Toggle(isOn: $settings.cameraPreview) {
                    SettingsRowTitle(.calendarJoining, "Camera Preview")
                    Text("Before joining a meeting.")
                }
                MeetingBrowserPicker(selection: $settings.meetingBrowserBundleID)
            } header: {
                SettingsSectionHeader(.calendarJoining)
            }
            .settingsEnabled(settings.calendarEnabled)

            Section {
                Picker(selection: $settings.calendarMenuBarDisplay) {
                    ForEach(CalendarMenuBarDisplay.allCases) { display in
                        Text(display.title).tag(display)
                    }
                } label: {
                    SettingsRowTitle(.calendarMenuBar, "Calendar in Menu Bar")
                    Text("Separate from the Tinycast icon.")
                }
                Picker(selection: $settings.calendarSpan) {
                    ForEach(MeetingSpan.allCases) { span in
                        Text(span.title).tag(span)
                    }
                } label: {
                    SettingsRowTitle(.calendarMenuBar, "Days to Show")
                    Text("In the menu, My Schedule and launcher search.")
                }
                Picker(selection: $settings.menuBarEvents) {
                    ForEach(MenuBarEvents.allCases) { lead in
                        Text(lead.title).tag(lead)
                    }
                } label: {
                    SettingsRowTitle(.calendarMenuBar, "Show Upcoming Events")
                    Text("When the next event appears.")
                }
                .settingsEnabled(settings.calendarMenuBarDisplay != .disabled)
                Toggle(isOn: $settings.menuBarLinkedEventsOnly) {
                    SettingsRowTitle(.calendarMenuBar, "Only show events with meetings")
                }
                .toggleStyle(.checkbox)
                .settingsEnabled(settings.calendarMenuBarDisplay != .disabled)
                Toggle(isOn: $settings.calendarMenuBarHidesWhenEmpty) {
                    SettingsRowTitle(.calendarMenuBar, "Hide when there are no upcoming events")
                }
                .toggleStyle(.checkbox)
                .settingsEnabled(settings.calendarMenuBarDisplay != .disabled)
                Picker(selection: $settings.hideCurrentEvent) {
                    ForEach(HideCurrentEvent.allCases) { hide in
                        Text(hide.title).tag(hide)
                    }
                } label: {
                    SettingsRowTitle(.calendarMenuBar, "Hide Current Event")
                    Text("Once it has started.")
                }
                .settingsEnabled(settings.calendarMenuBarDisplay != .disabled)
            } header: {
                SettingsSectionHeader(.calendarMenuBar)
            }
            .settingsEnabled(settings.calendarEnabled)

            FeatureCommandsSection(owner: .calendar, anchor: .calendarCommands)
                .settingsEnabled(settings.calendarEnabled)

            CalendarPickerSection()
                .settingsEnabled(settings.calendarEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.calendar)
        .releasesFocusOnOutsideClick()
        // The snapshot reloads only while the feature runs, so a Settings grant lands here.
        .onAppear { store.refreshAccess() }
    }

    private var enableSubtitle: LocalizedStringResource {
        switch settings.calendarSpan {
        case .today:
            "Reads today's events for join links. Nothing leaves this Mac."
        case .todayAndTomorrow:
            "Reads today's and tomorrow's events for join links. Nothing leaves this Mac."
        case .nextSevenDays:
            "Reads the next 7 days' events for join links. Nothing leaves this Mac."
        }
    }

    /// Routed through the coordinator so enabling, which is also consent, confirms first.
    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.calendarEnabled },
            set: { core.calendarCoordinator.setCalendarEnabled($0) }
        )
    }
}

private struct MeetingBrowserPicker: View {
    @Binding var selection: String?
    @State private var browsers: [MeetingLauncher.Browser] = []

    var body: some View {
        Picker(selection: installedSelection) {
            Text("Default Browser").tag(String?.none)
            Divider()
            ForEach(browsers) { browser in
                Text(browser.name).tag(Optional(browser.id))
            }
        } label: {
            SettingsRowTitle(.calendarJoining, "Open Meeting Links In")
            Text("When no meeting app handles the link.")
        }
        .onAppear { browsers = MeetingLauncher.installedBrowsers() }
    }

    /// A browser since removed reads as the default, which is what joining falls back to.
    private var installedSelection: Binding<String?> {
        Binding(
            get: { browsers.contains { $0.id == selection } ? selection : nil },
            set: { selection = $0 }
        )
    }
}

/// Machine-local by nature, so these live on the store and never travel in a backup.
private struct CalendarPickerSection: View {
    @Environment(CalendarStore.self) private var store
    @State private var query = ""

    private var calendars: [MeetingCalendar] {
        guard !query.isEmpty else { return store.calendars }
        return store.calendars.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.accountName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        Section {
            SettingsFilterField(prompt: "Search calendars…", query: $query)

            if calendars.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ForEach(calendars) { calendar in
                    CalendarRow(calendar: calendar)
                }
            }
        } header: {
            SettingsSectionHeader(.calendarCalendars)
        }
    }

    private var emptyMessage: String {
        if !query.isEmpty { return String(localized: "No matches for “\(query)”.") }
        return store.access == .granted
            ? String(localized: "No calendars on this Mac.") : String(localized: "Nothing to show yet.")
    }
}

private struct CalendarRow: View {
    let calendar: MeetingCalendar
    @Environment(CalendarStore.self) private var store

    var body: some View {
        SettingsRow(title: calendar.title, subtitle: calendar.accountName) {
            Toggle("", isOn: binding)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .accessibilityLabel("Include \(calendar.title) in meetings")
        }
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { store.isEnabled(calendar) },
            set: { store.setEnabled($0, for: calendar) }
        )
    }
}

/// MorsCast keeps the calendar grant beside the feature that needs it, not on Permissions.
private struct CalendarPermissionSection: View {
    @Environment(AppCore.self) private var core
    @Environment(CalendarStore.self) private var store

    var body: some View {
        Section {
            SettingsRow(
                title: String(localized: "Calendar access"),
                subtitle: String(localized: "Needed to read events and find join links.")
            ) {
                HStack(spacing: Theme.Spacing.lg) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: status.symbol).accessibilityHidden(true)
                        Text(status.title)
                    }
                    .foregroundStyle(status.tint)
                    Button(store.access == .notDetermined ? "Grant Access…" : "Open…") {
                        // Settings lists no app TCC was never asked about, so asking is the way in.
                        if store.access == .notDetermined {
                            core.calendarCoordinator.setCalendarEnabled(true)
                        } else {
                            Permissions.openCalendarSettings()
                        }
                    }
                }
            }
        }
    }

    private var status: (title: String, symbol: String, tint: Color) {
        switch store.access {
        case .granted: (String(localized: "Granted"), "checkmark.circle.fill", .green)
        case .notDetermined: (String(localized: "Not asked yet"), "questionmark.circle.fill", .secondary)
        case .denied: (String(localized: "Not granted"), "exclamationmark.triangle.fill", .orange)
        }
    }
}
