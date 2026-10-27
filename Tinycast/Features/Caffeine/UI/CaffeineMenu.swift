import SwiftUI

/// The Caffeine rows of the menu-bar menu: a toggle, timed starts and the two preferences.
struct CaffeineMenu: View {
    let caffeine: CaffeineManager

    var body: some View {
        Toggle("Keep Awake", isOn: Binding(get: { caffeine.isActive }, set: { _ in caffeine.toggle() }))
        Menu("Keep Awake For") {
            if caffeine.isActive {
                if let endsAt = caffeine.endsAt {
                    Text("Until \(endsAt.formatted(date: .omitted, time: .shortened))")
                } else {
                    Text("Until turned off")
                }
                Divider()
            }
            Button("Indefinitely") { caffeine.activate(for: nil) }
            ForEach(CaffeineManager.durations, id: \.self) { duration in
                Button(Self.label(duration)) { caffeine.activate(for: duration) }
            }
            Divider()
            Picker("Default Duration", selection: defaultDuration) {
                Text("Indefinitely").tag(Duration?.none)
                ForEach(CaffeineManager.durations, id: \.self) { duration in
                    Text(Self.label(duration)).tag(Optional(duration))
                }
            }
            Toggle("Activate at Launch", isOn: activatesAtLaunch)
        }
    }

    private static func label(_ duration: Duration) -> String {
        duration.formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }

    private var defaultDuration: Binding<Duration?> {
        Binding(get: { caffeine.defaultDuration }, set: { caffeine.defaultDuration = $0 })
    }

    private var activatesAtLaunch: Binding<Bool> {
        Binding(get: { caffeine.activatesAtLaunch }, set: { caffeine.activatesAtLaunch = $0 })
    }
}
