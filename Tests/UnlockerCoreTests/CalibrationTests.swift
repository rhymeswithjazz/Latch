import Testing
@testable import UnlockerCore

private func atDesk() -> CalibrationSession {
    var calibration = CalibrationSession()
    calibration.start(at: 0)
    for time in 0 ... 9 { calibration.receive(rssi: -45, at: Double(time)) }
    calibration.tick(at: 10)
    return calibration
}

@Test func calibrationSuggestsThresholdBetweenDeskAndSustainedDeparture() {
    var calibration = atDesk()
    #expect(calibration.phase == .ready)
    calibration.startWalk(at: 20)
    for time in 20 ... 60 {
        calibration.receive(rssi: (30 ... 45).contains(time) ? -70 : -45, at: Double(time))
    }
    calibration.finishWalk(at: 61)
    guard case .review(let result) = calibration.phase else { Issue.record("Expected a recommendation"); return }
    #expect(result.deskRSSI == -45)
    #expect(result.awayRSSI == -70)
    #expect(result.threshold == -58)
}

@Test func calibrationDoesNotUseOneWeakOutlier() {
    var calibration = atDesk()
    calibration.startWalk(at: 20)
    for time in 20 ... 60 { calibration.receive(rssi: time == 35 ? -105 : -45, at: Double(time)) }
    calibration.finishWalk(at: 61)
    guard case .failed = calibration.phase else { Issue.record("A single dip must not suggest a threshold"); return }
}

@Test func missingAwaySignalDoesNotBecomeDistanceEstimate() {
    var calibration = atDesk()
    calibration.startWalk(at: 20)
    calibration.receive(rssi: -90, at: 30)
    calibration.receive(rssi: -90, at: 40)
    calibration.finishWalk(at: 60)
    guard case .failed = calibration.phase else { Issue.record("Sparse readings must be rejected"); return }
}

@Test func deskNeedsEnoughReadingsAcrossTime() {
    var calibration = CalibrationSession()
    calibration.start(at: 0)
    for time in 0 ... 20 { calibration.receive(rssi: -45, at: Double(time) / 20) }
    calibration.tick(at: 10)
    guard case .failed = calibration.phase else { Issue.record("A short burst is not a desk baseline"); return }
}

@Test func noisyDeskRequiresRetry() {
    var calibration = CalibrationSession()
    calibration.start(at: 0)
    for time in 0 ... 9 { calibration.receive(rssi: time.isMultiple(of: 2) ? -40 : -80, at: Double(time)) }
    calibration.tick(at: 10)
    guard case .failed = calibration.phase else { Issue.record("Noisy desk must be rejected"); return }
}

@Test func calibrationTimesOutAndCanRestart() {
    var calibration = atDesk()
    calibration.startWalk(at: 20)
    calibration.tick(at: 140)
    guard case .failed = calibration.phase else { Issue.record("Expected timeout"); return }
    calibration.start(at: 150)
    #expect(calibration.phase == .desk)
    #expect(calibration.startedAt == 150)
}

@Test func calibrationCancelDiscardsThePreviousWatchReadings() {
    var calibration = atDesk()
    calibration.startWalk(at: 20)
    calibration.cancel("Watch changed")
    calibration.receive(rssi: -90, at: 30)
    calibration.finishWalk(at: 60)
    #expect(calibration.phase == .failed("Watch changed"))
    calibration.cancel()
    #expect(calibration.phase == .idle)
}

@Test func deskAndAwayNeedUsefulSeparation() {
    var calibration = atDesk()
    calibration.startWalk(at: 20)
    for time in 20 ... 60 { calibration.receive(rssi: -50, at: Double(time)) }
    calibration.finishWalk(at: 61)
    guard case .failed = calibration.phase else { Issue.record("Overlapping readings must be rejected"); return }
}

@Test func invalidReadingsDoNotAdvanceCalibration() {
    var calibration = CalibrationSession()
    calibration.start(at: 0)
    for time in 0 ... 9 { calibration.receive(rssi: 127, at: Double(time)) }
    calibration.receive(rssi: .nan, at: 9)
    calibration.tick(at: 10)
    guard case .failed = calibration.phase else { Issue.record("Invalid RSSI must not count"); return }
}
