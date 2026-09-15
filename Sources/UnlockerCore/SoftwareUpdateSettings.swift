import Foundation

public struct SoftwareUpdateSettings: Sendable {
    public static let feedURL = "https://rhymeswithjazz.github.io/Latch/appcast.xml"
    public static let testBuildsKey = "includeTestBuilds"
    public let isEnabled: Bool

    public init(info: [String: Any]) {
        isEnabled = info["LatchUpdatesEnabled"] as? Bool == true
            && info["SUFeedURL"] as? String == Self.feedURL
            && Data(base64Encoded: info["SUPublicEDKey"] as? String ?? "")?.count == 32
    }

    public static func channels(includeTestBuilds: Bool) -> Set<String> {
        includeTestBuilds ? ["beta"] : []
    }
}
