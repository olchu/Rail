import SwiftUI

struct ProjectCard: View {
    let section: ProjectSection
    let actions: SidebarActions
    @Binding var isCollapsed: Bool

    private var project: Project { section.project }
    private var color: Color { ProjectPalette.color(project.color) }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            header
            if !isCollapsed {
                rows
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .padding(5)
        .background { background }
        .clipShape(.rect(cornerRadius: 18, style: .continuous))
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(colors: [color.opacity(0.22), color.opacity(0.07)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [color.opacity(0.45), color.opacity(0.08)],
                                                 startPoint: .top, endPoint: .bottom),
                                  lineWidth: 0.75)
            }
    }

    // MARK: Header

    private var header: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { isCollapsed.toggle() }
        } label: {
            HStack(spacing: 9) {
                Monogram(name: project.name, color: color)
                Text(project.name)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(-0.1)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if isCollapsed {
                    AppIconStack(icons: section.icons)
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .trailing)))
                } else if section.openCount > 0 {
                    Text("\(section.openCount)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(color)
                        .transition(.opacity)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(PressStyle())
        .contextMenu { menu }
    }

    @ViewBuilder private var menu: some View {
        Button("Переименовать…") { actions.renameProject(project) }
        Menu("Цвет") {
            ForEach(ProjectPalette.colors.indices, id: \.self) { index in
                Toggle(ProjectPalette.colors[index].name, isOn: Binding(
                    get: { project.color == index },
                    set: { _ in actions.setColor(index, project) }
                ))
            }
        }
        Menu("Правила") {
            ForEach(project.rules, id: \.self) { rule in
                Button("Удалить: \(rule.label)") { actions.removeRule(rule, project) }
            }
        }
        Divider()
        Button("Удалить проект", role: .destructive) { actions.deleteProject(project) }
    }

    // MARK: Rows

    @ViewBuilder private var rows: some View {
        ForEach(section.pins) { entry in
            Group {
                if let window = entry.window {
                    WindowRow(window: window, tint: color, showsIcon: true, isPinned: true) {
                        actions.select(window)
                    }
                } else {
                    WindowRow(closedPin: entry.pin, icon: entry.icon, tint: color) {
                        actions.openPin(entry.pin)
                    }
                    .help("Открыть в \(entry.pin.appName)")
                }
            }
            .contextMenu {
                Button("Изменить…") { actions.editPin(entry.pin, project) }
                Button("Открепить") { actions.unpin(entry.pin, project) }
            }
        }
        if section.windows.isEmpty && section.pins.isEmpty {
            Text("Нет открытых окон")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
        }
        ForEach(section.windows) { window in
            WindowRow(window: window, tint: color, showsIcon: true) {
                actions.select(window)
            }
            .contextMenu {
                Button("Закрепить") { actions.pin(window, project) }
                Button("Добавить в проект…") { actions.addToProject(window) }
                Button("Убрать из «\(project.name)»") { actions.removeFromProject(window, project) }
            }
        }
    }
}

/// First letter of the project on a colored tile, like a space in Arc.
private struct Monogram: View {
    let name: String
    let color: Color

    var body: some View {
        Text(name.first.map { String($0).uppercased() } ?? "•")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(color.gradient, in: .rect(cornerRadius: 6, style: .continuous))
            .shadow(color: color.opacity(0.5), radius: 4, y: 1)
    }
}

/// Overlapping icons of the apps in a collapsed project.
private struct AppIconStack: View {
    let icons: [NSImage]

    var body: some View {
        HStack(spacing: -6) {
            ForEach(Array(icons.prefix(4).enumerated()), id: \.offset) { _, icon in
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
            }
        }
    }
}
