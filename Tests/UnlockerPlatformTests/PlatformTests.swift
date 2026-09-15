import Foundation
import CoreGraphics
import Testing
import UnlockerCore
@testable import UnlockerPlatform

@Test @MainActor func sessionDictionaryHandlesInactiveAndMissingSessions() {
    #expect(SessionMonitor.decode(nil) == .unknown)
    #expect(SessionMonitor.decode([:]) == .inactive)
    let active: [String: Any] = [kCGSessionOnConsoleKey as String: true, kCGSessionLoginDoneKey as String: true]
    #expect(SessionMonitor.decode(active) == .unlocked)
    var locked = active
    locked["CGSSessionScreenIsLocked"] = true
    #expect(SessionMonitor.decode(locked) == .locked)
}

@Test @MainActor func localStorePreservesUnreadableSettings() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try LocalStore(directory: directory)
    let broken = Data("broken".utf8)
    try broken.write(to: store.configurationURL)
    #expect(throws: (any Error).self) { try store.load() }
    #expect(try Data(contentsOf: store.configurationURL) == broken)
}

@Test @MainActor func traceRotationAndConfigurationPersistence() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try LocalStore(directory: directory, maximumTraceBytes: 1)
    let configuration = SavedConfiguration(deviceID: UUID(), deviceName: "My Watch")
    try store.save(configuration)
    #expect(try store.load() == configuration)
    try store.record("sample", fields: ["rssi": "-50"])
    try store.record("wouldLock")
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("diagnostics.previous.jsonl").path))
    let entry = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: store.traceURL))
    #expect(entry["event"] == "wouldLock")
    let permissions = try FileManager.default.attributesOfItem(atPath: store.traceURL.path)[.posixPermissions] as? Int
    #expect(permissions == 0o600)
}
