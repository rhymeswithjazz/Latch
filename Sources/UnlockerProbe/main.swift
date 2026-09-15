import Foundation
import UnlockerPlatform

let locker = ScreenLock()
let session = SessionMonitor()
let report: [String: String] = [
    "os": ProcessInfo.processInfo.operatingSystemVersionString,
    "session": session.current().rawValue,
    "lockFunctionAvailable": String(locker.isAvailable),
    "mode": "readOnly"
]
let data = try JSONEncoder().encode(report)
print(String(decoding: data, as: UTF8.self))
