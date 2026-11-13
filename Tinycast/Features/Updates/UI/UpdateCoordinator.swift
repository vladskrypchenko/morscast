import Foundation

/// The installer only performs an update the coordinator has decided to run.
@MainActor
@Observable
final class UpdateCoordinator {
    enum Stage: Equatable {
        case idle
        case checking
        case available(AvailableRelease)
        case installing(AvailableRelease, UpdateInstaller.Phase)
        case readyToRelaunch
        case failed(UpdateFailure)
    }

    private(set) var stage: Stage = .idle

    private let store: UpdateCheckStore
    /// For other features only — never for state this type owns.
    private unowned let core: AppCore
    @ObservationIgnored private var installTask: Task<Void, Never>?
    /// The bundle on disk is already the new version, so only a relaunch is left to offer.
    @ObservationIgnored private var isInstalled = false

    init(store: UpdateCheckStore, core: AppCore) {
        self.store = store
        self.core = core
    }

    /// A local build has no release stream, so it does not advertise the command either.
    func applyEnabled() {
        core.appIndex.setCommandsVisible([.checkForUpdates], store.channel.updatesItself)
    }

    func applyAutomaticChecking() {
        if core.settings.automaticallyCheckForUpdates {
            store.start()
        } else {
            store.stop()
        }
    }

    // MARK: - Entry points

    /// Never re-offers an update under way: that would discard it.
    func checkForUpdates() {
        guard store.channel.updatesItself else {
            core.showMessage(
                String(localized: "This is a local build — rebuild it to move it forward."),
                tone: .neutral)
            return
        }
        if isInstalled { stage = .readyToRelaunch }
        switch stage {
        case .installing, .readyToRelaunch:
            showPill()
        case .checking:
            break
        case .idle, .available, .failed:
            check()
        }
    }

    /// The automatic path: the pill waits for the next palette open and never interrupts.
    func offer(_ release: AvailableRelease) {
        guard core.settings.automaticallyCheckForUpdates, !isInstalled else { return }
        switch stage {
        case .checking, .installing, .readyToRelaunch:
            break
        case .idle, .available, .failed:
            stage = .available(release)
        }
    }

    // MARK: - Actions

    func install() {
        guard let release = pendingRelease else { return }
        stage = .installing(release, .downloading(received: 0, expected: release.assetSize))
        let installer = self.installer
        // Hoisted: nesting the hop inside the task body would re-capture its weak `self`.
        let onProgress: @Sendable (UpdateInstaller.Phase) -> Void = { [weak self] phase in
            Task { @MainActor in self?.report(phase, for: release) }
        }
        installTask = Task { [weak self] in
            do {
                try await installer.install(release, onProgress: onProgress)
                self?.store.recordInstall(of: release.version)
                self?.isInstalled = true
                self?.stage = .readyToRelaunch
            } catch is CancellationError {
                self?.stage = .available(release)
            } catch let failure as UpdateFailure {
                self?.stage = .failed(failure)
            } catch {
                self?.stage = .failed(.downloadFailed(error.localizedDescription))
            }
        }
    }

    /// Records nothing, so the pill returns at the next launch or for a newer release.
    func dismiss() {
        switch stage {
        case .installing:
            installTask?.cancel()
            installTask = nil
        case .available, .readyToRelaunch, .failed:
            stage = .idle
        case .idle, .checking:
            break
        }
    }

    func showFailure() {
        guard case .failed(let failure) = stage else { return }
        let message = [failure.errorDescription, failure.recoverySuggestion]
            .compactMap(\.self)
            .joined(separator: " ")
        Task {
            let retry = await core.reportFailure(
                title: String(localized: "Update failed"), message: message,
                symbol: "arrow.down.circle", recovery: String(localized: "Try Again"))
            if retry, case .failed = stage { install() }
        }
    }

    func relaunch() {
        core.relaunch()
    }

    // MARK: - Private

    private func check() {
        stage = .checking
        core.showProgress(String(localized: "Checking for updates…"))
        Task { [weak self] in
            guard let self else { return }
            let answered = await store.check()
            core.hideProgress()
            guard case .checking = stage else { return }
            if let release = store.update {
                stage = .available(release)
                showPill()
                return
            }
            stage = .idle
            if answered {
                core.showMessage(String(localized: "\(Bundle.main.appDisplayName) is up to date"))
            } else {
                core.showMessage(
                    String(localized: "\(Bundle.main.appDisplayName) could not reach GitHub."),
                    tone: .danger)
            }
        }
    }

    private func showPill() {
        guard !core.paletteCoordinator.isVisible else { return }
        core.paletteCoordinator.showPalette(mode: .launcher, restoreAnyMode: true)
    }

    private func report(_ phase: UpdateInstaller.Phase, for release: AvailableRelease) {
        guard case .installing = stage else { return }
        stage = .installing(release, phase)
    }

    private var pendingRelease: AvailableRelease? {
        switch stage {
        case .available(let release), .installing(let release, _):
            return release
        case .idle, .checking, .readyToRelaunch, .failed:
            return store.update
        }
    }

    private var installer: UpdateInstaller {
        UpdateInstaller(
            bundleURL: AppTranslocation.originalURL(of: Bundle.main.bundleURL),
            stagingDirectory: AppPaths.caches().appendingPathComponent("Updates", isDirectory: true))
    }
}
