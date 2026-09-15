import AppKit
import Observation
import SwiftUI
import UnlockerPlatform

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let model = AppModel()
    let updater = SoftwareUpdater()
    private var windowController: NSWindowController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        updater.start()
        installStatusItem()
        showDiagnostics()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDiagnostics()
        return true
    }

    @objc func showDiagnostics() {
        if windowController == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: DiagnosticsView(model: model, updater: updater)))
            window.title = "Latch Diagnostics"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 650, height: 680))
            window.contentMinSize = NSSize(width: 600, height: 560)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("UnlockerDiagnostics")
            window.center()
            windowController = NSWindowController(window: window)
        }
        windowController?.showWindow(nil)
        windowController?.window?.deminiaturize(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        item.isVisible = true
        observeMenuBarState()
        item.button?.toolTip = "Latch — Watch proximity"
        item.button?.setAccessibilityLabel("Latch")
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        menuNeedsUpdate(menu)
        model.recordMenuBarStatus(visible: item.isVisible, hasButton: item.button != nil,
                                  hasImage: item.button?.image != nil)
    }

    private func observeMenuBarState() {
        withObservationTracking {
            statusItem?.button?.image = Self.latchImage(paused: model.paused)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeMenuBarState() }
        }
    }

    private static func latchImage(paused: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            NSColor.black.set()
            let housing = NSBezierPath(roundedRect: NSRect(x: 1.5, y: 4, width: 10, height: 10), xRadius: 2, yRadius: 2)
            let keeper = NSBezierPath(roundedRect: NSRect(x: 15.5, y: 4, width: 3, height: 10), xRadius: 1, yRadius: 1)
            let bolt = NSBezierPath(rect: NSRect(x: 9, y: 7, width: 7, height: 4))
            for path in [housing, keeper, bolt] {
                if paused { path.lineWidth = 1.25; path.stroke() }
                else { path.fill() }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Latch"
        return image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for title in [model.automaticLocking ? "Latch · Automatic locking on" : "Latch · Preview mode", model.status, "\(model.selectedName) · \(model.signal)"] {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())
        addItem("Open Diagnostics…", action: #selector(showDiagnostics), to: menu)
        addItem(model.paused ? "Resume Monitoring" : "Pause Monitoring", action: #selector(togglePaused), to: menu)
        addItem(model.automaticLocking ? "Turn Off Automatic Locking" : "Turn On Automatic Locking", action: #selector(toggleAutomaticLocking), enabled: model.automaticLocking || model.canEnableAutomaticLocking, to: menu)
        addItem("Lock Now", action: #selector(lockNow), enabled: model.canLock, to: menu)
        menu.addItem(.separator())
        addItem("Check for Updates…", action: #selector(checkForUpdates), enabled: updater.canCheckForUpdates, to: menu)
        addItem("Reveal Diagnostic Logs", action: #selector(revealLogs), to: menu)
        addItem("Quit Latch", action: #selector(quit), to: menu)
    }

    private func addItem(_ title: String, action: Selector, enabled: Bool = true, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        menu.addItem(item)
    }

    @objc private func togglePaused() { model.togglePaused() }
    @objc private func toggleAutomaticLocking() { model.setAutomaticLocking(!model.automaticLocking) }
    @objc private func lockNow() { model.lockNow() }
    @objc private func checkForUpdates() { updater.checkForUpdates() }
    @objc private func revealLogs() { model.revealDiagnostics() }
    @objc private func quit() { NSApp.terminate(nil) }

}

@main
struct UnlockerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Open Diagnostics…", action: delegate.showDiagnostics).keyboardShortcut(",")
            }
        }
    }
}

private struct DiagnosticsView: View {
    @Bindable var model: AppModel
    @ObservedObject var updater: SoftwareUpdater
    @State private var deviceSearch = ""
    @State private var changingWatch = false

    private var matchingDevices: [UnlockerPlatform.NearbyDevice] {
        let query = deviceSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.devices.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.id.uuidString.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Watch proximity").font(.largeTitle.bold())
                Text("Latch runs from the latch icon in your menu bar.").foregroundStyle(.secondary)
                Text(model.modeDescription)
                    .foregroundStyle(.secondary)
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Automatically lock when I walk away", isOn: Binding(get: { model.automaticLocking }, set: { model.setAutomaticLocking($0) }))
                            .disabled(!model.automaticLocking && !model.canEnableAutomaticLocking)
                        Text(model.status).font(.headline)
                        Text("\(model.selectedName) · \(model.signal)")
                        if let age = model.sampleAge {
                            Text("Last valid sample \(Int(age)) seconds ago").font(.caption).foregroundStyle(.secondary)
                        }
                        Text(model.lastEvent).font(.caption)
                        HStack {
                            Button(model.paused ? "Resume" : "Pause") { model.togglePaused() }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if let error = model.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                DisclosureGroup(model.selectedID == nil ? "Select your Watch" : "\(model.selectedName) · Change Watch", isExpanded: Binding(get: { model.selectedID == nil || changingWatch }, set: { changingWatch = $0 })) {
                    VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Select your Watch").font(.headline)
                        Spacer()
                        Button(model.scanning ? "Scanning…" : "Scan for 60 seconds") { model.scan() }
                            .disabled(model.scanning)
                    }
                    Text(model.bluetoothStatus).font(.caption).foregroundStyle(.secondary)
                    Text("Use the same Apple Account on both devices. Move your Watch closer and farther away to identify its signal. Names alone do not prove identity.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("Search by name or device ID", text: $deviceSearch)
                        .textFieldStyle(.roundedBorder)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(matchingDevices) { device in
                                let stale = model.observationTime - device.lastSeen > 60
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(device.name)
                                            .fontWeight(device.id == model.selectedID ? .semibold : .regular)
                                            .lineLimit(1)
                                        Text(device.id.uuidString)
                                            .font(.caption2.monospaced()).foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    Text(stale ? "Not seen" : "\(device.rssi) dBm")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 70, alignment: .trailing)
                                    Button(device.id == model.selectedID ? "Selected" : "Select") { model.select(device) }
                                        .frame(width: 70)
                                        .disabled(!model.canSelect || stale || device.id == model.selectedID)
                                }
                                .frame(height: 56)
                                Divider()
                            }
                            if matchingDevices.isEmpty {
                                Text(deviceSearch.isEmpty ? "No devices discovered yet." : "No matching devices.")
                                    .foregroundStyle(.secondary).padding(.vertical, 16)
                            }
                        }.padding(.horizontal, 8)
                    }
                    .frame(height: 220)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                    Text("Rows stay in discovery order. New devices appear at the bottom. Scan again to clear old results.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                }
                CalibrationView(model: model)
                SignalHistoryView(model: model)
                Divider()
                DisclosureGroup("Advanced settings") {
                    VStack(alignment: .leading, spacing: 10) {
                    Text("Compare readings at your desk and at the departure point. Raise the threshold to lock sooner. Signal strength does not map to a fixed distance.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text("Lock below \(Int(model.threshold)) dBm").frame(width: 180, alignment: .leading)
                        Slider(value: $model.threshold, in: -100 ... -20, step: 1)
                    }
                    Stepper("Weak signal delay: \(Int(model.weakDelay)) seconds", value: $model.weakDelay, in: 1 ... 60)
                    Stepper("Missing signal delay: \(Int(model.missingDelay)) seconds", value: $model.missingDelay, in: 5 ... 300, step: 5)
                    Toggle("Passive scanning", isOn: $model.passive)
                    Text("Passive scanning avoids holding a connection, but readings may arrive less often.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Save advanced settings") { model.applySettings() }.disabled(!model.canSelect)
                    Divider()
                    Button("Lock Now") { model.lockNow() }.disabled(!model.canLock)
                    Text("Lock Now immediately locks this Mac. The guided test only previews locking.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                Toggle("Launch at login", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                if updater.isEnabled {
                    Button("Check for Updates…") { updater.checkForUpdates() }.disabled(!updater.canCheckForUpdates)
                    Toggle("Automatically check for updates", isOn: Binding(get: { updater.automaticallyChecksForUpdates }, set: { updater.setAutomaticallyChecks($0) }))
                    Toggle("Include test builds", isOn: $updater.includeTestBuilds)
                } else {
                    Text("Updates are disabled in development builds.").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Reveal Diagnostic Logs") { model.revealDiagnostics() }
                    Text("Logs stay on this Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(24)
        }.frame(minWidth: 600, minHeight: 560)
    }
}
