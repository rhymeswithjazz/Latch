import CoreBluetooth
import Foundation

public struct NearbyDevice: Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var rssi: Int
    public var lastSeen: TimeInterval
}

@MainActor
public protocol SignalSource: AnyObject {
    var onSample: ((UUID, Double, TimeInterval) -> Void)? { get set }
    func select(_ id: UUID?, passive: Bool)
    func setMonitoring(_ enabled: Bool)
}

// Core Bluetooth invokes these delegates on the explicitly selected main queue.
@MainActor
public final class BluetoothMonitor: NSObject, SignalSource, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    public var onSample: ((UUID, Double, TimeInterval) -> Void)?
    public var onDevices: (([NearbyDevice]) -> Void)?
    public var onStatus: ((String) -> Void)?
    public var onEvent: ((String, String) -> Void)?
    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var devices: [UUID: NearbyDevice] = [:]
    private var deviceOrder: [UUID] = []
    private var target: UUID?
    private var passive = false
    private var monitoring = false
    private var discovering = false
    private var connectionStarted: TimeInterval?
    private var retryAfter: TimeInterval = 0
    private var rssiRequestedAt: TimeInterval?

    public override init() { super.init() }

    public func startDiscovery() {
        devices = devices.filter { $0.key == target }
        peripherals = peripherals.filter { $0.key == target }
        deviceOrder = deviceOrder.filter { $0 == target }
        discovering = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else { updateScan() }
    }

    public func stopDiscovery() {
        discovering = false
        updateScan()
    }

    public func select(_ id: UUID?, passive: Bool) {
        if let target, let old = peripherals[target], old.state != .disconnected {
            central?.cancelPeripheralConnection(old)
        }
        target = id
        self.passive = passive
        connectionStarted = nil
        rssiRequestedAt = nil
        retryAfter = 0
        if central == nil, id != nil { central = CBCentralManager(delegate: self, queue: .main) }
        updateScan()
        tick()
    }

    public func setMonitoring(_ enabled: Bool) {
        guard monitoring != enabled else { return }
        monitoring = enabled
        if !enabled, let target, let peripheral = peripherals[target], peripheral.state != .disconnected {
            central?.cancelPeripheralConnection(peripheral)
        }
        connectionStarted = nil
        rssiRequestedAt = nil
        updateScan()
    }

    public func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        onDevices?(deviceOrder.compactMap { devices[$0] })
        guard monitoring, !passive, let target, central?.state == .poweredOn else { return }
        if peripherals[target] == nil {
            if let restored = central.retrievePeripherals(withIdentifiers: [target]).first {
                peripherals[target] = restored
                restored.delegate = self
            }
        }
        guard let peripheral = peripherals[target] else { return }
        switch peripheral.state {
        case .connected:
            if rssiRequestedAt == nil {
                rssiRequestedAt = now
                peripheral.readRSSI()
            } else if now - (rssiRequestedAt ?? now) >= 5 {
                onEvent?("rssiTimeout", target.uuidString)
                central.cancelPeripheralConnection(peripheral)
                rssiRequestedAt = nil
                retryAfter = now + 3
            }
        case .disconnected:
            guard now >= retryAfter else { return }
            peripheral.delegate = self
            connectionStarted = now
            central.connect(peripheral)
            onEvent?("connecting", target.uuidString)
        case .connecting:
            if let connectionStarted, now - connectionStarted >= 10 {
                central.cancelPeripheralConnection(peripheral)
                self.connectionStarted = nil
                retryAfter = now + 3
            }
        default: break
        }
    }

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let message: String
        switch central.state {
        case .poweredOn: message = "Bluetooth ready"
        case .poweredOff: message = "Bluetooth is off"
        case .unauthorized: message = "Bluetooth permission denied. Enable Latch in System Settings."
        case .unsupported: message = "Bluetooth LE is unavailable"
        case .resetting: message = "Bluetooth is restarting"
        default: message = "Waiting for Bluetooth"
        }
        onStatus?(message)
        onEvent?("bluetoothState", message)
        if central.state != .poweredOn {
            connectionStarted = nil
            rssiRequestedAt = nil
        }
        updateScan()
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let now = ProcessInfo.processInfo.systemUptime
        guard discovering || peripheral.identifier == target else { return }
        if devices[peripheral.identifier] == nil { deviceOrder.append(peripheral.identifier) }
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unnamed device"
        peripherals[peripheral.identifier] = peripheral
        peripheral.delegate = self
        devices[peripheral.identifier] = NearbyDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue, lastSeen: now)
        if peripheral.identifier == target, passive, monitoring {
            onSample?(peripheral.identifier, RSSI.doubleValue, now)
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral.identifier == target, monitoring, !passive else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        connectionStarted = nil
        onEvent?("connected", peripheral.identifier.uuidString)
        rssiRequestedAt = nil
        tick()
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionEnded(peripheral, error: error)
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectionEnded(peripheral, error: error)
    }

    private func connectionEnded(_ peripheral: CBPeripheral, error: Error?) {
        onEvent?("disconnected", "\(peripheral.identifier): \(error?.localizedDescription ?? "closed")")
        guard peripheral.identifier == target else { return }
        connectionStarted = nil
        rssiRequestedAt = nil
        retryAfter = ProcessInfo.processInfo.systemUptime + 3
    }

    public func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard peripheral.identifier == target, monitoring, !passive else { return }
        rssiRequestedAt = nil
        if let error {
            onEvent?("rssiError", error.localizedDescription)
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if devices[peripheral.identifier] == nil { deviceOrder.append(peripheral.identifier) }
        devices[peripheral.identifier] = NearbyDevice(id: peripheral.identifier, name: peripheral.name ?? "Selected Watch",
                                                     rssi: RSSI.intValue, lastSeen: now)
        onSample?(peripheral.identifier, RSSI.doubleValue, now)
    }

    private func updateScan() {
        guard central?.state == .poweredOn else { return }
        if discovering || (monitoring && target != nil) {
            if !central.isScanning {
                central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            }
        } else { central.stopScan() }
    }
}
