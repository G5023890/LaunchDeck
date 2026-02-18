import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var viewModel: DiagnosticsViewModel
    let processCount: Int
    let launchJobCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Diagnostics", systemImage: "stethoscope")
                    .font(.title3.weight(.semibold))

                Spacer()

                Button {
                    viewModel.captureSnapshot(processCount: processCount, launchJobCount: launchJobCount)
                } label: {
                    Label("Capture snapshot", systemImage: "waveform.and.magnifyingglass")
                }
            }

            if !viewModel.errorMessage.isEmpty {
                Text(viewModel.errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            GroupBox {
                ScrollView {
                    Text(viewModel.consoleText.isEmpty ? "No diagnostics snapshot yet." : viewModel.consoleText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .font(.system(.footnote, design: .monospaced))
                        .padding(12)
                }
                .background(Color.black.opacity(0.9))
                .foregroundStyle(Color.green.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } label: {
                Label("Console", systemImage: "terminal")
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
}
