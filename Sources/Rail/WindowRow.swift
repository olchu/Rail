import SwiftUI

struct WindowRow: View {
    let window: WindowItem
    let tint: Color
    let showsIcon: Bool
    let action: () -> Void

    /// Local and unanimated, so the highlight is under the pointer at once
    /// and moving between rows does not redraw the whole list.
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if showsIcon, let icon = window.app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 18, height: 18)
                }
                titles
                Spacer(minLength: 0)
                if window.isMinimized {
                    Image(systemName: "dock.arrow.down.rectangle")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .padding(.vertical, 5)
            .frame(minHeight: 30)
            .background { highlight }
            .overlay(alignment: .leading) { focusMark }
            .contentShape(.rect)
        }
        .buttonStyle(PressStyle())
        .opacity(window.isMinimized ? 0.6 : 1)
        .onHover { isHovered = $0 }
    }

    private var titles: some View {
        let parts = window.titleParts
        return VStack(alignment: .leading, spacing: 1) {
            Text(parts.primary)
                .font(.system(size: 13, weight: window.isFocused ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
            if let secondary = parts.secondary {
                Text(secondary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    @ViewBuilder private var highlight: some View {
        if isHovered {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.primary.opacity(0.09))
        } else if window.isFocused {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.14))
        }
    }

    @ViewBuilder private var focusMark: some View {
        if window.isFocused {
            Capsule()
                .fill(tint)
                .frame(width: 3, height: 14)
                .offset(x: 2)
                .shadow(color: tint.opacity(0.6), radius: 3)
        }
    }
}

/// Feedback on press, not on release.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.15, dampingFraction: 1), value: configuration.isPressed)
    }
}
