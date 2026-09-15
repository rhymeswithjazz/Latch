import AppKit
import Observation
import ServiceManagement
import UnlockerCore
import UnlockerPlatform

struct SignalHistoryPoint: Identifiable {
    let id = UUID()
    let date: Date
    let rssi: Double
    let segment: Int
}

struct LockPreviewEvent: Identifiable {
    let id = UUID()
    let date: Date
    let message: String
}

@MainActor
@Observable
final class AppModel {
    private(set) var devices: [NearbyDevice] = []
    private(set) var bluetoothStatus = "Choose Scan to request Bluetooth access"
    private(set) var monitor = ProximityMonitor(diagnosticOnly: true)
    private(set) var configuration = SavedConfiguration()
    private(set) var error: String?
    private(set) var rawRSSI: Double?
    private(set) var sampleAge: Double?
    private(set) var paused = false
    private(set) var scanning = false
    private(set) var observationTime = ProcessInfo.processInfo.systemUptime
    private(set) var lastEvent = "No lock events yet"
    private(set) var loginEnabled = SMAppService.mainApp.status == .enabled
    var threshold = -75.0
    var weakDelay = 5.0
    var missingDelay = 30.0
    var passive = false
    private let bluetooth = BluetoothMonitor()
    private let session = SessionMonitor()
    private let locker = ScreenLock()
    private var store: LocalStore?
    private var canSave = true
    private var timer: Timer?
    private var discoveryDeadline: TimeInterval?
    private var lastState: MonitorState?
    private(set) var calibration = CalibrationSession()
    private(set) var calibrationSaved = false
    private(set) var history: [SignalHistoryPoint] = []
    private(set) var previewEvents: [LockPreviewEvent] = []
    private(set) var historyNow = Date()
    private var historySegment = 0
    private var lastHistorySample: TimeInterval?

    var canCalibrate: Bool {
        selectedID != nil && !paused && monitor.session == .unlocked && canSelect &&
            monitor.state != .verifyingLock &&
            sampleAge.map { $0 <= 3 } == true
    }
    var calibrationElapsed: Int { max(0, Int(observationTime - calibration.startedAt)) }

    func startCalibration() {
        guard canCalibrate else { return }
        if automaticLocking {
            setAutomaticLocking(false)
            guard !automaticLocking else { return }
        }
        calibration.start(at: ProcessInfo.processInfo.systemUptime)
        calibrationSaved = false
        history = []
        previewEvents = []
        historySegment += 1
        lastHistorySample = nil
        record("calibrationStarted")
    }

    func startCalibrationWalk() {
        guard canCalibrate else { return }
        calibration.startWalk(at: ProcessInfo.processInfo.systemUptime)
        record("calibrationWalkStarted")
    }

    func finishCalibrationWalk() {
        calibration.finishWalk(at: ProcessInfo.processInfo.systemUptime)
        if case .review(let result) = calibration.phase {
            record("calibrationSuggested", ["threshold": String(result.threshold)])
        }
    }

    func cancelCalibration() { calibration.cancel(); calibrationSaved = false }

    func useCalibration() {
        guard case .review(let result) = calibration.phase else { return }
        var next = configuration
        next.settings.threshold = result.threshold
        guard save(next) else { return }
        threshold = result.threshold
        weakDelay = next.settings.weakSignalDelay
        missingDelay = next.settings.missingSignalDelay
        passive = next.settings.passive
        monitor.configure(settings: next.settings, selected: true, lockAvailable: locker.isAvailable)
        previewEvents = []
        calibrationSaved = true
        record("calibrationApplied", ["threshold": String(threshold)])
        tick()
    }

    private func interruptCalibration(_ message: String) {
        switch calibration.phase {
        case .desk, .ready, .walking: calibration.cancel(message)
        case .review: calibration.cancel()
        default: break
        }
        calibrationSaved = false
    }


    var automaticLocking: Bool { configuration.automaticLocking }
    var canEnableAutomaticLocking: Bool {
        canSelect && selectedID != nil && locker.isAvailable && !calibration.isRecording &&
            monitor.session == .unlocked && !paused && monitor.state != .verifyingLock
    }
    var modeDescription: String {
        automaticLocking
            ? "Automatic locking is on. Latch locks after \(Int(configuration.settings.weakSignalDelay)) seconds of weak signal or \(Int(configuration.settings.missingSignalDelay)) seconds without a signal."
            : "Preview mode. Latch shows when it would lock. Turn on automatic locking when you are ready."
    }

    func setAutomaticLocking(_ enabled: Bool) {
        guard !enabled || canEnableAutomaticLocking else { return }
        var next = configuration
        next.automaticLocking = enabled
        guard save(next) else { return }
        if enabled { interruptCalibration("Calibration ended.") }
        monitor.setAutomaticLocking(enabled)
        record("automaticLocking", ["enabled": String(enabled)])
        tick()
    }

    var selectedName: String { configuration.deviceName ?? "No Watch selected" }
    var selectedID: UUID? { configuration.deviceID }
    var canLock: Bool { locker.isAvailable && monitor.session == .unlocked && monitor.state != .verifyingLock && !calibration.isRecording }
    var canSelect: Bool { canSave && store != nil }
    var signal: String {
        guard let rssi = monitor.smoothedRSSI else { return "No valid signal" }
        return String(format: "%.0f dBm", rssi)
    }
    var status: String {
        switch monitor.state {
        case .waitingForNearby: return selectedID == nil ? "Select your Watch" : "Waiting for a nearby reading"
        case .armed: return automaticLocking ? "Automatic locking armed" : "Observing proximity"
        case .weakSignal: return "Weak signal. Timing departure…"
        case .paused: return "Monitoring paused"
        case .suspended: return "Monitoring suspended: \(monitor.session.rawValue)"
        case .verifyingLock: return "Waiting for lock confirmation"
        case .proposedLock(let reason): return "Would lock: \(reason == .weakSignal ? "weak signal" : "signal lost")"
        case .fault(let message): return message
        }
    }

    init() {
        do {
            let storage = try LocalStore()
            store = storage
            do { configuration = try storage.load() }
            catch {
                canSave = false
                self.error = "Could not read settings. The original file was kept. Reveal diagnostics to inspect it."
            }
        } catch { self.error = "Could not open local storage: \(error.localizedDescription)" }
        threshold = configuration.settings.threshold
        weakDelay = configuration.settings.weakSignalDelay
        missingDelay = configuration.settings.missingSignalDelay
        passive = configuration.settings.passive
        monitor.configure(settings: configuration.settings, selected: selectedID != nil, lockAvailable: locker.isAvailable)
        monitor.setAutomaticLocking(configuration.automaticLocking)
        _ = monitor.updateSession(session.current())
        bluetooth.onDevices = { [weak self] in self?.devices = $0 }
        bluetooth.onStatus = { [weak self] in self?.bluetoothStatus = $0 }
        bluetooth.onEvent = { [weak self] event, detail in self?.record(event, ["detail": detail]) }
        bluetooth.onSample = { [weak self] id, rssi, time in self?.receive(id: id, rssi: rssi, time: time) }
        session.onChange = { [weak self] in self?.sessionChanged($0) }
        record("launch", ["mode": automaticLocking ? "automaticLocking" : "preview", "lockFunctionAvailable": String(locker.isAvailable),
                          "deviceID": selectedID?.uuidString ?? "none", "os": ProcessInfo.processInfo.operatingSystemVersionString])
        bluetooth.select(selectedID, passive: passive)
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        timer?.tolerance = 0.2
    }

    func scan() {
        scanning = true
        discoveryDeadline = ProcessInfo.processInfo.systemUptime + 60
        bluetooth.startDiscovery()
    }

    func select(_ device: NearbyDevice) {
        guard canSelect else { return }
        var next = configuration
        next.deviceID = device.id
        next.deviceName = device.name
        guard save(next) else { return }
        interruptCalibration("The selected Watch changed. Start a new calibration.")
        history = []; previewEvents = []; lastHistorySample = nil
        rawRSSI = nil
        monitor.configure(settings: next.settings, selected: true, lockAvailable: locker.isAvailable)
        bluetooth.select(device.id, passive: next.settings.passive)
        record("selected", ["deviceID": device.id.uuidString, "name": device.name])
        tick()
    }

    func applySettings() {
        var next = configuration
        next.settings = MonitorSettings(threshold: threshold, weakSignalDelay: weakDelay,
                                        missingSignalDelay: missingDelay, passive: passive)
        guard next.settings.isValid else { error = "Enter valid thresholds and delays."; return }
        guard save(next) else { return }
        interruptCalibration("Settings changed. Start a new calibration to use these settings.")
        monitor.configure(settings: next.settings, selected: selectedID != nil, lockAvailable: locker.isAvailable)
        bluetooth.select(selectedID, passive: passive)
        record("settings", ["threshold": String(threshold), "weakDelay": String(weakDelay),
                            "missingDelay": String(missingDelay), "passive": String(passive)])
        tick()
    }

    func togglePaused() {
        if !paused { interruptCalibration("Calibration stopped because monitoring was paused.") }
        paused.toggle()
        monitor.setPaused(paused)
        record("pause", ["paused": String(paused)])
        tick()
    }

    func lockNow() {
        guard canLock else { return }
        sessionChanged(session.current())
        process(monitor.manualLock(at: ProcessInfo.processInfo.systemUptime))
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if enabled && !loginEnabled { SMAppService.openSystemSettingsLoginItems() }
        } catch { self.error = "Launch at login: \(error.localizedDescription)" }
    }

    func recordMenuBarStatus(visible: Bool, hasButton: Bool, hasImage: Bool) {
        record("menuBarRegistered", ["visible": String(visible), "hasButton": String(hasButton),
                                    "hasImage": String(hasImage)])
    }

    func revealDiagnostics() {
        guard let store else { return }
        NSWorkspace.shared.open(store.directory)
    }

    private func save(_ value: SavedConfiguration) -> Bool {
        guard canSelect, let store else { return false }
        do {
            try store.save(value)
            configuration = value
            return true
        } catch {
            self.error = "Could not save settings: \(error.localizedDescription)"
            return false
        }
    }

    private func receive(id: UUID, rssi: Double, time: TimeInterval) {
        guard id == selectedID else { return }
        guard rssi.isFinite, (-127 ... -1).contains(rssi) else {
            record("invalidRSSI", ["value": String(rssi)])
            return
        }
        calibration.tick(at: time)
        calibration.receive(rssi: rssi, at: time)
        rawRSSI = rssi
        monitor.receive(rssi: rssi, at: time)
        if let smoothed = monitor.smoothedRSSI {
            if let last = lastHistorySample, time - last > 3 { historySegment += 1 }
            lastHistorySample = time
            history.append(.init(date: Date(), rssi: smoothed, segment: historySegment))
            history.removeAll { Date().timeIntervalSince($0.date) > 300 }
            if history.count > 600 { history.removeFirst(history.count - 600) }
        }
        record("sample", ["deviceID": id.uuidString, "rssi": String(rssi), "smoothedRSSI": signal,
                          "gap": monitor.lastSampleGap.map(String.init(describing:)) ?? "first"])
    }

    private func sessionChanged(_ value: SessionState) {
        guard value != monitor.session else { return }
        if value != .unlocked { interruptCalibration("Calibration stopped because the Mac locked, slept, or changed session. Return to your desk to restart.") }
        historySegment += 1
        process(monitor.updateSession(value))
        rawRSSI = nil
        record("session", ["state": value.rawValue])
        bluetooth.setMonitoring(value == .unlocked && !paused)
        if value != .unlocked {
            bluetooth.stopDiscovery()
            scanning = false
            discoveryDeadline = nil
        }
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        observationTime = now
        historyNow = Date()
        calibration.tick(at: now)
        sessionChanged(session.current())
        bluetooth.setMonitoring(monitor.session == .unlocked && !paused)
        bluetooth.tick()
        if let discoveryDeadline, now >= discoveryDeadline {
            scanning = false
            self.discoveryDeadline = nil
            bluetooth.stopDiscovery()
        }
        sampleAge = monitor.lastSampleTime.map { max(0, now - $0) }
        process(monitor.tick(at: now))
        if lastState != monitor.state {
            lastState = monitor.state
            record("state", ["state": status])
        }
    }

    private func process(_ effects: [MonitorEffect]) {
        for effect in effects {
            switch effect {
            case .proposeLock(let reason):
                let message = reason == .weakSignal ? "Would lock: Watch stayed beyond the signal threshold" : "Would lock: Watch signal was lost"
                lastEvent = message
                previewEvents.insert(.init(date: Date(), message: message), at: 0)
                if previewEvents.count > 20 { previewEvents.removeLast() }
                record("wouldLock", ["reason": reason.rawValue])
            case .requestLock(let reason):
                lastEvent = "Lock requested: \(reason.rawValue)"
                record("lockRequested", ["reason": reason.rawValue])
                if !locker.lock() { process(monitor.lockInvocationFailed()) }
            case .lockConfirmed:
                lastEvent = "Mac lock confirmed"
                record("lockConfirmed")
            case .lockFailed:
                lastEvent = "Lock failed"
                record("lockFailed")
            }
        }
    }

    private func record(_ event: String, _ fields: [String: String] = [:]) {
        do { try store?.record(event, fields: fields) }
        catch { self.error = "Could not write diagnostics: \(error.localizedDescription)" }
    }
}
