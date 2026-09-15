import AppKit
import Combine
import Sparkle
import UnlockerCore

@MainActor
final class SoftwareUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published var includeTestBuilds: Bool {
        didSet { UserDefaults.standard.set(includeTestBuilds, forKey: SoftwareUpdateSettings.testBuildsKey) }
    }
    let isEnabled: Bool
    private var controller: SPUStandardUpdaterController?

    override init() {
        isEnabled = SoftwareUpdateSettings(info: Bundle.main.infoDictionary ?? [:]).isEnabled
        includeTestBuilds = UserDefaults.standard.bool(forKey: SoftwareUpdateSettings.testBuildsKey)
        super.init()
    }
    func start() {
        guard isEnabled, controller == nil else { return }
        UserDefaults.standard.removeObject(forKey: "SUFeedURL")
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticallyChecksForUpdates)
        controller.startUpdater()
    }
    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }
    func setAutomaticallyChecks(_ enabled: Bool) { controller?.updater.automaticallyChecksForUpdates = enabled }
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? { SoftwareUpdateSettings.feedURL }
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        SoftwareUpdateSettings.channels(includeTestBuilds: includeTestBuilds)
    }
}
