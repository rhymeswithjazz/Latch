import SwiftUI
import Charts
import UnlockerCore

struct CalibrationView: View {
    @Bindable var model: AppModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Find your lock setting").font(.title2.bold())
                switch model.calibration.phase {
                case .idle:
                    Text("We’ll measure your Watch at your desk, then while you walk away and return. Starting a test turns automatic locking off. Turn it back on when you finish.")
                    Text("1. Sit at your laptop with your Watch on.\n2. Record your desk signal for 10 seconds.\n3. Walk to your chosen spot, stay 15 seconds, then return.")
                        .foregroundStyle(.secondary)
                    Button("Record my desk signal") { model.startCalibration() }
                        .buttonStyle(.borderedProminent).disabled(!model.canCalibrate)
                    if !model.canCalibrate {
                        Text("Select your Watch, resume monitoring, and wait for a fresh signal before starting.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                case .desk:
                    Text("Step 1 · Stay at your desk").font(.headline)
                    Text("Wear your Watch normally. Recording for \(max(0, 10 - model.calibrationElapsed)) more seconds…")
                    ProgressView(value: Double(min(10, model.calibrationElapsed)), total: 10)
                    Button("Cancel test") { model.cancelCalibration() }
                case .ready:
                    Text("Step 2 · Take a short walk").font(.headline)
                    Text("Your desk signal is recorded. Click below, walk to the spot where you want the Mac to lock, and stay there for 15 seconds. Then come back and click “I’m back.”")
                    Text("You don’t need to read the screen while you’re away. Finish within two minutes.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Start walk-away test") { model.startCalibrationWalk() }
                            .buttonStyle(.borderedProminent).disabled(!model.canCalibrate)
                        Button("Cancel") { model.cancelCalibration() }
                    }
                case .walking:
                    Text("Step 2 · Recording your walk").font(.headline)
                    Text("Walk to your chosen spot, stay for 15 seconds, then return to your laptop.")
                    Text("Recording: \(model.calibrationElapsed) seconds · limit 2 minutes")
                        .monospacedDigit().foregroundStyle(.secondary)
                    HStack {
                        Button("I’m back — review my test") { model.finishCalibrationWalk() }
                            .buttonStyle(.borderedProminent).disabled(model.calibrationElapsed < 10)
                        Button("Cancel test") { model.cancelCalibration() }
                    }
                case .review(let result):
                    Text(model.calibrationSaved ? "Setting saved" : "Step 3 · Review your setting").font(.headline)
                    HStack(spacing: 24) {
                        measurement("At your desk", result.deskRSSI)
                        measurement("While away", result.awayRSSI)
                        measurement("Suggested threshold", result.threshold)
                    }
                    if model.calibrationSaved {
                        Text("Wait for “Observing proximity,” then walk away once more and return. The event list below will show when Latch would have locked. When you are happy with the result, turn on “Automatically lock when I walk away” above.")
                    } else {
                        Text("This setting falls between your desk signal and the sustained weaker part of your walk. Save it, then repeat the walk to check the result.")
                        Text("Saving keeps your current delays: \(Int(model.configuration.settings.weakSignalDelay)) seconds for weak signal and \(Int(model.configuration.settings.missingSignalDelay)) seconds for missing signal.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        if !model.calibrationSaved {
                            Button("Use this setting") { model.useCalibration() }.buttonStyle(.borderedProminent)
                        }
                        Button("Start over") { model.cancelCalibration() }
                    }
                case .failed(let message):
                    Text("Let’s try again").font(.headline)
                    Text(message)
                    Text("No suggested setting was applied.").font(.caption).foregroundStyle(.secondary)
                    Button("Back to setup") { model.cancelCalibration() }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
        }
    }

    private func measurement(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(Int(value)) dBm").font(.headline.monospacedDigit())
        }
    }
}

struct SignalSettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Lock signal level").font(.headline)
                Text("Adjust this anytime after your signal test. A higher level, such as -60 instead of -75 dBm, locks sooner. A lower level lets you move farther away. Signal strength does not map to a fixed distance.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("Lock below \(Int(model.threshold)) dBm")
                        .monospacedDigit().frame(width: 180, alignment: .leading)
                    Slider(value: $model.threshold, in: -100 ... -20, step: 1)
                        .accessibilityLabel("Lock signal level")
                        .accessibilityValue("\(Int(model.threshold)) dBm")
                }
                .disabled(!model.canAdjustSignal)
                HStack {
                    Button("Save signal level") { model.applySignalLevel() }
                        .disabled(!model.canAdjustSignal || model.threshold == model.configuration.settings.threshold)
                    Text("Saved: \(Int(model.configuration.settings.threshold)) dBm")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text("Saving applies the level to the current mode and keeps your delays. To check it with lock previews, turn off automatic locking and try another walk.")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
        }
    }
}

struct SignalHistoryView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Signal history").font(.headline)
            if model.history.isEmpty {
                ContentUnavailableView("Waiting for Watch readings", systemImage: "waveform.path",
                                       description: Text("Your signal and lock previews will appear here."))
                    .frame(height: 150)
            } else {
                Chart {
                    ForEach(model.history.filter { $0.date >= model.historyNow.addingTimeInterval(-180) }) { point in
                        LineMark(x: .value("Time", point.date), y: .value("Signal", point.rssi),
                                 series: .value("Segment", point.segment))
                            .foregroundStyle(.teal)
                    }
                    RuleMark(y: .value("Saved threshold", model.configuration.settings.threshold))
                        .foregroundStyle(.orange).lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    ForEach(model.previewEvents.filter { $0.date >= model.historyNow.addingTimeInterval(-180) }) { event in
                        RuleMark(x: .value("Would lock", event.date))
                            .foregroundStyle(.orange.opacity(0.6))
                    }
                }
                .chartXScale(domain: model.historyNow.addingTimeInterval(-180) ... model.historyNow)
                .chartYScale(domain: -127 ... -1)
                .chartPlotStyle { plot in plot.clipped() }
                .chartXAxis { AxisMarks(values: .stride(by: .minute)) { _ in
                    AxisGridLine(); AxisValueLabel(format: .dateTime.hour().minute())
                } }
                .frame(height: 150)
                .accessibilityLabel("Recent Watch signal. Saved threshold \(Int(model.configuration.settings.threshold)) decibels.")
            }
            Text("Higher means a stronger signal. The dashed line is your saved setting. Orange vertical lines mark lock previews. Gaps mean no fresh readings.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Lock previews").font(.headline)
            if model.previewEvents.isEmpty {
                Text("No lock previews yet. After saving a setting, return nearby to rearm, then try another walk.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.previewEvents.prefix(5)) { event in
                HStack(alignment: .top) {
                    Image(systemName: "lock.fill").foregroundStyle(.orange)
                    Text(event.message)
                    Spacer()
                    Text(event.date, style: .time).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            Text("Recent history is kept while Latch is open. Saving a signal level clears earlier preview events so you can test it afresh.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
