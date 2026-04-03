import SwiftUI

struct LaunchJobResourceOverlayView: View {
    let model: ResourceOverlayViewModel

    var body: some View {
        if let snapshot = model.snapshot {
            VStack(alignment: .leading, spacing: 12) {
                header(snapshot: snapshot)
                metrics(snapshot: snapshot)
                trendSection

                if let note = model.uncertaintyText {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(snapshot.resolution.confidence == .uncertain ? .orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            ContentUnavailableView(
                "Not Running",
                systemImage: "pause.circle",
                description: Text(overlayDescription)
            )
        }
    }

    private func header(snapshot: LaunchJobResourceSnapshot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.resolution.process?.processName ?? model.label ?? "Launch Service")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(snapshot.executablePathText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            statusBadge(title: snapshot.resolution.confidence.title, color: confidenceColor(snapshot.resolution.confidence))
        }
    }

    private func metrics(snapshot: LaunchJobResourceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("PID") {
                Text(snapshot.pidText)
                    .font(.system(.body, design: .monospaced))
                    .monospacedDigit()
            }

            LabeledContent("CPU") {
                Text(snapshot.cpuText)
                    .font(.system(.body, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(cpuColor(snapshot.cpu))
            }

            LabeledContent("Memory") {
                Text(snapshot.memoryText)
                    .font(.system(.body, design: .monospaced))
                    .monospacedDigit()
            }

            LabeledContent("Uptime") {
                Text(snapshot.uptimeText)
                    .font(.system(.body, design: .monospaced))
                    .monospacedDigit()
            }

            LabeledContent("State") {
                Text(snapshot.stateText)
                    .font(.system(.body, design: .monospaced))
                    .monospacedDigit()
            }

            LabeledContent("Child processes") {
                Text(snapshot.childProcessCountText)
                    .font(.system(.body, design: .monospaced))
                    .monospacedDigit()
            }

            LabeledContent("Open files") {
                Text(snapshot.openFilesCountText)
                    .font(.system(.body, design: .monospaced))
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private var trendSection: some View {
        let oneMinute = model.oneMinuteTrend
        let fiveMinute = model.fiveMinuteTrend

        if oneMinute != nil || fiveMinute != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("Trend")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let oneMinute {
                    trendRow(title: "1 min", trend: oneMinute)
                }

                if let fiveMinute {
                    trendRow(title: "5 min", trend: fiveMinute)
                }
            }
        }
    }

    private func trendRow(title: String, trend: LaunchJobResourceTrend) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(trend.sampleCount) samples")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                trendMetric(
                    label: "CPU",
                    value: String(format: "%.1f%%", trend.averageCPU),
                    delta: trend.cpuDelta,
                    direction: trend.cpuDirection,
                    tint: cpuColor(trend.currentCPU)
                )

                trendMetric(
                    label: "Memory",
                    value: memoryValue(trend.averageMemoryMB),
                    delta: trend.memoryDelta,
                    direction: trend.memoryDirection,
                    tint: .secondary
                )
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func trendMetric(
        label: String,
        value: String,
        delta: Double,
        direction: LaunchJobResourceTrend.Direction,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Image(systemName: direction.symbol)
                    .font(.caption2.weight(.semibold))
                Text(value)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(tint)

            Text(deltaText(delta))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusBadge(title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.20)))
            .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 1))
            .foregroundStyle(color)
    }

    private func confidenceColor(_ confidence: LaunchJobProcessResolution.Confidence) -> Color {
        switch confidence {
        case .exact:
            return .green
        case .likely:
            return .blue
        case .uncertain:
            return .orange
        case .none:
            return .secondary
        }
    }

    private func cpuColor(_ cpu: Double?) -> Color {
        guard let cpu else { return .secondary }
        if cpu > 80 { return .red }
        if cpu >= 40 { return .orange }
        return .accentColor
    }

    private func deltaText(_ delta: Double) -> String {
        let formatted = String(format: "%.1f", abs(delta))
        if delta > 0 {
            return "+\(formatted)"
        }
        if delta < 0 {
            return "-\(formatted)"
        }
        return "0.0"
    }

    private func memoryValue(_ value: Double) -> String {
        if value >= 1024 {
            return String(format: "%.2f GB", value / 1024)
        }
        return String(format: "%.1f MB", value)
    }

    private var overlayDescription: String {
        if let note = model.uncertaintyText {
            return note
        }
        if let reason = model.resolution?.reason {
            return reason
        }
        return "LaunchDeck will show live CPU, memory, uptime, and process details here when it can confidently associate this job with a running process."
    }
}
