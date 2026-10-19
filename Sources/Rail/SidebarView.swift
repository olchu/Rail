import SwiftUI

struct SidebarActions {
    let select: (WindowItem) -> Void
    let open: (NSRunningApplication) -> Void
    let addToProject: (WindowItem) -> Void
    let removeFromProject: (WindowItem, Project) -> Void
    let renameProject: (Project) -> Void
    let setColor: (Int, Project) -> Void
    let deleteProject: (Project) -> Void
    let removeRule: (WindowRule, Project) -> Void
}

struct SidebarView: View {
    let store: WindowStore
    let model: SidebarModel
    let actions: SidebarActions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var collapsed: Set<UUID> = []
    /// Natural height of the list, so the glass hugs short content and only scrolls when full.
    @State private var contentHeight: CGFloat = 0

    private typealias M = SidebarMetrics

    var body: some View {
        HStack(spacing: 0) {
            card.frame(width: M.width)
            Spacer(minLength: 0)
        }
    }

    // MARK: Card

    /// Full height and flush with the screen edge; only the corners facing the screen are rounded.
    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if store.isTrusted {
                content
                Spacer(minLength: 0)
                if !store.idleApps.isEmpty {
                    IdleApps(apps: store.idleApps, open: actions.open)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 12)
                        .entrance(2, isOpen: isOpen, reduceMotion: reduceMotion)
                }
            } else {
                PermissionCard()
                    .entrance(1, isOpen: isOpen, reduceMotion: reduceMotion)
                Spacer(minLength: 0)
            }
        }
        .frame(maxHeight: .infinity)
        // NSGlassEffectView rounds every corner; the left ones hang past the screen edge and are cut off.
        .background {
            GlassBackground(cornerRadius: M.cornerRadius)
                .padding(.leading, -M.cornerRadius)
        }
        .overlay(alignment: .trailing) { edgeGlow }
        .offset(x: offset)
        .opacity(model.phase == .hidden ? 0 : 1)
    }

    private var isOpen: Bool { model.phase == .shown }

    private var offset: CGFloat {
        switch model.phase {
        case .shown: 0
        case .peeking: -M.width + M.peekWidth
        case .hidden: reduceMotion ? 0 : -(M.width + 12)
        }
    }

    /// Light catching the edge of the glass while it peeks out of the screen border.
    private var edgeGlow: some View {
        Capsule()
            .fill(LinearGradient(colors: [.white.opacity(0), .white, .white.opacity(0)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: 2)
            .padding(.vertical, 60)
            .blur(radius: 1.5)
            .opacity(model.phase == .peeking ? 0.9 : 0)
            .allowsHitTesting(false)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Rail")
                .font(.system(size: 20, weight: .bold))
                .tracking(-0.5)
            Spacer()
            if store.isTrusted {
                Text(summary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 10)
        .entrance(0, isOpen: isOpen, reduceMotion: reduceMotion)
    }

    private var summary: String {
        let windows = Plural.ru(store.windowCount, "окно", "окна", "окон")
        let projects = store.projects.projects.count
        guard projects > 0 else { return windows }
        return "\(Plural.ru(projects, "проект", "проекта", "проектов")) · \(windows)"
    }

    // MARK: Content

    private var content: some View {
        let layout = store.layout
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(layout.sections.enumerated()), id: \.element.id) { index, section in
                    ProjectCard(
                        section: section,
                        actions: actions,
                        isCollapsed: collapsedBinding(section.id)
                    )
                    .entrance(index + 1, isOpen: isOpen, reduceMotion: reduceMotion)
                }

                if layout.sections.isEmpty {
                    EmptyProjectsCard()
                        .entrance(1, isOpen: isOpen, reduceMotion: reduceMotion)
                }

                if !layout.ungrouped.isEmpty {
                    Text(layout.sections.isEmpty ? "Окна" : "Без проекта")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                        .entrance(layout.sections.count + 2, isOpen: isOpen, reduceMotion: reduceMotion)
                }

                ForEach(Array(layout.ungrouped.enumerated()), id: \.element.id) { index, group in
                    AppBlock(group: group, actions: actions)
                        .entrance(layout.sections.count + 3 + index, isOpen: isOpen, reduceMotion: reduceMotion)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 16)
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { height in
                withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) { contentHeight = height }
            }
        }
        .frame(maxHeight: contentHeight)
        .scrollIndicators(.never)
        // Content dissolves under the header and bottom edge instead of hitting a hard line.
        .mask {
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.025),
                .init(color: .black, location: 0.95),
                .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
        .animation(.spring(response: 0.35, dampingFraction: 1), value: store.projects.projects)
    }

    private func collapsedBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { collapsed.contains(id) },
            set: { isCollapsed in
                if isCollapsed { collapsed.insert(id) } else { collapsed.remove(id) }
            }
        )
    }
}

// MARK: - Ungrouped apps

private struct AppBlock: View {
    let group: AppGroup
    let actions: SidebarActions

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 7) {
                if let icon = group.icon {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                }
                Text(group.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                if group.windows.count > 1 {
                    Text("\(group.windows.count)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)

            ForEach(group.windows) { window in
                WindowRow(window: window, tint: .accentColor, showsIcon: false) {
                    actions.select(window)
                }
                .padding(.leading, 14)
                .contextMenu {
                    Button("Добавить в проект…") { actions.addToProject(window) }
                }
            }
        }
    }
}

// MARK: - Apps without windows

/// Running apps with nothing to list, as a strip of icons like the right side of the Dock.
private struct IdleApps: View {
    let apps: [NSRunningApplication]
    let open: (NSRunningApplication) -> Void

    @State private var hovered: pid_t?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Без окон")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 8)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 32), spacing: 2)], alignment: .leading, spacing: 2) {
                ForEach(apps, id: \.processIdentifier) { app in
                    Button { open(app) } label: {
                        Image(nsImage: app.icon ?? NSImage())
                            .resizable()
                            .frame(width: 24, height: 24)
                            .padding(4)
                            .background {
                                if hovered == app.processIdentifier {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(.primary.opacity(0.09))
                                }
                            }
                            .contentShape(.rect)
                    }
                    .buttonStyle(PressStyle())
                    .help(app.localizedName ?? "")
                    .onHover { inside in
                        if inside {
                            hovered = app.processIdentifier
                        } else if hovered == app.processIdentifier {
                            hovered = nil
                        }
                    }
                }
            }
            .padding(.horizontal, 6)
        }
    }
}

// MARK: - Empty and permission states

private struct EmptyProjectsCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text("Собери окна в проекты")
                    .font(.system(size: 13, weight: .semibold))
                Text("Правый клик по любому окну → «Добавить в проект»")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.primary.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
    }
}

private struct PermissionCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("Rail нужен доступ\nк Accessibility")
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.2)
            Text("Без него Rail не видит окна других приложений и не может их переключать.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Открыть настройки") { Accessibility.requestAccess() }
                .buttonStyle(.glassProminent)
                .padding(.top, 4)
        }
        .padding(20)
    }
}
