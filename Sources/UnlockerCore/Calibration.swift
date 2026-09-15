import Foundation

public struct CalibrationReading: Identifiable, Sendable {
    public var id: TimeInterval { time }
    public let time: TimeInterval
    public let rssi: Double
    public init(time: TimeInterval, rssi: Double) { self.time = time; self.rssi = rssi }
}

public struct CalibrationResult: Equatable, Sendable {
    public let deskRSSI: Double
    public let awayRSSI: Double
    public let threshold: Double
}

public enum CalibrationPhase: Equatable, Sendable {
    case idle, desk, ready, walking
    case review(CalibrationResult)
    case failed(String)
}

public struct CalibrationSession: Sendable {
    public private(set) var phase: CalibrationPhase = .idle
    public private(set) var startedAt: TimeInterval = 0
    private var desk: [CalibrationReading] = []
    private var away: [CalibrationReading] = []
    public var isRecording: Bool { phase == .desk || phase == .walking }

    public init() {}

    public mutating func start(at now: TimeInterval) {
        desk = []; away = []; startedAt = now; phase = .desk
    }

    public mutating func startWalk(at now: TimeInterval) {
        guard phase == .ready else { return }
        startedAt = now
        phase = .walking
    }

    public mutating func receive(rssi: Double, at now: TimeInterval) {
        guard isRecording, now.isFinite, now >= startedAt, rssi.isFinite, (-127 ... -1).contains(rssi) else { return }
        let reading = CalibrationReading(time: now, rssi: rssi)
        if phase == .desk, now - startedAt <= 10, desk.last.map({ now - $0.time >= 0.5 }) ?? true {
            desk.append(reading)
        } else if phase == .walking, now - startedAt <= 120, away.last.map({ now - $0.time >= 0.5 }) ?? true {
            away.append(reading)
        }
    }

    public mutating func tick(at now: TimeInterval) {
        if phase == .desk && now - startedAt >= 10 {
            guard desk.count >= 6, let first = desk.first, let last = desk.last,
                  last.time - first.time >= 6, noGaps(desk) else {
                phase = .failed("Not enough steady Watch readings. Keep your Watch nearby and try again. If you use passive scanning, try active mode.")
                return
            }
            let values = desk.map(\.rssi).sorted()
            guard percentile(values, 0.8) - percentile(values, 0.2) <= 15 else {
                phase = .failed("Your desk signal varied too much. Sit normally with your Watch on and record it again.")
                return
            }
            phase = .ready
        } else if phase == .walking && now - startedAt >= 120 {
            phase = .failed("The walk test timed out. Return to your desk and start again. Aim for a trip under two minutes.")
        }
    }

    public mutating func finishWalk(at now: TimeInterval) {
        tick(at: now)
        guard phase == .walking else { return }
        let near = percentile(desk.map(\.rssi).sorted(), 0.2)
        let readings = away.filter { $0.time >= startedAt + 3 && $0.time <= now }
        var candidates: [Double] = []
        for first in readings {
            let window = readings.filter { $0.time >= first.time && $0.time <= first.time + 5 }
            guard window.count >= 4, let last = window.last,
                  last.time - first.time >= 4, noGaps(window) else { continue }
            let values = window.map(\.rssi).sorted()
            guard percentile(values, 0.8) - percentile(values, 0.2) <= 12 else { continue }
            candidates.append(percentile(values, 0.8))
        }
        guard let far = candidates.min() else {
            phase = .failed("We did not capture a steady away signal. Try again and stay at your chosen spot for 15 seconds. Missing signal alone cannot suggest a threshold.")
            return
        }
        guard near - far >= 8 else {
            phase = .failed("Your desk and away signals overlap too much. Try a spot farther away. We kept your existing settings.")
            return
        }
        let threshold = ((near + far) / 2).rounded(.down)
        guard (-100 ... -20).contains(threshold) else {
            phase = .failed("The signal is outside the useful calibration range. Try a closer departure point.")
            return
        }
        phase = .review(.init(deskRSSI: near, awayRSSI: far, threshold: threshold))
    }

    public mutating func cancel(_ message: String? = nil) {
        desk = []; away = []
        phase = message.map(CalibrationPhase.failed) ?? .idle
    }

    private func noGaps(_ readings: [CalibrationReading]) -> Bool {
        zip(readings, readings.dropFirst()).allSatisfy { $1.time - $0.time <= 3 }
    }

    private func percentile(_ values: [Double], _ fraction: Double) -> Double {
        values[Int(Double(values.count - 1) * fraction)]
    }
}
