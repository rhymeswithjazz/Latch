import Foundation
import UnlockerCore

@MainActor
public final class LocalStore {
    public let directory: URL
    public var traceURL: URL { directory.appendingPathComponent("diagnostics.jsonl") }
    public var configurationURL: URL { directory.appendingPathComponent("configuration.json") }
    private let maximumTraceBytes: UInt64

    public init(directory: URL? = nil, maximumTraceBytes: UInt64 = 5_000_000) throws {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Unlocker", isDirectory: true)
        self.maximumTraceBytes = maximumTraceBytes
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
    }

    public func load() throws -> SavedConfiguration {
        guard FileManager.default.fileExists(atPath: configurationURL.path) else { return .init() }
        return try SavedConfiguration.decode(Data(contentsOf: configurationURL))
    }

    public func save(_ configuration: SavedConfiguration) throws {
        guard configuration.version == 1, configuration.settings.isValid else { throw ConfigurationError.unsupported }
        try JSONEncoder().encode(configuration).write(to: configurationURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configurationURL.path)
    }

    public func record(_ event: String, fields: [String: String] = [:]) throws {
        if let attributes = try? FileManager.default.attributesOfItem(atPath: traceURL.path),
           let size = attributes[.size] as? UInt64, size >= maximumTraceBytes {
            let previous = directory.appendingPathComponent("diagnostics.previous.jsonl")
            if FileManager.default.fileExists(atPath: previous.path) { try FileManager.default.removeItem(at: previous) }
            try FileManager.default.moveItem(at: traceURL, to: previous)
        }
        if !FileManager.default.fileExists(atPath: traceURL.path) {
            guard FileManager.default.createFile(atPath: traceURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        var entry = fields
        entry["event"] = event
        entry["time"] = ISO8601DateFormatter().string(from: Date())
        entry["uptime"] = String(ProcessInfo.processInfo.systemUptime)
        var data = try JSONEncoder().encode(entry)
        data.append(0x0a)
        let handle = try FileHandle(forWritingTo: traceURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }
}
