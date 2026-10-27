import Foundation

public enum DepartureAction: String, Codable, CaseIterable, Sendable {
    case lockScreen, startScreenSaver
}

public struct SavedConfiguration: Codable, Equatable, Sendable {
    public var automaticLocking = false
    public var departureAction: DepartureAction = .lockScreen
    public var version = 1
    public var deviceID: UUID?
    public var deviceName: String?
    public var settings: MonitorSettings

    public init(deviceID: UUID? = nil, deviceName: String? = nil, settings: MonitorSettings = .init()) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.settings = settings
    }

    private enum CodingKeys: String, CodingKey {
        case version, deviceID, deviceName, settings, automaticLocking, departureAction
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        deviceID = try values.decodeIfPresent(UUID.self, forKey: .deviceID)
        deviceName = try values.decodeIfPresent(String.self, forKey: .deviceName)
        settings = try values.decode(MonitorSettings.self, forKey: .settings)
        automaticLocking = try values.decodeIfPresent(Bool.self, forKey: .automaticLocking) ?? false
        departureAction = try values.decodeIfPresent(DepartureAction.self, forKey: .departureAction) ?? .lockScreen
    }

    public static func decode(_ data: Data) throws -> SavedConfiguration {
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.version == 1, value.settings.isValid else { throw ConfigurationError.unsupported }
        return value
    }
}

public enum ConfigurationError: Error { case unsupported }
