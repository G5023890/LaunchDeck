import AppKit
import SwiftUI

struct ProcessesView: View {
    @ObservedObject var viewModel: ProcessesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !viewModel.errorMessage.isEmpty {
                statusText(viewModel.errorMessage, color: .red)
            } else if !viewModel.statusMessage.isEmpty {
                statusText(viewModel.statusMessage, color: .secondary)
            }

            Table(viewModel.processes, selection: $viewModel.selectedProcessID, sortOrder: $viewModel.sortOrder) {
                TableColumn("PID", value: \RunningProcess.pid) { item in
                    Text(item.pidText)
                        .font(.system(.body, design: .monospaced))
                        .contextMenu {
                            processContextMenu(process: item)
                        }
                }
                .width(min: 70, ideal: 90, max: 110)

                TableColumn("Command", value: \RunningProcess.command) { item in
                    Text(item.command)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .contextMenu {
                            processContextMenu(process: item)
                        }
                }

                TableColumn("CPU", value: \RunningProcess.cpu) { item in
                    Text(item.cpuText)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(item.cpu > 50 ? .red : .primary)
                }
                .width(min: 80, ideal: 100, max: 120)

                TableColumn("Memory", value: \RunningProcess.memoryMB) { item in
                    Text(item.memoryText)
                        .font(.system(.body, design: .monospaced))
                }
                .width(min: 100, ideal: 120, max: 140)
            }
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.large)
                }
            }
        }
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

    @ViewBuilder
    private func processContextMenu(process: RunningProcess) -> some View {
        Button("Kill TERM") { viewModel.kill(process, force: false) }
        Button("Kill KILL") { viewModel.kill(process, force: true) }
        Divider()
        Button("Copy process name") {
            let processName = process.command
                .split(separator: " ")
                .first
                .map(String.init)?
                .split(separator: "/")
                .last
                .map(String.init) ?? process.command
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(processName, forType: .string)
            viewModel.statusMessage = "Copied \(processName)"
        }
        Button("Copy command") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(process.command, forType: .string)
            viewModel.statusMessage = "Copied command"
        }
        Button("Reveal binary") { viewModel.revealBinary(for: process) }
        Button("Copy path") {
            if let path = process.binaryPath {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
                viewModel.statusMessage = "Copied \(path)"
            }
        }
    }

    private func statusText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(color)
    }
}
