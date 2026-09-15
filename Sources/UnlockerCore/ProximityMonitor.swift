import Foundation

public struct MonitorSettings: Codable, Equatable, Sendable {
    public var threshold: Double
    public var weakSignalDelay: TimeInterval
    public var missingSignalDelay: TimeInterval
    public var passive: Bool

    public init(threshold: Double = -75, weakSignalDelay: TimeInterval = 5,
                missingSignalDelay: TimeInterval = 30, passive: Bool = false) {
        self.threshold = threshold
        self.weakSignalDelay = weakSignalDelay
        self.missingSignalDelay = missingSignalDelay
        self.passive = passive
    }

    public var isValid: Bool {
        threshold.isFinite && (-100 ... -20).contains(threshold)
            && weakSignalDelay.isFinite && (1 ... 60).contains(weakSignalDelay)
            && missingSignalDelay.isFinite && (5 ... 300).contains(missingSignalDelay)
    }
}

public enum SessionState: String, Sendable {
    case unlocked, locked, asleep, inactive, unknown
}

public enum LockReason: String, Codable, Sendable {
    case weakSignal, missingSignal, manual
}

public enum MonitorState: Equatable, Sendable {
    case waitingForNearby, armed, weakSignal, paused, suspended, verifyingLock
    case proposedLock(LockReason)
    case fault(String)
}

public enum MonitorEffect: Equatable, Sendable {
    case proposeLock(LockReason)
    case requestLock(LockReason)
    case lockConfirmed
    case lockFailed
}

public struct ProximityMonitor: Sendable {
    public private(set) var state: MonitorState = .waitingForNearby
    public private(set) var smoothedRSSI: Double?
    public private(set) var lastSampleTime: TimeInterval?
    public private(set) var lastSampleGap: TimeInterval?
    public private(set) var session: SessionState = .unknown
    public private(set) var settings: MonitorSettings
    public private(set) var diagnosticOnly: Bool
    private var samples: [(time: TimeInterval, rssi: Double)] = []
    private var armed = false
    private var paused = false
    private var available = false
    private var selected = false
    private var weakSince: TimeInterval?
    private var pendingLockAt: TimeInterval?
    private var proposal: LockReason?
    private var failure: String?

    public init(settings: MonitorSettings = .init(), diagnosticOnly: Bool = true) {
        self.settings = settings
        self.diagnosticOnly = diagnosticOnly
    }

    public mutating func configure(settings: MonitorSettings, selected: Bool, lockAvailable: Bool) {
        self.settings = settings
        self.selected = selected
        available = lockAvailable
        resetReadings()
        failure = nil
        refreshState()
    }

    public mutating func setAutomaticLocking(_ enabled: Bool) {
        diagnosticOnly = !enabled
        resetReadings()
        refreshState()
    }

    public mutating func setPaused(_ value: Bool) {
        paused = value
        resetReadings()
        refreshState()
    }

    public mutating func updateSession(_ value: SessionState) -> [MonitorEffect] {
        guard value != session else { return [] }
        let confirmed = value == .locked && pendingLockAt != nil
        session = value
        resetReadings()
        if confirmed { pendingLockAt = nil }
        refreshState()
        return confirmed ? [.lockConfirmed] : []
    }

    public mutating func receive(rssi: Double, at now: TimeInterval) {
        guard now.isFinite, rssi.isFinite, (-127 ... -1).contains(rssi),
              canMonitor, pendingLockAt == nil, failure == nil else { return }
        if let last = lastSampleTime, now < last { return }
        lastSampleGap = lastSampleTime.map { now - $0 }
        if let last = lastSampleTime, now - last > 3 {
            samples.removeAll()
            weakSince = nil
        }
        lastSampleTime = now
        samples.removeAll { now - $0.time > 4 }
        samples.append((now, rssi))
        if samples.count > 20 { samples.removeFirst(samples.count - 20) }
        smoothedRSSI = samples.map(\.rssi).reduce(0, +) / Double(samples.count)
        if let signal = smoothedRSSI, signal >= settings.threshold {
            armed = true
            weakSince = nil
            proposal = nil
        } else if armed && weakSince == nil {
            weakSince = now
        }
        refreshState()
    }

    public mutating func tick(at now: TimeInterval) -> [MonitorEffect] {
        if let requested = pendingLockAt, now - requested >= 3 {
            pendingLockAt = nil
            failure = "Lock was not confirmed. Check the Mac, then retry Lock Now."
            refreshState()
            return [.lockFailed]
        }
        guard canMonitor, armed, failure == nil, pendingLockAt == nil,
              proposal == nil, let last = lastSampleTime else { return [] }
        if now - last >= settings.missingSignalDelay {
            return trigger(.missingSignal, at: now)
        }
        // Silence is not sustained weak signal; use the longer loss timeout.
        if now - last > 3 {
            weakSince = nil
            refreshState()
            return []
        }
        if let weakSince, now - weakSince >= settings.weakSignalDelay {
            return trigger(.weakSignal, at: now)
        }
        return []
    }

    public mutating func manualLock(at now: TimeInterval) -> [MonitorEffect] {
        guard session == .unlocked, available, pendingLockAt == nil else { return [] }
        failure = nil
        pendingLockAt = now
        refreshState()
        return [.requestLock(.manual)]
    }

    public mutating func lockInvocationFailed() -> [MonitorEffect] {
        pendingLockAt = nil
        failure = "The macOS lock function failed. Monitoring is stopped."
        refreshState()
        return [.lockFailed]
    }

    private var canMonitor: Bool {
        selected && available && settings.isValid && !paused && session == .unlocked
    }

    private mutating func trigger(_ reason: LockReason, at now: TimeInterval) -> [MonitorEffect] {
        if diagnosticOnly {
            proposal = reason
            refreshState()
            return [.proposeLock(reason)]
        }
        pendingLockAt = now
        refreshState()
        return [.requestLock(reason)]
    }

    private mutating func resetReadings() {
        samples.removeAll()
        smoothedRSSI = nil
        lastSampleTime = nil
        lastSampleGap = nil
        weakSince = nil
        armed = false
        proposal = nil
        // An issued lock stays pending across pause/setup/session changes until verified.
    }

    private mutating func refreshState() {
        if let failure { state = .fault(failure) }
        else if pendingLockAt != nil { state = .verifyingLock }
        else if !available { state = .fault("The macOS lock function is unavailable.") }
        else if !settings.isValid { state = .fault("Invalid monitoring settings.") }
        else if paused { state = .paused }
        else if session != .unlocked { state = .suspended }
        else if let proposal { state = .proposedLock(proposal) }
        else if !armed { state = .waitingForNearby }
        else if weakSince != nil { state = .weakSignal }
        else { state = .armed }
    }
}
