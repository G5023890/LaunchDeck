import SwiftUI

struct LaunchJobRelationsView: View {
    @ObservedObject var viewModel: LaunchServicesViewModel
    let selectedJob: LaunchServiceJob
    @Binding var isExpanded: Bool

    @State private var presentationMode: RelationPresentationMode = .grouped
    @State private var filterKind: LaunchJobRelationKind?

    private var analysis: LaunchJobRelationAnalysis? {
        viewModel.relationAnalysis
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Related Jobs", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Related jobs stay collapsed until you ask for them.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("Open this section to compute relationship clusters for the current selection.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    Button(isExpanded ? "Hide" : "Load") {
                        isExpanded.toggle()
                        syncRequestState()
                    }
                    .buttonStyle(.bordered)
                }

                if isExpanded {
                    controls

                    switch viewModel.relationDetailsPhase {
                    case .idle:
                        ContentUnavailableView(
                            "Details not requested",
                            systemImage: "link",
                            description: Text("Open this section to request the related job analysis for the selected job.")
                        )
                    case .loading:
                        ProgressView("Loading related jobs...")
                            .controlSize(.regular)
                    case .ready:
                        if let analysis {
                            if analysis.relatedJobs.isEmpty {
                                ContentUnavailableView(
                                    "No related jobs found",
                                    systemImage: "link",
                                    description: Text("No observable relation matched this job in the current scan.")
                                )
                            } else {
                                switch presentationMode {
                                case .grouped:
                                    groupedList(analysis)
                                case .graph:
                                    graphView(analysis)
                                }
                            }
                        } else {
                            ContentUnavailableView(
                                "Related Jobs unavailable",
                                systemImage: "link.badge.plus",
                                description: Text("Refresh launch jobs and processes to compute relation clusters.")
                            )
                        }
                    }
                }
            }
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
        .onAppear {
            syncRequestState()
        }
        .onChange(of: selectedJob.id) { _, _ in
            syncRequestState()
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Selected: \(selectedJob.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if let analysis {
                    Text("\(analysis.relatedJobs.count) related")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Picker("View", selection: $presentationMode) {
                ForEach(RelationPresentationMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                Menu {
                    Button("All relation types") {
                        filterKind = nil
                    }
                    Divider()
                    ForEach(LaunchJobRelationKind.allCases) { kind in
                        Button(kind.title) {
                            filterKind = kind
                        }
                    }
                } label: {
                    Label(filterKind?.title ?? "Filter by relation", systemImage: "line.3.horizontal.decrease.circle")
                }
                .buttonStyle(.bordered)

                if filterKind != nil {
                    Button("Clear") {
                        filterKind = nil
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func syncRequestState() {
        if isExpanded {
            viewModel.requestRelationDetails()
        } else {
            viewModel.cancelRelationDetailsRequest()
        }
    }

    @ViewBuilder
    private func groupedList(_ analysis: LaunchJobRelationAnalysis) -> some View {
        let groups = groupedRelations(from: analysis)

        if groups.isEmpty {
            ContentUnavailableView(
                "No matches for filter",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Try a different relation type or clear the filter.")
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(groups, id: \.kind) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(group.kind.title, systemImage: iconName(for: group.kind))
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                scoreBadge("\(group.relations.count)")
                            }

                            ForEach(group.relations) { relation in
                                relationRow(relation)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 420)
        }
    }

    @ViewBuilder
    private func relationRow(_ relation: LaunchJobRelation) -> some View {
        Button {
            viewModel.selectedJobID = relation.relatedJob.id
        } label: {
            HStack(alignment: .top, spacing: 12) {
                relationIcon(for: relation)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(relation.relatedJob.label)
                                .font(.body.weight(.semibold))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(relation.relatedJob.program ?? relation.relatedJob.plistPath ?? "No executable path")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            scoreBadge(relation.score.priority)
                            Text("\(relation.score.value)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }

                    FlowBadges(items: relation.reasons.map { $0.summary }, color: .accentColor)

                    if relation.reasons.isEmpty == false {
                        Text(relation.reasons.compactMap { reason -> String? in
                            guard let detail = reason.detail else { return reason.summary }
                            return "\(reason.summary): \(detail)"
                        }.joined(separator: " • "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(viewModel.selectedJobID == relation.relatedJob.id ? Color.accentColor.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func graphView(_ analysis: LaunchJobRelationAnalysis) -> some View {
        RelationGraphView(
            graph: analysis.graph,
            selectedJob: selectedJob,
            onSelectJob: { viewModel.selectedJobID = $0 }
        )
        .frame(height: 420)
    }

    private func groupedRelations(from analysis: LaunchJobRelationAnalysis) -> [RelationGroup] {
        let filtered = analysis.relatedJobs.filter { relation in
            guard let filterKind else { return true }
            return relation.kinds.contains(filterKind)
        }

        let groups = Dictionary(grouping: filtered) { relation -> LaunchJobRelationKind in
            if let filterKind {
                return filterKind
            }
            return relation.primaryKind
        }

        return LaunchJobRelationKind.allCases.compactMap { kind in
            guard let relations = groups[kind], relations.isEmpty == false else { return nil }
            return RelationGroup(kind: kind, relations: relations)
        }
    }

    private func iconName(for kind: LaunchJobRelationKind) -> String {
        switch kind {
        case .sameExecutablePath:
            return "shippingbox"
        case .sameExecutableDirectory:
            return "folder"
        case .sameLabelNamespace:
            return "tag"
        case .sharedWatchPath:
            return "eye"
        case .sharedQueueDirectory:
            return "tray.full"
        case .sharedLogFile:
            return "text.alignleft"
        case .sharedWorkingDirectory:
            return "shippingbox.and.arrow.backward"
        case .sharedEnvironmentSignature:
            return "slider.horizontal.3"
        case .sameOwnerScope:
            return "person.crop.square"
        case .sameManagedOrigin:
            return "sparkles"
        case .sameRuntimeProcessFamily:
            return "atom"
        }
    }

    private func relationIcon(for relation: LaunchJobRelation) -> some View {
        ZStack {
            Circle()
                .fill(color(for: relation.primaryKind).opacity(0.16))
            Image(systemName: iconName(for: relation.primaryKind))
                .font(.caption.weight(.semibold))
                .foregroundStyle(color(for: relation.primaryKind))
        }
    }

    private func color(for kind: LaunchJobRelationKind) -> Color {
        switch kind {
        case .sameExecutablePath:
            return .blue
        case .sameExecutableDirectory:
            return .teal
        case .sameLabelNamespace:
            return .indigo
        case .sharedWatchPath:
            return .green
        case .sharedQueueDirectory:
            return .mint
        case .sharedLogFile:
            return .orange
        case .sharedWorkingDirectory:
            return .cyan
        case .sharedEnvironmentSignature:
            return .purple
        case .sameOwnerScope:
            return .pink
        case .sameManagedOrigin:
            return .yellow
        case .sameRuntimeProcessFamily:
            return .red
        }
    }

    private func scoreBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.accentColor.opacity(0.14)))
            .foregroundStyle(Color.accentColor)
    }
}

private enum RelationPresentationMode: String, CaseIterable, Identifiable {
    case grouped
    case graph

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grouped:
            return "Grouped"
        case .graph:
            return "Graph"
        }
    }
}

private struct RelationGroup: Identifiable, Hashable {
    let kind: LaunchJobRelationKind
    let relations: [LaunchJobRelation]

    var id: String { kind.rawValue }
}

private struct RelationGraphView: View {
    let graph: RelationGraph
    let selectedJob: LaunchServiceJob
    let onSelectJob: (LaunchServiceJob.ID) -> Void

    var body: some View {
        GeometryReader { proxy in
            let layout = makeLayout(in: proxy.size)

            ZStack {
                Canvas { context, _ in
                    for edge in graph.edges {
                        guard let source = layout[edge.sourceID], let target = layout[edge.targetID] else { continue }
                        var path = Path()
                        path.move(to: source)
                        path.addLine(to: target)
                        context.stroke(path, with: .color(color(for: edge.kind).opacity(0.28)), lineWidth: 2)
                    }
                }

                ForEach(graph.nodes) { node in
                    if let point = layout[node.id] {
                        graphNode(node, at: point)
                    }
                }
            }
        }
    }

    private func graphNode(_ node: RelationGraphNode, at point: CGPoint) -> some View {
        Button {
            if node.isSelected == false {
                onSelectJob(node.id)
            }
        } label: {
            VStack(spacing: 6) {
                Text(node.label)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if let subtitle = node.subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                Text(node.isSelected ? "Selected" : "\(node.score)")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
            }
            .padding(10)
            .frame(width: node.isSelected ? 148 : 126, height: node.isSelected ? 94 : 82)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(node.isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(node.isSelected ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .position(point)
    }

    private func makeLayout(in size: CGSize) -> [String: CGPoint] {
        guard graph.nodes.isEmpty == false else { return [:] }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let related = graph.nodes.filter { $0.isSelected == false }
        guard related.isEmpty == false else {
            return [graph.nodes[0].id: center]
        }

        let radius = max(120, min(size.width, size.height) * 0.32)
        var layout: [String: CGPoint] = [graph.nodes.first(where: { $0.isSelected })?.id ?? selectedJob.id: center]

        for (index, node) in related.enumerated() {
            let angle = (-Double.pi / 2) + (Double(index) * (2 * Double.pi / Double(related.count)))
            let x = center.x + CGFloat(cos(angle)) * radius
            let y = center.y + CGFloat(sin(angle)) * radius
            layout[node.id] = CGPoint(x: x, y: y)
        }

        return layout
    }

    private func color(for kind: LaunchJobRelationKind) -> Color {
        switch kind {
        case .sameExecutablePath:
            return .blue
        case .sameExecutableDirectory:
            return .teal
        case .sameLabelNamespace:
            return .indigo
        case .sharedWatchPath:
            return .green
        case .sharedQueueDirectory:
            return .mint
        case .sharedLogFile:
            return .orange
        case .sharedWorkingDirectory:
            return .cyan
        case .sharedEnvironmentSignature:
            return .purple
        case .sameOwnerScope:
            return .pink
        case .sameManagedOrigin:
            return .yellow
        case .sameRuntimeProcessFamily:
            return .red
        }
    }
}

private struct FlowBadges: View {
    let items: [String]
    let color: Color

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(color.opacity(0.10)))
                        .foregroundStyle(color)
                }
            }
        }
    }
}
