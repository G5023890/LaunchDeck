import AppKit
import SwiftUI

struct ProcessesView: View {
    @ObservedObject var viewModel: ProcessesViewModel
    @StateObject private var iconCache = ProcessIconCache()
    @State private var pendingProcessAction: PendingProcessAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !viewModel.errorMessage.isEmpty {
                statusText(viewModel.errorMessage, color: .red)
            } else if !viewModel.statusMessage.isEmpty {
                statusText(viewModel.statusMessage, color: .secondary)
            }

            HSplitView {
                processesTable
                    .frame(minWidth: 600, idealWidth: 744, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                inspectorPanel
                    .frame(minWidth: 360, idealWidth: 420, maxWidth: 500, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .background(backgroundLayer)
        .confirmationDialog(
            pendingProcessAction?.title ?? "Confirm",
            isPresented: Binding(
                get: { pendingProcessAction != nil },
                set: { if !$0 { pendingProcessAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingProcessAction {
                Button(pendingProcessAction.confirmTitle, role: .destructive) {
                    pendingProcessAction.perform(on: viewModel)
                    self.pendingProcessAction = nil
                }
                Button("Cancel", role: .cancel) {
                    self.pendingProcessAction = nil
                }
            }
        } message: {
            Text(pendingProcessAction?.message ?? "")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Label("Processes", systemImage: "waveform.path.ecg")
                    .font(.title3.weight(.semibold))

                Text("Live process activity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Text("\(viewModel.processes.count)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                    .foregroundStyle(Color.accentColor)

                Toggle("Live refresh", isOn: $viewModel.isLiveRefresh)
                    .toggleStyle(.switch)
            }

            Button {
                viewModel.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
    }

    private var processesTable: some View {
        Table(viewModel.processes, selection: $viewModel.selectedProcessID, sortOrder: $viewModel.sortOrder) {
            TableColumn("PID", value: \.pid) { process in
                Text(process.pidText)
                    .font(.system(.body, design: .monospaced))
                    .monospacedDigit()
                    .contextMenu { processContextMenu(process) }
            }
            .width(min: 78, ideal: 92, max: 108)

            TableColumn("Name", value: \.processName) { process in
                VStack(alignment: .leading, spacing: 2) {
                    Text(process.processName)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(process.displayPath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .contextMenu { processContextMenu(process) }
            }

            TableColumn("CPU", value: \.cpu) { process in
                HStack(spacing: 8) {
                    ProgressView(value: min(max(process.cpu, 0), 100), total: 100)
                        .tint(cpuTintColor(process.cpu))
                        .controlSize(.small)
                        .frame(width: 72)

                    Text(process.cpuText)
                        .font(.system(.body, design: .monospaced))
                        .monospacedDigit()
                }
                .contextMenu { processContextMenu(process) }
            }
            .width(min: 132, ideal: 152, max: 172)

            TableColumn("Memory", value: \.memoryMB) { process in
                Text(process.memoryText)
                    .font(.system(.body, design: .monospaced))
                    .monospacedDigit()
                    .contextMenu { processContextMenu(process) }
            }
            .width(min: 110, ideal: 130, max: 148)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay {
                if viewModel.isLoading {
                    ProgressView().controlSize(.large)
                } else if viewModel.processes.isEmpty {
                    ContentUnavailableView(
                        "No running processes",
                        systemImage: "cpu",
                        description: Text("Refresh to update the process list.")
                    )
                }
            }
    }

    @ViewBuilder
    private var inspectorPanel: some View {
        if let process = viewModel.selectedProcess {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    overviewCard(process)
                    performanceCard(process)
                    fileInfoCard(process)
                    actionsCard(process)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.thinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            )
        } else {
            ContentUnavailableView(
                "Select a process",
                systemImage: "cursorarrow.click",
                description: Text("Inspector shows process details and actions.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
        }
    }

    private func overviewCard(_ process: RunningProcess) -> some View {
        card(title: "Overview", symbol: "person.crop.rectangle") {
            HStack(spacing: 10) {
                Image(nsImage: iconCache.icon(for: process))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text(process.processName)
                        .font(.headline)
                        .lineLimit(1)
                    Text("PID \(process.pid)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Divider()

            LabeledContent("User") {
                Text(process.user ?? "-")
            }
            LabeledContent("Parent PID") {
                Text(process.parentPID.map(String.init) ?? "-")
                    .font(.system(.body, design: .monospaced))
                    .monospacedDigit()
            }
        }
    }

    private func performanceCard(_ process: RunningProcess) -> some View {
        card(title: "Performance", symbol: "gauge.with.dots.needle.33percent") {
            LabeledContent("CPU") {
                Text(process.cpuText)
                    .font(.system(.body, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(cpuTintColor(process.cpu))
            }
            LabeledContent("Memory") {
                Text(process.memoryInspectorText)
                    .font(.system(.body, design: .monospaced))
                    .monospacedDigit()
            }
            LabeledContent("Threads") {
                Text(process.threadCount.map(String.init) ?? "-")
                    .font(.system(.body, design: .monospaced))
                    .monospacedDigit()
            }
            LabeledContent("Uptime") {
                Text(process.uptime ?? "-")
                    .font(.system(.body, design: .monospaced))
                    .monospacedDigit()
            }
        }
    }

    private func fileInfoCard(_ process: RunningProcess) -> some View {
        card(title: "File Info", symbol: "doc.text") {
            Text(process.displayPath)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .truncationMode(.middle)

            HStack {
                Spacer()
                Button("Reveal in Finder") {
                    viewModel.revealBinary(for: process)
                }
                .disabled(!viewModel.isProcessAlive(process) || process.binaryPath == nil)
            }
        }
    }

    private func actionsCard(_ process: RunningProcess) -> some View {
        card(title: "Actions", symbol: "bolt") {
            HStack(spacing: 8) {
                Button("Terminate") {
                    pendingProcessAction = .terminate(process)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isProcessAlive(process))

                Button("Force Kill") {
                    pendingProcessAction = .forceKill(process)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.isProcessAlive(process))
            }

            HStack(spacing: 8) {
                Button("Copy PID") {
                    viewModel.copyPID(process)
                }
                .buttonStyle(.bordered)

                Button("Reveal in Finder") {
                    viewModel.revealBinary(for: process)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.isProcessAlive(process) || process.binaryPath == nil)

                Button("Copy Full Path") {
                    viewModel.copyFullPath(process)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private func processContextMenu(_ process: RunningProcess) -> some View {
        Button("Terminate") { pendingProcessAction = .terminate(process) }
            .disabled(!viewModel.isProcessAlive(process))
        Button("Force Kill") { pendingProcessAction = .forceKill(process) }
            .disabled(!viewModel.isProcessAlive(process))
        Divider()
        Button("Copy PID") { viewModel.copyPID(process) }
        Button("Reveal in Finder") { viewModel.revealBinary(for: process) }
            .disabled(process.binaryPath == nil)
        Button("Copy Full Path") { viewModel.copyFullPath(process) }
    }

    private func card<Content: View>(title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
    }

    private var backgroundLayer: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color(nsColor: .underPageBackgroundColor),
                Color(nsColor: .controlBackgroundColor)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topLeading) {
            Circle()
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 240, height: 240)
                .blur(radius: 60)
                .offset(x: -80, y: -80)
        }
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(Color.orange.opacity(0.10))
                .frame(width: 280, height: 280)
                .blur(radius: 72)
                .offset(x: 100, y: 120)
        }
        .ignoresSafeArea()
    }

    private func cpuTintColor(_ cpu: Double) -> Color {
        if cpu > 80 { return .red }
        if cpu >= 40 { return .orange }
        return .accentColor
    }

    private func statusText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(color)
    }
}

private enum PendingProcessAction {
    case terminate(RunningProcess)
    case forceKill(RunningProcess)

    var title: String {
        switch self {
        case .terminate(let process):
            return "Terminate PID \(process.pid)?"
        case .forceKill(let process):
            return "Force kill PID \(process.pid)?"
        }
    }

    var confirmTitle: String {
        switch self {
        case .terminate:
            return "Terminate"
        case .forceKill:
            return "Force Kill"
        }
    }

    var message: String {
        switch self {
        case .terminate(let process):
            return "Send SIGTERM to \(process.processName) (\(process.pid))?"
        case .forceKill(let process):
            return "Send SIGKILL to \(process.processName) (\(process.pid))? This can immediately stop the process."
        }
    }

    @MainActor
    func perform(on viewModel: ProcessesViewModel) {
        switch self {
        case .terminate(let process):
            viewModel.kill(process, force: false)
        case .forceKill(let process):
            viewModel.kill(process, force: true)
        }
    }
}

@MainActor
private final class ProcessIconCache: ObservableObject {
    private let cache = NSCache<NSString, NSImage>()

    func icon(for process: RunningProcess) -> NSImage {
        let key = (process.binaryPath ?? process.processName) as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let image: NSImage
        if let path = process.binaryPath, FileManager.default.fileExists(atPath: path) {
            image = NSWorkspace.shared.icon(forFile: path)
        } else {
            image = NSImage(systemSymbolName: "cpu", accessibilityDescription: nil) ?? NSImage()
        }

        cache.setObject(image, forKey: key)
        return image
    }
}
