import AppKit

@MainActor
public struct ScreenSaver {
    private let applicationURL = URL(filePath: "/System/Library/CoreServices/ScreenSaverEngine.app")

    public init() {}

    public var isAvailable: Bool {
        FileManager.default.fileExists(atPath: applicationURL.path)
    }

    public func start() async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        _ = try await NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration)
    }
}
