import AppKit
import CoreGraphics
import Darwin
import UnlockerCore

@MainActor
public protocol ScreenLocking {
    var isAvailable: Bool { get }
    func lock() -> Bool
}

@MainActor
public final class ScreenLock: ScreenLocking {
    private typealias LockFunction = @convention(c) () -> Void
    private let handle: UnsafeMutableRawPointer?
    private let function: LockFunction?
    public var isAvailable: Bool { function != nil }

    public init() {
        handle = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_LAZY | RTLD_LOCAL)
        if let handle, let symbol = dlsym(handle, "SACLockScreenImmediate") {
            function = unsafeBitCast(symbol, to: LockFunction.self)
        } else { function = nil }
    }

    public func lock() -> Bool {
        guard let function else { return false }
        function()
        return true
    }
}

@MainActor
public protocol SessionReading {
    func current() -> SessionState
}

@MainActor
public final class SessionMonitor: SessionReading {
    private var sleeping = false
    private var inactive = false
    public var onChange: ((SessionState) -> Void)?
    private var observers: [NSObjectProtocol] = []

    public init() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let name = notification.name
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch name {
                    case NSWorkspace.willSleepNotification: self.sleeping = true
                    case NSWorkspace.didWakeNotification: self.sleeping = false
                    case NSWorkspace.sessionDidResignActiveNotification: self.inactive = true
                    case NSWorkspace.sessionDidBecomeActiveNotification: self.inactive = false
                    default: break
                    }
                    self.onChange?(self.current())
                }
            })
        }
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            observers.append(DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(name), object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.onChange?(self.current())
                }
            })
        }
    }

    public func current() -> SessionState {
        if sleeping { return .asleep }
        if inactive { return .inactive }
        return Self.decode(CGSessionCopyCurrentDictionary() as? [String: Any])
    }

    public static func decode(_ dictionary: [String: Any]?) -> SessionState {
        guard let dictionary else { return .unknown }
        // This lock key and the distributed notifications are undocumented macOS behavior.
        if dictionary["CGSSessionScreenIsLocked"] as? Bool == true { return .locked }
        guard dictionary[kCGSessionOnConsoleKey as String] as? Bool == true else { return .inactive }
        guard dictionary[kCGSessionLoginDoneKey as String] as? Bool == true else { return .unknown }
        return .unlocked
    }
}
