import SwiftUI

struct LaunchdJobEditorView: View {
    @ObservedObject var viewModel: LaunchdJobEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showApplyConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    editorModeCard
                    editorBodyCard
                    validationCard
                    previewCard
                    backupsCard
                    resultCard
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(background)
            .navigationTitle("Safe Edit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", role: .cancel) { dismiss() }
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        Task { await viewModel.dryRun() }
                    } label: {
                        Label("Dry Run", systemImage: "checklist")
                    }
                    .disabled(viewModel.isLoading || viewModel.isValidating || viewModel.isApplying)

                    Button {
                        showApplyConfirmation = true
                    } label: {
                        Label("Apply", systemImage: "checkmark.shield")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isLoading || viewModel.isApplying)
                }
            }
        }
        .task {
            await viewModel.load()
        }
        .confirmationDialog(
            "Apply changes to \(viewModel.title)?",
            isPresented: $showApplyConfirmation,
            titleVisibility: .visible
        ) {
            Button("Apply Changes", role: .destructive) {
                Task { await viewModel.applyChanges() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("A backup will be created before LaunchDeck writes the plist. You can restore a previous version afterward.")
        }
        .onChange(of: viewModel.editorMode) { _, newValue in
            viewModel.switchMode(to: newValue)
        }
    }

    private var background: some View {
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
                .fill(Color.accentColor.opacity(0.10))
                .frame(width: 220, height: 220)
                .blur(radius: 70)
                .offset(x: -50, y: -50)
        }
        .ignoresSafeArea()
    }

    private var headerCard: some View {
        editorCard(title: "Job Snapshot", symbol: "doc.text.magnifyingglass") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.title)
                            .font(.title2.weight(.semibold))
                            .lineLimit(2)
                            .truncationMode(.middle)

                        Text(viewModel.fileURL?.path ?? "No plist file available")
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        badge(viewModel.sourceJob.domain.title, color: .blue)
                        badge(viewModel.sourceJob.statusBadgeTitle, color: viewModel.sourceJob.isLoaded ? .green : .gray)
                    }
                }

                Divider()

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("Last modified")
                            .foregroundStyle(.secondary)
                        Text(lastModifiedText)
                            .monospacedDigit()
                    }
                    GridRow {
                        Text("Validation")
                            .foregroundStyle(.secondary)
                        Text(viewModel.issueCountsText)
                            .foregroundStyle(issueTextColor)
                    }
                    GridRow {
                        Text("Backup")
                            .foregroundStyle(.secondary)
                        Text(viewModel.latestBackup?.backupURL.lastPathComponent ?? "No backups yet")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                if !viewModel.errorMessage.isEmpty {
                    noticeBanner(text: viewModel.errorMessage, color: .red)
                } else if !viewModel.applySummary.isEmpty {
                    noticeBanner(text: viewModel.applySummary, color: .green)
                }
            }
        }
    }

    private var editorModeCard: some View {
        editorCard(title: "Editor Mode", symbol: "slider.horizontal.3") {
            Picker("Editor Mode", selection: $viewModel.editorMode) {
                ForEach(LaunchdEditorMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                Toggle("Reload after apply", isOn: $viewModel.shouldReloadAfterApply)
                Toggle("Kickstart after reload", isOn: $viewModel.shouldKickstartAfterApply)
                    .disabled(!viewModel.shouldReloadAfterApply)
            }
        }
    }

    @ViewBuilder
    private var editorBodyCard: some View {
        editorCard(title: viewModel.editorMode == .structured ? "Structured Fields" : "Raw Plist", symbol: viewModel.editorMode == .structured ? "square.grid.2x2" : "text.alignleft") {
            if viewModel.editorMode == .structured {
                structuredEditor
            } else {
                rawEditor
            }
        }
    }

    private var structuredEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Identity")
            fieldGrid {
                labeledField("Label") {
                    TextField("com.example.job", text: $viewModel.label)
                }
                labeledField("Program") {
                    TextField("/usr/bin/your-tool", text: $viewModel.program)
                }
            }

            labeledField("Program Arguments") {
                TextEditor(text: $viewModel.programArgumentsText)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 72)
                    .overlay(alignment: .topLeading) {
                        if viewModel.programArgumentsText.isEmpty {
                            Text("One argument per line")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 6)
                        }
                    }
            }

            Toggle("Run At Load", isOn: $viewModel.runAtLoad)

            Divider()

            sectionTitle("KeepAlive")
            Picker("KeepAlive", selection: $viewModel.keepAliveMode) {
                ForEach(LaunchdKeepAliveEditorMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if viewModel.keepAliveMode == .flags {
                labeledField("KeepAlive Flags") {
                    TextField("SuccessfulExit=false, PathState=true", text: $viewModel.keepAliveFlagsText)
                        .font(.system(.footnote, design: .monospaced))
                }
            }

            Divider()

            sectionTitle("Schedule")
            fieldGrid {
                labeledField("Start Interval (seconds)") {
                    TextField("0", text: $viewModel.startIntervalText)
                        .font(.system(.footnote, design: .monospaced))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Start Calendar Interval")
                        .font(.headline)
                    Spacer()
                    Button("Add Row") { viewModel.addCalendarRow() }
                }

                ForEach($viewModel.calendarRows) { $row in
                    HStack(spacing: 10) {
                        Picker("Weekday", selection: $row.weekday) {
                            ForEach(1...7, id: \.self) { weekday in
                                Text(weekdayName(weekday)).tag(weekday)
                            }
                        }
                        .frame(width: 120)

                        Stepper("Hour \(row.hour)", value: $row.hour, in: 0...23)
                        Stepper("Minute \(row.minute)", value: $row.minute, in: 0...59)

                        Spacer()

                        Button(role: .destructive) {
                            if let index = viewModel.calendarRows.firstIndex(where: { $0.id == row.id }) {
                                viewModel.calendarRows.remove(at: index)
                            }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
            }

            Divider()

            sectionTitle("Paths")
            fieldGrid {
                labeledField("Working Directory") {
                    TextField("/path/to/workdir", text: $viewModel.workingDirectory)
                }
                labeledField("Standard Out") {
                    TextField("/path/to/output.log", text: $viewModel.standardOutPath)
                }
                labeledField("Standard Error") {
                    TextField("/path/to/error.log", text: $viewModel.standardErrorPath)
                }
            }

            Divider()

            sectionTitle("Environment Variables")
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Environment Variables")
                        .font(.headline)
                    Spacer()
                    Button("Add Variable") { viewModel.addEnvironmentRow() }
                }

                ForEach($viewModel.environmentRows) { $row in
                    HStack(spacing: 10) {
                        TextField("KEY", text: $row.key)
                            .font(.system(.footnote, design: .monospaced))
                        TextField("value", text: $row.value)
                        Button(role: .destructive) {
                            if let index = viewModel.environmentRows.firstIndex(where: { $0.id == row.id }) {
                                viewModel.environmentRows.remove(at: index)
                            }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private var rawEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit the plist text directly. Dry Run will reparse this text before anything is written.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            TextEditor(text: $viewModel.rawText)
                .font(.system(.footnote, design: .monospaced))
                .frame(minHeight: 520)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
    }

    private var validationCard: some View {
        editorCard(title: "Validation", symbol: "checkmark.seal") {
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.isValidating {
                    ProgressView("Validating plist...")
                }

                if let report = viewModel.validationReport {
                    validationSummary(report)

                    issueSection(title: "Errors", issues: report.errors, color: .red)
                    issueSection(title: "Warnings", issues: report.warnings, color: .orange)
                    issueSection(title: "Notices", issues: report.notices, color: .blue)
                } else {
                    Text("Run Dry Run to inspect syntax, semantics, and launchctl preflight results.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var previewCard: some View {
        editorCard(title: "Normalized Preview", symbol: "doc.text.viewfinder") {
            VStack(alignment: .leading, spacing: 10) {
                Text("LaunchDeck will write the normalized plist below if you apply the plan.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TextEditor(text: Binding(get: { viewModel.normalizedPreview }, set: { _ in }))
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 280)
                    .allowsHitTesting(false)
                    .opacity(0.95)
            }
        }
    }

    private var backupsCard: some View {
        editorCard(title: "Backups and Rollback", symbol: "archivebox") {
            VStack(alignment: .leading, spacing: 12) {
                if let latest = viewModel.latestBackup {
                    LabeledContent("Latest backup") {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(latest.backupURL.lastPathComponent)
                                .font(.system(.footnote, design: .monospaced))
                            Text("\(latest.sizeText) • \(dateText(latest.createdAt))")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("No backups yet. Applying changes will create the first snapshot automatically.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Restore Selected Backup") {
                        Task { await viewModel.restoreSelectedBackup() }
                    }
                    .disabled(viewModel.latestBackups.isEmpty)

                    Spacer()

                    Text("Backups are kept alongside the edited plist and can be restored at any time.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if !viewModel.latestBackups.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(viewModel.latestBackups.prefix(3))) { backup in
                            HStack {
                                Button {
                                    viewModel.selectedBackupID = backup.id
                                } label: {
                                    HStack {
                                        Image(systemName: viewModel.selectedBackupID == backup.id ? "checkmark.circle.fill" : "circle")
                                        Text(backup.backupURL.lastPathComponent)
                                            .font(.system(.footnote, design: .monospaced))
                                    }
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                Text(dateText(backup.createdAt))
                                    .foregroundStyle(.secondary)
                                    .font(.footnote)
                            }
                        }
                    }
                }
            }
        }
    }

    private var resultCard: some View {
        Group {
            if !viewModel.applySummary.isEmpty || viewModel.isApplying {
                editorCard(title: "Apply Result", symbol: "arrow.triangle.2.circlepath") {
                    if viewModel.isApplying {
                        ProgressView("Applying changes...")
                    } else {
                        Text(viewModel.applySummary)
                            .font(.footnote)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func validationSummary(_ report: LaunchdValidationReport) -> some View {
        HStack(spacing: 12) {
            summaryChip(title: "\(report.errors.count)", subtitle: "Errors", color: .red)
            summaryChip(title: "\(report.warnings.count)", subtitle: "Warnings", color: .orange)
            summaryChip(title: "\(report.notices.count)", subtitle: "Notices", color: .blue)
            Text(report.summaryText)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func issueSection(title: String, issues: [ValidationIssue], color: Color) -> some View {
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                ForEach(issues) { issue in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: issue.severity.symbol)
                            .foregroundStyle(color)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(issue.title)
                                .font(.subheadline.weight(.semibold))
                            Text(issue.message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func editorCard<Content: View>(title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.headline)
                Spacer()
            }
            content()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func fieldGrid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
            content()
        }
    }

    private func labeledField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GridRow {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                content()
            }
            .gridCellColumns(2)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(.secondary)
    }

    private func summaryChip(title: String, subtitle: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.headline.weight(.bold))
            Text(subtitle)
                .font(.caption)
        }
        .frame(minWidth: 70)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.12))
        )
        .foregroundStyle(color)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.16)))
            .foregroundStyle(color)
    }

    private func noticeBanner(text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(color)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.10))
        )
    }

    private var lastModifiedText: String {
        guard let date = viewModel.sourceJob.plistPath.flatMap({ URL(fileURLWithPath: $0) }).flatMap({ try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }) else {
            return "Unknown"
        }
        return dateText(date)
    }

    private var issueTextColor: Color {
        if let report = viewModel.validationReport {
            if report.canApply {
                return .green
            }
            return .red
        }
        return .secondary
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .standard)
    }
}

private func weekdayName(_ weekday: Int) -> String {
    switch weekday {
    case 1: return "Sun"
    case 2: return "Mon"
    case 3: return "Tue"
    case 4: return "Wed"
    case 5: return "Thu"
    case 6: return "Fri"
    case 7: return "Sat"
    default: return "?"
    }
}
