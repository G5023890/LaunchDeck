import AppKit
import SwiftUI

struct ProcessesView: View {
    @ObservedObject var viewModel: ProcessesViewModel
    @StateObject private var iconCache = ProcessIconCache()

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
                    .frame(minWidth: 540, idealWidth: 720, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                inspectorPanel
                    .frame(minWidth: 330, idealWidth: 400, maxWidth: 460, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .controlBackgroundColor)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var header: some View {
        HStack {
            Label("Processes", systemImage: "waveform.path.ecg")
                .font(.title3.weight(.semibold))

            Spacer()

            Toggle("Live refresh", isOn: $viewModel.isLiveRefresh)
                .toggleStyle(.switch)

            Button {
                viewModel.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
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
            .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
        } else {
            ContentUnavailableView(
                "Select a process",
                systemImage: "cursorarrow.click",
                description: Text("Inspector shows process metadata and actions.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
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
                    viewModel.kill(process, force: false)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isProcessAlive(process))

                Button("Force Kill") {
                    viewModel.kill(process, force: true)
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
        Button("Terminate") { viewModel.kill(process, force: false) }
            .disabled(!viewModel.isProcessAlive(process))
        Button("Force Kill") { viewModel.kill(process, force: true) }
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
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
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
