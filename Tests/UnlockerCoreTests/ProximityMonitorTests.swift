import Foundation
import Testing
@testable import UnlockerCore

private func ready(diagnostic: Bool = true) -> ProximityMonitor {
    var monitor = ProximityMonitor(diagnosticOnly: diagnostic)
    monitor.configure(settings: .init(), selected: true, lockAvailable: true)
    _ = monitor.updateSession(.unlocked)
    return monitor
}

@Test func neverArmsWithoutNearbyWatch() {
    var monitor = ready()
    monitor.receive(rssi: -90, at: 0)
    #expect(monitor.tick(at: 100).isEmpty)
    #expect(monitor.state == .waitingForNearby)
}

@Test func singleDipDoesNotLock() {
    var monitor = ready()
    for time in 0 ... 10 {
        monitor.receive(rssi: time == 5 ? -100 : -50, at: Double(time))
        #expect(monitor.tick(at: Double(time)).isEmpty)
    }
    #expect(monitor.state == .armed)
}

@Test func sustainedWeakSignalProposesExactlyOnce() {
    var monitor = ready()
    monitor.receive(rssi: -50, at: 0)
    var effects: [MonitorEffect] = []
    for time in 1 ... 15 {
        monitor.receive(rssi: -90, at: Double(time))
        effects += monitor.tick(at: Double(time))
    }
    #expect(effects == [.proposeLock(.weakSignal)])
    #expect(monitor.state == .proposedLock(.weakSignal))
}

@Test func diagnosticModeNeverAutomaticallyRequestsLock() {
    var monitor = ready()
    monitor.receive(rssi: -50, at: 0)
    #expect(monitor.tick(at: 29).isEmpty)
    #expect(monitor.tick(at: 30) == [.proposeLock(.missingSignal)])
    #expect(monitor.tick(at: 31).isEmpty)
}

@Test func lostRadioUsesNoSignalDeadline() {
    var monitor = ready(diagnostic: false)
    monitor.receive(rssi: -50, at: 0)
    #expect(monitor.tick(at: 30) == [.requestLock(.missingSignal)])
    #expect(monitor.tick(at: 31).isEmpty)
    #expect(monitor.updateSession(.locked) == [.lockConfirmed])
    #expect(monitor.tick(at: 99).isEmpty)
}

@Test func gapsDoNotCountAsSustainedWeakSignal() {
    var monitor = ready()
    monitor.receive(rssi: -50, at: 0)
    monitor.receive(rssi: -90, at: 5)
    #expect(monitor.tick(at: 10).isEmpty)
    monitor.receive(rssi: -90, at: 11)
    #expect(monitor.tick(at: 11).isEmpty)
    #expect(monitor.tick(at: 40).isEmpty)
    #expect(monitor.tick(at: 41) == [.proposeLock(.missingSignal)])
}

@Test func recoveryCancelsDeparture() {
    var monitor = ready()
    monitor.receive(rssi: -50, at: 0)
    for time in 1 ... 3 {
        monitor.receive(rssi: -90, at: Double(time))
        #expect(monitor.tick(at: Double(time)).isEmpty)
    }
    for time in 4 ... 12 {
        monitor.receive(rssi: -40, at: Double(time))
        #expect(monitor.tick(at: Double(time)).isEmpty)
    }
    #expect(monitor.state == .armed)
}

@Test func pauseAndResumeRequireNewNearbyReading() {
    var monitor = ready()
    monitor.receive(rssi: -50, at: 0)
    monitor.setPaused(true)
    #expect(monitor.tick(at: 90).isEmpty)
    monitor.setPaused(false)
    monitor.receive(rssi: -90, at: 91)
    #expect(monitor.tick(at: 200).isEmpty)
    #expect(monitor.state == .waitingForNearby)
}

@Test(arguments: [SessionState.asleep, .locked, .inactive, .unknown])
func sessionChangesDiscardStaleReadings(state: SessionState) {
    var monitor = ready()
    monitor.receive(rssi: -50, at: 0)
    _ = monitor.updateSession(state)
    #expect(monitor.tick(at: 100).isEmpty)
    _ = monitor.updateSession(.unlocked)
    monitor.receive(rssi: -90, at: 101)
    #expect(monitor.tick(at: 200).isEmpty)
    monitor.receive(rssi: -50, at: 201)
    #expect(monitor.tick(at: 230).isEmpty)
    #expect(monitor.tick(at: 231) == [.proposeLock(.missingSignal)])
}

@Test func unavailableLockFunctionPreventsArming() {
    var monitor = ready()
    monitor.configure(settings: .init(), selected: true, lockAvailable: false)
    monitor.receive(rssi: -50, at: 0)
    #expect(monitor.tick(at: 100).isEmpty)
    #expect(monitor.manualLock(at: 101).isEmpty)
    guard case .fault = monitor.state else { Issue.record("Expected unavailable lock fault"); return }
}

@Test func failedLockRemainsVisibleAndCanBeRetriedManually() {
    var monitor = ready(diagnostic: false)
    monitor.receive(rssi: -50, at: 0)
    #expect(monitor.tick(at: 30) == [.requestLock(.missingSignal)])
    #expect(monitor.tick(at: 33) == [.lockFailed])
    monitor.receive(rssi: -50, at: 34)
    guard case .fault = monitor.state else { Issue.record("Expected lock failure"); return }
    #expect(monitor.tick(at: 100).isEmpty)
    #expect(monitor.manualLock(at: 101) == [.requestLock(.manual)])
    #expect(monitor.updateSession(.locked) == [.lockConfirmed])
}

@Test func sleepAndPauseDoNotHideUnconfirmedLock() {
    var monitor = ready()
    #expect(monitor.manualLock(at: 1) == [.requestLock(.manual)])
    monitor.setPaused(true)
    _ = monitor.updateSession(.asleep)
    #expect(monitor.tick(at: 4) == [.lockFailed])
}

@Test func invalidAndOutOfOrderReadingsDoNotRefreshSignal() {
    var monitor = ready()
    monitor.receive(rssi: -50, at: 5)
    monitor.receive(rssi: 127, at: 10)
    monitor.receive(rssi: 0, at: 20)
    monitor.receive(rssi: .nan, at: 21)
    monitor.receive(rssi: -40, at: 4)
    #expect(monitor.lastSampleTime == 5)
    #expect(monitor.tick(at: 35) == [.proposeLock(.missingSignal)])
}

@Test func changingWatchOrSettingsDisarms() {
    var monitor = ready()
    monitor.receive(rssi: -50, at: 0)
    monitor.configure(settings: .init(), selected: false, lockAvailable: true)
    monitor.receive(rssi: -50, at: 1)
    #expect(monitor.tick(at: 100).isEmpty)
    monitor.configure(settings: .init(threshold: -60), selected: true, lockAvailable: true)
    #expect(monitor.tick(at: 200).isEmpty)
}

@Test func configurationsRoundTripAndRejectInvalidValues() throws {
    let configuration = SavedConfiguration(deviceID: UUID(), deviceName: "Watch")
    #expect(try SavedConfiguration.decode(JSONEncoder().encode(configuration)) == configuration)
    var future = configuration
    future.version = 2
    #expect(throws: (any Error).self) { try SavedConfiguration.decode(JSONEncoder().encode(future)) }
    var invalid = configuration
    invalid.settings.missingSignalDelay = -1
    #expect(throws: (any Error).self) { try SavedConfiguration.decode(JSONEncoder().encode(invalid)) }
}

@Test func enablingAutomaticLockingDiscardsPreviewReadings() {
    var monitor = ready()
    monitor.receive(rssi: -50, at: 0)
    #expect(monitor.tick(at: 30) == [.proposeLock(.missingSignal)])
    monitor.setAutomaticLocking(true)
    #expect(monitor.tick(at: 100).isEmpty)
    monitor.receive(rssi: -90, at: 101)
    #expect(monitor.tick(at: 140).isEmpty)
    monitor.receive(rssi: -50, at: 141)
    #expect(monitor.tick(at: 171) == [.requestLock(.missingSignal)])
    #expect(monitor.updateSession(.locked) == [.lockConfirmed])
    _ = monitor.updateSession(.unlocked)
    #expect(monitor.tick(at: 300).isEmpty)
}

@Test func disablingAutomaticLockingPreviewsAndKeepsPendingConfirmation() {
    var monitor = ready(diagnostic: false)
    monitor.receive(rssi: -50, at: 0)
    monitor.setAutomaticLocking(false)
    monitor.receive(rssi: -50, at: 1)
    #expect(monitor.tick(at: 31) == [.proposeLock(.missingSignal)])
    #expect(monitor.manualLock(at: 32) == [.requestLock(.manual)])
    monitor.setAutomaticLocking(false)
    #expect(monitor.tick(at: 35) == [.lockFailed])
}

@Test func automaticWeakSignalRequestsLock() {
    var monitor = ready(diagnostic: false)
    monitor.receive(rssi: -50, at: 0)
    var effects: [MonitorEffect] = []
    for time in 1 ... 10 {
        monitor.receive(rssi: -90, at: Double(time))
        effects += monitor.tick(at: Double(time))
        if !effects.isEmpty { break }
    }
    #expect(effects == [.requestLock(.weakSignal)])
}

@Test func oldSettingsDefaultToPreviewAndAutomaticChoicePersists() throws {
    var configuration = SavedConfiguration(deviceID: UUID(), deviceName: "Watch")
    let data = try JSONEncoder().encode(configuration)
    var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    legacy.removeValue(forKey: "automaticLocking")
    #expect(try !SavedConfiguration.decode(JSONSerialization.data(withJSONObject: legacy)).automaticLocking)
    configuration.automaticLocking = true
    #expect(try SavedConfiguration.decode(JSONEncoder().encode(configuration)) == configuration)
}
