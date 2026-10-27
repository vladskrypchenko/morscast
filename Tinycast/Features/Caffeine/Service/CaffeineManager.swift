import Foundation

/// Keeps the Mac and its display awake, indefinitely or for a set time, like Caffeine.
@MainActor
@Observable
final class CaffeineManager {
    static let durations: [Duration] = [
        .seconds(5 * 60), .seconds(10 * 60), .seconds(15 * 60), .seconds(30 * 60),
        .seconds(3600), .seconds(2 * 3600), .seconds(5 * 3600)
    ]

    private static let activatesAtLaunchKey = "caffeineActivatesAtLaunch"
    private static let defaultMinutesKey = "caffeineDefaultMinutes"

    private(set) var isActive = false
    /// Nil while active indefinitely.
    private(set) var endsAt: Date?

    var activatesAtLaunch: Bool {
        didSet { UserDefaults.standard.set(activatesAtLaunch, forKey: Self.activatesAtLaunchKey) }
    }

    /// What a plain toggle uses; nil means indefinitely.
    var defaultDuration: Duration? {
        didSet {
            let minutes = defaultDuration.map { Int($0.components.seconds / 60) } ?? 0
            UserDefaults.standard.set(minutes, forKey: Self.defaultMinutesKey)
        }
    }

    @ObservationIgnored private var activity: (any NSObjectProtocol)?
    @ObservationIgnored private var expiry: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        activatesAtLaunch = defaults.bool(forKey: Self.activatesAtLaunchKey)
        let minutes = defaults.integer(forKey: Self.defaultMinutesKey)
        defaultDuration = minutes > 0 ? .seconds(minutes * 60) : nil
    }

    func start() {
        if activatesAtLaunch { activate(for: defaultDuration) }
    }

    /// Returns the resulting state, so a caller can report it.
    @discardableResult
    func toggle() -> Bool {
        if isActive { deactivate() } else { activate(for: defaultDuration) }
        return isActive
    }

    func activate(for duration: Duration?) {
        expiry?.cancel()
        if activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled],
                reason: "Caffeine keeps the Mac awake")
        }
        isActive = true
        guard let duration else {
            endsAt = nil
            expiry = nil
            return
        }
        endsAt = Date.now.addingTimeInterval(TimeInterval(duration.components.seconds))
        // The continuous clock keeps counting while the Mac sleeps, so the deadline stays real.
        expiry = Task { [weak self] in
            try? await Task.sleep(for: duration, clock: .continuous)
            guard !Task.isCancelled else { return }
            self?.deactivate()
        }
    }

    func deactivate() {
        expiry?.cancel()
        expiry = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        isActive = false
        endsAt = nil
    }
}
