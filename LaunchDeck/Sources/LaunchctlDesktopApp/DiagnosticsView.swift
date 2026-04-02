import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var viewModel: DiagnosticsViewModel
    let processCount: Int
    let launchJobCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if !viewModel.errorMessage.isEmpty {
                Text(viewModel.errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            consoleCard
        }
        .padding(16)
        .background(backgroundLayer)
    }

    private var header: some View {
        HStack {
            Label("Diagnostics", systemImage: "stethoscope")
                .font(.title3.weight(.semibold))

            Spacer()

            HStack(spacing: 8) {
                statChip(title: "Processes", value: processCount)
                statChip(title: "Launch jobs", value: launchJobCount)
            }

            Button {
                viewModel.captureSnapshot(processCount: processCount, launchJobCount: launchJobCount)
            } label: {
                Label("Capture diagnostics", systemImage: "waveform.and.magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var consoleCard: some View {
        inspectorCard(title: "Console", symbol: "terminal") {
            ScrollView {
                Text(viewModel.consoleText.isEmpty ? "No diagnostics snapshot yet." : viewModel.consoleText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .font(.system(.footnote, design: .monospaced))
                    .padding(14)
            }
            .frame(minHeight: 320)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.88))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.green.opacity(0.18), lineWidth: 1)
            )
            .foregroundStyle(Color.green.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.large)
                }
            }
        }
    }

    private func statChip(title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Color.accentColor.opacity(0.14))
        )
    }

    private func inspectorCard<Content: View>(title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
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
                .blur(radius: 64)
                .offset(x: -90, y: -90)
        }
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(Color.green.opacity(0.10))
                .frame(width: 280, height: 280)
                .blur(radius: 76)
                .offset(x: 100, y: 120)
        }
        .ignoresSafeArea()
    }
}
